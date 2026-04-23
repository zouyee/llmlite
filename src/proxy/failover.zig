//! Failover Manager for llmlite Proxy
//!
//! Manages automatic failover to backup providers when primary provider fails.
//! Features:
//! - Deduplication (prevents multiple simultaneous failover attempts)
//! - Provider state tracking
//! - Automatic recovery detection
//! - SwitchLock for concurrent switch prevention
//! - Hot swap provider support

const std = @import("std");
const provider_types = @import("types");
const time_compat = @import("time_compat");

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

/// SwitchLock prevents concurrent provider switches for the same app_type:provider_id.
/// Uses std.Io.Mutex to protect the active_switches map.
pub const SwitchLock = struct {
    lock: std.Io.Mutex,
    active_switches: std.array_hash_map.String(bool),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SwitchLock {
        return .{
            .lock = std.Io.Mutex.init,
            .active_switches = std.array_hash_map.String(bool){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SwitchLock) void {
        var it = self.active_switches.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.active_switches.deinit(self.allocator);
    }

    /// Try to acquire the switch lock for the given key.
    /// Returns false if the key is already locked (another switch is in progress).
    pub fn tryAcquire(self: *SwitchLock, io: std.Io, key: []const u8) bool {
        self.lock.lock(io) catch return false;
        defer self.lock.unlock(io);

        if (self.active_switches.contains(key)) {
            return false;
        }

        const owned_key = self.allocator.dupe(u8, key) catch return false;
        self.active_switches.put(self.allocator, owned_key, true) catch {
            self.allocator.free(owned_key);
            return false;
        };
        return true;
    }

    /// Release the switch lock for the given key.
    pub fn release(self: *SwitchLock, io: std.Io, key: []const u8) void {
        self.lock.lock(io) catch return;
        defer self.lock.unlock(io);

        if (self.active_switches.fetchSwapRemove(key)) |entry| {
            self.allocator.free(entry.key);
        }
    }
};

pub const FailoverManager = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    config: FailoverConfig,
    pending_switches: std.array_hash_map.String(i64),
    provider_states: std.array_hash_map.String(ProviderState),
    cooldown_endpoints: std.array_hash_map.String(i64),
    event_history: std.array_list.Managed(FailoverEvent),
    switch_lock: SwitchLock,
    /// Tracks current provider per app_type for hot swap
    current_providers: std.array_hash_map.String([]const u8),
    lock: std.Io.Mutex,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, config: FailoverConfig) FailoverManager {
        return .{
            .allocator = allocator,
            .io = io,
            .config = config,
            .pending_switches = std.array_hash_map.String(i64){},
            .provider_states = std.array_hash_map.String(ProviderState){},
            .cooldown_endpoints = std.array_hash_map.String(i64){},
            .event_history = std.array_list.Managed(FailoverEvent).init(allocator),
            .switch_lock = SwitchLock.init(allocator),
            .current_providers = std.array_hash_map.String([]const u8){},
            .lock = std.Io.Mutex.init,
        };
    }

    pub fn deinit(self: *FailoverManager) void {
        var it = self.pending_switches.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.pending_switches.deinit(self.allocator);

        var pit = self.provider_states.iterator();
        while (pit.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.provider_states.deinit(self.allocator);

        var cit = self.cooldown_endpoints.iterator();
        while (cit.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.cooldown_endpoints.deinit(self.allocator);

        for (self.event_history.items) |event| {
            self.allocator.free(event.app_type);
            self.allocator.free(event.from_provider);
            self.allocator.free(event.to_provider);
            self.allocator.free(event.reason);
        }
        self.event_history.deinit();

        self.switch_lock.deinit();

        var cp_it = self.current_providers.iterator();
        while (cp_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.current_providers.deinit(self.allocator);
    }

    /// Check if failover is allowed (not in cooldown, not already pending, not switch-locked)
    pub fn canFailover(self: *FailoverManager, app_type: []const u8, provider_id: []const u8) bool {
        if (!self.config.enabled) return false;

        self.lock.lock(self.io) catch return false;
        defer self.lock.unlock(self.io);

        // Build the composite key
        var buf: [512]u8 = undefined;
        const key = std.fmt.bufPrint(&buf, "{s}:{s}", .{ app_type, provider_id }) catch return false;

        // Check SwitchLock deduplication
        if (self.switch_lock.active_switches.contains(key)) {
            return false;
        }

        // Check if switch is pending
        if (self.pending_switches.contains(key)) {
            return false;
        }

        // Check cooldown
        if (self.cooldown_endpoints.get(key)) |cooldown_end| {
            const now = time_compat.timestamp(self.io) * 1000;
            if (now < cooldown_end) {
                return false;
            }
        }

        return true;
    }

    /// Record a provider failure
    pub fn recordFailure(self: *FailoverManager, app_type: []const u8, provider: provider_types.ProviderType) void {
        self.lock.lock(self.io) catch return;
        defer self.lock.unlock(self.io);

        const provider_name = provider.toString();
        var buf: [512]u8 = undefined;
        const key = std.fmt.bufPrint(&buf, "{s}:{s}", .{ app_type, provider_name }) catch return;

        const data = self.provider_states.getOrPut(self.allocator, key) catch return;
        if (!data.found_existing) {
            const owned_key = self.allocator.dupe(u8, key) catch return;
            data.key_ptr.* = owned_key;
        }
        data.value_ptr.* = .unhealthy;
    }

    /// Record a provider success (recovery)
    pub fn recordSuccess(self: *FailoverManager, app_type: []const u8, provider: provider_types.ProviderType) void {
        self.lock.lock(self.io) catch return;
        defer self.lock.unlock(self.io);

        const provider_name = provider.toString();
        var buf: [512]u8 = undefined;
        const key = std.fmt.bufPrint(&buf, "{s}:{s}", .{ app_type, provider_name }) catch return;

        const data = self.provider_states.getOrPut(self.allocator, key) catch return;
        if (!data.found_existing) {
            const owned_key = self.allocator.dupe(u8, key) catch return;
            data.key_ptr.* = owned_key;
        }
        data.value_ptr.* = .healthy;

        // Clear cooldown on success
        if (self.cooldown_endpoints.fetchSwapRemove(key)) |entry| {
            self.allocator.free(entry.key);
        }
    }

    /// Get provider state
    pub fn getProviderState(self: *FailoverManager, app_type: []const u8, provider: provider_types.ProviderType) ProviderState {
        self.lock.lock(self.io) catch return .healthy;
        defer self.lock.unlock(self.io);

        const provider_name = provider.toString();
        var buf: [512]u8 = undefined;
        const key = std.fmt.bufPrint(&buf, "{s}:{s}", .{ app_type, provider_name }) catch return .healthy;

        return self.provider_states.get(key) orelse .healthy;
    }

    /// Start a failover attempt (marks as pending)
    pub fn startFailover(self: *FailoverManager, app_type: []const u8, provider_id: []const u8) !void {
        self.lock.lock(self.io) catch return error.OutOfMemory;
        defer self.lock.unlock(self.io);

        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ app_type, provider_id });
        errdefer self.allocator.free(key);

        try self.pending_switches.put(self.allocator, key, time_compat.timestamp(self.io));
    }

    /// End a failover attempt
    pub fn endFailover(self: *FailoverManager, app_type: []const u8, provider_id: []const u8, success: bool) void {
        self.lock.lock(self.io) catch return;
        defer self.lock.unlock(self.io);

        var buf: [512]u8 = undefined;
        const key = std.fmt.bufPrint(&buf, "{s}:{s}", .{ app_type, provider_id }) catch return;

        if (self.pending_switches.fetchSwapRemove(key)) |entry| {
            self.allocator.free(entry.key);
        }

        if (!success) {
            // Set cooldown on failure
            const cooldown_end = time_compat.timestamp(self.io) * 1000 + self.config.cooldown_period_ms;
            const owned_key = self.allocator.dupe(u8, key) catch return;
            self.cooldown_endpoints.put(self.allocator, owned_key, cooldown_end) catch {
                self.allocator.free(owned_key);
            };
        }
    }

    /// Hot swap provider for an app_type without restart.
    /// Acquires SwitchLock, updates current provider, records event, releases lock.
    /// Returns true if swap succeeded, false if lock was held.
    pub fn hotSwapProvider(self: *FailoverManager, app_type: []const u8, new_provider_id: []const u8) !bool {
        var buf: [512]u8 = undefined;
        const key = std.fmt.bufPrint(&buf, "{s}:{s}", .{ app_type, new_provider_id }) catch return false;

        // Try to acquire the switch lock
        if (!self.switch_lock.tryAcquire(self.io, key)) {
            return false;
        }
        // Ensure lock is released even on error
        errdefer self.switch_lock.release(self.io, key);

        self.lock.lock(self.io) catch return false;
        defer self.lock.unlock(self.io);

        // Get old provider for event recording
        const old_provider = if (self.current_providers.get(app_type)) |p| p else "none";

        // Update current provider for this app_type
        const owned_app_type = try self.allocator.dupe(u8, app_type);
        errdefer self.allocator.free(owned_app_type);
        const owned_provider = try self.allocator.dupe(u8, new_provider_id);
        errdefer self.allocator.free(owned_provider);

        if (self.current_providers.fetchSwapRemove(app_type)) |old_entry| {
            self.allocator.free(old_entry.key);
            self.allocator.free(old_entry.value);
        }
        try self.current_providers.put(self.allocator, owned_app_type, owned_provider);

        // Record failover event
        const event = FailoverEvent{
            .timestamp = time_compat.timestamp(self.io),
            .app_type = app_type,
            .from_provider = old_provider,
            .to_provider = new_provider_id,
            .reason = "hot_swap",
            .success = true,
        };
        try self.recordEvent(event);

        // Release the switch lock
        self.switch_lock.release(self.io, key);

        return true;
    }

    /// Get best available provider from a list
    pub fn selectBestProvider(self: *FailoverManager, providers: []const provider_types.ProviderType, app_type: []const u8) ?provider_types.ProviderType {
        self.lock.lock(self.io) catch return null;
        defer self.lock.unlock(self.io);

        var best: ?provider_types.ProviderType = null;
        var best_state: ProviderState = .offline;

        for (providers) |provider| {
            const provider_name = provider.toString();
            var pbuf: [512]u8 = undefined;
            const pkey = std.fmt.bufPrint(&pbuf, "{s}:{s}", .{ app_type, provider_name }) catch continue;
            const state = self.provider_states.get(pkey) orelse .healthy;

            // Priority: healthy > degraded > unhealthy > offline
            const state_priority = switch (state) {
                .healthy => @as(u8, 0),
                .degraded => 1,
                .unhealthy => 2,
                .offline => 3,
            };

            const best_priority = switch (best_state) {
                .healthy => @as(u8, 0),
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

        const cutoff = time_compat.timestamp(self.io) - 300; // Last 5 minutes
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
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const config = FailoverConfig{
        .enabled = true,
        .max_retries = 3,
        .retry_delay_ms = 1000,
        .cooldown_period_ms = 30000,
    };

    var manager = FailoverManager.init(allocator, io, config);
    defer manager.deinit();

    try std.testing.expect(manager.config.enabled == true);
    try std.testing.expect(manager.config.max_retries == 3);
}

test "FailoverManager.canFailover - enabled config allows failover" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const config = FailoverConfig{
        .enabled = true,
        .max_retries = 3,
        .retry_delay_ms = 1000,
        .cooldown_period_ms = 30000,
    };

    var manager = FailoverManager.init(allocator, io, config);
    defer manager.deinit();

    try std.testing.expect(manager.canFailover("claude", "openai"));
}

test "FailoverManager.canFailover - disabled config blocks failover" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const config = FailoverConfig{
        .enabled = false,
        .max_retries = 3,
        .retry_delay_ms = 1000,
        .cooldown_period_ms = 30000,
    };

    var manager = FailoverManager.init(allocator, io, config);
    defer manager.deinit();

    try std.testing.expect(!manager.canFailover("claude", "openai"));
}

test "FailoverManager.recordFailure - sets provider to unhealthy" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, io, config);
    defer manager.deinit();

    manager.recordFailure("claude", .openai);

    const state = manager.getProviderState("claude", .openai);
    try std.testing.expect(state == .unhealthy);
}

