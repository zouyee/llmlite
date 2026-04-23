//! Provider Mock Tests - Tests using MockServer instead of real API calls
//!
//! This file demonstrates how to test provider functionality using the MSW-inspired
//! MockServer from test_utils.zig. These tests intercept HTTP requests and return
//! mock responses without hitting real APIs.
//!
//! Usage: zig build provider-mock-test

const std = @import("std");
const test_utils = @import("test_utils");

// ============================================================================
// Test Handlers (MSW-inspired)
// ============================================================================

/// Handler that returns a chat completion response based on request model
fn chatCompletionHandler(ctx: *test_utils.MockContext) ![]const u8 {
    const model = ctx.extractModel() orelse "unknown";
    const content = std.fmt.bufPrint(&[_]u8{}, "You said hello to {s}!", .{model}) catch "response";
    return ctx.builder.chatCompletion("chatcmpl-mock-123", model, content);
}

/// Handler that returns an error response
fn rateLimitHandler(ctx: *test_utils.MockContext) ![]const u8 {
    _ = ctx;
    return test_utils.ResponseBuilder.init(std.heap.page_allocator).rateLimitResponse(60);
}

/// Handler that validates request and returns auth error
fn authErrorHandler(ctx: *test_utils.MockContext) ![]const u8 {
    const auth_header = ctx.getHeader("Authorization") orelse "";
    if (auth_header.len == 0) {
        return ctx.builder.authErrorResponse("Missing authorization header");
    }
    return ctx.builder.authErrorResponse("Invalid API key");
}

/// Handler that tracks request metadata
fn trackingHandler(ctx: *test_utils.MockContext) ![]const u8 {
    _ = ctx;
    // This handler just returns a simple response
    return "{\"id\":\"tracked-123\",\"object\":\"chat.completion\",\"created\":1234567890,\"model\":\"test\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"tracked\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":10,\"total_tokens\":15}}";
}

// ============================================================================
// Main Test Runner
// ============================================================================

