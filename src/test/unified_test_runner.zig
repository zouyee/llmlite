//! Unified Test Runner - Runs all unit tests together
//!
//! This module imports all testable proxy components and runs their inline tests.
//! Run with: zig build unified-test
//!
//! Test categories:
//! - Proxy error handling tests
//! - Rate limiting tests
//! - Circuit breaker tests
//! - Latency/health tracking tests

const std = @import("std");

// Import all proxy modules to make their inline tests available
const error_handler = @import("proxy_error_handler");
const rate_limit = @import("proxy_rate_limit");
const latency_health = @import("latency_health");
const circuit_breaker = @import("circuit_breaker");

// Re-export types for convenience
const ProviderType = @import("types").ProviderType;

test "unified test imports" {
    // Basic test to verify all modules are importable
    try std.testing.expect(true);
}

// ============================================================================
// Error Handler Tests
// ============================================================================

test "error_handler.normalizeError - MissingAuthHeader" {
    const err = error_handler.normalizeError(error.MissingAuthHeader, null);
    try std.testing.expectEqual(error_handler.ProxyErrorCode.authentication_error, err.code);
    try std.testing.expectEqual(@as(u16, 401), err.status);
}

test "error_handler.normalizeError - InvalidApiKey" {
    const err = error_handler.normalizeError(error.InvalidApiKey, null);
    try std.testing.expectEqual(error_handler.ProxyErrorCode.authentication_error, err.code);
    try std.testing.expectEqual(@as(u16, 401), err.status);
}

test "error_handler.normalizeError - RateLimitExceeded" {
    const err = error_handler.normalizeError(error.RateLimitExceeded, null);
    try std.testing.expectEqual(error_handler.ProxyErrorCode.rate_limit_exceeded, err.code);
    try std.testing.expectEqual(@as(u16, 429), err.status);
}

test "error_handler.normalizeError - ModelNotAllowed" {
    const err = error_handler.normalizeError(error.ModelNotAllowed, null);
    try std.testing.expectEqual(error_handler.ProxyErrorCode.permission_denied, err.code);
    try std.testing.expectEqual(@as(u16, 403), err.status);
}

test "error_handler.normalizeError - ModelNotFound" {
    const err = error_handler.normalizeError(error.ModelNotFound, null);
    try std.testing.expectEqual(error_handler.ProxyErrorCode.model_not_found, err.code);
    try std.testing.expectEqual(@as(u16, 404), err.status);
}

test "error_handler.normalizeError - ConnectionRefused (service unavailable)" {
    const err = error_handler.normalizeError(error.ConnectionRefused, null);
    try std.testing.expectEqual(error_handler.ProxyErrorCode.service_unavailable, err.code);
    try std.testing.expectEqual(@as(u16, 503), err.status);
}

test "error_handler.normalizeError - unknown error" {
    const err = error_handler.normalizeError(error.FileNotFound, null);
    try std.testing.expectEqual(error_handler.ProxyErrorCode.internal_error, err.code);
    try std.testing.expectEqual(@as(u16, 500), err.status);
}

test "error_handler.getStatusText" {
    try std.testing.expectEqualStrings("Bad Request", error_handler.getStatusText(400));
    try std.testing.expectEqualStrings("Unauthorized", error_handler.getStatusText(401));
    try std.testing.expectEqualStrings("Forbidden", error_handler.getStatusText(403));
    try std.testing.expectEqualStrings("Not Found", error_handler.getStatusText(404));
    try std.testing.expectEqualStrings("Too Many Requests", error_handler.getStatusText(429));
    try std.testing.expectEqualStrings("Internal Server Error", error_handler.getStatusText(500));
    try std.testing.expectEqualStrings("Service Unavailable", error_handler.getStatusText(503));
}

test "error_handler.formatErrorJson" {
    const err = error_handler.NormalizedError{
        .code = .invalid_request,
        .message = "Test error message",
        .reason = "Test reason",
        .provider_code = null,
        .status = 400,
    };

    const allocator = std.heap.page_allocator;
    const json = try error_handler.formatErrorJson(err, allocator);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "Test error message") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "Test reason") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "400") != null);
}

// ============================================================================
// Rate Limiter Tests
// ============================================================================

test "rate_limit.RateLimiter.init" {
    const allocator = std.heap.page_allocator;
    var limiter = rate_limit.RateLimiter.init(allocator);
    defer limiter.deinit();
    try std.testing.expect(limiter.windows.count() == 0);
}

test "rate_limit.RateLimiter.check within limit" {
    const allocator = std.heap.page_allocator;
    var limiter = rate_limit.RateLimiter.init(allocator);
    defer limiter.deinit();

    // First request should be allowed
    const allowed = try limiter.check("test-key", 10);
    try std.testing.expect(allowed);
}

test "rate_limit.RateLimiter.check exceeds limit" {
    const allocator = std.heap.page_allocator;
    var limiter = rate_limit.RateLimiter.init(allocator);
    defer limiter.deinit();

    // Exhaust the limit (limit is 5)
    const key = "exhaust-key";
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        _ = try limiter.check(key, 1);
    }

    // Next request should be denied
    const allowed = try limiter.check(key, 1);
    try std.testing.expect(!allowed);
}

