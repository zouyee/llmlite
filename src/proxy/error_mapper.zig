//! Error Mapper for llmlite Proxy
//!
//! Maps ProxyError to HTTP status codes and user-friendly error messages.
//! Generates structured JSON error responses with error codes.

const std = @import("std");

/// Proxy error types
pub const ProxyError = enum {
    timeout,
    forward_failed,
    no_available_provider,
    all_providers_circuit_open,
    transform_error,
    authentication_failed,
    rate_limited,
    upstream_error,
    internal_error,
    no_providers_configured,
    provider_unhealthy,
    max_retries_exceeded,
};

/// Map ProxyError to HTTP status code
///
/// Mapping rules:
/// - timeout: 504 Gateway Timeout
/// - forward_failed: 502 Bad Gateway
/// - no_available_provider: 503 Service Unavailable
/// - all_providers_circuit_open: 503 Service Unavailable
/// - transform_error: 500 Internal Server Error
/// - authentication_failed: 401 Unauthorized
/// - rate_limited: 429 Too Many Requests
/// - upstream_error: 502 Bad Gateway
/// - internal_error: 500 Internal Server Error
/// - no_providers_configured: 503 Service Unavailable
/// - provider_unhealthy: 503 Service Unavailable
/// - max_retries_exceeded: 503 Service Unavailable
pub fn mapProxyErrorToStatus(err: ProxyError) u16 {
    return switch (err) {
        .timeout => 504,
        .forward_failed => 502,
        .no_available_provider => 503,
        .all_providers_circuit_open => 503,
        .transform_error => 500,
        .authentication_failed => 401,
        .rate_limited => 429,
        .upstream_error => 502,
        .internal_error => 500,
        .no_providers_configured => 503,
        .provider_unhealthy => 503,
        .max_retries_exceeded => 503,
    };
}

/// Get user-friendly error message for each error type
pub fn getErrorMessage(err: ProxyError) []const u8 {
    return switch (err) {
        .timeout => "Request timeout",
        .forward_failed => "Forward failed",
        .no_available_provider => "No available provider",
        .all_providers_circuit_open => "All providers circuit open",
        .transform_error => "Transform error",
        .authentication_failed => "Authentication failed",
        .rate_limited => "Rate limited",
        .upstream_error => "Upstream error",
        .internal_error => "Internal error",
        .no_providers_configured => "No providers configured",
        .provider_unhealthy => "Provider unhealthy",
        .max_retries_exceeded => "Max retries exceeded",
    };
}

/// Get the structured error code for each error type
fn getErrorCode(err: ProxyError) []const u8 {
    return switch (err) {
        .timeout => "RSP-004",
        .forward_failed => "FWD-003",
        .no_available_provider => "FO-005",
        .all_providers_circuit_open => "FO-004",
        .transform_error => "RSP-003",
        .authentication_failed => "SRV-007",
        .rate_limited => "SRV-008",
        .upstream_error => "FWD-002",
        .internal_error => "SRV-004",
        .no_providers_configured => "FO-005",
        .provider_unhealthy => "CB-004",
        .max_retries_exceeded => "FWD-001",
    };
}

/// Escape a string for safe inclusion in JSON output.
/// Handles: \, ", and control characters (\n, \r, \t).
fn appendJsonEscaped(list: *std.ArrayList(u8), allocator: std.mem.Allocator, input: []const u8) !void {
    for (input) |c| {
        switch (c) {
            '\\' => try list.appendSlice(allocator, "\\\\"),
            '"' => try list.appendSlice(allocator, "\\\""),
            '\n' => try list.appendSlice(allocator, "\\n"),
            '\r' => try list.appendSlice(allocator, "\\r"),
            '\t' => try list.appendSlice(allocator, "\\t"),
            else => {
                if (c < 0x20) {
                    // Other control characters: encode as \u00XX
                    var buf: [6]u8 = undefined;
                    _ = std.fmt.bufPrint(&buf, "\\u{X:0>4}", .{c}) catch unreachable;
                    try list.appendSlice(allocator, &buf);
                } else {
                    try list.append(allocator, c);
                }
            },
        }
    }
}