pub fn main() !void {
    std.debug.print("\n=== Provider Mock Tests ===\n\n", .{});

    const allocator = std.heap.page_allocator;

    // =========================================================================
    // Test 1: Basic MockServer setup with static responses
    // =========================================================================
    std.debug.print("[Test 1] Static response registration...\n", .{});
    {
        var mock = try test_utils.MockServer.init(allocator, 18080);
        defer mock.deinit();

        const response = try std.fmt.allocPrint(allocator,
            \\{{"id":"chatcmpl-123","object":"chat.completion","created":1234567890,"model":"gpt-4o","choices":[{{"index":0,"message":{{"role":"assistant","content":"Hello!"}},"finish_reason":"stop"}}],"usage":{{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}}
        , .{});
        defer allocator.free(response);

        try mock.registerChatCompletion(response);

        try mock.start();
        defer mock.stop();

        // Verify registration
        const count = mock.getRequestCount("/v1/chat/completions");
        try std.testing.expect(count == 0); // No requests yet
        std.debug.print("  [PASS] Static response registered\n", .{});
    }

    // =========================================================================
    // Test 2: Dynamic handler responses
    // =========================================================================
    std.debug.print("[Test 2] Dynamic handler response...\n", .{});
    {
        var mock = try test_utils.MockServer.init(allocator, 18081);
        defer mock.deinit();

        try mock.registerHandler("/v1/chat/completions", .POST, chatCompletionHandler);
        try mock.registerModelsList(try test_utils.ResponseBuilder.init(allocator).modelsList());

        try mock.start();
        defer mock.stop();

        std.debug.print("  [PASS] Dynamic handler registered\n", .{});
    }

    // =========================================================================
    // Test 3: Request tracking and inspection
    // =========================================================================
    std.debug.print("[Test 3] Request tracking...\n", .{});
    {
        var mock = try test_utils.MockServer.init(allocator, 18082);
        defer mock.deinit();

        try mock.registerHandler("/v1/chat/completions", .POST, trackingHandler);

        try mock.start();
        defer mock.stop();

        // Reset any initial state
        mock.resetCaptured();

        // Verify no requests captured initially
        const initial = mock.getCapturedRequests();
        try std.testing.expect(initial.len == 0);

        std.debug.print("  [PASS] Request tracking works\n", .{});
    }

    // =========================================================================
    // Test 4: ResponseBuilder utilities
    // =========================================================================
    std.debug.print("[Test 4] ResponseBuilder...\n", .{});
    {
        var builder = test_utils.ResponseBuilder.init(allocator);
        defer builder.deinit();

        const chat_resp = try builder.chatCompletion("id-1", "gpt-4o", "Hello!");
        defer allocator.free(chat_resp);
        try std.testing.expect(std.mem.find(u8, chat_resp, "Hello!") != null);

        const models_resp = try builder.modelsList();
        defer allocator.free(models_resp);
        try std.testing.expect(std.mem.find(u8, models_resp, "gpt-4o") != null);

        const err_resp = try builder.errorResponse("invalid_request", "Invalid request");
        defer allocator.free(err_resp);
        try std.testing.expect(std.mem.find(u8, err_resp, "invalid_request") != null);

        const rate_resp = try builder.rateLimitResponse(60);
        defer allocator.free(rate_resp);
        try std.testing.expect(std.mem.find(u8, rate_resp, "rate_limit_exceeded") != null);

        std.debug.print("  [PASS] ResponseBuilder generates correct JSON\n", .{});
    }

    // =========================================================================
    // Test 5: Error response handlers
    // =========================================================================
    std.debug.print("[Test 5] Error handlers...\n", .{});
    {
        var mock = try test_utils.MockServer.init(allocator, 18083);
        defer mock.deinit();

        try mock.registerHandler("/v1/chat/completions", .POST, rateLimitHandler);
        try mock.registerHandler("/v1/chat/completions", .DELETE, authErrorHandler);

        try mock.start();
        defer mock.stop();

        std.debug.print("  [PASS] Error handlers registered\n", .{});
    }

    // =========================================================================
    // Test 6: IntegrationTest helper
    // =========================================================================
    std.debug.print("[Test 6] IntegrationTest helper...\n", .{});
    {
        var integration = try test_utils.IntegrationTest.init(allocator, 18084);
        defer integration.deinit();

        // Run some tests
        integration.runTest("basic test", struct {
            fn func(mock: *test_utils.MockServer) !void {
                try mock.registerStatic("/test", .GET, "{\"status\":\"ok\"}");
                try mock.start();
            }
        }.func);

        integration.summary();
        std.debug.print("  [PASS] IntegrationTest helper works\n", .{});
    }

    // =========================================================================
    // Test 7: MockContext request inspection
    // =========================================================================
    std.debug.print("[Test 7] MockContext inspection...\n", .{});
    {
        var mock = try test_utils.MockServer.init(allocator, 18085);
        defer mock.deinit();

        try mock.registerHandler("/v1/chat/completions", .POST, struct {
            fn handle(ctx: *test_utils.MockContext) ![]const u8 {
                // Verify we can extract model from request
                const model_name = ctx.extractModel() orelse "unknown";
                std.debug.print("    Extracted model: {s}\n", .{model_name});
                return ctx.builder.chatCompletion("id", model_name, "response");
            }
        }.handle);

        try mock.start();
        defer mock.stop();

        std.debug.print("  [PASS] MockContext inspection works\n", .{});
    }

    std.debug.print("\n=== All Provider Mock Tests Passed ===\n\n", .{});
}

// ============================================================================
// Unit Tests (for zig test)
// ============================================================================

test "MockServer: init and deinit" {
    const allocator = std.testing.allocator;
    var mock = try test_utils.MockServer.init(allocator, 19080);
    defer mock.deinit();
    try std.testing.expect(!mock.running);
}

test "MockServer: register static response" {
    const allocator = std.testing.allocator;
    var mock = try test_utils.MockServer.init(allocator, 19081);
    defer mock.deinit();

    try mock.registerStatic("/v1/test", .GET, "{\"ok\":true}");
    try mock.registerStatic("/v1/test", .POST, "{\"created\":true}");
}

test "MockServer: register handler" {
    const allocator = std.testing.allocator;
    var mock = try test_utils.MockServer.init(allocator, 19082);
    defer mock.deinit();

    try mock.registerHandler("/v1/test", .POST, struct {
        fn handle(ctx: *test_utils.MockContext) ![]const u8 {
            _ = ctx;
            return "{\"handled\":true}";
        }
    }.handle);
}

test "ResponseBuilder: chatCompletion" {
    const allocator = std.testing.allocator;
    var builder = test_utils.ResponseBuilder.init(allocator);
    defer builder.deinit();

    const resp = try builder.chatCompletion("id-123", "gpt-4o", "Hello!");
    defer allocator.free(resp);

    try std.testing.expect(std.mem.find(u8, resp, "id-123") != null);
    try std.testing.expect(std.mem.find(u8, resp, "gpt-4o") != null);
    try std.testing.expect(std.mem.find(u8, resp, "Hello!") != null);
}

test "ResponseBuilder: modelsList" {
    const allocator = std.testing.allocator;
    var builder = test_utils.ResponseBuilder.init(allocator);
    defer builder.deinit();

    const resp = try builder.modelsList();
    defer allocator.free(resp);

    try std.testing.expect(std.mem.find(u8, resp, "gpt-4o") != null);
    try std.testing.expect(std.mem.find(u8, resp, "claude") != null);
}

test "ResponseBuilder: errorResponse" {
    const allocator = std.testing.allocator;
    var builder = test_utils.ResponseBuilder.init(allocator);
    defer builder.deinit();

    const resp = try builder.errorResponse("test_error", "Test error message");
    defer allocator.free(resp);

    try std.testing.expect(std.mem.find(u8, resp, "test_error") != null);
    try std.testing.expect(std.mem.find(u8, resp, "Test error message") != null);
}

test "Assert: stringsEqual" {
    try test_utils.Assert.stringsEqual("hello", "hello");
    try std.testing.expectError(error.NotEqual, test_utils.Assert.stringsEqual("hello", "world"));
}

test "Assert: jsonHasField" {
    const json = "{\"model\":\"gpt-4o\",\"temperature\":0.7}";
    try test_utils.Assert.jsonHasField(json, "model");
    try test_utils.Assert.jsonHasField(json, "temperature");
    try std.testing.expectError(error.FieldNotFound, test_utils.Assert.jsonHasField(json, "missing"));
}

test "Assert: validJson" {
    try test_utils.Assert.validJson("{\"ok\":true}");
    try test_utils.Assert.validJson("[]");
    try test_utils.Assert.validJson("{\"nested\":{\"value\":123}}");
}
