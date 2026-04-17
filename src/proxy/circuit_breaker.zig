//! Circuit Breaker for Edge Routing
//!
//! Implements the circuit breaker pattern to prevent cascading failures
//! when backend providers are experiencing issues.
//!
//! States:
//!   CLOSED -> OPEN -> HALF_OPEN -> CLOSED
//!                    or
//!                  -> OPEN
//!
//! Key features for edge routing:
//!   - Fast failure detection (3 consecutive failures opens circuit)
//!   - Configurable recovery timeout (30 seconds default)
//!   - Half-open state to test recovery
//!   - Success threshold to close circuit (2 successes)

const std = @import("std");
const provider_types = @import("types");

pub const CircuitState = enum {
    closed,
    open,
    half_open,
};

pub const CircuitBreakerConfig = struct {
    failure_threshold: u32 = 4, // Failures before opening
    recovery_timeout_ms: u32 = 60000, // Time before attempting recovery
    half_open_success_threshold: u32 = 2, // Successes needed to close
    success_window: usize = 5, // Window for success rate calculation
    error_rate_threshold: f32 = 0.6, // Error rate threshold for opening
    min_requests: u32 = 10, // Minimum requests before error rate applies
    half_open_max_permits: u32 = 1, // Max concurrent requests in HalfOpen
};

pub const AllowResult = struct {
    allowed: bool,
    used_half_open_permit: bool,
};

