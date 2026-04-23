//! File KV Store Plugin for llmlite Proxy
//!
//! Persistent key-value storage using JSON Lines format
//! Implements the plugin.KvStore interface for interchangeable storage backends
//!
//! Format: One JSON object per line: {"key":"...","value":"..."}

const std = @import("std");
const time_compat = @import("time_compat");

// Zig 0.16.0 compat: managed StringArrayHashMap wrapper
fn StringArrayHashMap(comptime V: type) type {
    return struct {
        const Self = @This();
        unmanaged: std.StringArrayHashMapUnmanaged(V),
        allocator: std.mem.Allocator,
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .unmanaged = .empty, .allocator = allocator };
        }
        pub fn deinit(self: *Self) void { self.unmanaged.deinit(self.allocator); }
        pub fn put(self: *Self, key: []const u8, value: V) !void { return self.unmanaged.put(self.allocator, key, value); }
        pub fn get(self: Self, key: []const u8) ?V { return self.unmanaged.get(key); }
        pub fn getPtr(self: Self, key: []const u8) ?*V { return self.unmanaged.getPtr(key); }
        pub fn getOrPut(self: *Self, key: []const u8) !std.StringArrayHashMapUnmanaged(V).GetOrPutResult { return self.unmanaged.getOrPut(self.allocator, key); }
        pub fn getOrPutValue(self: *Self, key: []const u8, value: V) !std.StringArrayHashMapUnmanaged(V).GetOrPutResult { return self.unmanaged.getOrPutValue(self.allocator, key, value); }
        pub fn contains(self: Self, key: []const u8) bool { return self.unmanaged.contains(key); }
        pub fn count(self: Self) usize { return self.unmanaged.count(); }
        pub fn iterator(self: Self) std.StringArrayHashMapUnmanaged(V).Iterator { return self.unmanaged.iterator(); }
        pub fn fetchSwapRemove(self: *Self, key: []const u8) ?std.StringArrayHashMapUnmanaged(V).KV { return self.unmanaged.fetchSwapRemove(key); }
        pub fn fetchRemove(self: *Self, key: []const u8) ?std.StringArrayHashMapUnmanaged(V).KV { return self.unmanaged.fetchSwapRemove(key); }
        pub fn swapRemove(self: *Self, key: []const u8) bool { return self.unmanaged.swapRemove(key); }
        pub fn keys(self: Self) [][]const u8 { return self.unmanaged.keys(); }
        pub fn values(self: Self) []V { return self.unmanaged.values(); }
    };
}
const plugin = @import("plugin");