test "rate_limit.RateLimiter.getCount" {
    const allocator = std.heap.page_allocator;
    var limiter = rate_limit.RateLimiter.init(allocator);
    defer limiter.deinit();

    const key = "count-key";
    try std.testing.expectEqual(@as(u32, 0), limiter.getCount(key));

    _ = try limiter.check(key, 1);
    try std.testing.expectEqual(@as(u32, 1), limiter.getCount(key));

    _ = try limiter.check(key, 1);
    try std.testing.expectEqual(@as(u32, 2), limiter.getCount(key));
}

test "rate_limit.RateLimiter.reset" {
    const allocator = std.heap.page_allocator;
    var limiter = rate_limit.RateLimiter.init(allocator);
    defer limiter.deinit();

    const key = "reset-key";
    _ = try limiter.check(key, 5);
    try std.testing.expectEqual(@as(u32, 5), limiter.getCount(key));

    limiter.reset(key);
    try std.testing.expectEqual(@as(u32, 0), limiter.getCount(key));
}

// ============================================================================
// Circuit Breaker Tests
// ============================================================================

test "circuit_breaker.CircuitBreaker.init" {
    const allocator = std.heap.page_allocator;
    var cb = circuit_breaker.CircuitBreaker.init(allocator, .{
        .failure_threshold = 3,
        .recovery_timeout_ms = 30000,
    });
    defer cb.deinit();
    try std.testing.expect(cb.getState(.openai) == .closed);
}

test "circuit_breaker.CircuitBreaker.recordSuccess" {
    const allocator = std.heap.page_allocator;
    var cb = circuit_breaker.CircuitBreaker.init(allocator, .{
        .failure_threshold = 3,
        .recovery_timeout_ms = 30000,
    });
    defer cb.deinit();

    // Record some successes
    cb.recordSuccess(.openai);
    cb.recordSuccess(.openai);
    try std.testing.expect(cb.getState(.openai) == .closed);
}

test "circuit_breaker.CircuitBreaker.recordFailure transitions to open" {
    const allocator = std.heap.page_allocator;
    var cb = circuit_breaker.CircuitBreaker.init(allocator, .{
        .failure_threshold = 3,
        .recovery_timeout_ms = 30000,
    });
    defer cb.deinit();

    // Record enough failures to trip the circuit breaker
    cb.recordFailure(.openai);
    cb.recordFailure(.openai);
    cb.recordFailure(.openai);

    try std.testing.expect(cb.getState(.openai) == .open);
}

test "circuit_breaker.CircuitBreaker.isOpen when closed" {
    const allocator = std.heap.page_allocator;
    var cb = circuit_breaker.CircuitBreaker.init(allocator, .{
        .failure_threshold = 3,
        .recovery_timeout_ms = 30000,
    });
    defer cb.deinit();

    // isOpen returns false when circuit is closed (allowing requests)
    const is_open = cb.isOpen(.openai);
    try std.testing.expect(!is_open);
}

test "circuit_breaker.CircuitBreaker.forceState halfOpen allows requests" {
    const allocator = std.heap.page_allocator;
    var cb = circuit_breaker.CircuitBreaker.init(allocator, .{
        .failure_threshold = 3,
        .recovery_timeout_ms = 30000,
    });
    defer cb.deinit();

    // Force to half-open state
    cb.forceState(.openai, .half_open);
    try std.testing.expect(cb.getState(.openai) == .half_open);
    // Half-open isOpen returns false (allows request through)
    try std.testing.expect(!cb.isOpen(.openai));
}

// ============================================================================
// Health Checker Tests
// ============================================================================

test "latency_health.HealthChecker.init" {
    const allocator = std.heap.page_allocator;
    var checker = latency_health.HealthChecker.init(allocator, 10000, 5000);
    defer checker.deinit();
    try std.testing.expect(checker.check_interval_ms == 10000);
    try std.testing.expect(checker.timeout_ms == 5000);
}

test "latency_health.LatencyTracker.init" {
    const allocator = std.heap.page_allocator;
    var tracker = latency_health.LatencyTracker.init(allocator, 10);
    defer tracker.deinit();
    try std.testing.expect(tracker.window_size == 10);
}

test "latency_health.LatencyTracker.record" {
    const allocator = std.heap.page_allocator;
    var tracker = latency_health.LatencyTracker.init(allocator, 10);
    defer tracker.deinit();

    tracker.record(.openai, 100);
    tracker.record(.openai, 200);
    tracker.record(.openai, 150);

    // getMovingAvg returns average
    const avg = tracker.getMovingAvg(.openai);
    try std.testing.expect(avg == 150); // (100+200+150)/3 = 150
}

test "latency_health.LatencyTracker.getMovingAvg" {
    const allocator = std.heap.page_allocator;
    var tracker = latency_health.LatencyTracker.init(allocator, 10);
    defer tracker.deinit();

    tracker.record(.openai, 100);
    tracker.record(.openai, 200);

    const avg = tracker.getMovingAvg(.openai);
    try std.testing.expect(avg == 150);
}

test "latency_health.LatencyTracker.getPercentile" {
    const allocator = std.heap.page_allocator;
    var tracker = latency_health.LatencyTracker.init(allocator, 10);
    defer tracker.deinit();

    tracker.record(.openai, 100);
    tracker.record(.openai, 200);
    tracker.record(.openai, 300);

    const p50 = tracker.getPercentile(.openai, 50);
    try std.testing.expect(p50 == 200); // median
}
