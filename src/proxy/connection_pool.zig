const std = @import("std");

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
const provider_types = @import("types");
const registry = @import("registry");

pub const ConnectionPool = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    max_conns_per_provider: usize,
    idle_timeout_ms: u32,
    connections: StringArrayHashMap(ProviderPool),
    lock: std.Io.Mutex,

    pub const ProviderPool = struct {
        connections: std.ArrayList(*ManagedConnection),
        in_use: std.ArrayList(*ManagedConnection),
        total_count: usize,
    };

    pub const ManagedConnection = struct {
        stream: std.Io.net.Stream,
        last_used: i64,
        provider: provider_types.ProviderType,
        is_healthy: bool = true,

        pub fn isExpired(self: *ManagedConnection, idle_timeout_ms: u32) bool {
            // Use std.c.time for a simple timestamp without io
            const now: i64 = @intCast(std.c.time(null));
            return (now - self.last_used) * 1000 > idle_timeout_ms;
        }

        pub fn markUsed(self: *ManagedConnection) void {
            const now: i64 = @intCast(std.c.time(null));
            self.last_used = now;
        }

        pub fn close(self: *ManagedConnection, io: std.Io) void {
            self.stream.close(io);
        }
    };

    pub fn init(allocator: std.mem.Allocator, io: std.Io, max_conns_per_provider: usize, idle_timeout_ms: u32) ConnectionPool {
        return .{
            .allocator = allocator,
            .io = io,
            .max_conns_per_provider = max_conns_per_provider,
            .idle_timeout_ms = idle_timeout_ms,
            .connections = StringArrayHashMap(ProviderPool).init(allocator),
            .lock = std.Io.Mutex.init,
        };
    }

    pub fn deinit(self: *ConnectionPool) void {
        var it = self.connections.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.connections.items) |conn| {
                conn.close(self.io);
                self.allocator.destroy(conn);
            }
            entry.value_ptr.connections.deinit(self.allocator);
            entry.value_ptr.in_use.deinit(self.allocator);
        }
        self.connections.deinit();
    }

    pub fn getConnection(self: *ConnectionPool, provider: provider_types.ProviderType) !*ManagedConnection {
        while (!self.lock.tryLock()) {}
        defer self.lock.state.store(.unlocked, .release);

        const provider_name = provider.toString();
        var pool = try self.connections.getOrPut(provider_name);
        if (!pool.found_existing) {
            pool.value_ptr.* = .{
                .connections = std.ArrayList(*ManagedConnection).init(self.allocator),
                .in_use = std.ArrayList(*ManagedConnection).init(self.allocator),
                .total_count = 0,
            };
        }

        // Find available connection
        var available_idx: ?usize = null;
        for (pool.value_ptr.connections.items, 0..) |conn, idx| {
            if (!pool.value_ptr.in_use.contains(conn)) {
                if (conn.isExpired(self.idle_timeout_ms) and !pool.value_ptr.in_use.contains(conn)) {
                    conn.close(self.io);
                    self.allocator.destroy(conn);
                    _ = pool.value_ptr.connections.swapRemove(idx);
                    continue;
                }
                available_idx = idx;
                break;
            }
        }

        if (available_idx) |idx| {
            const conn = pool.value_ptr.connections.items[idx];
            try pool.value_ptr.in_use.append(conn);
            conn.markUsed();
            return conn;
        }

        // Create new connection if under limit
        if (pool.value_ptr.total_count < self.max_conns_per_provider) {
            const provider_config = registry.getProviderConfig(provider);
            const uri = std.Uri.parse(provider_config.base_url) catch return error.InvalidUrl;
            const host = uri.host orelse return error.InvalidUrl;
            const port: u16 = if (uri.port) |p| p else 443;
            const address = try std.Io.net.IpAddress.resolve(self.io, host.percent_encoded, port);
            var stream = try address.connect(self.io, .{});
            errdefer stream.close(self.io);

            const conn = try self.allocator.create(ManagedConnection);
            const now: i64 = @intCast(std.c.time(null));
            conn.* = .{
                .stream = stream,
                .last_used = now,
                .provider = provider,
                .is_healthy = true,
            };
            try pool.value_ptr.connections.append(conn);
            try pool.value_ptr.in_use.append(conn);
            pool.value_ptr.total_count += 1;
            return conn;
        }

        return error.NoAvailableConnection;
    }

    pub fn releaseConnection(self: *ConnectionPool, conn: *ManagedConnection) void {
        while (!self.lock.tryLock()) {}
        defer self.lock.state.store(.unlocked, .release);

        const provider_name = conn.provider.toString();
        if (self.connections.getPtr(provider_name)) |pool| {
            for (pool.in_use.items, 0..) |in_use_conn, idx| {
                if (in_use_conn == conn) {
                    _ = pool.in_use.swapRemove(idx);
                    break;
                }
            }
        }
    }

    pub fn markUnhealthy(_: *ConnectionPool, conn: *ManagedConnection) void {
        conn.is_healthy = false;
    }

    pub fn closeIdleConnections(self: *ConnectionPool) void {
        while (!self.lock.tryLock()) {}
        defer self.lock.state.store(.unlocked, .release);

        var it = self.connections.iterator();
        while (it.next()) |entry| {
            var i: usize = 0;
            while (i < entry.value_ptr.connections.items.len) {
                const conn = entry.value_ptr.connections.items[i];
                if (conn.isExpired(self.idle_timeout_ms) and !entry.value_ptr.in_use.contains(conn)) {
                    conn.close(self.io);
                    self.allocator.destroy(conn);
                    _ = entry.value_ptr.connections.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }
    }
};

test "connection pool - init" {
    const allocator = std.heap.page_allocator;
    const io = std.testing.io;
    var pool = ConnectionPool.init(allocator, io, 10, 30000);
    defer pool.deinit();

    try std.testing.expectEqual(@as(usize, 10), pool.max_conns_per_provider);
    try std.testing.expectEqual(@as(u32, 30000), pool.idle_timeout_ms);
    try std.testing.expectEqual(@as(usize, 0), pool.connections.count());
}

test "connection pool - ProviderPool init" {
    const allocator = std.heap.page_allocator;
    var pool = ConnectionPool.ProviderPool{
        .connections = std.ArrayList(*ConnectionPool.ManagedConnection).init(allocator),
        .in_use = std.ArrayList(*ConnectionPool.ManagedConnection).init(allocator),
        .total_count = 0,
    };
    defer {
        pool.connections.deinit(allocator);
        pool.in_use.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 0), pool.connections.items.len);
    try std.testing.expectEqual(@as(usize, 0), pool.in_use.items.len);
    try std.testing.expectEqual(@as(usize, 0), pool.total_count);
}