pub const CircuitBreaker = struct {
    allocator: std.mem.Allocator,
    config: CircuitBreakerConfig,
    circuits: std.StringArrayHashMap(CircuitStateData),
    half_open_permits: std.StringArrayHashMap(u32),
    lock: std.Thread.Mutex,

    pub const CircuitStateData = struct {
        state: CircuitState = .closed,
        consecutive_failures: u32 = 0,
        consecutive_successes: u32 = 0,
        last_failure_time: i64 = 0,
        last_state_change: i64 = 0,
        total_requests: u64 = 0,
        total_failures: u64 = 0,
        total_successes: u64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator, config: CircuitBreakerConfig) CircuitBreaker {
        return .{
            .allocator = allocator,
            .config = config,
            .circuits = std.StringArrayHashMap(CircuitStateData).init(allocator),
            .half_open_permits = std.StringArrayHashMap(u32).init(allocator),
            .lock = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *CircuitBreaker) void {
        self.half_open_permits.deinit();
        self.circuits.deinit();
    }

    /// Check if circuit allows requests
    pub fn isOpen(self: *CircuitBreaker, provider: provider_types.ProviderType) bool {
        self.lock.lock();
        defer self.lock.unlock();

        const provider_name = provider.toString();
        const data = self.circuits.get(provider_name) orelse return false;

        switch (data.state) {
            .closed => return false, // Allow requests
            .open => {
                // Check if recovery timeout has elapsed
                const now = std.time.timestamp();
                const time_since_failure = (now - data.last_failure_time) * 1000;
                if (time_since_failure >= self.config.recovery_timeout_ms) {
                    // Transition to half-open
                    self.transitionState(provider_name, .half_open);
                    return false; // Allow one request to test
                }
                return true; // Block requests
            },
            .half_open => return false, // Allow limited requests
        }
    }

    /// Record a successful request
    pub fn recordSuccess(self: *CircuitBreaker, provider: provider_types.ProviderType) void {
        self.lock.lock();
        defer self.lock.unlock();

        const provider_name = provider.toString();
        var data = self.circuits.getOrPut(provider_name) catch return;
        if (!data.found_existing) {
            data.value_ptr.* = .{};
        }

        data.value_ptr.total_requests += 1;
        data.value_ptr.total_successes += 1;

        switch (data.value_ptr.state) {
            .closed => {
                // Reset failure count on success
                data.value_ptr.consecutive_failures = 0;
            },
            .half_open => {
                data.value_ptr.consecutive_successes += 1;
                // If enough successes in half-open, close the circuit
                if (data.value_ptr.consecutive_successes >= self.config.half_open_success_threshold) {
                    self.transitionState(provider_name, .closed);
                }
            },
            .open => {
                // Shouldn't happen, but reset if it does
                data.value_ptr.consecutive_failures = 0;
            },
        }
    }

    /// Record a failed request
    pub fn recordFailure(self: *CircuitBreaker, provider: provider_types.ProviderType) void {
        self.lock.lock();
        defer self.lock.unlock();

        const provider_name = provider.toString();
        var data = self.circuits.getOrPut(provider_name) catch return;
        if (!data.found_existing) {
            data.value_ptr.* = .{};
        }

        data.value_ptr.total_requests += 1;
        data.value_ptr.total_failures += 1;
        data.value_ptr.consecutive_failures += 1;
        data.value_ptr.last_failure_time = std.time.timestamp();

        switch (data.value_ptr.state) {
            .closed => {
                if (data.value_ptr.consecutive_failures >= self.config.failure_threshold) {
                    self.transitionState(provider_name, .open);
                }
            },
            .half_open => {
                // Any failure in half-open opens the circuit again
                self.transitionState(provider_name, .open);
            },
            .open => {
                // Already open, just update failure count
            },
        }
    }

    /// Get current state of a circuit
    pub fn getState(self: *CircuitBreaker, provider: provider_types.ProviderType) CircuitState {
        self.lock.lock();
        defer self.lock.unlock();

        const provider_name = provider.toString();
        const data = self.circuits.get(provider_name) orelse return .closed;
        return data.state;
    }

    /// Get circuit statistics
    pub fn getStats(self: *CircuitBreaker, provider: provider_types.ProviderType) ?CircuitStateData {
        self.lock.lock();
        defer self.lock.unlock();

        const provider_name = provider.toString();
        return self.circuits.get(provider_name);
    }

    /// Force transition to a specific state (for testing/admin)
    pub fn forceState(self: *CircuitBreaker, provider: provider_types.ProviderType, state: CircuitState) void {
        self.lock.lock();
        defer self.lock.unlock();

        const provider_name = provider.toString();
        const data = self.circuits.getOrPut(provider_name) catch return;
        if (!data.found_existing) {
            data.value_ptr.* = .{};
        }
        self.transitionState(provider_name, state);
    }

    fn transitionState(self: *CircuitBreaker, provider_name: []const u8, new_state: CircuitState) void {
        if (self.circuits.getPtr(provider_name)) |data| {
            data.state = new_state;
            data.last_state_change = std.time.timestamp();

            // Reset counters on state transition
            switch (new_state) {
                .closed => {
                    data.consecutive_failures = 0;
                    data.consecutive_successes = 0;
                },
                .open => {
                    data.consecutive_successes = 0;
                },
                .half_open => {
                    data.consecutive_failures = 0;
                    data.consecutive_successes = 0;
                },
            }
        }
    }

    /// Get all circuits in a specific state
    pub fn getCircuitsByState(self: *CircuitBreaker, state: CircuitState) []const []const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);
        var it = self.circuits.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.state == state) {
                result.append(entry.key_ptr.*) catch {};
            }
        }
        return result.toOwnedSlice();
    }

    /// Reset all circuits to closed state
    pub fn resetAll(self: *CircuitBreaker) void {
        self.lock.lock();
        defer self.lock.unlock();

        var it = self.circuits.iterator();
        while (it.next()) |entry| {
            self.transitionState(entry.key_ptr.*, .closed);
        }
    }

    // ===== New string-key based methods =====

    /// Routing decision: check if a key is available for requests.
    /// Does NOT change any state or counters.
    /// Returns true if Closed or HalfOpen, false if Open (unless timeout elapsed → transition to HalfOpen and return true).
    pub fn isAvailable(self: *CircuitBreaker, key: []const u8) bool {
        self.lock.lock();
        defer self.lock.unlock();

        const data = self.circuits.get(key) orelse return true;

        switch (data.state) {
            .closed => return true,
            .open => {
                const now = std.time.timestamp();
                const time_since_failure = (now - data.last_failure_time) * 1000;
                if (time_since_failure >= self.config.recovery_timeout_ms) {
                    // Transition to half-open
                    self.transitionState(key, .half_open);
                    return true;
                }
                return false;
            },
            .half_open => return true,
        }
    }

    /// Actual request permit: returns whether the request is allowed and whether a HalfOpen permit was used.
    /// In HalfOpen state, limits concurrent requests to half_open_max_permits.
    pub fn allowRequest(self: *CircuitBreaker, key: []const u8) AllowResult {
        self.lock.lock();
        defer self.lock.unlock();

        const data = self.circuits.get(key) orelse return .{ .allowed = true, .used_half_open_permit = false };

        switch (data.state) {
            .closed => return .{ .allowed = true, .used_half_open_permit = false },
            .open => {
                const now = std.time.timestamp();
                const time_since_failure = (now - data.last_failure_time) * 1000;
                if (time_since_failure >= self.config.recovery_timeout_ms) {
                    self.transitionState(key, .half_open);
                    // Try to acquire a half-open permit
                    const current_permits = self.half_open_permits.get(key) orelse 0;
                    if (current_permits < self.config.half_open_max_permits) {
                        self.half_open_permits.put(key, current_permits + 1) catch {};
                        return .{ .allowed = true, .used_half_open_permit = true };
                    }
                    return .{ .allowed = false, .used_half_open_permit = false };
                }
                return .{ .allowed = false, .used_half_open_permit = false };
            },
            .half_open => {
                const current_permits = self.half_open_permits.get(key) orelse 0;
                if (current_permits < self.config.half_open_max_permits) {
                    self.half_open_permits.put(key, current_permits + 1) catch {};
                    return .{ .allowed = true, .used_half_open_permit = true };
                }
                return .{ .allowed = false, .used_half_open_permit = false };
            },
        }
    }

    /// Release a HalfOpen permit without recording success or failure.
    /// Used by rectifier scenarios.
    pub fn releasePermitNeutral(self: *CircuitBreaker, key: []const u8) void {
        self.lock.lock();
        defer self.lock.unlock();

        if (self.half_open_permits.get(key)) |current| {
            if (current > 0) {
                self.half_open_permits.put(key, current - 1) catch {};
            }
        }
    }

    /// Update config without resetting state or counters.
    pub fn updateConfig(self: *CircuitBreaker, config: CircuitBreakerConfig) void {
        self.lock.lock();
        defer self.lock.unlock();

        self.config = config;
    }

    /// Record success using "app_type:provider_id" composite key.
    pub fn recordSuccessForKey(self: *CircuitBreaker, app_type: []const u8, provider_id: []const u8) void {
        const key = self.buildCompositeKey(app_type, provider_id) orelse return;
        defer self.allocator.free(key);
        self.recordSuccessByKey(key);
    }

    /// Record failure using "app_type:provider_id" composite key.
    pub fn recordFailureForKey(self: *CircuitBreaker, app_type: []const u8, provider_id: []const u8) void {
        const key = self.buildCompositeKey(app_type, provider_id) orelse return;
        defer self.allocator.free(key);
        self.recordFailureByKey(key);
    }

    /// Check availability using "app_type:provider_id" composite key.
    pub fn isAvailableForKey(self: *CircuitBreaker, app_type: []const u8, provider_id: []const u8) bool {
        const key = self.buildCompositeKey(app_type, provider_id) orelse return true;
        defer self.allocator.free(key);
        return self.isAvailable(key);
    }

    // ===== Internal helpers for string-key methods =====

    fn buildCompositeKey(self: *CircuitBreaker, app_type: []const u8, provider_id: []const u8) ?[]u8 {
        const key = std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ app_type, provider_id }) catch return null;
        return key;
    }

    fn recordSuccessByKey(self: *CircuitBreaker, key: []const u8) void {
        self.lock.lock();
        defer self.lock.unlock();

        var data = self.circuits.getOrPut(key) catch return;
        if (!data.found_existing) {
            data.value_ptr.* = .{};
        }

        data.value_ptr.total_requests += 1;
        data.value_ptr.total_successes += 1;

        switch (data.value_ptr.state) {
            .closed => {
                data.value_ptr.consecutive_failures = 0;
            },
            .half_open => {
                data.value_ptr.consecutive_successes += 1;
                if (data.value_ptr.consecutive_successes >= self.config.half_open_success_threshold) {
                    self.transitionState(key, .closed);
                    // Clear half-open permits on close
                    _ = self.half_open_permits.fetchSwapRemove(key);
                }
            },
            .open => {
                data.value_ptr.consecutive_failures = 0;
            },
        }
    }

    fn recordFailureByKey(self: *CircuitBreaker, key: []const u8) void {
        self.lock.lock();
        defer self.lock.unlock();

        var data = self.circuits.getOrPut(key) catch return;
        if (!data.found_existing) {
            data.value_ptr.* = .{};
        }

        data.value_ptr.total_requests += 1;
        data.value_ptr.total_failures += 1;
        data.value_ptr.consecutive_failures += 1;
        data.value_ptr.last_failure_time = std.time.timestamp();

        switch (data.value_ptr.state) {
            .closed => {
                if (data.value_ptr.consecutive_failures >= self.config.failure_threshold) {
                    self.transitionState(key, .open);
                }
            },
            .half_open => {
                self.transitionState(key, .open);
                // Clear half-open permits on re-open
                _ = self.half_open_permits.fetchSwapRemove(key);
            },
            .open => {},
        }
    }
};

