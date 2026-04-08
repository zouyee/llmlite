//! Proxy Configuration
//!
//! Configuration for the llmlite proxy server including
//! server settings, virtual keys, and routing rules.

const std = @import("std");
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
    rules: std.StringArrayHashMap([]RouteTarget),

    pub fn init(allocator: std.mem.Allocator) RoutingTable {
        return .{
            .allocator = allocator,
            .rules = std.StringArrayHashMap([]RouteTarget).init(allocator),
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
        const timestamp = @as(u64, @intCast(std.time.timestamp()));
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