test "FailoverManager.recordSuccess - sets provider to healthy" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, io, config);
    defer manager.deinit();

    // First record a failure
    manager.recordFailure("claude", .openai);
    try std.testing.expect(manager.getProviderState("claude", .openai) == .unhealthy);

    // Then record success (recovery)
    manager.recordSuccess("claude", .openai);
    try std.testing.expect(manager.getProviderState("claude", .openai) == .healthy);
}

test "FailoverManager.getProviderState - unknown provider is healthy" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, io, config);
    defer manager.deinit();

    const state = manager.getProviderState("claude", .openai);
    try std.testing.expect(state == .healthy);
}

test "FailoverManager.startFailover and endFailover - pending state" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, io, config);
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
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const config = FailoverConfig{
        .enabled = true,
        .max_retries = 3,
        .retry_delay_ms = 1000,
        .cooldown_period_ms = 30000, // 30 seconds
    };
    var manager = FailoverManager.init(allocator, io, config);
    defer manager.deinit();

    // Start and end with failure
    try manager.startFailover("claude", "openai");
    manager.endFailover("claude", "openai", false);

    // Cannot failover due to cooldown
    try std.testing.expect(!manager.canFailover("claude", "openai"));
}

test "FailoverManager.selectBestProvider - selects healthy over unhealthy" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, io, config);
    defer manager.deinit();

    // Mark openai as unhealthy
    manager.recordFailure("claude", .openai);

    const providers = &.{ .openai, .anthropic };
    const best = manager.selectBestProvider(providers, "claude");

    try std.testing.expect(best != null);
    try std.testing.expect(best.? == .anthropic);
}