/// Format a structured JSON error response.
///
/// Output format:
/// ```json
/// {"error":{"type":"proxy_error","code":"FO-004","message":"All providers circuit open","status":503,"upstream_message":"..."}}
/// ```
///
/// - `allocator`: Memory allocator for the result buffer.
/// - `err`: The proxy error type.
/// - `upstream_msg`: Optional upstream error message to include.
/// - `log_code`: Optional log code override (uses default if null).
///
/// Caller owns the returned slice and must free it with the same allocator.
pub fn formatErrorResponse(
    allocator: std.mem.Allocator,
    err: ProxyError,
    upstream_msg: ?[]const u8,
    log_code: ?[]const u8,
) ![]u8 {
    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);

    const status = mapProxyErrorToStatus(err);
    const message = getErrorMessage(err);
    const code = log_code orelse getErrorCode(err);

    try result.appendSlice(allocator, "{\"error\":{\"type\":\"proxy_error\",\"code\":\"");
    try appendJsonEscaped(&result, allocator, code);
    try result.appendSlice(allocator, "\",\"message\":\"");
    try appendJsonEscaped(&result, allocator, message);
    try result.appendSlice(allocator, "\",\"status\":");
    try result.print(allocator, "{d}", .{status});

    if (upstream_msg) |um| {
        try result.appendSlice(allocator, ",\"upstream_message\":\"");
        try appendJsonEscaped(&result, allocator, um);
        try result.appendSlice(allocator, "\"");
    }

    try result.appendSlice(allocator, "}}");

    return result.toOwnedSlice(allocator);
}

// ============================================================================
// TESTS
// ============================================================================

test "error_mapper - timeout returns 504" {
    try std.testing.expectEqual(@as(u16, 504), mapProxyErrorToStatus(.timeout));
}

test "error_mapper - forward failed returns 502" {
    try std.testing.expectEqual(@as(u16, 502), mapProxyErrorToStatus(.forward_failed));
}

test "error_mapper - no available provider returns 503" {
    try std.testing.expectEqual(@as(u16, 503), mapProxyErrorToStatus(.no_available_provider));
}

test "error_mapper - all providers circuit open returns 503" {
    try std.testing.expectEqual(@as(u16, 503), mapProxyErrorToStatus(.all_providers_circuit_open));
}

test "error_mapper - transform error returns 500" {
    try std.testing.expectEqual(@as(u16, 500), mapProxyErrorToStatus(.transform_error));
}

test "error_mapper - authentication failed returns 401" {
    try std.testing.expectEqual(@as(u16, 401), mapProxyErrorToStatus(.authentication_failed));
}

test "error_mapper - rate limited returns 429" {
    try std.testing.expectEqual(@as(u16, 429), mapProxyErrorToStatus(.rate_limited));
}

test "error_mapper - upstream error returns 502" {
    try std.testing.expectEqual(@as(u16, 502), mapProxyErrorToStatus(.upstream_error));
}

test "error_mapper - internal error returns 500" {
    try std.testing.expectEqual(@as(u16, 500), mapProxyErrorToStatus(.internal_error));
}

test "error_mapper - no providers configured returns 503" {
    try std.testing.expectEqual(@as(u16, 503), mapProxyErrorToStatus(.no_providers_configured));
}

test "error_mapper - provider unhealthy returns 503" {
    try std.testing.expectEqual(@as(u16, 503), mapProxyErrorToStatus(.provider_unhealthy));
}

test "error_mapper - max retries exceeded returns 503" {
    try std.testing.expectEqual(@as(u16, 503), mapProxyErrorToStatus(.max_retries_exceeded));
}

test "error_mapper - all errors map to valid HTTP status codes (4xx/5xx)" {
    const all_errors = std.enums.values(ProxyError);
    for (all_errors) |err| {
        const status = mapProxyErrorToStatus(err);
        try std.testing.expect(status >= 400 and status < 600);
    }
}

