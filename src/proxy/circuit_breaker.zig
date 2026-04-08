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
    failure_threshold: u32 = 3, // Failures before opening
    recovery_timeout_ms: u32 = 30000, // Time before attempting recovery
    half_open_success_threshold: u32 = 2, // Successes needed to close
    success_window: usize = 5, // Window for success rate calculation
};

pub const CircuitBreaker = struct {
    allocator: std.mem.Allocator,
    config: CircuitBreakerConfig,
    circuits: std.StringArrayHashMap(CircuitStateData),
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
            .lock = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *CircuitBreaker) void {
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
