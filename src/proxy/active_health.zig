//! Active Health Checker for Edge Routing
//!
//! Implements active health probing to detect provider issues before
//! they cause request failures. Unlike passive health tracking (which
//! only tracks failures from actual requests), active probing periodically
//! sends lightweight requests to verify provider availability.
//!
//! Key features for edge routing:
//!   - Configurable probe interval (default 30 seconds)
//!   - Lightweight endpoint probing (model list endpoint or health endpoint)
//!   - Timeout for probe requests (default 5 seconds)
//!   - Consecutive success/failure threshold for state transitions
//!   - Integration with existing HealthChecker for state management

const std = @import("std");
const provider_types = @import("types");
const registry = @import("registry");

pub const ActiveHealthCheckerConfig = struct {
    probe_interval_ms: u32 = 30000, // How often to probe (30 seconds)
    probe_timeout_ms: u32 = 5000, // Timeout for each probe (5 seconds)
    success_threshold: u32 = 2, // Successes needed to mark healthy
    failure_threshold: u32 = 2, // Failures needed to mark unhealthy
    enabled: bool = true, // Enable active probing
};

pub const ActiveHealthChecker = struct {
    allocator: std.mem.Allocator,
    config: ActiveHealthCheckerConfig,
    probe_state: std.StringArrayHashMap(ProbeState),
    lock: std.Thread.Mutex,
    last_probe_time: i64 = 0,

    pub const ProbeState = struct {
        consecutive_successes: u32 = 0,
        consecutive_failures: u32 = 0,
        is_healthy: bool = true,
        last_probe: i64 = 0,
        last_latency_ms: u64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator, config: ActiveHealthCheckerConfig) ActiveHealthChecker {
        return .{
            .allocator = allocator,
            .config = config,
            .probe_state = std.StringArrayHashMap(ProbeState).init(allocator),
            .lock = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *ActiveHealthChecker) void {
        self.probe_state.deinit();
    }

    /// Check if it's time to run a probe cycle
    pub fn shouldProbe(self: *ActiveHealthChecker) bool {
        if (!self.config.enabled) return false;

        self.lock.lock();
        defer self.lock.unlock();

        const now = std.time.timestamp();
        const time_since_last = (now - self.last_probe_time) * 1000;
        return time_since_last >= self.config.probe_interval_ms;
    }

    /// Record a successful probe
    pub fn recordProbeSuccess(self: *ActiveHealthChecker, provider: provider_types.ProviderType, latency_ms: u64) void {
        self.lock.lock();
        defer self.lock.unlock();

        const provider_name = provider.toString();
        var state = self.probe_state.getOrPut(provider_name) catch return;
        if (!state.found_existing) {
            state.value_ptr.* = .{};
        }

        state.value_ptr.consecutive_successes += 1;
        state.value_ptr.consecutive_failures = 0;
        state.value_ptr.last_probe = std.time.timestamp();
        state.value_ptr.last_latency_ms = latency_ms;

        // Transition to healthy after success_threshold successes
        if (state.value_ptr.consecutive_successes >= self.config.success_threshold) {
            state.value_ptr.is_healthy = true;
        }
    }

    /// Record a failed probe
    pub fn recordProbeFailure(self: *ActiveHealthChecker, provider: provider_types.ProviderType) void {
        self.lock.lock();
        defer self.lock.unlock();

        const provider_name = provider.toString();
        var state = self.probe_state.getOrPut(provider_name) catch return;
        if (!state.found_existing) {
            state.value_ptr.* = .{};
        }

        state.value_ptr.consecutive_failures += 1;
        state.value_ptr.consecutive_successes = 0;
        state.value_ptr.last_probe = std.time.timestamp();

        // Transition to unhealthy after failure_threshold failures
        if (state.value_ptr.consecutive_failures >= self.config.failure_threshold) {
            state.value_ptr.is_healthy = false;
        }
    }

    /// Check if a provider is healthy based on active probing
    pub fn isHealthy(self: *ActiveHealthChecker, provider: provider_types.ProviderType) bool {
        self.lock.lock();
        defer self.lock.unlock();

        const provider_name = provider.toString();
        const state = self.probe_state.get(provider_name) orelse return true; // Default healthy
        return state.is_healthy;
    }

    /// Get probe state for a provider
    pub fn getProbeState(self: *ActiveHealthChecker, provider: provider_types.ProviderType) ?ProbeState {
        self.lock.lock();
        defer self.lock.unlock();

        const provider_name = provider.toString();
        return self.probe_state.get(provider_name);
    }

    /// Mark that a probe cycle completed
    pub fn markProbeCycleComplete(self: *ActiveHealthChecker) void {
        self.lock.lock();
        defer self.lock.unlock();

        self.last_probe_time = std.time.timestamp();
    }

    /// Get the target endpoint for probing a provider
    /// Returns a lightweight endpoint that can be used to check provider health
    pub fn getProbeEndpoint(provider: provider_types.ProviderType) []const u8 {
        return switch (provider) {
            .openai => "/v1/models",
            .anthropic => "/v1/messages",
            .google => "/v1beta/models",
            .moonshot => "/v1/models",
            .minimax => "/v1/models",
            .deepseek => "/v1/models",
            .cohere => "/v1/models",
            .fireworks => "/v1/models",
            .cerebras => "/v1/models",
            .mistral => "/v1/models",
            .perplexity => "/v1/models",
            .openai_compatible => "/v1/models",
            .custom => "/v1/models",
        };
    }

    /// Check if all enabled providers are healthy
    pub fn areAllProvidersHealthy(self: *ActiveHealthChecker) bool {
        self.lock.lock();
        defer self.lock.unlock();

        var it = self.probe_state.iterator();
        while (it.next()) |entry| {
            if (!entry.value_ptr.is_healthy) {
                return false;
            }
        }
        return true;
    }

    /// Get count of healthy vs unhealthy providers
    pub fn getHealthSummary(self: *ActiveHealthChecker) struct { healthy: usize, unhealthy: usize } {
        self.lock.lock();
        defer self.lock.unlock();

        var healthy: usize = 0;
        var unhealthy: usize = 0;

        var it = self.probe_state.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.is_healthy) {
                healthy += 1;
            } else {
                unhealthy += 1;
            }
        }
        return .{ .healthy = healthy, .unhealthy = unhealthy };
    }

    /// Reset probe state for all providers
    pub fn resetAll(self: *ActiveHealthChecker) void {
        self.lock.lock();
        defer self.lock.unlock();

        var it = self.probe_state.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.* = .{};
        }
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "active health checker - init and deinit" {
    const allocator = std.heap.page_allocator;
    var checker = ActiveHealthChecker.init(allocator, .{
        .probe_interval_ms = 30000,
        .probe_timeout_ms = 5000,
        .success_threshold = 2,
        .failure_threshold = 2,
    });
    defer checker.deinit();

    try std.testing.expect(checker.config.enabled);
    try std.testing.expectEqual(@as(u32, 30000), checker.config.probe_interval_ms);
    try std.testing.expectEqual(@as(usize, 0), checker.probe_state.count());
}

