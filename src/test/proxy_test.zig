//! Proxy Component Unit Tests
//!
//! Tests for error_handler, rate_limit, and virtual_key components

const std = @import("std");
const testing = std.testing;

// Import proxy components
const error_handler = @import("proxy_error_handler");
const rate_limit = @import("proxy_rate_limit");
const virtual_key = @import("virtual_key");

test "error_handler.normalizeError - MissingAuthHeader" {
    const err = error_handler.normalizeError(error.MissingAuthHeader, null);
    try testing.expectEqual(error_handler.ProxyErrorCode.authentication_error, err.code);
    try testing.expectEqual(@as(u16, 401), err.status);
}

test "error_handler.normalizeError - InvalidApiKey" {
    const err = error_handler.normalizeError(error.InvalidApiKey, null);
    try testing.expectEqual(error_handler.ProxyErrorCode.authentication_error, err.code);
    try testing.expectEqual(@as(u16, 401), err.status);
}

test "error_handler.normalizeError - RateLimitExceeded" {
    const err = error_handler.normalizeError(error.RateLimitExceeded, null);
    try testing.expectEqual(error_handler.ProxyErrorCode.rate_limit_exceeded, err.code);
    try testing.expectEqual(@as(u16, 429), err.status);
}

test "error_handler.normalizeError - ModelNotAllowed" {
    const err = error_handler.normalizeError(error.ModelNotAllowed, null);
    try testing.expectEqual(error_handler.ProxyErrorCode.permission_denied, err.code);
    try testing.expectEqual(@as(u16, 403), err.status);
}

test "error_handler.normalizeError - ModelNotFound" {
    const err = error_handler.normalizeError(error.ModelNotFound, null);
    try testing.expectEqual(error_handler.ProxyErrorCode.model_not_found, err.code);
    try testing.expectEqual(@as(u16, 404), err.status);
}

test "error_handler.normalizeError - ConnectionRefused (service unavailable)" {
    const err = error_handler.normalizeError(error.ConnectionRefused, null);
    try testing.expectEqual(error_handler.ProxyErrorCode.service_unavailable, err.code);
    try testing.expectEqual(@as(u16, 503), err.status);
}

test "error_handler.normalizeError - unknown error" {
    const err = error_handler.normalizeError(error.FileNotFound, null);
    try testing.expectEqual(error_handler.ProxyErrorCode.internal_error, err.code);
    try testing.expectEqual(@as(u16, 500), err.status);
}

test "error_handler.getStatusText" {
    try testing.expectEqualStrings("Bad Request", error_handler.getStatusText(400));
    try testing.expectEqualStrings("Unauthorized", error_handler.getStatusText(401));
    try testing.expectEqualStrings("Forbidden", error_handler.getStatusText(403));
    try testing.expectEqualStrings("Not Found", error_handler.getStatusText(404));
    try testing.expectEqualStrings("Too Many Requests", error_handler.getStatusText(429));
    try testing.expectEqualStrings("Internal Server Error", error_handler.getStatusText(500));
    try testing.expectEqualStrings("Service Unavailable", error_handler.getStatusText(503));
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

    try testing.expect(std.mem.find(u8, json, "Test error message") != null);
    try testing.expect(std.mem.find(u8, json, "Test reason") != null);
    try testing.expect(std.mem.find(u8, json, "400") != null);
}

test "error_handler.formatErrorJson - with provider_code" {
    const err = error_handler.NormalizedError{
        .code = .authentication_error,
        .message = "Invalid API key",
        .reason = "The API key is invalid",
        .provider_code = "deepseek",
        .status = 401,
    };

    const allocator = std.heap.page_allocator;
    const json = try error_handler.formatErrorJson(err, allocator);
    defer allocator.free(json);

    try testing.expect(std.mem.find(u8, json, "provider_code") != null);
    try testing.expect(std.mem.find(u8, json, "deepseek") != null);
}

test "error_handler.getStatusText - extended" {
    try testing.expectEqualStrings("Payment Required", error_handler.getStatusText(402));
    try testing.expectEqualStrings("Unprocessable Entity", error_handler.getStatusText(422));
}

test "rate_limit.RateLimiter.init" {
    const allocator = std.heap.page_allocator;
    var limiter = rate_limit.RateLimiter.init(allocator);
    defer limiter.deinit();

    // Should initialize with empty windows
    try testing.expectEqual(@as(usize, 0), limiter.windows.count());
}

test "rate_limit.RateLimiter.check - first request" {
    const allocator = std.heap.page_allocator;
    var limiter = rate_limit.RateLimiter.init(allocator);
    defer limiter.deinit();

    // First request should be allowed
    const result = try limiter.check("test-key", 10);
    try testing.expect(result);
}

test "rate_limit.RateLimiter.check - within limit" {
    const allocator = std.heap.page_allocator;
    var limiter = rate_limit.RateLimiter.init(allocator);
    defer limiter.deinit();

    // Make requests within limit
    const limit: u32 = 5;
    var i: u32 = 0;
    while (i < limit) : (i += 1) {
        const result = try limiter.check("test-key", limit);
        try testing.expect(result);
    }
}

