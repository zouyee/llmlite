//! Chat Completions Only Test Runner
//!
//! Usage: Set OPENAI_API_KEY and OPENAI_BASE_URL environment variables before running

const std = @import("std");

// Zig 0.16.0 compat: replacement for removed _getEnvVarOwned
fn _getEnvVarOwned(allocator: std.mem.Allocator, key: [*:0]const u8) error{EnvironmentVariableNotFound, OutOfMemory}![]u8 {
    const ptr = std.c.getenv(key) orelse return error.EnvironmentVariableNotFound;
    const slice = std.mem.sliceTo(ptr, 0);
    return allocator.dupe(u8, slice);
}
const http = @import("http");
const chat = @import("chat");
const language_model = @import("language_model");

var g_io: std.Io = undefined;

const MODEL = "gpt-4o-mini";

/// Get API key from environment variable
fn getApiKey(allocator: std.mem.Allocator) ![]const u8 {
    const api_key = _getEnvVarOwned(allocator, "OPENAI_API_KEY") catch {
        std.debug.print("Error: OPENAI_API_KEY environment variable not set\n", .{});
        std.debug.print("Please set it in your .env file or export it:\n", .{});
        std.debug.print("  export OPENAI_API_KEY=your_api_key_here\n", .{});
        return error.MissingApiKey;
    };
    return api_key;
}

/// Get base URL from environment variable
fn getBaseUrl(allocator: std.mem.Allocator) ![]const u8 {
    const base_url = _getEnvVarOwned(allocator, "OPENAI_BASE_URL") catch {
        std.debug.print("Error: OPENAI_BASE_URL environment variable not set\n", .{});
        std.debug.print("Please set it in your .env file or export it:\n", .{});
        std.debug.print("  export OPENAI_BASE_URL=https://api.openai.com/v1\n", .{});
        return error.MissingBaseUrl;
    };
    return base_url;
}

pub fn main(init: std.process.Init) !void {
    g_io = init.io;
    std.debug.print("=== Chat Completions Test ===\n\n", .{});

    const allocator = std.heap.page_allocator;

    const api_key = try getApiKey(allocator);
    defer allocator.free(api_key);

    const base_url = try getBaseUrl(allocator);
    defer allocator.free(base_url);

    var passed: u32 = 0;
    var failed: u32 = 0;

    std.debug.print("[1.1] Basic Chat Completion... ", .{});
    if (testBasicChat(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.2] System Message... ", .{});
    if (testSystemMessage(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.3] Multi-turn Conversation... ", .{});
    if (testMultiTurn(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.4] Temperature... ", .{});
    if (testTemperature(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.5] Max Tokens... ", .{});
    if (testMaxTokens(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("\n========================================\n", .{});
    std.debug.print("SUMMARY\n", .{});
    std.debug.print("========================================\n", .{});
    std.debug.print("Passed:  {d}\n", .{passed});
    std.debug.print("Failed:  {d}\n", .{failed});

    if (failed > 0) {
        return error.TestsFailed;
    }
}

fn createHttpClient(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) http.HttpClient {
    return http.HttpClient.initWithAuthType(
        allocator,
        g_io,
        base_url,
        api_key,
        null,
        60000,
        .bearer,
    );
}

fn testBasicChat(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(allocator, &http_client, .openai, MODEL);

    const params = chat.CreateChatCompletionParams{
        .model = MODEL,
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
    std.debug.print("OK: {s}\n", .{result.choices[0].message.content orelse ""});
}

fn testSystemMessage(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(allocator, &http_client, .openai, MODEL);

    const params = chat.CreateChatCompletionParams{
        .model = MODEL,
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
    std.debug.print("OK: {s}\n", .{result.choices[0].message.content orelse ""});
}

fn testMultiTurn(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(allocator, &http_client, .openai, MODEL);

    const params = chat.CreateChatCompletionParams{
        .model = MODEL,
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
    std.debug.print("OK: {s}\n", .{result.choices[0].message.content orelse ""});
}

fn testTemperature(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(allocator, &http_client, .openai, MODEL);

    const params = chat.CreateChatCompletionParams{
        .model = MODEL,
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
    std.debug.print("OK: {s}\n", .{result.choices[0].message.content orelse ""});
}

fn testMaxTokens(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(allocator, &http_client, .openai, MODEL);

    const params = chat.CreateChatCompletionParams{
        .model = MODEL,
        .messages = &.{
            .{ .role = .user, .content = "Count from 1 to 5." },
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
    std.debug.print("OK: {s}\n", .{result.choices[0].message.content orelse ""});
}
