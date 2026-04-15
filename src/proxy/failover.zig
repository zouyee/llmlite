//! Failover Manager for llmlite Proxy
//!
//! Manages automatic failover to backup providers when primary provider fails.
//! Features:
//! - Deduplication (prevents multiple simultaneous failover attempts)
//! - Provider state tracking
//! - Automatic recovery detection

const std = @import("std");
const provider_types = @import("types");

pub const FailoverConfig = struct {
    enabled: bool = true,
    max_retries: u32 = 3,
    retry_delay_ms: u32 = 1000,
    cooldown_period_ms: u32 = 30000,
};

pub const ProviderState = enum {
    healthy,
    degraded,
    unhealthy,
    offline,
};

pub const FailoverEvent = struct {
    timestamp: i64,
    app_type: []const u8,
    from_provider: []const u8,
    to_provider: []const u8,
    reason: []const u8,
    success: bool,
};

pub const FailoverManager = struct {
    allocator: std.mem.Allocator,
    config: FailoverConfig,
    pending_switches: std.StringArrayHashMap(i64),
    provider_states: std.StringArrayHashMap(ProviderState),
    cooldown_endpoints: std.StringArrayHashMap(i64),
    event_history: std.ArrayList(FailoverEvent),

    pub fn init(allocator: std.mem.Allocator, config: FailoverConfig) FailoverManager {
        return .{
            .allocator = allocator,
            .config = config,
            .pending_switches = std.StringArrayHashMap(i64).init(allocator),
            .provider_states = std.StringArrayHashMap(ProviderState).init(allocator),
            .cooldown_endpoints = std.StringArrayHashMap(i64).init(allocator),
            .event_history = std.ArrayList(FailoverEvent).init(allocator),
        };
    }

    pub fn deinit(self: *FailoverManager) void {
        var it = self.pending_switches.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.pending_switches.deinit();

        it = self.provider_states.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.provider_states.deinit();

        var cit = self.cooldown_endpoints.iterator();
        while (cit.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.cooldown_endpoints.deinit();

        for (self.event_history.items) |event| {
            self.allocator.free(event.app_type);
            self.allocator.free(event.from_provider);
            self.allocator.free(event.to_provider);
            self.allocator.free(event.reason);
        }
        self.event_history.deinit();
    }

    /// Check if failover is allowed (not in cooldown, not already pending)
    pub fn canFailover(self: *FailoverManager, app_type: []const u8, provider_id: []const u8) bool {
        if (!self.config.enabled) return false;

        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ app_type, provider_id });
        defer self.allocator.free(key);

        // Check if switch is pending
        if (self.pending_switches.contains(key)) {
            return false;
        }

        // Check cooldown
        if (self.cooldown_endpoints.get(key)) |cooldown_end| {
            const now = std.time.timestamp() * 1000;
            if (now < cooldown_end) {
                return false;
            }
        }

        return true;
    }

    /// Record a provider failure
    pub fn recordFailure(self: *FailoverManager, app_type: []const u8, provider: provider_types.ProviderType) void {
        const provider_name = provider.toString();
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ app_type, provider_name });
        defer self.allocator.free(key);

        self.provider_states.put(key, .unhealthy) catch return;
    }

    /// Record a provider success (recovery)
    pub fn recordSuccess(self: *FailoverManager, app_type: []const u8, provider: provider_types.ProviderType) void {
        const provider_name = provider.toString();
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ app_type, provider_name });
        defer self.allocator.free(key);

        self.provider_states.put(key, .healthy) catch return;

        // Clear cooldown on success
        _ = self.cooldown_endpoints.fetchRemove(key);
    }

    /// Get provider state
    pub fn getProviderState(self: *FailoverManager, app_type: []const u8, provider: provider_types.ProviderType) ProviderState {
        const provider_name = provider.toString();
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ app_type, provider_name });
        defer self.allocator.free(key);

        return self.provider_states.get(key) orelse .healthy;
    }

    /// Start a failover attempt (marks as pending)
    pub fn startFailover(self: *FailoverManager, app_type: []const u8, provider_id: []const u8) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ app_type, provider_id });
        errdefer self.allocator.free(key);

        try self.pending_switches.put(key, std.time.timestamp());
    }

    /// End a failover attempt
    pub fn endFailover(self: *FailoverManager, app_type: []const u8, provider_id: []const u8, success: bool) void {
        const key = std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ app_type, provider_id }) catch return;
        defer self.allocator.free(key);

        _ = self.pending_switches.fetchRemove(key);

        if (!success) {
            // Set cooldown on failure
            const cooldown_end = std.time.timestamp() * 1000 + self.config.cooldown_period_ms;
            self.cooldown_endpoints.put(key, cooldown_end) catch return;
        }
    }

    /// Get best available provider from a list
    pub fn selectBestProvider(self: *FailoverManager, providers: []const provider_types.ProviderType, app_type: []const u8) ?provider_types.ProviderType {
        var best: ?provider_types.ProviderType = null;
        var best_state: ProviderState = .offline;

        for (providers) |provider| {
            const state = self.getProviderState(app_type, provider);

            // Priority: healthy > degraded > unhealthy > offline
            const state_priority = switch (state) {
                .healthy => 0,
                .degraded => 1,
                .unhealthy => 2,
                .offline => 3,
            };

            const best_priority = switch (best_state) {
                .healthy => 0,
                .degraded => 1,
                .unhealthy => 2,
                .offline => 3,
            };

            if (state_priority < best_priority) {
                best = provider;
                best_state = state;
            }
        }

        return best;
    }

    /// Record a failover event
    pub fn recordEvent(self: *FailoverManager, event: FailoverEvent) !void {
        const event_copy = FailoverEvent{
            .timestamp = event.timestamp,
            .app_type = try self.allocator.dupe(u8, event.app_type),
            .from_provider = try self.allocator.dupe(u8, event.from_provider),
            .to_provider = try self.allocator.dupe(u8, event.to_provider),
            .reason = try self.allocator.dupe(u8, event.reason),
            .success = event.success,
        };
        try self.event_history.append(event_copy);
    }

    /// Get recent failover events
    pub fn getRecentEvents(self: *FailoverManager, limit: usize) []const FailoverEvent {
        if (self.event_history.items.len <= limit) {
            return self.event_history.items;
        }
        return self.event_history.items[self.event_history.items.len - limit ..];
    }

    /// Check if any provider is available for failover
    pub fn hasAvailableProvider(self: *FailoverManager, providers: []const provider_types.ProviderType, app_type: []const u8) bool {
        for (providers) |provider| {
            const state = self.getProviderState(app_type, provider);
            if (state != .offline) {
                return true;
            }
        }
        return false;
    }

    /// Reset all provider states
    pub fn resetAllStates(self: *FailoverManager) void {
        var it = self.provider_states.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.provider_states.clearRetainingCapacity();
    }

    /// Get failover statistics
    pub fn getStats(self: *FailoverManager) struct {
        total_events: usize,
        recent_successes: usize,
        recent_failures: usize,
        pending_switches: usize,
        unhealthy_providers: usize,
    } {
        var recent_successes: usize = 0;
        var recent_failures: usize = 0;

        const cutoff = std.time.timestamp() - 300; // Last 5 minutes
        for (self.event_history.items) |event| {
            if (event.timestamp >= cutoff) {
                if (event.success) {
                    recent_successes += 1;
                } else {
                    recent_failures += 1;
                }
            }
        }

        var unhealthy_providers: usize = 0;
        var it = self.provider_states.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == .unhealthy or entry.value_ptr.* == .offline) {
                unhealthy_providers += 1;
            }
        }

        return .{
            .total_events = self.event_history.items.len,
            .recent_successes = recent_successes,
            .recent_failures = recent_failures,
            .pending_switches = self.pending_switches.count(),
            .unhealthy_providers = unhealthy_providers,
        };
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "FailoverManager.init and deinit" {
    const allocator = std.heap.page_allocator;
    const config = FailoverConfig{
        .enabled = true,
        .max_retries = 3,
        .retry_delay_ms = 1000,
        .cooldown_period_ms = 30000,
    };

    var manager = FailoverManager.init(allocator, config);
    defer manager.deinit();

    try std.testing.expect(manager.config.enabled == true);
    try std.testing.expect(manager.config.max_retries == 3);
}