test "circuit breaker - initial state" {
    const allocator = std.heap.page_allocator;
    var cb = CircuitBreaker.init(allocator, .{
        .failure_threshold = 3,
        .recovery_timeout_ms = 30000,
    });
    defer cb.deinit();

    // Circuit should be closed (allow requests)
    try std.testing.expect(!cb.isOpen(.openai));
}

test "circuit breaker - opens after threshold" {
    const allocator = std.heap.page_allocator;
    var cb = CircuitBreaker.init(allocator, .{
        .failure_threshold = 3,
        .recovery_timeout_ms = 30000,
    });
    defer cb.deinit();

    // Record 3 failures
    cb.recordFailure(.openai);
    try std.testing.expect(!cb.isOpen(.openai)); // Still closed until threshold reached

    cb.recordFailure(.openai);
    try std.testing.expect(!cb.isOpen(.openai));

    cb.recordFailure(.openai);
    try std.testing.expect(cb.isOpen(.openai)); // Now open
}

test "circuit breaker - success resets failure count" {
    const allocator = std.heap.page_allocator;
    var cb = CircuitBreaker.init(allocator, .{
        .failure_threshold = 3,
        .recovery_timeout_ms = 30000,
    });
    defer cb.deinit();

    // Record 2 failures
    cb.recordFailure(.openai);
    cb.recordFailure(.openai);

    // Success resets
    cb.recordSuccess(.openai);

    // Now record 3 more failures - should still open
    cb.recordFailure(.openai);
    cb.recordFailure(.openai);
    cb.recordFailure(.openai);

    try std.testing.expect(cb.isOpen(.openai));
}