test "active health checker - shouldProbe when disabled" {
    const allocator = std.heap.page_allocator;
    var checker = ActiveHealthChecker.init(allocator, .{
        .enabled = false,
    });
    defer checker.deinit();

    try std.testing.expect(!checker.shouldProbe());
}

test "active health checker - shouldProbe when enabled" {
    const allocator = std.heap.page_allocator;
    var checker = ActiveHealthChecker.init(allocator, .{
        .enabled = true,
        .probe_interval_ms = 30000,
    });
    defer checker.deinit();

    // First probe should succeed since last_probe_time is 0
    try std.testing.expect(checker.shouldProbe());
}

test "active health checker - isHealthy for unknown provider" {
    const allocator = std.heap.page_allocator;
    var checker = ActiveHealthChecker.init(allocator, .{});
    defer checker.deinit();

    // Unknown provider is considered healthy
    try std.testing.expect(checker.isHealthy(.openai));
}

test "active health checker - consecutive successes mark healthy" {
    const allocator = std.heap.page_allocator;
    var checker = ActiveHealthChecker.init(allocator, .{
        .success_threshold = 2,
    });
    defer checker.deinit();

    // First success - still not enough
    checker.recordProbeSuccess(.openai, 100);
    try std.testing.expect(checker.isHealthy(.openai)); // Default true, not yet confirmed

    // Second success - threshold reached
    checker.recordProbeSuccess(.openai, 100);
    try std.testing.expect(checker.isHealthy(.openai));
}

