//! Proxy Integration Tests
//!
//! Tests the proxy server by starting it and making HTTP requests.
//! This is a standalone test executable, not part of the main test suite.
//!
//! Usage:
//!   zig build proxy-integration-test
//!   ./zig-out/bin/proxy_integration_test
//!
//! Or with custom port:
//!   PROXY_TEST_PORT=4001 ./zig-out/bin/proxy_integration_test

const std = @import("std");
const http = @import("http");

// Test configuration
const TEST_PORT = 4001;
const TEST_API_KEY = "sk-test-key";
const TEST_MODEL = "minimax/MiniMax-M2.7";

/// Simple HTTP client for testing
const TestClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,

    fn init(allocator: std.mem.Allocator, base_url: []const u8) TestClient {
        return .{ .allocator = allocator, .base_url = base_url };
    }

    fn makeRequest(self: *TestClient, method: []const u8, path: []const u8, body: []const u8) ![]u8 {
        const uri = try std.Uri.parse(self.base_url);
        const host = uri.host orelse return error.InvalidUrl;
        const port = uri.port orelse 80;

        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const stream = try client.connect(host, port, .{});
        defer stream.close();

        var req = try stream.request(.{
            .method = if (std.mem.eql(u8, method, "GET")) std.http.Method.GET else std.http.Method.POST,
            .uri = .{ .host = host, .port = port, .path = path, .scheme = uri.scheme },
        });
        defer req.deinit();

        // Add headers
        try req.headers.appendValue("Host", host);
        try req.headers.appendValue("Content-Type", "application/json");
        try req.headers.appendValue("Accept", "application/json");

        if (body.len > 0) {
            try req.headers.appendValue("Content-Length", std.fmt.bufPrint(&[_]u8{}, "{d}", .{body.len}) catch @panic("fmt fail"));
        }

        if (body.len > 0) {
            try req.writeAll(body);
        }

        try req.finish();

        var response_body = std.ArrayList(u8).init(self.allocator);
        errdefer response_body.deinit();

        try req.reader().readAllArrayList(&response_body, 10_000_000);

        return try response_body.toOwnedSlice();
    }

    fn get(self: *TestClient, path: []const u8) ![]u8 {
        return self.makeRequest("GET", path, "");
    }

    fn post(self: *TestClient, path: []const u8, body: []const u8) ![]u8 {
        return self.makeRequest("POST", path, body);
    }
};

/// Test result tracking
const TestResult = struct {
    name: []const u8,
    passed: bool,
    error_message: ?[]const u8 = null,
};

var test_results: [10]TestResult = undefined;
var test_count: usize = 0;

fn recordTest(name: []const u8, passed: bool, err: ?[]const u8) void {
    if (test_count < test_results.len) {
        test_results[test_count] = .{ .name = name, .passed = passed, .error_message = err };
        test_count += 1;
    }
}