test "circuit breaker - getState" {
    const allocator = std.heap.page_allocator;
    var cb = CircuitBreaker.init(allocator, .{
        .failure_threshold = 2,
        .recovery_timeout_ms = 30000,
    });
    defer cb.deinit();

    try std.testing.expect(cb.getState(.openai) == .closed);

    cb.recordFailure(.openai);
    cb.recordFailure(.openai);
    try std.testing.expect(cb.getState(.openai) == .open);
}

test "circuit breaker - forceState" {
    const allocator = std.heap.page_allocator;
    var cb = CircuitBreaker.init(allocator, .{
        .failure_threshold = 3,
        .recovery_timeout_ms = 30000,
    });
    defer cb.deinit();

    // Force to half-open
    cb.forceState(.openai, .half_open);
    try std.testing.expect(cb.getState(.openai) == .half_open);
    try std.testing.expect(!cb.isOpen(.openai)); // Half-open allows requests
}

test "circuit breaker - half open to closed" {
    const allocator = std.heap.page_allocator;
    var cb = CircuitBreaker.init(allocator, .{
        .failure_threshold = 3,
        .recovery_timeout_ms = 30000,
        .half_open_success_threshold = 2,
    });
    defer cb.deinit();

    // Open the circuit
    cb.recordFailure(.openai);
    cb.recordFailure(.openai);
    cb.recordFailure(.openai);
    try std.testing.expect(cb.getState(.openai) == .open);

    // Force to half-open to simulate recovery timeout
    cb.forceState(.openai, .half_open);
    try std.testing.expect(cb.getState(.openai) == .half_open);

    // Record successes in half-open
    cb.recordSuccess(.openai);
    try std.testing.expect(cb.getState(.openai) == .half_open);

    cb.recordSuccess(.openai);
    try std.testing.expect(cb.getState(.openai) == .closed);
}

