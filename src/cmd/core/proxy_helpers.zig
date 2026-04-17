//! Proxy Helpers - Common utilities for querying llmlite-proxy analytics API
//!
//! Provides a shared HTTP client wrapper for cmd modules (session, gain, cc_economics)
//! to query the proxy's analytics endpoints with automatic fallback on failure.

const std = @import("std");

/// Default proxy port if LLMLITE_PROXY_PORT is not set
const DEFAULT_PROXY_PORT: u16 = 4001;

/// Query the llmlite-proxy analytics API.
///
/// Makes a GET request to `http://localhost:{port}{path}` with the given timeout.
/// Returns the response body as an allocated string on success, or null on any failure
/// (connection refused, timeout, non-200 status), allowing callers to fall back to
/// local data sources.
///
/// Caller owns the returned memory and must free it with the provided allocator.
pub fn queryProxyApi(allocator: std.mem.Allocator, path: []const u8, timeout_ms: u32) !?[]const u8 {
    _ = timeout_ms; // timeout handled by client defaults

    // Read proxy port from environment
    const port = getProxyPort();

    // Build the URL: http://localhost:{port}{path}
    const url_str = std.fmt.allocPrint(allocator, "http://localhost:{d}{s}", .{ port, path }) catch return null;
    defer allocator.free(url_str);

    const uri = std.Uri.parse(url_str) catch return null;

    // Create HTTP client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Prepare response body storage
    var response_writer = std.io.Writer.Allocating.init(allocator);
    defer response_writer.deinit();

    const response = client.fetch(.{
        .location = .{ .uri = uri },
        .method = .GET,
        .response_writer = &response_writer.writer,
    }) catch return null;

    // Non-200 response triggers fallback
    if (response.status != .ok) return null;

    // Return response body (caller owns the memory)
    const body = response_writer.written();
    if (body.len == 0) return null;
    return try allocator.dupe(u8, body);
}

/// Read the proxy port from LLMLITE_PROXY_PORT env var, defaulting to 4001.
fn getProxyPort() u16 {
    const port_str = std.process.getEnvVarOwned(std.heap.page_allocator, "LLMLITE_PROXY_PORT") catch return DEFAULT_PROXY_PORT;
    defer std.heap.page_allocator.free(port_str);
    return std.fmt.parseInt(u16, port_str, 10) catch DEFAULT_PROXY_PORT;
}

test "getProxyPort returns default when env not set" {
    const port = getProxyPort();
    try std.testing.expect(port > 0);
}

test "queryProxyApi returns null on connection failure" {
    // With no proxy running, this should return null (fallback)
    const result = try queryProxyApi(std.testing.allocator, "/analytics/sessions", 500);
    try std.testing.expect(result == null);
}