test "FailoverManager.canFailover - enabled config allows failover" {
    const allocator = std.heap.page_allocator;
    const config = FailoverConfig{
        .enabled = true,
        .max_retries = 3,
        .retry_delay_ms = 1000,
        .cooldown_period_ms = 30000,
    };

    var manager = FailoverManager.init(allocator, config);
    defer manager.deinit();

    try std.testing.expect(manager.canFailover("claude", "openai"));
}

test "FailoverManager.canFailover - disabled config blocks failover" {
    const allocator = std.heap.page_allocator;
    const config = FailoverConfig{
        .enabled = false,
        .max_retries = 3,
        .retry_delay_ms = 1000,
        .cooldown_period_ms = 30000,
    };

    var manager = FailoverManager.init(allocator, config);
    defer manager.deinit();

    try std.testing.expect(!manager.canFailover("claude", "openai"));
}

test "FailoverManager.recordFailure - sets provider to unhealthy" {
    const allocator = std.heap.page_allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, config);
    defer manager.deinit();

    manager.recordFailure("claude", .openai);

    const state = manager.getProviderState("claude", .openai);
    try std.testing.expect(state == .unhealthy);
}

test "FailoverManager.recordSuccess - sets provider to healthy" {
    const allocator = std.heap.page_allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, config);
    defer manager.deinit();

    // First record a failure
    manager.recordFailure("claude", .openai);
    try std.testing.expect(manager.getProviderState("claude", .openai) == .unhealthy);

    // Then record success (recovery)
    manager.recordSuccess("claude", .openai);
    try std.testing.expect(manager.getProviderState("claude", .openai) == .healthy);
}