test "circuit breaker - half open failure reopens" {
    const allocator = std.heap.page_allocator;
    var cb = CircuitBreaker.init(allocator, .{
        .failure_threshold = 3,
        .recovery_timeout_ms = 30000,
    });
    defer cb.deinit();

    // Open the circuit
    cb.recordFailure(.openai);
    cb.recordFailure(.openai);
    cb.recordFailure(.openai);

    // Force to half-open
    cb.forceState(.openai, .half_open);

    // Failure in half-open reopens
    cb.recordFailure(.openai);
    try std.testing.expect(cb.getState(.openai) == .open);
}

test "circuit breaker - stats tracking" {
    const allocator = std.heap.page_allocator;
    var cb = CircuitBreaker.init(allocator, .{
        .failure_threshold = 3,
        .recovery_timeout_ms = 30000,
    });
    defer cb.deinit();

    cb.recordSuccess(.openai);
    cb.recordSuccess(.openai);
    cb.recordFailure(.openai);

    const stats = cb.getStats(.openai);
    try std.testing.expect(stats != null);
    try std.testing.expect(stats.?.total_requests == 3);
    try std.testing.expect(stats.?.total_successes == 2);
    try std.testing.expect(stats.?.total_failures == 1);
}

test "circuit breaker - getCircuitsByState" {
    const allocator = std.heap.page_allocator;
    var cb = CircuitBreaker.init(allocator, .{
        .failure_threshold = 1,
        .recovery_timeout_ms = 30000,
    });
    defer cb.deinit();

    // Open multiple circuits
    cb.recordFailure(.openai); // Opens
    cb.recordFailure(.anthropic); // Opens

    cb.forceState(.google, .half_open);

    const open_circuits = cb.getCircuitsByState(.open);
    try std.testing.expect(open_circuits.len == 2);
}

test "circuit breaker - resetAll" {
    const allocator = std.heap.page_allocator;
    var cb = CircuitBreaker.init(allocator, .{
        .failure_threshold = 1,
        .recovery_timeout_ms = 30000,
    });
    defer cb.deinit();

    // Open circuits
    cb.recordFailure(.openai);
    cb.recordFailure(.anthropic);
    cb.recordFailure(.google);

    // Reset all
    cb.resetAll();

    try std.testing.expect(cb.getState(.openai) == .closed);
    try std.testing.expect(cb.getState(.anthropic) == .closed);
    try std.testing.expect(cb.getState(.google) == .closed);
}

// ===== New tests for enhanced circuit breaker =====

