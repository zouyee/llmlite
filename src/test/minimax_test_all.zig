//! MiniMax Full API Capability Test Runner
//!
//! Tests all OpenAI-compatible interfaces with MiniMax provider
//! This validates that llmlite's API surface works correctly
//!
//! Usage: Set MINIMAX_API_KEY environment variable before running

const std = @import("std");
const http = @import("http");
const chat = @import("chat");
const embedding = @import("embedding");
const image = @import("image");
const audio = @import("audio");
const file = @import("file");
const moderation = @import("moderation");
const completion = @import("completion");
const provider = @import("provider");
const language_model = @import("language_model");

/// Get API key from environment variable
fn getApiKey(allocator: std.mem.Allocator) ![]const u8 {
    const api_key = std.process.getEnvVarOwned(allocator, "MINIMAX_API_KEY") catch {
        std.debug.print("Error: MINIMAX_API_KEY environment variable not set\n", .{});
        std.debug.print("Please set it in your .env file or export it:\n", .{});
        std.debug.print("  export MINIMAX_API_KEY=your_api_key_here\n", .{});
        return error.MissingApiKey;
    };
    return api_key;
}

pub fn main() !void {
    std.debug.print("=== MiniMax Full API Capability Test Runner ===\n\n", .{});

    const allocator = std.heap.page_allocator;

    const api_key = try getApiKey(allocator);
    defer allocator.free(api_key);

    var passed: u32 = 0;
    var failed: u32 = 0;
    var skipped: u32 = 0;

    // =========================================================================
    // 1. Chat Completions API
    // =========================================================================
    std.debug.print("========================================\n", .{});
    std.debug.print("[Category 1] Chat Completions API\n", .{});
    std.debug.print("========================================\n", .{});

    // Test 1.1: Basic Chat
    std.debug.print("[1.1] Basic Chat Completion... ", .{});
    if (testChatBasic(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // Test 1.2: System Message
    std.debug.print("[1.2] System Message... ", .{});
    if (testChatSystemMessage(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // Test 1.3: Multi-turn Conversation
    std.debug.print("[1.3] Multi-turn Conversation... ", .{});
    if (testChatMultiTurn(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // Test 1.4: Temperature/Top_P/MaxTokens
    std.debug.print("[1.4] Generation Parameters... ", .{});
    if (testChatGenerationParams(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // Test 1.5: Streaming
    std.debug.print("[1.5] Streaming Chat... ", .{});
    if (testChatStreaming(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // =========================================================================
    // 2. Embeddings API
    // =========================================================================
    std.debug.print("\n========================================\n", .{});
    std.debug.print("[Category 2] Embeddings API\n", .{});
    std.debug.print("========================================\n", .{});

    std.debug.print("[2.1] Create Embedding... ", .{});
    if (testEmbeddingCreate(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // =========================================================================
    // 3. Images API
    // =========================================================================
    std.debug.print("\n========================================\n", .{});
    std.debug.print("[Category 3] Images API\n", .{});
    std.debug.print("========================================\n", .{});

    std.debug.print("[3.1] Generate Image... ", .{});
    if (testImageGenerate(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[3.2] Edit Image (skip - needs image file)... ", .{});
    skipped += 1;

    std.debug.print("[3.3] Image Variation (skip - needs image file)... ", .{});
    skipped += 1;

    // =========================================================================
    // 4. Audio API
    // =========================================================================
    std.debug.print("\n========================================\n", .{});
    std.debug.print("[Category 4] Audio API\n", .{});
    std.debug.print("========================================\n", .{});

    std.debug.print("[4.1] Speech TTS... ", .{});
    if (testAudioSpeech(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[4.2] Transcription (skip - needs audio file)... ", .{});
    skipped += 1;

    std.debug.print("[4.3] Translation (skip - needs audio file)... ", .{});
    skipped += 1;

    // =========================================================================
    // 5. Files API
    // =========================================================================
    std.debug.print("\n========================================\n", .{});
    std.debug.print("[Category 5] Files API\n", .{});
    std.debug.print("========================================\n", .{});

    std.debug.print("[5.1] Upload File... ", .{});
    if (testFileUpload(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[5.2] List Files... ", .{});
    if (testFileList(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    std.debug.print("[5.3] Retrieve File (skip - needs file ID)... ", .{});
    skipped += 1;

    std.debug.print("[5.4] Delete File (skip - needs file ID)... ", .{});
    skipped += 1;

    // =========================================================================
    // 6. Moderations API
    // =========================================================================
    std.debug.print("\n========================================\n", .{});
    std.debug.print("[Category 6] Moderations API\n", .{});
    std.debug.print("========================================\n", .{});

    std.debug.print("[6.1] Create Moderation... ", .{});
    if (testModeration(allocator, api_key)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // =========================================================================
    // 7. Completions API (Legacy)
    // =========================================================================
    std.debug.print("\n========================================\n", .{});
    std.debug.print("[Category 7] Completions API (Legacy)\n", .{});
    std.debug.print("========================================\n", .{});

    std.debug.print("[7.1] Create Completion... ", .{});
    if (testCompletion(allocator, api_key)) |_| {
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
    std.debug.print("Skipped: {d}\n", .{skipped});
    std.debug.print("Total:   {d}\n", .{passed + failed + skipped});

    if (failed > 0) {
        std.debug.print("\nSome tests failed.\n", .{});
        return error.TestsFailed;
    } else {
        std.debug.print("\nAll tests passed!\n", .{});
    }
}

// =============================================================================
// Chat Completions Tests
// =============================================================================

fn testChatBasic(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.minimax.chat/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(allocator, &http_client, .minimax, "MiniMax-Text-01");

    const params = chat.CreateChatCompletionParams{
        .model = "MiniMax-Text-01",
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
    std.debug.print("OK\n", .{});
}

fn testChatSystemMessage(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.minimax.chat/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(allocator, &http_client, .minimax, "MiniMax-Text-01");

    const params = chat.CreateChatCompletionParams{
        .model = "MiniMax-Text-01",
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
    std.debug.print("OK\n", .{});
}

fn testChatMultiTurn(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.minimax.chat/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(allocator, &http_client, .minimax, "MiniMax-Text-01");

    const params = chat.CreateChatCompletionParams{
        .model = "MiniMax-Text-01",
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
    std.debug.print("OK\n", .{});
}

fn testChatGenerationParams(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.minimax.chat/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(allocator, &http_client, .minimax, "MiniMax-Text-01");

    const params = chat.CreateChatCompletionParams{
        .model = "MiniMax-Text-01",
        .messages = &.{
            .{ .role = .user, .content = "Give me a random number." },
        },
        .max_tokens = 5,
        .temperature = 1.0,
        .top_p = 0.9,
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
    std.debug.print("OK\n", .{});
}

fn testChatStreaming(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.minimax.chat/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(allocator, &http_client, .minimax, "MiniMax-Text-01");

    const params = chat.CreateChatCompletionParams{
        .model = "MiniMax-Text-01",
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
    std.debug.print("OK (received {d} bytes)\n", .{response.len});
}

// =============================================================================
// Embeddings Tests
// =============================================================================

fn testEmbeddingCreate(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.minimax.chat/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var embedding_service = embedding.Service.init(allocator, &http_client);

    const params = embedding.CreateEmbeddingParams{
        .input = .{ .string = "The quick brown fox jumps over the lazy dog" },
        .model = "embo-01",
    };

    const result = try ((&embedding_service)).createEmbedding(params);
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

fn testImageGenerate(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.minimax.chat/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var image_service = image.Service.init(allocator, &http_client);

    const params = image.ImageGenerateParams{
        .prompt = "A cute dog",
        .model = "image-01",
        .size = .w1024,
    };

    const result = try ((&image_service)).generateImage(params);
    defer {
        for (result.data) |item| {
            allocator.free(item.url);
        }
        allocator.free(result.data);
    }

    try std.testing.expect(result.data.len > 0);
    std.debug.print("OK\n", .{});
}

// =============================================================================
// Audio Tests
// =============================================================================

fn testAudioSpeech(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.minimax.chat/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var audio_service = audio.Service.init(allocator, &http_client);

    const params = audio.SpeechParams{
        .model = .tts1,
        .input = "Hello, this is a test.",
        .voice = .alloy,
    };

    const result = try ((&audio_service)).createSpeech(params);
    defer allocator.free(result);

    // Verify we got audio data
    try std.testing.expect(result.len > 0);
    std.debug.print("OK (audio size: {d} bytes)\n", .{result.len});
}

// =============================================================================
// Files Tests
// =============================================================================

fn testFileUpload(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.minimax.chat/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var file_service = file.Service.init(allocator, &http_client);

    const content = "Hello, this is a test file.\nIt contains some text for testing.";
    const result = try ((&file_service)).uploadFile(content, "test.txt", .assistants);

    std.debug.print("OK (file id: {s})\n", .{result.id});
}

fn testFileList(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.minimax.chat/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var file_service = file.Service.init(allocator, &http_client);

    const result = try ((&file_service)).listFiles(null);
    defer {
        for (result.data) |f| {
            allocator.free(f.id);
            allocator.free(f.filename);
            allocator.free(f.bytes);
        }
        allocator.free(result.data);
    }

    std.debug.print("OK (found {d} files)\n", .{result.data.len});
}

// =============================================================================
// Moderations Tests
// =============================================================================

fn testModeration(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.minimax.chat/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var mod_service = moderation.Service.init(allocator, &http_client);

    const params = moderation.ModerationParams{
        .input = "This is a normal, harmless text.",
        .model = .text_moderation_latest,
    };

    const result = try ((&mod_service)).createModeration(params);
    defer {
        for (result.results) |r| {
            allocator.free(r.id);
            allocator.free(r.model);
        }
        allocator.free(result.results);
    }

    try std.testing.expect(result.results.len > 0);
    std.debug.print("OK (flagged: {})\n", .{result.results[0].flagged});
}

// =============================================================================
// Completions Tests (Legacy)
// =============================================================================

fn testCompletion(allocator: std.mem.Allocator, api_key: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.minimax.chat/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var completion_service = completion.Service.init(allocator, &http_client);

    const params = completion.CreateCompletionParams{
        .model = "MiniMax-Text-01",
        .prompt = "The capital of France is",
        .max_tokens = 10,
        .stream = false,
    };

    const result = try ((&completion_service)).createCompletion(params);
    defer {
        for (result.choices) |c| {
            allocator.free(c.text);
            if (c.finish_reason) |fr| allocator.free(fr);
        }
        allocator.free(result.choices);
        allocator.free(result.id);
        allocator.free(result.model);
    }

    try std.testing.expect(result.choices.len > 0);
    std.debug.print("OK\n", .{});
}
