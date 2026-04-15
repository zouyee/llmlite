//! SQLite KV Store Plugin for llmlite Proxy
//!
//! Persistent key-value storage using zig-sqlite
//! Implements the plugin.KvStore interface for interchangeable storage backends

const std = @import("std");
const plugin = @import("plugin");
const sqlite = @import("sqlite");

pub const SqliteKvStore = struct {
    db: sqlite.Database,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !SqliteKvStore {
        const db = try sqlite.Database.open(.{ .mode = .{ .File = path } });
        errdefer db.close();

        // Create the KV store table if it doesn't exist
        try db.exec("CREATE TABLE IF NOT EXISTS kv_store (key TEXT PRIMARY KEY, value TEXT)", .{});

        return SqliteKvStore{
            .db = db,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SqliteKvStore) void {
        self.db.close();
    }

    /// Convert to plugin.KvStore interface for polymorphic use
    pub fn toKvStore(self: *SqliteKvStore) plugin.KvStore {
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
        const self: *SqliteKvStore = @ptrCast(@alignCast(interface));
        const stmt = self.db.prepare(struct { value: []const u8 }, void, "SELECT value FROM kv_store WHERE key = ?") catch return null;
        defer stmt.finalize();
        stmt.bind(.{key}) catch return null;
        if (stmt.step()) |row| {
            return row.value;
        }
        return null;
    }

    fn setWrapper(interface: *anyopaque, key: []const u8, value: []const u8) !void {
        const self: *SqliteKvStore = @ptrCast(@alignCast(interface));
        const stmt = self.db.prepare(void, void, "INSERT OR REPLACE INTO kv_store (key, value) VALUES (?, ?)") catch return error.InitFailed;
        defer stmt.finalize();
        try stmt.exec(.{ key, value });
    }

    fn deleteWrapper(interface: *anyopaque, key: []const u8) bool {
        const self: *SqliteKvStore = @ptrCast(@alignCast(interface));
        const stmt = self.db.prepare(void, void, "DELETE FROM kv_store WHERE key = ?") catch return false;
        defer stmt.finalize();
        stmt.exec(.{key}) catch return false;
        return true;
    }

    fn listWrapper(interface: *anyopaque, prefix: []const u8) [][]const u8 {
        const self: *SqliteKvStore = @ptrCast(@alignCast(interface));
        const query = if (prefix.len > 0) "SELECT key FROM kv_store WHERE key LIKE ?" else "SELECT key FROM kv_store";
        const stmt = self.db.prepare(struct { key: []const u8 }, void, query) catch return &.{};
        defer stmt.finalize();

        if (prefix.len > 0) {
            const pattern = std.fmt.allocPrint(self.allocator, "{s}%%", .{prefix}) catch return &.{};
            defer self.allocator.free(pattern);
            stmt.bind(.{pattern}) catch return &.{};
        }

        var result = std.ArrayList([]const u8).init(self.allocator);
        while (stmt.step()) |row| {
            const key_copy = self.allocator.dupe(u8, row.key) catch continue;
            result.append(key_copy) catch {
                self.allocator.free(key_copy);
                continue;
            };
        }
        return result.toOwnedSlice() catch &.{};
    }

    fn closeWrapper(_: *anyopaque) void {
        // Database is closed in deinit
    }
};

// Plugin info for registration
pub const PLUGIN_INFO = plugin.PluginInfo{
    .name = "kvstore.sqlite",
    .version = "1.0.0",
    .description = "SQLite-based persistent key-value store",
    .plugin_type = .kv_store,
    .dependencies = &.{},
};

test "sqlite kv store basic operations" {
    const allocator = std.heap.page_allocator;
    const test_path = "/tmp/llmlite_test_kv.db";

    // Clean up any existing test database
    std.fs.deleteFileAbsolute(test_path) catch {};

    var store = try SqliteKvStore.init(allocator, test_path);
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
    std.fs.deleteFileAbsolute(test_path) catch {};
}
