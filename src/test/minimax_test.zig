//! MiniMax API Capability Tests
//!
//! Tests MiniMax API using the provider-based architecture
//!
//! Usage: Set MINIMAX_API_KEY environment variable before running

const std = @import("std");

// Zig 0.16.0 compat: replacement for removed _getEnvVarOwned
fn _getEnvVarOwned(allocator: std.mem.Allocator, key: [*:0]const u8) error{EnvironmentVariableNotFound, OutOfMemory}![]u8 {
    const ptr = std.c.getenv(key) orelse return error.EnvironmentVariableNotFound;
    const slice = std.mem.sliceTo(ptr, 0);
    return allocator.dupe(u8, slice);
}
const testing = std.testing;
const http = @import("http");
const chat = @import("chat");
const provider = @import("../provider/provider");
const language_model = @import("../provider/language_model");

/// Get API key from environment variable
fn getApiKey(allocator: std.mem.Allocator) ![]const u8 {
    const api_key = _getEnvVarOwned(allocator, "MINIMAX_API_KEY") catch {
        std.debug.print("Error: MINIMAX_API_KEY environment variable not set\n", .{});
        std.debug.print("Please set it in your .env file or export it:\n", .{});
        std.debug.print("  export MINIMAX_API_KEY=your_api_key_here\n", .{});
        return error.MissingApiKey;
    };
    return api_key;
}

test "MiniMax: Chat Completion" {
    const allocator = testing.allocator;

    const api_key = try getApiKey(allocator);
    defer allocator.free(api_key);

    // Create client with MiniMax provider
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.minimax.chat/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    // Create language model
    var lm = language_model.LanguageModel.init(
        allocator,
        &http_client,
        .minimax,
        "MiniMax-Text-01",
    );

    // Create chat completion
    const params = chat.CreateChatCompletionParams{
        .model = "MiniMax-Text-01",
        .messages = &.{
            .{ .role = .user, .content = "Hello, how are you?" },
        },
        .max_tokens = 100,
        .temperature = 0.7,
    };

    const result = try lm.complete(params);
    defer {
        allocator.free(result.id);
        allocator.free(result.model);
        for (result.choices) |choice| {
            allocator.free(choice.finish_reason);
            if (choice.message.content) |c| allocator.free(c);
        }
        allocator.free(result.choices);
    }

    try testing.expect(result.choices.len > 0);
    try testing.expect(result.choices[0].message.content != null);
    std.debug.print("MiniMax Chat: {s}\n", .{result.choices[0].message.content.?});
}

test "MiniMax: Transform Request Format" {
    const allocator = testing.allocator;

    const params = chat.CreateChatCompletionParams{
        .model = "MiniMax-Text-01",
        .messages = &.{
            .{ .role = .system, .content = "You are a helpful assistant." },
            .{ .role = .user, .content = "What is 2+2?" },
        },
        .max_tokens = 50,
        .temperature = 0.5,
    };

    const request_json = try provider.openai.transformRequest(allocator, params);
    defer allocator.free(request_json);

    // Verify request format
    try testing.expect(std.mem.find(u8, request_json, "\"model\":\"MiniMax-Text-01\"") != null);
    try testing.expect(std.mem.find(u8, request_json, "\"messages\"") != null);
    try testing.expect(std.mem.find(u8, request_json, "\"max_tokens\":50") != null);
    try testing.expect(std.mem.find(u8, request_json, "\"temperature\":") != null);

    std.debug.print("MiniMax Request: {s}\n", .{request_json});
}

test "MiniMax: Parse Response Format" {
    const allocator = testing.allocator;

    // Mock response in OpenAI format (MiniMax compatible)
    const mock_response =
        \\{"id":"chatcmpl-123","object":"chat.completion","created":1234567890,"model":"MiniMax-Text-01","choices":[{"index":0,"message":{"role":"assistant","content":"The answer is 4."},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}
    ;

    const result = try provider.openai.parseResponse(allocator, mock_response);
    defer {
        allocator.free(result.id);
        allocator.free(result.model);
        for (result.choices) |choice| {
            allocator.free(choice.finish_reason);
            if (choice.message.content) |c| allocator.free(c);
        }
        allocator.free(result.choices);
    }

    try testing.expect(std.mem.eql(u8, result.id, "chatcmpl-123"));
    try testing.expect(std.mem.eql(u8, result.model, "MiniMax-Text-01"));
    try testing.expect(result.choices.len > 0);
    try testing.expect(result.choices[0].message.content != null);
    try testing.expect(std.mem.eql(u8, result.choices[0].message.content.?, "The answer is 4."));
}

test "MiniMax: Provider Config" {
    const config = provider.registry.getProviderConfig(.minimax);

    try testing.expect(std.mem.eql(u8, config.base_url, "https://api.minimax.chat/v1"));
    try testing.expect(config.auth_type == .bearer);
}

pub fn main() !void {
    std.debug.print("Starting MiniMax API capability tests...\n", .{});
    std.debug.print("API Key: Read from MINIMAX_API_KEY environment variable\n", .{});
}