test "FailoverManager.getProviderState - unknown provider is healthy" {
    const allocator = std.heap.page_allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, config);
    defer manager.deinit();

    const state = manager.getProviderState("claude", .openai);
    try std.testing.expect(state == .healthy);
}

test "FailoverManager.startFailover and endFailover - pending state" {
    const allocator = std.heap.page_allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, config);
    defer manager.deinit();

    // Initially can failover
    try std.testing.expect(manager.canFailover("claude", "openai"));

    // Start failover
    try manager.startFailover("claude", "openai");

    // Now cannot failover (pending)
    try std.testing.expect(!manager.canFailover("claude", "openai"));

    // End failover with success
    manager.endFailover("claude", "openai", true);

    // Can failover again
    try std.testing.expect(manager.canFailover("claude", "openai"));
}

test "FailoverManager.endFailover - failure sets cooldown" {
    const allocator = std.heap.page_allocator;
    const config = FailoverConfig{
        .enabled = true,
        .max_retries = 3,
        .retry_delay_ms = 1000,
        .cooldown_period_ms = 30000, // 30 seconds
    };
    var manager = FailoverManager.init(allocator, config);
    defer manager.deinit();

    // Start and end with failure
    try manager.startFailover("claude", "openai");
    manager.endFailover("claude", "openai", false);

    // Cannot failover due to cooldown
    try std.testing.expect(!manager.canFailover("claude", "openai"));
}

test "FailoverManager.selectBestProvider - selects healthy over unhealthy" {
    const allocator = std.heap.page_allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, config);
    defer manager.deinit();

    // Mark openai as unhealthy
    manager.recordFailure("claude", .openai);

    const providers = &.{ .openai, .anthropic };
    const best = manager.selectBestProvider(providers, "claude");

    try std.testing.expect(best != null);
    try std.testing.expect(best.? == .anthropic);
}

test "FailoverManager.selectBestProvider - selects healthy over degraded" {
    const allocator = std.heap.page_allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, config);
    defer manager.deinit();

    // Mark openai as degraded (via state directly)
    const key_openai = try std.fmt.allocPrint(allocator, "claude:openai", .{});
    defer allocator.free(key_openai);
    try manager.provider_states.put(key_openai, .degraded);

    const providers = &.{ .openai, .anthropic };
    const best = manager.selectBestProvider(providers, "claude");

    try std.testing.expect(best != null);
    try std.testing.expect(best.? == .anthropic);
}

test "FailoverManager.hasAvailableProvider - returns true when providers available" {
    const allocator = std.heap.page_allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, config);
    defer manager.deinit();

    const providers = &.{ .openai, .anthropic };
    try std.testing.expect(manager.hasAvailableProvider(providers, "claude"));
}

test "FailoverManager.hasAvailableProvider - returns false when all offline" {
    const allocator = std.heap.page_allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, config);
    defer manager.deinit();

    // Mark all as offline
    const key_openai = try std.fmt.allocPrint(allocator, "claude:openai", .{});
    defer allocator.free(key_openai);
    try manager.provider_states.put(key_openai, .offline);

    const key_anthropic = try std.fmt.allocPrint(allocator, "claude:anthropic", .{});
    defer allocator.free(key_anthropic);
    try manager.provider_states.put(key_anthropic, .offline);

    const providers = &.{ .openai, .anthropic };
    try std.testing.expect(!manager.hasAvailableProvider(providers, "claude"));
}

test "FailoverManager.recordEvent - records events" {
    const allocator = std.heap.page_allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, config);
    defer manager.deinit();

    const event = FailoverEvent{
        .timestamp = std.time.timestamp(),
        .app_type = "claude",
        .from_provider = "openai",
        .to_provider = "anthropic",
        .reason = "circuit_open",
        .success = true,
    };

    try manager.recordEvent(event);

    const events = manager.getRecentEvents(10);
    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0].success == true);
}

test "FailoverManager.getStats - returns correct stats" {
    const allocator = std.heap.page_allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, config);
    defer manager.deinit();

    const stats = manager.getStats();
    try std.testing.expect(stats.total_events == 0);
    try std.testing.expect(stats.pending_switches == 0);
    try std.testing.expect(stats.unhealthy_providers == 0);
}

test "FailoverManager.resetAllStates - clears all states" {
    const allocator = std.heap.page_allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, config);
    defer manager.deinit();

    // Mark providers as unhealthy
    manager.recordFailure("claude", .openai);
    manager.recordFailure("claude", .anthropic);

    try std.testing.expect(manager.provider_states.count() > 0);

    // Reset
    manager.resetAllStates();

    try std.testing.expect(manager.provider_states.count() == 0);
}