test "circuit breaker - isAvailable does not change state" {
    const allocator = std.heap.page_allocator;
    var cb = CircuitBreaker.init(allocator, .{
        .failure_threshold = 2,
        .recovery_timeout_ms = 60000,
    });
    defer cb.deinit();

    const key = "test_key";

    // For a closed circuit, isAvailable should return true
    const result1 = cb.isAvailable(key);
    try std.testing.expect(result1 == true);

    // Call again - same result, no state change
    const result2 = cb.isAvailable(key);
    try std.testing.expect(result2 == true);

    // No circuit data should have been created (isAvailable doesn't create entries)
    const stats = cb.circuits.get(key);
    try std.testing.expect(stats == null);

    // Now create a circuit with some state via recordFailureByKey
    cb.recordFailureByKey(key);
    cb.recordFailureByKey(key);

    // Should be open now
    {
        const data = cb.circuits.get(key).?;
        try std.testing.expect(data.state == .open);
        const before_requests = data.total_requests;
        const before_failures = data.total_failures;

        // isAvailable should return false (open, timeout not elapsed)
        const avail1 = cb.isAvailable(key);
        try std.testing.expect(avail1 == false);

        // Call again - same result
        const avail2 = cb.isAvailable(key);
        try std.testing.expect(avail2 == false);

        // Counters should not have changed
        const after = cb.circuits.get(key).?;
        try std.testing.expect(after.total_requests == before_requests);
        try std.testing.expect(after.total_failures == before_failures);
    }
}

test "circuit breaker - allowRequest limits HalfOpen to 1 concurrent permit" {
    const allocator = std.heap.page_allocator;
    var cb = CircuitBreaker.init(allocator, .{
        .failure_threshold = 2,
        .recovery_timeout_ms = 60000,
        .half_open_max_permits = 1,
    });
    defer cb.deinit();

    const key = "test_key";

    // Create a circuit and force to half-open
    cb.lock.lock();
    cb.circuits.put(key, .{ .state = .half_open }) catch {};
    cb.lock.unlock();

    // First allowRequest should succeed with half_open permit
    const result1 = cb.allowRequest(key);
    try std.testing.expect(result1.allowed == true);
    try std.testing.expect(result1.used_half_open_permit == true);

    // Second allowRequest should be denied (max 1 permit)
    const result2 = cb.allowRequest(key);
    try std.testing.expect(result2.allowed == false);
    try std.testing.expect(result2.used_half_open_permit == false);

    // Release the permit
    cb.releasePermitNeutral(key);

    // Now should be allowed again
    const result3 = cb.allowRequest(key);
    try std.testing.expect(result3.allowed == true);
    try std.testing.expect(result3.used_half_open_permit == true);
}

test "circuit breaker - releasePermitNeutral releases permit without affecting counters" {
    const allocator = std.heap.page_allocator;
    var cb = CircuitBreaker.init(allocator, .{
        .failure_threshold = 2,
        .recovery_timeout_ms = 60000,
        .half_open_max_permits = 1,
    });
    defer cb.deinit();

    const key = "test_key";

    // Create a circuit in half-open with some stats
    cb.lock.lock();
    cb.circuits.put(key, .{
        .state = .half_open,
        .total_requests = 5,
        .total_successes = 3,
        .total_failures = 2,
    }) catch {};
    cb.lock.unlock();

    // Acquire a permit
    const result = cb.allowRequest(key);
    try std.testing.expect(result.allowed == true);

    // Record counters before release
    const before = cb.circuits.get(key).?;
    const before_requests = before.total_requests;
    const before_successes = before.total_successes;
    const before_failures = before.total_failures;

    // Release permit neutrally
    cb.releasePermitNeutral(key);

    // Counters should be unchanged
    const after = cb.circuits.get(key).?;
    try std.testing.expect(after.total_requests == before_requests);
    try std.testing.expect(after.total_successes == before_successes);
    try std.testing.expect(after.total_failures == before_failures);

    // Permit should be released (can acquire again)
    const result2 = cb.allowRequest(key);
    try std.testing.expect(result2.allowed == true);
}

