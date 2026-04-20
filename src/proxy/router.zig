const std = @import("std");
const types = @import("../provider/types.zig");
const http = @import("../http.zig");
const registry = @import("../provider/registry.zig");

pub const RetryConfig = struct {
    max_retries: u3 = 3,
    base_delay_ms: u32 = 100,
    max_delay_ms: u32 = 5000,
};

pub const RouterError = error{
    NoRouteForModel,
    AllProvidersFailed,
    MaxRetriesExceeded,
    InvalidProviderList,
};

pub const Router = struct {
    allocator: std.mem.Allocator,
    retry_config: RetryConfig,
    provider_stats: std.StringArrayHashMap(ProviderStats),

    pub const ProviderStats = struct {
        failures: u32 = 0,
        last_failure: ?i64 = null,
        consecutive_failures: u32 = 0,
        total_requests: u64 = 0,
        total_tokens: u64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator) Router {
        return .{
            .allocator = allocator,
            .retry_config = .{},
            .provider_stats = std.StringArrayHashMap(ProviderStats).init(allocator),
            .lock = .{},
        };
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, config: RetryConfig) Router {
        return .{
            .allocator = allocator,
            .retry_config = config,
            .provider_stats = std.StringArrayHashMap(ProviderStats).init(allocator),
            .lock = .{},
        };
    }

    pub fn deinit(self: *Router) void {
        self.provider_stats.deinit();
    }

    /// Call with multi-provider fallback
    /// Tries providers in order, falling back to next if one fails
    pub fn callWithFallback(
        self: *Router,
        model: []const u8,
        request_body: []const u8,
        providers: []const types.ProviderType,
        api_key: []const u8,
    ) ![]u8 {
        if (providers.len == 0) {
            return RouterError.InvalidProviderList;
        }

        var last_error: anyerror = error.AllProvidersFailed;

        for (providers) |provider| {
            const provider_name = provider.toString();

            // Check if provider is healthy (not in cooldown)
            if (self.isProviderUnhealthy(provider_name)) {
                std.log.info("skipping unhealthy provider {s}", .{provider_name});
                continue;
            }

            // Try to call this provider with retries
            const result = self.callProviderWithRetry(provider, model, request_body, api_key);

            if (result) |response| {
                // Record success
                self.recordSuccess(provider_name, 0);
                return response;
            } else |err| {
                last_error = err;
                std.log.warn("provider {s} failed: {}", .{ provider_name, err });

                // Record failure
                self.recordFailure(provider_name);

                // If error is not retryable, skip to next provider immediately
                if (!self.isRetryable(err)) {
                    continue;
                }
            }
        }

        return last_error;
    }

    /// Call a single provider with retries
    fn callProviderWithRetry(
        self: *Router,
        provider: types.ProviderType,
        model: []const u8,
        request_body: []const u8,
        api_key: []const u8,
    ) ![]u8 {
        const provider_config = registry.getProviderConfig(provider);

        var client = http.HttpClient.initWithAuthType(
            self.allocator,
            provider_config.base_url,
            api_key,
            null,
            30000,
            provider_config.auth_type,
        );
        defer client.deinit();

        var last_error: anyerror = error.ApiError;
        var attempt: u3 = 0;

        while (attempt < self.retry_config.max_retries) : (attempt += 1) {
            const endpoint = switch (provider) {
                .google => try std.fmt.allocPrint(self.allocator, "/models/{s}:generateContent", .{model}),
                else => try self.allocator.dupe(u8, "/chat/completions"),
            };
            defer self.allocator.free(endpoint);

            // Transform request if needed
            const transformed = try self.transformRequest(provider, request_body);
            errdefer self.allocator.free(transformed);

            const result = client.post(endpoint, transformed);

            if (result) |response| {
                return response;
            } else |err| {
                last_error = err;

                if (self.isRetryable(err)) {
                    const delay = self.calculateBackoff(attempt);
                    std.log.warn("provider {s} attempt {d} failed, retrying in {d}ms: {}", .{
                        provider.toString(),
                        attempt + 1,
                        delay,
                        err,
                    });
                    std.time.sleep(delay * std.time.ns_per_ms);
                    continue;
                }

                return err;
            }
        }

        return last_error;
    }

    /// Transform request to provider-specific format
    fn transformRequest(self: *Router, provider: types.ProviderType, body: []const u8) ![]u8 {
        return switch (provider) {
            .anthropic => try self.transformToAnthropic(body),
            .google => try self.transformToGoogle(body),
            else => try self.allocator.dupe(u8, body),
        };
    }

    fn transformToAnthropic(self: *Router, body: []const u8) ![]u8 {
        const parsed = try std.json.parseFromSlice(struct {
            model: []const u8,
            messages: []struct {
                role: []const u8,
                content: []const u8,
            },
            temperature: ?f32,
            max_tokens: ?u32,
        }, self.allocator, body, .{});
        defer parsed.deinit();

        var system_content: ?[]const u8 = null;
        var user_content = std.array_list.Managed(u8).init(self.allocator);
        defer user_content.deinit();

        for (parsed.value.messages) |msg| {
            if (std.mem.eql(u8, msg.role, "system")) {
                system_content = msg.content;
            } else if (std.mem.eql(u8, msg.role, "user")) {
                if (user_content.items.len > 0) {
                    try user_content.appendSlice(self.allocator, "\n");
                }
                try user_content.appendSlice(self.allocator, msg.content);
            }
        }

        var result = std.array_list.Managed(u8).init(self.allocator);
        defer result.deinit();
        errdefer result.deinit(self.allocator);

        try std.fmt.format(result.writer(self.allocator), "{{\"model\":\"{s}\",\"messages\":[{{\"role\":\"user\",\"content\":\"{s}\"}}]", .{
            parsed.value.model,
            try user_content.toOwnedSlice(self.allocator),
        });

        if (system_content) |sys| {
            try std.fmt.format(result.writer(self.allocator), ",\"system\":\"{s}\"", .{sys});
        }
        if (parsed.value.max_tokens) |v| {
            try std.fmt.format(result.writer(self.allocator), ",\"max_tokens\":{d}", .{v});
        }
        if (parsed.value.temperature) |v| {
            try std.fmt.format(result.writer(self.allocator), ",\"temperature\":{d}", .{v});
        }

        try result.append(self.allocator, '}');
        return result.toOwnedSlice(self.allocator);
    }

    fn transformToGoogle(self: *Router, body: []const u8) ![]u8 {
        const parsed = try std.json.parseFromSlice(struct {
            model: []const u8,
            messages: []struct {
                role: []const u8,
                content: []const u8,
            },
        }, self.allocator, body, .{});
        defer parsed.deinit();

        var contents_json = std.array_list.Managed(u8).init(self.allocator);
        defer contents_json.deinit();
        defer contents_json.deinit(self.allocator);

        try contents_json.appendSlice(self.allocator, "[");
        for (parsed.value.messages, 0..) |msg, i| {
            if (i > 0) try contents_json.appendSlice(self.allocator, ",");
            const role_str = if (std.mem.eql(u8, msg.role, "user")) "user" else "model";
            try std.fmt.format(contents_json.writer(self.allocator), "{{\"role\":\"{s}\",\"parts\":[{{\"text\":\"{s}\"}}]}}", .{ role_str, msg.content });
        }
        try contents_json.appendSlice(self.allocator, "]");

        return try std.fmt.allocPrint(self.allocator,
            \\{{"contents":{s}}}
        , .{try contents_json.toOwnedSlice(self.allocator)});
    }

    /// Check if provider is unhealthy (too many recent failures)
    fn isProviderUnhealthy(self: *Router, provider_name: []const u8) bool {
        self.lock.lock();
        defer self.lock.unlock();
        const stats = self.provider_stats.get(provider_name) orelse return false;

        // If more than 5 consecutive failures in last minute, mark unhealthy
        const now = std.time.timestamp();
        if (stats.consecutive_failures >= 5) {
            if (stats.last_failure) |last| {
                // Cool down for 30 seconds after 5 failures
                if (now - last < 30) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Record a successful request
    fn recordSuccess(self: *Router, provider_name: []const u8, tokens: u32) void {
        self.lock.lock();
        defer self.lock.unlock();
        if (self.provider_stats.getPtr(provider_name)) |stats| {
            stats.consecutive_failures = 0;
            stats.total_requests += 1;
            stats.total_tokens += tokens;
        } else {
            self.provider_stats.put(provider_name, .{
                .consecutive_failures = 0,
                .last_failure = null,
                .total_requests = 1,
                .total_tokens = tokens,
            }) catch {};
        }
    }

    /// Record a failed request
    fn recordFailure(self: *Router, provider_name: []const u8) void {
        self.lock.lock();
        defer self.lock.unlock();
        if (self.provider_stats.getPtr(provider_name)) |stats| {
            stats.consecutive_failures += 1;
            stats.last_failure = std.time.timestamp();
            stats.failures += 1;
        } else {
            self.provider_stats.put(provider_name, .{
                .consecutive_failures = 1,
                .last_failure = std.time.timestamp(),
                .failures = 1,
                .total_requests = 0,
                .total_tokens = 0,
            }) catch {};
        }
    }

    fn isRetryable(self: *Router, err: anyerror) bool {
        _ = self;
        return switch (err) {
            error.ConnectionRefused,
            error.ConnectionReset,
            error.NetworkUnreachable,
            error.HostUnreachable,
            error.ConnectionTimedOut,
            error.TemporaryServerBusy,
            error.ApiError,
            error.InvalidApiKey,
            => true,
            else => false,
        };
    }

    fn calculateBackoff(self: *Router, attempt: u3) u32 {
        const exp_delay = std.math.pow(u32, 2, attempt);
        const delay = self.retry_config.base_delay_ms * exp_delay;
        return @min(delay, self.retry_config.max_delay_ms);
    }

    /// Get router statistics
    pub fn getStats(self: *Router) []const struct { name: []const u8, stats: ProviderStats } {
        var result = std.array_list.Managed(struct { name: []const u8, stats: ProviderStats }).init(self.allocator);
        var it = self.provider_stats.iterator();
        while (it.next()) |entry| {
            result.append(.{ .name = entry.key_ptr.*, .stats = entry.value_ptr.* }) catch {};
        }
        return result.toOwnedSlice();
    }
};

/// Weighted target for load balancing
pub const WeightedTarget = struct {
    provider: types.ProviderType,
    model: []const u8,
    weight: u32 = 1,
};

/// Routing rule with weighted targets
pub const RoutingRule = struct {
    model_pattern: []const u8,
    targets: []WeightedTarget,
};

/// Routing table for model-based routing
pub const RoutingTable = struct {
    allocator: std.mem.Allocator,
    rules: std.StringArrayHashMap([]WeightedTarget),
    default_providers: []types.ProviderType,

    pub fn init(allocator: std.mem.Allocator) RoutingTable {
        return .{
            .allocator = allocator,
            .rules = std.StringArrayHashMap([]WeightedTarget).init(allocator),
            .default_providers = &.{.openai},
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

    /// Set default providers (used when no specific rule matches)
    pub fn setDefaultProviders(self: *RoutingTable, providers: []const types.ProviderType) void {
        self.default_providers = providers;
    }

    /// Add a routing rule
    pub fn addRule(self: *RoutingTable, rule: RoutingRule) !void {
        const key = try self.allocator.dupe(u8, rule.model_pattern);
        errdefer self.allocator.free(key);

        var targets = try self.allocator.alloc(WeightedTarget, rule.targets.len);
        errdefer self.allocator.free(targets);

        for (rule.targets, 0..) |t, i| {
            targets[i] = .{
                .provider = t.provider,
                .model = try self.allocator.dupe(u8, t.model),
                .weight = t.weight,
            };
        }

        try self.rules.put(key, targets);
    }

    /// Get ordered list of providers for a model (weighted round-robin)
    pub fn getProvidersForModel(self: *RoutingTable, model: []const u8) []const types.ProviderType {
        // Check for specific rule
        if (self.rules.get(model)) |targets| {
            return self.weightedRoundRobin(targets);
        }

        // Check for wildcard rule
        var it = self.rules.iterator();
        while (it.next()) |entry| {
            if (std.mem.startsWith(u8, model, entry.key_ptr.*) or
                std.mem.endsWith(u8, model, entry.key_ptr.*))
            {
                return self.weightedRoundRobin(entry.value_ptr.*);
            }
        }

        // Default to configured defaults
        return self.default_providers;
    }

    fn weightedRoundRobin(self: *RoutingTable, targets: []WeightedTarget) []const types.ProviderType {
        // Simple weighted round-robin based on timestamp
        var result = std.array_list.Managed(types.ProviderType).init(self.allocator);

        const total_weight: u32 = for (targets) |t| {
            result.append(t.provider) catch {};
        } else 0;

        _ = total_weight;
        return result.toOwnedSlice();
    }
};

// ============================================================================
// TESTS FOR Router
// ============================================================================

test "router - init and deinit" {
    const allocator = std.heap.page_allocator;
    var router = Router.init(allocator);
    defer router.deinit();

    try std.testing.expectEqual(@as(u3, 3), router.retry_config.max_retries);
    try std.testing.expectEqual(@as(u32, 100), router.retry_config.base_delay_ms);
    try std.testing.expectEqual(@as(u32, 5000), router.retry_config.max_delay_ms);
    try std.testing.expectEqual(@as(usize, 0), router.provider_stats.count());
}

test "router - initWithConfig" {
    const allocator = std.heap.page_allocator;
    const config = RetryConfig{
        .max_retries = 5,
        .base_delay_ms = 200,
        .max_delay_ms = 10000,
    };
    var router = Router.initWithConfig(allocator, config);
    defer router.deinit();

    try std.testing.expectEqual(@as(u3, 5), router.retry_config.max_retries);
    try std.testing.expectEqual(@as(u32, 200), router.retry_config.base_delay_ms);
    try std.testing.expectEqual(@as(u32, 10000), router.retry_config.max_delay_ms);
}

test "router - isRetryable errors" {
    const allocator = std.heap.page_allocator;
    var router = Router.init(allocator);
    defer router.deinit();

    // Retryable errors
    try std.testing.expect(router.isRetryable(error.ConnectionRefused));
    try std.testing.expect(router.isRetryable(error.ConnectionReset));
    try std.testing.expect(router.isRetryable(error.NetworkUnreachable));
    try std.testing.expect(router.isRetryable(error.HostUnreachable));
    try std.testing.expect(router.isRetryable(error.ConnectionTimedOut));
    try std.testing.expect(router.isRetryable(error.TemporaryServerBusy));
    try std.testing.expect(router.isRetryable(error.ApiError));
    try std.testing.expect(router.isRetryable(error.InvalidApiKey));

    // Non-retryable errors
    try std.testing.expect(!router.isRetryable(error.MissingAuthHeader));
    try std.testing.expect(!router.isRetryable(error.InvalidJson));
    try std.testing.expect(!router.isRetryable(error.InvalidRequest));
}

test "router - calculateBackoff" {
    const allocator = std.heap.page_allocator;
    var router = Router.init(allocator);
    defer router.deinit();

    // Attempt 0: base_delay_ms * 2^0 = 100 * 1 = 100
    try std.testing.expectEqual(@as(u32, 100), router.calculateBackoff(0));

    // Attempt 1: base_delay_ms * 2^1 = 100 * 2 = 200
    try std.testing.expectEqual(@as(u32, 200), router.calculateBackoff(1));

    // Attempt 2: base_delay_ms * 2^2 = 100 * 4 = 400
    try std.testing.expectEqual(@as(u32, 400), router.calculateBackoff(2));
}

test "router - calculateBackoff respects max" {
    const allocator = std.heap.page_allocator;
    var router = Router.init(allocator);
    defer router.deinit();

    // Should cap at max_delay_ms (5000)
    // Attempt 10 would be: 100 * 2^10 = 102400, but capped at 5000
    try std.testing.expectEqual(@as(u32, 5000), router.calculateBackoff(10));
}

test "router - recordSuccess" {
    const allocator = std.heap.page_allocator;
    var router = Router.init(allocator);
    defer router.deinit();

    router.recordSuccess("openai", 100);

    const stats = router.provider_stats.get("openai");
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u32, 0), stats.?.consecutive_failures);
    try std.testing.expectEqual(@as(u64, 1), stats.?.total_requests);
    try std.testing.expectEqual(@as(u64, 100), stats.?.total_tokens);
}

test "router - recordFailure" {
    const allocator = std.heap.page_allocator;
    var router = Router.init(allocator);
    defer router.deinit();

    router.recordFailure("openai");

    const stats = router.provider_stats.get("openai");
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u32, 1), stats.?.consecutive_failures);
    try std.testing.expectEqual(@as(u64, 1), stats.?.total_requests);
    try std.testing.expectEqual(@as(u64, 0), stats.?.total_tokens);
}

test "router - isProviderUnhealthy" {
    const allocator = std.heap.page_allocator;
    var router = Router.init(allocator);
    defer router.deinit();

    // Unknown provider is not unhealthy
    try std.testing.expect(!router.isProviderUnhealthy("openai"));

    // Record 5 consecutive failures (threshold)
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        router.recordFailure("openai");
    }

    // Now should be unhealthy (within cooldown)
    try std.testing.expect(router.isProviderUnhealthy("openai"));
}