test "FailoverManager.hasAvailableProvider - returns true when providers available" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, io, config);
    defer manager.deinit();

    const providers = &.{ .openai, .anthropic };
    try std.testing.expect(manager.hasAvailableProvider(providers, "claude"));
}

test "FailoverManager.recordEvent - records events" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, io, config);
    defer manager.deinit();

    const event = FailoverEvent{
        .timestamp = time_compat.timestamp(io),
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
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, io, config);
    defer manager.deinit();

    const stats = manager.getStats();
    try std.testing.expect(stats.total_events == 0);
    try std.testing.expect(stats.pending_switches == 0);
    try std.testing.expect(stats.unhealthy_providers == 0);
}

test "FailoverManager.resetAllStates - clears all states" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, io, config);
    defer manager.deinit();

    // Mark providers as unhealthy
    manager.recordFailure("claude", .openai);
    manager.recordFailure("claude", .anthropic);

    try std.testing.expect(manager.provider_states.count() > 0);

    // Reset
    manager.resetAllStates();

    try std.testing.expect(manager.provider_states.count() == 0);
}

// ============================================================================
// SwitchLock Tests
// ============================================================================

test "SwitchLock.tryAcquire - acquires lock successfully" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var lock = SwitchLock.init(allocator);
    defer lock.deinit();

    try std.testing.expect(lock.tryAcquire(io, "claude:openai"));
    lock.release(io, "claude:openai");
}

