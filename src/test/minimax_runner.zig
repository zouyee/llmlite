//! MiniMax Full API Capability Test Runner
//!
//! Tests all OpenAI-compatible interfaces and MiniMax native APIs
//! This validates that llmlite's API surface works correctly
//!
//! Usage: Set MINIMAX_API_KEY environment variable before running

const std = @import("std");

// Zig 0.16.0 compat: replacement for removed _getEnvVarOwned
fn _getEnvVarOwned(allocator: std.mem.Allocator, key: [*:0]const u8) error{EnvironmentVariableNotFound, OutOfMemory}![]u8 {
    const ptr = std.c.getenv(key) orelse return error.EnvironmentVariableNotFound;
    const slice = std.mem.sliceTo(ptr, 0);
    return allocator.dupe(u8, slice);
}
const http = @import("http");
const chat = @import("chat");
const provider = @import("provider");
const language_model = @import("language_model");

var g_io: std.Io = undefined;

pub fn main(init: std.process.Init) !void {
    g_io = init.io;
    std.debug.print("=== MiniMax Full API Capability Test Runner ===\n\n", .{});

    const allocator = std.heap.page_allocator;

    // Read API key from environment variable
    const api_key_env = _getEnvVarOwned(allocator, "MINIMAX_API_KEY") catch null;
    const api_key: []const u8 = api_key_env orelse {
        std.debug.print("Error: MINIMAX_API_KEY environment variable not set\n", .{});
        std.debug.print("Please set it in your .env file or export it:\n", .{});
        std.debug.print("  export MINIMAX_API_KEY=your_api_key_here\n", .{});
        return error.MissingApiKey;
    };
    defer allocator.free(api_key_env.?);

    var passed: u32 = 0;
    var failed: u32 = 0;

    // =========================================================================
    // OpenAI-Compatible Chat Completions API
    // =========================================================================
    std.debug.print("========================================\n", .{});
    std.debug.print("[Category 1] OpenAI-Compatible Chat API\n", .{});
    std.debug.print("========================================\n", .{});

    std.debug.print("[1.1] Basic Chat Completion... ", .{});
    if (testChatBasic(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.2] System Message... ", .{});
    if (testChatSystemMessage(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.3] Multi-turn Conversation... ", .{});
    if (testChatMultiTurn(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.4] Temperature Parameter... ", .{});
    if (testChatTemperature(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.5] Max Tokens Parameter... ", .{});
    if (testChatMaxTokens(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.6] Top P Parameter... ", .{});
    if (testChatTopP(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.7] Stop Sequence... ", .{});
    if (testChatStopSequence(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.8] Streaming... ", .{});
    if (testStreaming(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // =========================================================================
    // Function Calling / Tools (Note: parameters must be JSON-encoded strings)
    // =========================================================================
    std.debug.print("\n========================================\n", .{});
    std.debug.print("[Category 2] Function Calling / Tools\n", .{});
    std.debug.print("========================================\n", .{});

    std.debug.print("[2.1] Tool Call (JSON params)... ", .{});
    if (testToolCall(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // =========================================================================
    // Summary
    // =========================================================================
    std.debug.print("\n========================================\n", .{});
    std.debug.print("SUMMARY\n", .{});
    std.debug.print("========================================\n", .{});
    std.debug.print("Passed:  {d}\n", .{passed});
    std.debug.print("Failed:  {d}\n", .{failed});
    std.debug.print("Total:   {d}\n", .{passed + failed});

    if (failed > 0) {
        std.debug.print("\nSome tests failed.\n", .{});
        return error.TestsFailed;
    } else {
        std.debug.print("\nAll tests passed!\n", .{});
    }
}

// =============================================================================
// Helper Functions
// =============================================================================

fn createHttpClient(allocator: std.mem.Allocator, api_key: []const u8) http.HttpClient {
    return http.HttpClient.initWithAuthType(
        allocator,
        g_io,
        "https://api.minimaxi.com/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
}

fn createLanguageModel(allocator: std.mem.Allocator, http_client: *http.HttpClient) language_model.LanguageModel {
    return language_model.LanguageModel.init(allocator, http_client, .minimax, "MiniMax-M2.7");
}

// =============================================================================
// Chat Completions Tests
// =============================================================================

fn testChatBasic(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

    const params = chat.CreateChatCompletionParams{
        .model = "MiniMax-M2.7",
        .messages = &.{
            .{ .role = .user, .content = "Say 'Hello World' exactly." },
        },
        .max_tokens = 20,
    };

    const result = try lm.complete(params);
    defer {
        allocator.free(result.id);
        allocator.free(result.model);
        for (result.choices) |c| {
            allocator.free(c.finish_reason);
            if (c.message.content) |content| allocator.free(content);
        }
        allocator.free(result.choices);
    }

    try std.testing.expect(result.choices.len > 0);
}

fn testChatSystemMessage(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

    const params = chat.CreateChatCompletionParams{
        .model = "MiniMax-M2.7",
        .messages = &.{
            .{ .role = .system, .content = "You are a helpful assistant." },
            .{ .role = .user, .content = "Hi" },
        },
        .max_tokens = 20,
    };

    const result = try lm.complete(params);
    defer {
        allocator.free(result.id);
        allocator.free(result.model);
        for (result.choices) |c| {
            allocator.free(c.finish_reason);
            if (c.message.content) |content| allocator.free(content);
        }
        allocator.free(result.choices);
    }

    try std.testing.expect(result.choices.len > 0);
}

fn testChatMultiTurn(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

    const params = chat.CreateChatCompletionParams{
        .model = "MiniMax-M2.7",
        .messages = &.{
            .{ .role = .user, .content = "What is 2+2?" },
            .{ .role = .assistant, .content = "4" },
            .{ .role = .user, .content = "Times 3?" },
        },
        .max_tokens = 20,
    };

    const result = try lm.complete(params);
    defer {
        allocator.free(result.id);
        allocator.free(result.model);
        for (result.choices) |c| {
            allocator.free(c.finish_reason);
            if (c.message.content) |content| allocator.free(content);
        }
        allocator.free(result.choices);
    }

    try std.testing.expect(result.choices.len > 0);
}

fn testChatTemperature(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

    const params = chat.CreateChatCompletionParams{
        .model = "MiniMax-M2.7",
        .messages = &.{
            .{ .role = .user, .content = "Give me a random number." },
        },
        .max_tokens = 5,
        .temperature = 1.0,
    };

    const result = try lm.complete(params);
    defer {
        allocator.free(result.id);
        allocator.free(result.model);
        for (result.choices) |c| {
            allocator.free(c.finish_reason);
            if (c.message.content) |content| allocator.free(content);
        }
        allocator.free(result.choices);
    }

    try std.testing.expect(result.choices.len > 0);
}

fn testChatMaxTokens(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

    const params = chat.CreateChatCompletionParams{
        .model = "MiniMax-M2.7",
        .messages = &.{
            .{ .role = .user, .content = "Write a long story." },
        },
        .max_tokens = 10,
    };

    const result = try lm.complete(params);
    defer {
        allocator.free(result.id);
        allocator.free(result.model);
        for (result.choices) |c| {
            allocator.free(c.finish_reason);
            if (c.message.content) |content| allocator.free(content);
        }
        allocator.free(result.choices);
    }

    try std.testing.expect(result.choices.len > 0);
}

fn testChatTopP(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

    const params = chat.CreateChatCompletionParams{
        .model = "MiniMax-M2.7",
        .messages = &.{
            .{ .role = .user, .content = "Say yes or no." },
        },
        .max_tokens = 5,
        .top_p = 0.5,
    };

    const result = try lm.complete(params);
    defer {
        allocator.free(result.id);
        allocator.free(result.model);
        for (result.choices) |c| {
            allocator.free(c.finish_reason);
            if (c.message.content) |content| allocator.free(content);
        }
        allocator.free(result.choices);
    }

    try std.testing.expect(result.choices.len > 0);
}

fn testChatStopSequence(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

    const params = chat.CreateChatCompletionParams{
        .model = "MiniMax-M2.7",
        .messages = &.{
            .{ .role = .user, .content = "Count: 1, 2, 3, 4, 5" },
        },
        .max_tokens = 20,
        .stop = ".",
    };

    const result = try lm.complete(params);
    defer {
        allocator.free(result.id);
        allocator.free(result.model);
        for (result.choices) |c| {
            allocator.free(c.finish_reason);
            if (c.message.content) |content| allocator.free(content);
        }
        allocator.free(result.choices);
    }

    try std.testing.expect(result.choices.len > 0);
}

// =============================================================================
// Function Calling / Tools Tests
// =============================================================================

fn testToolCall(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

    // Parameters as JSON string (required format for FunctionDefinition)
    const params_json = "{\"type\":\"object\",\"properties\":{\"location\":{\"type\":\"string\",\"description\":\"The city name\"}},\"required\":[\"location\"]}";

    var tools_array = [_]chat.ToolDefinition{
        .{
            .type = "function",
            .function = .{
                .name = "get_weather",
                .description = "Get the weather in a location",
                .parameters = params_json,
            },
        },
    };

    const params = chat.CreateChatCompletionParams{
        .model = "MiniMax-M2.7",
        .messages = &.{
            .{ .role = .user, .content = "What is the weather in Beijing?" },
        },
        .max_tokens = 100,
        .tools = tools_array[0..],
    };

    const result = try lm.complete(params);
    defer {
        allocator.free(result.id);
        allocator.free(result.model);
        for (result.choices) |c| {
            allocator.free(c.finish_reason);
            if (c.message.content) |content| allocator.free(content);
        }
        allocator.free(result.choices);
    }

    try std.testing.expect(result.choices.len > 0);
}

// =============================================================================
// Streaming Test
// =============================================================================

fn testStreaming(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

    const params = chat.CreateChatCompletionParams{
        .model = "MiniMax-M2.7",
        .messages = &.{
            .{ .role = .user, .content = "Count from 1 to 3." },
        },
        .max_tokens = 20,
        .stream = true,
    };

    const response = try lm.completeStream(params);
    defer allocator.free(response);

    // Just verify we get some response
    try std.testing.expect(response.len > 0);
}

// =============================================================================
// MiniMax-Specific Features
// =============================================================================

fn testReasoningSplit(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

    const params = chat.CreateChatCompletionParams{
        .model = "MiniMax-M2.7",
        .messages = &.{
            .{ .role = .user, .content = "What is 2+2? Think step by step." },
        },
        .max_tokens = 100,
        .extra_body = &.{
            .{ .key = "reasoning_split", .value = .{ .bool = true } },
        },
    };

    const result = try lm.complete(params);
    defer {
        allocator.free(result.id);
        allocator.free(result.model);
        for (result.choices) |c| {
            allocator.free(c.finish_reason);
            if (c.message.content) |content| allocator.free(content);
        }
        allocator.free(result.choices);
    }

    try std.testing.expect(result.choices.len > 0);
}