pub const FileKvStore = struct {
    allocator: std.mem.Allocator,
    data: StringArrayHashMap([]u8),
    file_path: []u8,
    mutex: std.Io.Mutex,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, dir_path: []const u8) !FileKvStore {
        // Ensure directory exists
        try std.Io.Dir.createDirAbsolute(self.io, dir_path, .default_dir);

        const file_path = try std.fmt.allocPrint(allocator, "{s}/kvstore.jsonl", .{dir_path});
        errdefer allocator.free(file_path);

        var store = FileKvStore{
            .allocator = allocator,
            .data = StringArrayHashMap([]u8).init(allocator),
            .file_path = file_path,
            .mutex = .{},
        };

        // Load existing data
        store.load() catch {};

        return store;
    }

    pub fn deinit(self: *FileKvStore) void {
        // Save before closing
        self.save() catch {};

        var it = self.data.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.deinit();
        self.allocator.free(self.file_path);
    }

    /// Convert to plugin.KvStore interface for polymorphic use
    pub fn toKvStore(self: *FileKvStore) plugin.KvStore {
        return .{
            .interface = @ptrCast(self),
            .vtable = &.{
                .get = getWrapper,
                .set = setWrapper,
                .delete = deleteWrapper,
                .list = listWrapper,
                .close = closeWrapper,
            },
        };
    }

    fn getWrapper(interface: *anyopaque, key: []const u8) ?[]const u8 {
        const self: *FileKvStore = @ptrCast(@alignCast(interface));
        const mutex = &self.mutex;
        while (!mutex.tryLock()) {}
        defer mutex.state.store(.unlocked, .release);
        return self.data.get(key);
    }

    fn setWrapper(interface: *anyopaque, key: []const u8, value: []const u8) !void {
        const self: *FileKvStore = @ptrCast(@alignCast(interface));
        const mutex = &self.mutex;
        while (!mutex.tryLock()) {}
        defer mutex.state.store(.unlocked, .release);

        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);

        const value_copy = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_copy);

        // Remove old entry if exists to free memory
        if (self.data.swapRemove(key_copy)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
        }
        self.data.putAssumeCapacity(key_copy, value_copy);

        // Persist to disk
        self.save() catch {};
    }

    fn deleteWrapper(interface: *anyopaque, key: []const u8) bool {
        const self: *FileKvStore = @ptrCast(@alignCast(interface));
        const mutex = &self.mutex;
        while (!mutex.tryLock()) {}
        defer mutex.state.store(.unlocked, .release);

        // swapRemove returns bool indicating if found
        if (self.data.swapRemove(key)) {
            self.save() catch {};
            return true;
        }
        return false;
    }

    fn listWrapper(interface: *anyopaque, prefix: []const u8) [][]const u8 {
        const self: *FileKvStore = @ptrCast(@alignCast(interface));
        const mutex = &self.mutex;
        while (!mutex.tryLock()) {}
        defer mutex.state.store(.unlocked, .release);

        var result = std.array_list.Managed([]const u8).init(self.allocator);
        var it = self.data.iterator();
        while (it.next()) |entry| {
            if (prefix.len == 0 or std.mem.startsWith(u8, entry.key_ptr.*, prefix)) {
                const key_copy = self.allocator.dupe(u8, entry.key_ptr.*) catch continue;
                result.append(key_copy) catch {
                    self.allocator.free(key_copy);
                    continue;
                };
            }
        }
        return result.toOwnedSlice() catch &.{};
    }

    fn closeWrapper(_: *anyopaque) void {
        // No-op, cleanup handled by deinit
    }

    fn load(self: *FileKvStore) !void {
        const file = std.Io.Dir.openFileAbsolute(self.io, self.file_path, .{}) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        defer file.close(self.io);

        const stat = try file.stat(self.io);
        if (stat.size == 0) return;

        const content = try blk: { var __buf: [8192]u8 = undefined; var __reader = file.reader(self.io, &__buf); break :blk __reader.interface.allocRemaining(self.allocator, .limited(stat.size)); };
        defer self.allocator.free(content);

        // Parse JSON Lines format: {"key":"...","value":"..."}
        var line_iter = std.mem.splitScalar(u8, content, '\n');
        while (line_iter.next()) |line| {
            if (line.len == 0) continue;

            // Simple JSON parsing for {"key":"...", "value":"..."}
            const key = extractJsonString(line, "key") catch continue;
            const value = extractJsonString(line, "value") catch continue;

            const key_copy = self.allocator.dupe(u8, key) catch continue;
            const value_copy = self.allocator.dupe(u8, value) catch continue;
            self.data.putAssumeCapacity(key_copy, value_copy);
        }
    }

    fn extractJsonString(json: []const u8, field_name: []const u8) ![]const u8 {
        // Build search pattern manually based on field name
        const key_pattern = "\"key\":\"";
        const value_pattern = "\"value\":\"";
        const search = if (std.mem.eql(u8, field_name, "key")) key_pattern else value_pattern;
        const start = std.mem.find(u8, json, search) orelse return error.NotFound;
        const value_start = start + search.len;
        const value_end = std.mem.findPos(u8, json, value_start, "\"") orelse return error.NotFound;
        return json[value_start..value_end];
    }

    fn save(self: *FileKvStore) !void {
        var content = std.array_list.Managed(u8).init(self.allocator);
        defer content.deinit();

        var it = self.data.iterator();
        while (it.next()) |entry| {
            // Write JSON line: {"key":"...","value":"..."}
            try content.appendSlice(&.{ '{', '"', 'k', 'e', 'y', '"', ':', '"' });
            try content.appendSlice(entry.key_ptr.*);
            try content.appendSlice(&.{ '"', ',', '"', 'v', 'a', 'l', 'u', 'e', '"', ':', '"' });
            try content.appendSlice(entry.value_ptr.*);
            try content.appendSlice(&.{ '"', '}', '\n' });
        }

        const file = try std.Io.Dir.createFileAbsolute(self.io, self.file_path, .{});
        defer file.close(self.io);
        try file.writeStreamingAll(self.io, content.items);
    }
};

test "file kv store basic operations" {
    const allocator = std.heap.page_allocator;
    const test_dir = "/tmp/llmlite_test_kv";

    // Clean up any existing test directory
    std.fs.deleteTreeAbsolute(test_dir) catch {};

    var store = try FileKvStore.init(allocator, test_dir);
    defer store.deinit();

    // Test set and get via interface
    const kv = store.toKvStore();
    try kv.set("test_key", "test_value");
    const value = kv.get("test_key");
    try std.testing.expect(value != null);
    try std.testing.expectEqualStrings("test_value", value.?);

    // Test delete
    _ = kv.delete("test_key");
    const deleted_value = kv.get("test_key");
    try std.testing.expect(deleted_value == null);

    // Clean up
    std.fs.deleteTreeAbsolute(test_dir) catch {};
}