test "rate_limit.RateLimiter.getCount" {
    const allocator = std.heap.page_allocator;
    var limiter = rate_limit.RateLimiter.init(allocator);
    defer limiter.deinit();

    // Initially zero
    try testing.expectEqual(@as(u32, 0), limiter.getCount("test-key"));

    // After one request
    _ = try limiter.check("test-key", 10);
    try testing.expectEqual(@as(u32, 1), limiter.getCount("test-key"));

    // After more requests
    _ = try limiter.check("test-key", 10);
    _ = try limiter.check("test-key", 10);
    try testing.expectEqual(@as(u32, 3), limiter.getCount("test-key"));
}

test "rate_limit.RateLimiter.reset" {
    const allocator = std.heap.page_allocator;
    var limiter = rate_limit.RateLimiter.init(allocator);
    defer limiter.deinit();

    // Make some requests
    _ = try limiter.check("test-key", 10);
    _ = try limiter.check("test-key", 10);
    try testing.expectEqual(@as(u32, 2), limiter.getCount("test-key"));

    // Reset
    limiter.reset("test-key");
    try testing.expectEqual(@as(u32, 0), limiter.getCount("test-key"));
}

test "rate_limit.TokenBucketLimiter.init" {
    const allocator = std.heap.page_allocator;
    var limiter = rate_limit.TokenBucketLimiter.init(allocator);
    defer limiter.deinit();

    try testing.expectEqual(@as(usize, 0), limiter.buckets.count());
}

test "rate_limit.TokenBucketLimiter.tryAcquire - first request" {
    const allocator = std.heap.page_allocator;
    var limiter = rate_limit.TokenBucketLimiter.init(allocator);
    defer limiter.deinit();

    // First request should succeed if capacity >= 1
    const result = try limiter.tryAcquire("test-key", 10, 1.0);
    try testing.expect(result);
}

test "rate_limit.TokenBucketLimiter.tryAcquire - depletes tokens" {
    const allocator = std.heap.page_allocator;
    var limiter = rate_limit.TokenBucketLimiter.init(allocator);
    defer limiter.deinit();

    // Request until depleted (capacity 2, refill rate 0)
    var result = try limiter.tryAcquire("test-key", 2, 0.0);
    try testing.expect(result);

    result = try limiter.tryAcquire("test-key", 2, 0.0);
    try testing.expect(result);

    // Now depleted
    result = try limiter.tryAcquire("test-key", 2, 0.0);
    try testing.expect(!result);
}

test "virtual_key.VirtualKeyStore.init" {
    const allocator = std.heap.page_allocator;
    var store = virtual_key.VirtualKeyStore.init(allocator);
    defer store.deinit();

    try testing.expectEqual(@as(usize, 0), store.keys.count());
}

test "virtual_key.VirtualKeyStore.add and validate" {
    const allocator = std.heap.page_allocator;
    var store = virtual_key.VirtualKeyStore.init(allocator);
    defer store.deinit();

    try store.add("test-key", .{
        .user_id = "user-123",
        .rate_limit = 100,
        .allowed_models = null,
    });

    // Validate should succeed
    try store.validate("test-key");
}

test "virtual_key.VirtualKeyStore.validate - invalid key" {
    const allocator = std.heap.page_allocator;
    var store = virtual_key.VirtualKeyStore.init(allocator);
    defer store.deinit();

    // Validate should fail for non-existent key
    const result = store.validate("invalid-key");
    try testing.expectError(error.InvalidVirtualKey, result);
}

test "virtual_key.VirtualKeyStore.checkModelAccess - no restrictions" {
    const allocator = std.heap.page_allocator;
    var store = virtual_key.VirtualKeyStore.init(allocator);
    defer store.deinit();

    try store.add("test-key", .{
        .user_id = "user-123",
        .rate_limit = 100,
        .allowed_models = null, // No restrictions
    });

    const vk = store.keys.get("test-key").?;
    // Should allow any model when no restrictions
    try testing.expect(store.checkModelAccess(vk, "gpt-4o"));
    try testing.expect(store.checkModelAccess(vk, "claude-3"));
    try testing.expect(store.checkModelAccess(vk, "any-model"));
}

test "virtual_key.VirtualKeyStore.checkModelAccess - with restrictions" {
    const allocator = std.heap.page_allocator;
    var store = virtual_key.VirtualKeyStore.init(allocator);
    defer store.deinit();

    try store.add("test-key", .{
        .user_id = "user-123",
        .rate_limit = 100,
        .allowed_models = &.{ "gpt-4o", "gpt-4o-mini" },
    });

    const vk = store.keys.get("test-key").?;
    // Should allow restricted models
    try testing.expect(store.checkModelAccess(vk, "gpt-4o"));
    try testing.expect(store.checkModelAccess(vk, "gpt-4o-mini"));
    // Should deny other models
    try testing.expect(!store.checkModelAccess(vk, "claude-3"));
    try testing.expect(!store.checkModelAccess(vk, "gemini-2"));
}