test "active health checker - consecutive failures mark unhealthy" {
    const allocator = std.heap.page_allocator;
    var checker = ActiveHealthChecker.init(allocator, .{
        .failure_threshold = 2,
    });
    defer checker.deinit();

    // First failure - still healthy
    checker.recordProbeFailure(.openai);
    try std.testing.expect(checker.isHealthy(.openai));

    // Second failure - threshold reached, now unhealthy
    checker.recordProbeFailure(.openai);
    try std.testing.expect(!checker.isHealthy(.openai));
}

test "active health checker - success resets failure count" {
    const allocator = std.heap.page_allocator;
    var checker = ActiveHealthChecker.init(allocator, .{
        .success_threshold = 1,
        .failure_threshold = 3,
    });
    defer checker.deinit();

    // Two failures
    checker.recordProbeFailure(.openai);
    checker.recordProbeFailure(.openai);
    try std.testing.expect(checker.isHealthy(.openai)); // Still at 2, threshold is 3

    // Third failure - now unhealthy
    checker.recordProbeFailure(.openai);
    try std.testing.expect(!checker.isHealthy(.openai));

    // Success resets
    checker.recordProbeSuccess(.openai, 100);
    try std.testing.expect(checker.isHealthy(.openai));
}

test "active health checker - getProbeState" {
    const allocator = std.heap.page_allocator;
    var checker = ActiveHealthChecker.init(allocator, .{});
    defer checker.deinit();

    // Unknown provider has no state
    const state = checker.getProbeState(.openai);
    try std.testing.expect(state == null);

    // After probing
    checker.recordProbeSuccess(.openai, 150);
    const state2 = checker.getProbeState(.openai);
    try std.testing.expect(state2 != null);
    try std.testing.expectEqual(@as(u32, 1), state2.?.consecutive_successes);
    try std.testing.expectEqual(@as(u64, 150), state2.?.last_latency_ms);
}

test "active health checker - areAllProvidersHealthy" {
    const allocator = std.heap.page_allocator;
    var checker = ActiveHealthChecker.init(allocator, .{});
    defer checker.deinit();

    // No providers probed yet - all healthy (empty)
    try std.testing.expect(checker.areAllProvidersHealthy());

    // Add some providers
    checker.recordProbeSuccess(.openai, 100);
    checker.recordProbeSuccess(.anthropic, 200);

    try std.testing.expect(checker.areAllProvidersHealthy());

    // Mark one unhealthy
    checker.recordProbeFailure(.google);
    checker.recordProbeFailure(.google);

    try std.testing.expect(!checker.areAllProvidersHealthy());
}

test "active health checker - getHealthSummary" {
    const allocator = std.heap.page_allocator;
    var checker = ActiveHealthChecker.init(allocator, .{});
    defer checker.deinit();

    var summary = checker.getHealthSummary();
    try std.testing.expectEqual(@as(usize, 0), summary.healthy);
    try std.testing.expectEqual(@as(usize, 0), summary.unhealthy);

    checker.recordProbeSuccess(.openai, 100);
    checker.recordProbeFailure(.anthropic);
    checker.recordProbeFailure(.anthropic);

    summary = checker.getHealthSummary();
    try std.testing.expectEqual(@as(usize, 1), summary.healthy);
    try std.testing.expectEqual(@as(usize, 1), summary.unhealthy);
}

test "active health checker - resetAll" {
    const allocator = std.heap.page_allocator;
    var checker = ActiveHealthChecker.init(allocator, .{});
    defer checker.deinit();

    // Add state
    checker.recordProbeFailure(.openai);
    checker.recordProbeFailure(.openai);
    try std.testing.expect(!checker.isHealthy(.openai));

    // Reset
    checker.resetAll();

    // Should be back to initial state
    const state = checker.getProbeState(.openai);
    try std.testing.expect(state == null); // Reset clears all state
}

test "active health checker - getProbeEndpoint" {
    try std.testing.expectEqualStrings("/v1/models", ActiveHealthChecker.getProbeEndpoint(.openai));
    try std.testing.expectEqualStrings("/v1/messages", ActiveHealthChecker.getProbeEndpoint(.anthropic));
    try std.testing.expectEqualStrings("/v1beta/models", ActiveHealthChecker.getProbeEndpoint(.google));
    try std.testing.expectEqualStrings("/v1/models", ActiveHealthChecker.getProbeEndpoint(.moonshot));
    try std.testing.expectEqualStrings("/v1/models", ActiveHealthChecker.getProbeEndpoint(.deepseek));
}