test "SwitchLock.tryAcquire - deduplication rejects second acquire on same key" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var lock = SwitchLock.init(allocator);
    defer lock.deinit();

    // First acquire succeeds
    try std.testing.expect(lock.tryAcquire(io, "claude:openai"));

    // Second acquire on same key fails (deduplication)
    try std.testing.expect(!lock.tryAcquire(io, "claude:openai"));

    // Release and re-acquire succeeds
    lock.release(io, "claude:openai");
    try std.testing.expect(lock.tryAcquire(io, "claude:openai"));
    lock.release(io, "claude:openai");
}

test "SwitchLock.tryAcquire - different keys are independent" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var lock = SwitchLock.init(allocator);
    defer lock.deinit();

    try std.testing.expect(lock.tryAcquire(io, "claude:openai"));
    try std.testing.expect(lock.tryAcquire(io, "codex:anthropic"));

    lock.release(io, "claude:openai");
    lock.release(io, "codex:anthropic");
}

test "SwitchLock.release - releasing non-existent key is safe" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var lock = SwitchLock.init(allocator);
    defer lock.deinit();

    // Should not crash
    lock.release(io, "nonexistent:key");
}

// ============================================================================
// hotSwapProvider Tests
// ============================================================================

test "FailoverManager.hotSwapProvider - basic swap succeeds" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, io, config);
    defer manager.deinit();

    const result = try manager.hotSwapProvider("claude", "anthropic");
    try std.testing.expect(result == true);

    // Verify current provider was updated
    const current = manager.current_providers.get("claude");
    try std.testing.expect(current != null);
    try std.testing.expectEqualStrings("anthropic", current.?);

    // Verify event was recorded
    const events = manager.getRecentEvents(10);
    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0].success == true);
    try std.testing.expectEqualStrings("hot_swap", events[0].reason);
}

