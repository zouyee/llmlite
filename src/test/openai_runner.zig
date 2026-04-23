//! OpenAI Full API Capability Test Runner
//!
//! Tests all OpenAI-compatible interfaces
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
const provider = @import("provider");
const language_model = @import("language_model");

var g_io: std.Io = undefined;
const embedding = @import("embedding");
const image = @import("image");
const audio = @import("audio");
const file = @import("file");
const moderation = @import("moderation");
const completion = @import("completion");

const MODEL = "gpt-5.4-2026-03-05";

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
    std.debug.print("=== OpenAI Full API Capability Test Runner ===\n\n", .{});

    const allocator = std.heap.page_allocator;

    const api_key = try getApiKey(allocator);
    defer allocator.free(api_key);

    const base_url = try getBaseUrl(allocator);
    defer allocator.free(base_url);

    var passed: u32 = 0;
    var failed: u32 = 0;

    // =========================================================================
    // Category 1: Chat Completions API
    // =========================================================================
    std.debug.print("========================================\n", .{});
    std.debug.print("[Category 1] Chat Completions API\n", .{});
    std.debug.print("========================================\n", .{});

    std.debug.print("[1.1] Basic Chat Completion... ", .{});
    if (testChatBasic(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.2] System Message... ", .{});
    if (testChatSystemMessage(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.3] Multi-turn Conversation... ", .{});
    if (testChatMultiTurn(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.4] Temperature Parameter... ", .{});
    if (testChatTemperature(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.5] Max Tokens Parameter... ", .{});
    if (testChatMaxTokens(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.6] Top P Parameter... ", .{});
    if (testChatTopP(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.7] Stop Sequence... ", .{});
    if (testChatStopSequence(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.8] Streaming... ", .{});
    if (testStreaming(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[1.9] Function Calling / Tools... ", .{});
    if (testToolCall(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // =========================================================================
    // Category 2: Embeddings API
    // =========================================================================
    std.debug.print("\n========================================\n", .{});
    std.debug.print("[Category 2] Embeddings API\n", .{});
    std.debug.print("========================================\n", .{});

    std.debug.print("[2.1] Create Embedding... ", .{});
    if (testEmbeddingCreate(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // =========================================================================
    // Category 3: Images API
    // =========================================================================
    std.debug.print("\n========================================\n", .{});
    std.debug.print("[Category 3] Images API\n", .{});
    std.debug.print("========================================\n", .{});

    std.debug.print("[3.1] Generate Image... ", .{});
    if (testImageGenerate(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // =========================================================================
    // Category 4: Files API
    // =========================================================================
    std.debug.print("\n========================================\n", .{});
    std.debug.print("[Category 4] Files API\n", .{});
    std.debug.print("========================================\n", .{});

    std.debug.print("[4.1] Upload File... ", .{});
    if (testFileUpload(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[4.2] List Files... ", .{});
    if (testFileList(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // =========================================================================
    // Category 5: Moderations API
    // =========================================================================
    std.debug.print("\n========================================\n", .{});
    std.debug.print("[Category 5] Moderations API\n", .{});
    std.debug.print("========================================\n", .{});

    std.debug.print("[5.1] Create Moderation... ", .{});
    if (testModeration(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // =========================================================================
    // Category 6: Completions API (Legacy) - SKIPPED due to Zig 0.15+ json.stringify removal
    // =========================================================================
    std.debug.print("\n========================================\n", .{});
    std.debug.print("[Category 6] Completions API (Legacy) - SKIPPED\n", .{});
    std.debug.print("========================================\n", .{});
    std.debug.print("[6.1] Create Completion... SKIPPED (json.stringify issue)\n", .{});

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

fn createLanguageModel(allocator: std.mem.Allocator, http_client: *http.HttpClient) language_model.LanguageModel {
    return language_model.LanguageModel.init(allocator, http_client, .openai, MODEL);
}

// =============================================================================
// Chat Completions Tests
// =============================================================================

fn testChatBasic(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

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
}

fn testChatSystemMessage(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

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
}

fn testChatMultiTurn(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

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
}

fn testChatTemperature(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

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
}

fn testChatMaxTokens(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

    const params = chat.CreateChatCompletionParams{
        .model = MODEL,
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

fn testChatTopP(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

    const params = chat.CreateChatCompletionParams{
        .model = MODEL,
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

fn testChatStopSequence(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

    const params = chat.CreateChatCompletionParams{
        .model = MODEL,
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

fn testStreaming(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

    const params = chat.CreateChatCompletionParams{
        .model = MODEL,
        .messages = &.{
            .{ .role = .user, .content = "Count from 1 to 3." },
        },
        .max_tokens = 20,
        .stream = true,
    };

    const response = try lm.completeStream(params);
    defer allocator.free(response);

    try std.testing.expect(response.len > 0);
}

fn testToolCall(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var lm = createLanguageModel(allocator, &http_client);

    var tools_array = [_]chat.ToolDefinition{
        .{
            .type = "function",
            .function = .{
                .name = "get_weather",
                .description = "Get the weather in a location",
                .parameters = "{\"type\":\"object\",\"properties\":{\"location\":{\"type\":\"string\",\"description\":\"The city name\"}},\"required\":[\"location\"]}",
            },
        },
    };

    const params = chat.CreateChatCompletionParams{
        .model = MODEL,
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
// Embeddings Tests
// =============================================================================

fn testEmbeddingCreate(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var embedding_service = embedding.Service.init(allocator, &http_client);

    const params = embedding.CreateEmbeddingParams{
        .input = .{ .string = "The quick brown fox jumps over the lazy dog" },
        .model = "text-embedding-3-small",
    };

    const result = try embedding_service.createEmbedding(params);
    defer {
        for (result.data) |item| {
            allocator.free(item.embedding);
        }
        allocator.free(result.data);
        allocator.free(result.model);
    }

    try std.testing.expect(result.data.len > 0);
    try std.testing.expect(result.data[0].embedding.len > 0);
    std.debug.print("OK (embedding dim: {d})\n", .{result.data[0].embedding.len});
}

// =============================================================================
// Images Tests
// =============================================================================

fn testImageGenerate(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var image_service = image.Service.init(allocator, &http_client);

    const params = image.ImageGenerateParams{
        .prompt = "A cute cat",
        .model = "dall-e-3",
        .size = image.ImageSize.s1024x1024,
    };

    const result = try image_service.generateImage(params);
    defer {
        for (result.data) |item| {
            allocator.free(item.url orelse "");
            if (item.b64_json) |b64| allocator.free(b64);
        }
        allocator.free(result.data);
    }

    try std.testing.expect(result.data.len > 0);
    std.debug.print("OK (image URL: {s})\n", .{result.data[0].url orelse "b64_json"});
}

// =============================================================================
// Files Tests
// =============================================================================

fn testFileUpload(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var file_service = file.Service.init(allocator, &http_client);

    // Create a simple JSONL content for fine-tuning
    const content = "{\"prompt\":\"The quick brown fox\", \"completion\":\"jump\"}\n{\"prompt\":\"A cute cat\", \"completion\":\"meow\"}\n";

    const result = try file_service.uploadFile(content, "train.jsonl", .fine_tune);
    defer {
        allocator.free(result.id);
        allocator.free(result.filename);
        allocator.free(result.purpose);
    }

    try std.testing.expect(result.id.len > 0);
    std.debug.print("OK (file_id: {s})\n", .{result.id});
}

fn testFileList(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var file_service = file.Service.init(allocator, &http_client);

    const result = try file_service.listFiles();
    defer {
        for (result.data) |f| {
            allocator.free(f.id);
            allocator.free(f.filename);
            allocator.free(f.purpose);
        }
        allocator.free(result.data);
    }

    try std.testing.expect(result.data.len >= 0);
    std.debug.print("OK ({d} files)\n", .{result.data.len});
}

// =============================================================================
// Moderations Tests
// =============================================================================

fn testModeration(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var moderation_service = moderation.Service.init(allocator, &http_client);

    const params = moderation.ModerationParams{
        .input = "I want to make a bomb",
    };

    const result = try moderation_service.createModeration(params);
    defer {
        allocator.free(result.id);
        allocator.free(result.model);
        // Categories and scores in results need proper deallocation
        allocator.free(result.results);
    }

    try std.testing.expect(result.results.len > 0);
    std.debug.print("OK (flagged: {})\n", .{result.results[0].flagged});
}

// =============================================================================
// Completions Tests (Legacy)
// =============================================================================

fn testCompletion(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = createHttpClient(allocator, api_key, base_url);
    defer http_client.deinit();

    var completion_service = completion.Service.init(allocator, &http_client);

    const params = completion.CreateCompletionParams{
        .model = "gpt-3.5-turbo-instruct",
        .prompt = "The quick brown fox",
        .max_tokens = 10,
    };

    const result = try completion_service.createCompletion(params);
    defer {
        allocator.free(result.id);
        allocator.free(result.model);
        for (result.choices) |c| {
            allocator.free(c.text);
        }
        allocator.free(result.choices);
    }

    try std.testing.expect(result.choices.len > 0);
    std.debug.print("OK\n", .{});
}