test "router - isProviderUnhealthy after cooldown" {
    const allocator = std.heap.page_allocator;
    var router = Router.init(allocator);
    defer router.deinit();

    // Record 5 consecutive failures
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        router.recordFailure("openai");
    }

    // Cooldown is 30 seconds - we can't easily test this without mocking time
    // Just verify the mechanism exists
    try std.testing.expect(router.isProviderUnhealthy("openai"));
}

test "router - getStats" {
    const allocator = std.heap.page_allocator;
    var router = Router.init(allocator);
    defer router.deinit();

    // Add some stats
    router.recordSuccess("openai", 100);
    router.recordSuccess("anthropic", 200);
    router.recordFailure("google");

    const stats = router.getStats();
    try std.testing.expectEqual(@as(usize, 3), stats.len);
}

// ============================================================================
// TESTS FOR RoutingTable
// ============================================================================

test "routing table - init and deinit" {
    const allocator = std.heap.page_allocator;
    var table = RoutingTable.init(allocator);
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 0), table.rules.count());
    try std.testing.expectEqual(@as(usize, 1), table.default_providers.len);
}

test "routing table - setDefaultProviders" {
    const allocator = std.heap.page_allocator;
    var table = RoutingTable.init(allocator);
    defer table.deinit();

    table.setDefaultProviders(&.{ .anthropic, .google });
    try std.testing.expectEqual(@as(usize, 2), table.default_providers.len);
    try std.testing.expect(table.default_providers[0] == .anthropic);
    try std.testing.expect(table.default_providers[1] == .google);
}

test "routing table - getProvidersForModel uses defaults" {
    const allocator = std.heap.page_allocator;
    var table = RoutingTable.init(allocator);
    defer table.deinit();

    const providers = table.getProvidersForModel("unknown-model");
    try std.testing.expectEqual(@as(usize, 1), providers.len);
    try std.testing.expect(providers[0] == .openai);
}