test "FailoverManager.hotSwapProvider - swap updates existing provider" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, io, config);
    defer manager.deinit();

    // First swap
    const result1 = try manager.hotSwapProvider("claude", "openai");
    try std.testing.expect(result1 == true);

    // Second swap replaces the first
    const result2 = try manager.hotSwapProvider("claude", "anthropic");
    try std.testing.expect(result2 == true);

    const current = manager.current_providers.get("claude");
    try std.testing.expect(current != null);
    try std.testing.expectEqualStrings("anthropic", current.?);

    // Two events recorded
    try std.testing.expect(manager.event_history.items.len == 2);
}

test "FailoverManager.hotSwapProvider - returns false when lock held" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const config = FailoverConfig{};
    var manager = FailoverManager.init(allocator, io, config);
    defer manager.deinit();

    // Manually acquire the switch lock
    try std.testing.expect(manager.switch_lock.tryAcquire(io, "claude:anthropic"));

    // hotSwapProvider should return false since lock is held
    const result = try manager.hotSwapProvider("claude", "anthropic");
    try std.testing.expect(result == false);

    // Release the lock
    manager.switch_lock.release(io, "claude:anthropic");

    // Now it should succeed
    const result2 = try manager.hotSwapProvider("claude", "anthropic");
    try std.testing.expect(result2 == true);
}

test "FailoverManager.canFailover - blocked by SwitchLock" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const config = FailoverConfig{ .enabled = true };
    var manager = FailoverManager.init(allocator, io, config);
    defer manager.deinit();

    // Initially can failover
    try std.testing.expect(manager.canFailover("claude", "openai"));

    // Acquire switch lock
    try std.testing.expect(manager.switch_lock.tryAcquire(io, "claude:openai"));

    // Now canFailover should return false due to SwitchLock
    try std.testing.expect(!manager.canFailover("claude", "openai"));

    // Release lock
    manager.switch_lock.release(io, "claude:openai");

    // Can failover again
    try std.testing.expect(manager.canFailover("claude", "openai"));
}