pub fn main() !void {
    std.debug.print("\n=== Proxy Integration Tests ===\n\n", .{});

    const allocator = std.heap.page_allocator;
    const port = TEST_PORT;

    // Get port from environment if set
    const env_port = std.process.getEnvVarOwned(allocator, "PROXY_TEST_PORT") catch null;
    const use_port = if (env_port) |p| std.fmt.parseInt(u16, p, 10) catch port else port;
    if (env_port) |p| allocator.free(p);

    std.debug.print("Using port: {d}\n\n", .{use_port});

    // Check if proxy is already running
    const base_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{use_port});
    defer allocator.free(base_url);

    var client = TestClient.init(allocator, base_url);

    // Test 1: Health endpoint
    std.debug.print("[Test 1] GET /health ... ", .{});
    if (client.get("/health")) |response| {
        defer allocator.free(response);
        if (std.mem.indexOf(u8, response, "healthy") != null) {
            std.debug.print("PASS\n", .{});
            recordTest("health endpoint", true, null);
        } else {
            std.debug.print("FAIL - unexpected response: {s}\n", .{response[0..@min(response.len, 100)]});
            recordTest("health endpoint", false, "unexpected response");
        }
    } else |err| {
        std.debug.print("FAIL - {}\n", .{err});
        recordTest("health endpoint", false, @errorName(err));
    }

    // Test 2: Health liveness
    std.debug.print("[Test 2] GET /health/live ... ", .{});
    if (client.get("/health/live")) |response| {
        defer allocator.free(response);
        if (std.mem.indexOf(u8, response, "alive") != null) {
            std.debug.print("PASS\n", .{});
            recordTest("health liveness", true, null);
        } else {
            std.debug.print("FAIL - unexpected response\n", .{});
            recordTest("health liveness", false, "unexpected response");
        }
    } else |err| {
        std.debug.print("FAIL - {}\n", .{err});
        recordTest("health liveness", false, @errorName(err));
    }

    // Test 3: Chat completions with valid API key
    std.debug.print("[Test 3] POST /v1/chat/completions (valid key) ... ", .{});
    const chat_body = try std.fmt.allocPrint(allocator,
        \\{{"model":"{s}","messages":[{{"role":"user","content":"Hi"}}]}},
    , .{TEST_MODEL});
    defer allocator.free(chat_body);

    const auth_value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{TEST_API_KEY});
    defer allocator.free(auth_value);

    // Make raw HTTP request with auth header
    const uri = try std.Uri.parse(base_url);
    const host = uri.host orelse @panic("no host");

    var http_client = std.http.Client{ .allocator = allocator };
    defer http_client.deinit();

    const stream = http_client.connect(host, use_port, .{}) catch |e| {
        std.debug.print("FAIL - connection error: {}\n", .{e});
        recordTest("chat completions valid key", false, @errorName(e));
        return;
    };
    defer stream.close();

    var req = try stream.request(.{
        .method = .POST,
        .uri = .{ .host = host, .port = use_port, .path = "/v1/chat/completions", .scheme = "http" },
    });
    defer req.deinit();

    try req.headers.appendValue("Host", host);
    try req.headers.appendValue("Authorization", auth_value);
    try req.headers.appendValue("Content-Type", "application/json");
    try req.headers.appendValue("Content-Length", std.fmt.bufPrint(&[_]u8{}, "{d}", .{chat_body.len}) catch @panic("fmt fail"));

    try req.writeAll(chat_body);
    try req.finish();

    var response_body = std.ArrayList(u8).init(allocator);
    defer response_body.deinit();

    const reader = req.reader();
    reader.readAllArrayList(&response_body, 10_000_000) catch |e| {
        std.debug.print("FAIL - read error: {}\n", .{e});
        recordTest("chat completions valid key", false, @errorName(e));
        return;
    };

    const response = try response_body.toOwnedSlice();
    defer allocator.free(response);

    // Check for MiniMax response (contains MiniMax AI)
    if (std.mem.indexOf(u8, response, "MiniMax") != null or std.mem.indexOf(u8, response, "content") != null) {
        std.debug.print("PASS (response contains expected content)\n", .{});
        recordTest("chat completions valid key", true, null);
    } else {
        std.debug.print("FAIL - no MiniMax content found\n", .{});
        recordTest("chat completions valid key", false, "unexpected response");
    }

    // Test 4: Chat completions with invalid API key
    std.debug.print("[Test 4] POST /v1/chat/completions (invalid key) ... ", .{});
    const invalid_auth = "Bearer invalid-key-12345";

    var req2 = try stream.request(.{
        .method = .POST,
        .uri = .{ .host = host, .port = use_port, .path = "/v1/chat/completions", .scheme = "http" },
    });
    defer req2.deinit();

    try req2.headers.appendValue("Host", host);
    try req2.headers.appendValue("Authorization", invalid_auth);
    try req2.headers.appendValue("Content-Type", "application/json");
    try req2.headers.appendValue("Content-Length", std.fmt.bufPrint(&[_]u8{}, "{d}", .{chat_body.len}) catch @panic("fmt fail"));

    try req2.writeAll(chat_body);
    try req2.finish();

    var response_body2 = std.ArrayList(u8).init(allocator);
    defer response_body2.deinit();

    const reader2 = req2.reader();
    reader2.readAllArrayList(&response_body2, 10_000_000) catch {};

    const response2 = try response_body2.toOwnedSlice();
    defer allocator.free(response2);

    // Should get 401 for invalid key
    if (std.mem.indexOf(u8, response2, "401") != null or std.mem.indexOf(u8, response2, "authentication_error") != null) {
        std.debug.print("PASS (correctly rejected invalid key)\n", .{});
        recordTest("chat completions invalid key", true, null);
    } else {
        std.debug.print("FAIL - should have returned 401\n", .{});
        recordTest("chat completions invalid key", false, "expected 401");
    }

    // Test 5: Models endpoint
    std.debug.print("[Test 5] GET /v1/models ... ", .{});
    if (client.get("/v1/models")) |models_response| {
        defer allocator.free(models_response);
        if (std.mem.indexOf(u8, models_response, "gpt-4o") != null and std.mem.indexOf(u8, models_response, "claude") != null) {
            std.debug.print("PASS\n", .{});
            recordTest("models endpoint", true, null);
        } else {
            std.debug.print("FAIL - missing expected models\n", .{});
            recordTest("models endpoint", false, "missing expected models");
        }
    } else |err| {
        std.debug.print("FAIL - {}\n", .{err});
        recordTest("models endpoint", false, @errorName(err));
    }

    // Summary
    std.debug.print("\n=== Test Summary ===\n", .{});
    var passed: usize = 0;
    var failed: usize = 0;
    for (test_results[0..test_count]) |result| {
        if (result.passed) {
            passed += 1;
            std.debug.print("  [PASS] {s}\n", .{result.name});
        } else {
            failed += 1;
            std.debug.print("  [FAIL] {s}", .{result.name});
            if (result.error_message) |e| {
                std.debug.print(" ({s})", .{e});
            }
            std.debug.print("\n", .{});
        }
    }
    std.debug.print("\nTotal: {d} passed, {d} failed\n\n", .{ passed, failed });

    if (failed > 0) {
        std.debug.print("NOTE: Some tests may fail if the proxy server is not running.\n", .{});
        std.debug.print("To run the proxy server:\n", .{});
        std.debug.print("  1. Start: ./zig-out/bin/llmlite-proxy &\n", .{});
        std.debug.print("  2. Wait a few seconds for startup\n", .{});
        std.debug.print("  3. Run: ./zig-out/bin/proxy_integration_test\n\n", .{});
    }
}