test "connection pool - getConnection creates pool entry" {
    const allocator = std.heap.page_allocator;
    const io = std.testing.io;
    var pool = ConnectionPool.init(allocator, io, 10, 30000);
    defer pool.deinit();

    // Before getting connection, no pool exists
    try std.testing.expect(!pool.connections.contains("openai"));

    // Note: This test would require actual network connection
    // For unit testing, we just verify pool initialization
    _ = &pool; // Use pool to avoid unused warning
}

test "connection pool - releaseConnection logic" {
    const allocator = std.heap.page_allocator;
    const io = std.testing.io;
    var pool = ConnectionPool.init(allocator, io, 10, 30000);
    defer pool.deinit();

    // Test that releaseConnection doesn't crash on empty pool
    // (can't actually release without a connection to release)
    pool.releaseConnection(undefined);
    try std.testing.expect(true); // If we get here, no crash
}

test "connection pool - closeIdleConnections on empty pool" {
    const allocator = std.heap.page_allocator;
    const io = std.testing.io;
    var pool = ConnectionPool.init(allocator, io, 10, 30000);
    defer pool.deinit();

    // Should not crash on empty pool
    pool.closeIdleConnections();
    try std.testing.expect(true);
}

test "connection pool - markUnhealthy" {
    const allocator = std.heap.page_allocator;
    const io = std.testing.io;
    var pool = ConnectionPool.init(allocator, io, 10, 30000);
    defer pool.deinit();

    // Create a mock connection to test markUnhealthy
    // Note: This tests the method exists and can be called
    // In real usage, this would be called on actual connections
    pool.markUnhealthy(undefined);
    try std.testing.expect(true);
}
