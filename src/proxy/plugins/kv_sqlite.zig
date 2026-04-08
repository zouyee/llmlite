//! SQLite KV Store Plugin for llmlite Proxy
//!
//! Persistent key-value storage using zig-sqlite
//! This is an OPTIONAL plugin - the proxy works without it using in-memory storage

const std = @import("std");
const plugin = @import("plugin");

// Note: This plugin requires zig-sqlite dependency
// If not available, use the built-in MemoryKvStore instead

pub const SqliteKvStore = struct {
    db: anyopaque, // sqlite3 database handle
    allocator: std.mem.Allocator,
    path: []const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !SqliteKvStore {
        // This is a placeholder implementation - actual SQLite support requires zig-sqlite
        // For production use with SQLite, add zig-sqlite dependency and implement here
        // For now, use the built-in MemoryKvStore instead
        _ = allocator;
        _ = path;
        return error.ImplementationRequiresZigSqlite;
    }

    pub fn deinit(self: *SqliteKvStore) void {
        _ = self;
        // Close database connection
    }

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
        _ = interface;
        _ = key;
        // Would implement: SELECT value FROM kv_store WHERE key = ?
        return null;
    }

    fn setWrapper(interface: *anyopaque, key: []const u8, value: []const u8) !void {
        _ = interface;
        _ = key;
        _ = value;
        // Would implement: INSERT OR REPLACE INTO kv_store (key, value) VALUES (?, ?)
    }

    fn deleteWrapper(interface: *anyopaque, key: []const u8) bool {
        _ = interface;
        _ = key;
        // Would implement: DELETE FROM kv_store WHERE key = ?
        return false;
    }

    fn listWrapper(interface: *anyopaque, prefix: []const u8) [][]const u8 {
        _ = interface;
        _ = prefix;
        // Would implement: SELECT key FROM kv_store WHERE key LIKE 'prefix%'
        return &.{};
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
    .dependencies = &.{"zig-sqlite"},
};

test "sqlite kv store returns error without zig-sqlite" {
    const allocator = std.heap.page_allocator;
    const result = SqliteKvStore.init(allocator, "/tmp/test.db");
    try std.testing.expectError(error.ImplementationRequiresZigSqlite, result);
}