test "circuit breaker - updateConfig preserves state" {
    const allocator = std.heap.page_allocator;
    var cb = CircuitBreaker.init(allocator, .{
        .failure_threshold = 2,
        .recovery_timeout_ms = 60000,
    });
    defer cb.deinit();

    const key = "test_key";

    // Build up some state
    cb.recordFailureByKey(key);
    cb.recordFailureByKey(key);

    // Should be open
    {
        const data = cb.circuits.get(key).?;
        try std.testing.expect(data.state == .open);
        try std.testing.expect(data.total_requests == 2);
        try std.testing.expect(data.total_failures == 2);
    }

    // Update config
    cb.updateConfig(.{
        .failure_threshold = 10,
        .recovery_timeout_ms = 120000,
        .error_rate_threshold = 0.8,
        .min_requests = 20,
    });

    // State and counters should be preserved
    {
        const data = cb.circuits.get(key).?;
        try std.testing.expect(data.state == .open);
        try std.testing.expect(data.total_requests == 2);
        try std.testing.expect(data.total_failures == 2);
    }

    // Config should be updated
    try std.testing.expect(cb.config.failure_threshold == 10);
    try std.testing.expect(cb.config.recovery_timeout_ms == 120000);
    try std.testing.expect(cb.config.error_rate_threshold == 0.8);
    try std.testing.expect(cb.config.min_requests == 20);
}

test "circuit breaker - ForKey methods work with composite keys independently" {
    const allocator = std.heap.page_allocator;
    var cb = CircuitBreaker.init(allocator, .{
        .failure_threshold = 2,
        .recovery_timeout_ms = 60000,
    });
    defer cb.deinit();

    // Record failures for one composite key
    cb.recordFailureForKey("claude", "provider_a");
    cb.recordFailureForKey("claude", "provider_a");

    // Record success for a different composite key
    cb.recordSuccessForKey("codex", "provider_b");

    // "claude:provider_a" should be open (2 failures >= threshold 2)
    try std.testing.expect(cb.isAvailableForKey("claude", "provider_a") == false);

    // "codex:provider_b" should be available (only successes)
    try std.testing.expect(cb.isAvailableForKey("codex", "provider_b") == true);

    // Verify stats for "claude:provider_a"
    const key_a = "claude:provider_a";
    const stats_a = cb.circuits.get(key_a).?;
    try std.testing.expect(stats_a.total_requests == 2);
    try std.testing.expect(stats_a.total_failures == 2);
    try std.testing.expect(stats_a.state == .open);

    // Verify stats for "codex:provider_b"
    const key_b = "codex:provider_b";
    const stats_b = cb.circuits.get(key_b).?;
    try std.testing.expect(stats_b.total_requests == 1);
    try std.testing.expect(stats_b.total_successes == 1);
    try std.testing.expect(stats_b.state == .closed);
}

test "circuit breaker - allowRequest on closed circuit" {
    const allocator = std.heap.page_allocator;
    var cb = CircuitBreaker.init(allocator, .{
        .failure_threshold = 4,
        .recovery_timeout_ms = 60000,
    });
    defer cb.deinit();

    // Closed circuit should always allow
    const result = cb.allowRequest("any_key");
    try std.testing.expect(result.allowed == true);
    try std.testing.expect(result.used_half_open_permit == false);
}

test "circuit breaker - config defaults" {
    const config = CircuitBreakerConfig{};
    try std.testing.expect(config.failure_threshold == 4);
    try std.testing.expect(config.recovery_timeout_ms == 60000);
    try std.testing.expect(config.error_rate_threshold == 0.6);
    try std.testing.expect(config.min_requests == 10);
    try std.testing.expect(config.half_open_max_permits == 1);
}
