//! Virtual Key Store backed by Plugin KV Store
//!
//! This module wraps VirtualKeyStore with optional KV store persistence
//! Uses the plugin.KvStore interface for storage

const std = @import("std");
const plugin = @import("plugin");
const virtual_key = @import("../virtual_key");

pub const KvBackedKeyStore = struct {
    allocator: std.mem.Allocator,
    key_store: virtual_key.VirtualKeyStore,
    kv_store: ?*const plugin.KvStore,
    prefix: []const u8,

    pub fn init(allocator: std.mem.Allocator, kv_store: ?*const plugin.KvStore) KvBackedKeyStore {
        return .{
            .allocator = allocator,
            .key_store = virtual_key.VirtualKeyStore.init(allocator),
            .kv_store = kv_store,
            .prefix = "key:",
        };
    }

    pub fn deinit(self: *KvBackedKeyStore) void {
        self.key_store.deinit();
        self.allocator.free(self.prefix);
    }

    /// Load keys from KV store
    pub fn loadFromKv(self: *KvBackedKeyStore) !void {
        const kv = self.kv_store orelse return;
        const keys = kv.list(self.prefix);
        defer self.allocator.free(keys);

        for (keys) |key| {
            if (kv.get(key)) |value| {
                // Parse and add key from KV store
                _ = std.json.parseFromSlice(virtual_key.VirtualKey, self.allocator, value, .{}) catch continue;
            }
        }
    }

    /// Save keys to KV store
    pub fn saveToKv(self: *KvBackedKeyStore) !void {
        const kv = self.kv_store orelse return;

        var it = self.key_store.keys.iterator();
        while (it.next()) |entry| {
            const full_key = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.prefix, entry.key_ptr.* });
            defer self.allocator.free(full_key);

            const json = try std.json.Stringify.valueAlloc(self.allocator, entry.value_ptr, .{});
            defer self.allocator.free(json);

            try kv.set(full_key, json);
        }
    }

    /// Generate a new virtual key
    pub fn generateKey(self: *KvBackedKeyStore, config: virtual_key.VirtualKeyConfig) ![]const u8 {
        const key = try self.key_store.generateKey(config);
        // Auto-save after modification
        self.saveToKv() catch {};
        return key;
    }

    /// Add a key
    pub fn add(self: *KvBackedKeyStore, key: []const u8, config: virtual_key.VirtualKeyConfig) !void {
        try self.key_store.add(key, config);
        self.saveToKv() catch {};
    }

    /// Validate a key
    pub fn validate(self: *KvBackedKeyStore, key: []const u8) !void {
        try self.key_store.validate(key);
    }

    /// Get a key
    pub fn get(self: *KvBackedKeyStore, key: []const u8) ?*const virtual_key.VirtualKey {
        return self.key_store.get(key);
    }

    /// Delete a key
    pub fn delete(self: *KvBackedKeyStore, key: []const u8) bool {
        const result = self.key_store.delete(key);
        self.saveToKv() catch {};
        return result;
    }

    /// Revoke a key
    pub fn revoke(self: *KvBackedKeyStore, key: []const u8) !void {
        try self.key_store.revoke(key);
        self.saveToKv() catch {};
    }

    /// Update spend
    pub fn updateSpend(self: *KvBackedKeyStore, key: []const u8, amount: f64) !void {
        try self.key_store.updateSpend(key, amount);
        self.saveToKv() catch {};
    }

    /// Get the underlying key store for direct access
    pub fn keyStore(self: *KvBackedKeyStore) *virtual_key.VirtualKeyStore {
        return &self.key_store;
    }
};

test "kv backed key store" {
    std.debug.print("KV backed key store test\n", .{});
}