test "error_mapper - all errors have non-empty messages" {
    const all_errors = std.enums.values(ProxyError);
    for (all_errors) |err| {
        const msg = getErrorMessage(err);
        try std.testing.expect(msg.len > 0);
    }
}

test "error_mapper - get error message for timeout" {
    try std.testing.expectEqualStrings("Request timeout", getErrorMessage(.timeout));
}

test "error_mapper - get error message for no available provider" {
    try std.testing.expectEqualStrings("No available provider", getErrorMessage(.no_available_provider));
}

test "error_mapper - get error message for upstream error" {
    try std.testing.expectEqualStrings("Upstream error", getErrorMessage(.upstream_error));
}

test "error_mapper - get error message for authentication failed" {
    try std.testing.expectEqualStrings("Authentication failed", getErrorMessage(.authentication_failed));
}

test "error_mapper - get error message for rate limited" {
    try std.testing.expectEqualStrings("Rate limited", getErrorMessage(.rate_limited));
}

test "error_mapper - formatErrorResponse generates valid JSON" {
    const allocator = std.testing.allocator;
    const response = try formatErrorResponse(allocator, .all_providers_circuit_open, null, null);
    defer allocator.free(response);

    // Verify it parses as valid JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    // Verify structure
    const root = parsed.value.object;
    const err_obj = root.get("error").?.object;
    try std.testing.expectEqualStrings("proxy_error", err_obj.get("type").?.string);
    try std.testing.expectEqualStrings("FO-004", err_obj.get("code").?.string);
    try std.testing.expectEqualStrings("All providers circuit open", err_obj.get("message").?.string);
    try std.testing.expectEqual(@as(i64, 503), err_obj.get("status").?.integer);
    // No upstream_message when null
    try std.testing.expect(err_obj.get("upstream_message") == null);
}

test "error_mapper - formatErrorResponse preserves upstream message" {
    const allocator = std.testing.allocator;
    const upstream = "rate limit exceeded for model claude-3";
    const response = try formatErrorResponse(allocator, .upstream_error, upstream, null);
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    const err_obj = parsed.value.object.get("error").?.object;
    try std.testing.expectEqualStrings(upstream, err_obj.get("upstream_message").?.string);
    try std.testing.expectEqual(@as(i64, 502), err_obj.get("status").?.integer);
}

test "error_mapper - formatErrorResponse with custom log code" {
    const allocator = std.testing.allocator;
    const response = try formatErrorResponse(allocator, .timeout, null, "CUSTOM-001");
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    const err_obj = parsed.value.object.get("error").?.object;
    try std.testing.expectEqualStrings("CUSTOM-001", err_obj.get("code").?.string);
}

test "error_mapper - formatErrorResponse escapes special characters in upstream message" {
    const allocator = std.testing.allocator;
    const upstream = "error: \"invalid\" request\nnew line";
    const response = try formatErrorResponse(allocator, .upstream_error, upstream, null);
    defer allocator.free(response);

    // Should be valid JSON even with special chars
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    const err_obj = parsed.value.object.get("error").?.object;
    try std.testing.expectEqualStrings(upstream, err_obj.get("upstream_message").?.string);
}

test "error_mapper - formatErrorResponse for all error types produces valid JSON" {
    const allocator = std.testing.allocator;
    const all_errors = std.enums.values(ProxyError);
    for (all_errors) |err| {
        const response = try formatErrorResponse(allocator, err, "test upstream", null);
        defer allocator.free(response);

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
        defer parsed.deinit();

        const err_obj = parsed.value.object.get("error").?.object;
        try std.testing.expectEqualStrings("proxy_error", err_obj.get("type").?.string);
        try std.testing.expect(err_obj.get("code").?.string.len > 0);
        try std.testing.expect(err_obj.get("message").?.string.len > 0);

        const status = err_obj.get("status").?.integer;
        try std.testing.expect(status >= 400 and status < 600);

        try std.testing.expectEqualStrings("test upstream", err_obj.get("upstream_message").?.string);
    }
}
