//! Proxy Configuration
//!
//! Configuration for the llmlite proxy server including
//! server settings, virtual keys, and routing rules.

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
const types = @import("../provider/types.zig");

pub const ProviderType = types.ProviderType;

/// Server configuration
pub const ServerConfig = struct {
    host: []const u8 = "0.0.0.0",
    port: u16 = 4000,
};

/// Virtual key configuration
pub const VirtualKeyConfig = struct {
    key: []const u8,
    user_id: ?[]const u8 = null,
    rate_limit: ?u32 = null,
    allowed_models: ?[][]const u8 = null,
    allowed_providers: ?[]ProviderType = null,
};

/// Route target configuration
pub const RouteTargetConfig = struct {
    provider: ProviderType,
    model: []const u8,
    weight: u32 = 1,
};

/// Routing rule for a model
pub const RoutingRuleConfig = struct {
    model: []const u8,
    targets: []RouteTargetConfig,
};

/// Proxy configuration
pub const ProxyConfig = struct {
    server: ServerConfig = .{},
    virtual_keys: []VirtualKeyConfig = &.{},
    routing: []RoutingRuleConfig = &.{},
    log_requests: bool = true,
    log_file_path: ?[]const u8 = null,
};

/// Parsed routing target with computed values
pub const RouteTarget = struct {
    provider: ProviderType,
    model: []const u8,
    weight: u32,
};

/// Routing rule with parsed targets
pub const RoutingRule = struct {
    model: []const u8,
    targets: []RouteTarget,
};

/// Routing table for model routing
pub const RoutingTable = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    rules: StringArrayHashMap([]RouteTarget),

    pub fn init(allocator: std.mem.Allocator, io: std.Io) RoutingTable {
        return .{
            .allocator = allocator,
            .io = io,
            .rules = StringArrayHashMap([]RouteTarget).init(allocator),
        };
    }

    pub fn deinit(self: *RoutingTable) void {
        var it = self.rules.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |target| {
                self.allocator.free(target.model);
            }
            self.allocator.free(entry.value_ptr.*);
        }
        self.rules.deinit();
    }

    pub fn addRule(self: *RoutingTable, rule: RoutingRuleConfig) !void {
        const model_key = try self.allocator.dupe(u8, rule.model);
        errdefer self.allocator.free(model_key);

        var targets = try self.allocator.alloc(RouteTarget, rule.targets.len);
        errdefer self.allocator.free(targets);

        for (rule.targets, 0..) |config, i| {
            targets[i] = .{
                .provider = config.provider,
                .model = try self.allocator.dupe(u8, config.model),
                .weight = config.weight,
            };
        }

        try self.rules.put(model_key, targets);
    }

    pub fn selectTarget(self: *RoutingTable, model: []const u8) !RouteTarget {
        const targets = self.rules.get(model) orelse {
            // Default: route to OpenAI with the same model name
            return .{
                .provider = .openai,
                .model = try self.allocator.dupe(u8, model),
                .weight = 1,
            };
        };

        if (targets.len == 0) {
            return error.NoRouteForModel;
        }

        // Weighted round-robin selection
        var total_weight: u32 = 0;
        for (targets) |t| total_weight += t.weight;

        // Use timestamp for simple round-robin
        const timestamp = @as(u64, @intCast(time_compat.timestamp(self.io)));
        const selection = timestamp % total_weight;

        var running: u32 = 0;
        for (targets) |*t| {
            running += t.weight;
            if (running > selection) {
                // Return a copy with duplicated string
                return .{
                    .provider = t.provider,
                    .model = try self.allocator.dupe(u8, t.model),
                    .weight = t.weight,
                };
            }
        }

        // Fallback to first target
        return .{
            .provider = targets[0].provider,
            .model = try self.allocator.dupe(u8, targets[0].model),
            .weight = targets[0].weight,
        };
    }
};
