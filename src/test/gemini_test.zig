//! Google Provider Tests
//!
//! Tests for Google Gemini API integration

const std = @import("std");
const testing = std.testing;

const google = @import("../provider/google");
const chat = @import("../chat");
const embedding = @import("../embedding");

// ============================================================================
// Request Transformation Tests
// ============================================================================

test "Google transformRequest creates valid Gemini format" {
    const allocator = testing.allocator;

    const params = chat.CreateChatCompletionParams{
        .model = "gemini-2.0-flash",
        .messages = &.{
            .{ .role = .user, .content = "Hello" },
        },
        .stream = false,
    };

    const request_json = try google.transformRequest(allocator, params);
    defer allocator.free(request_json);

    // Should contain Gemini-native format
    try testing.expect(std.mem.indexOf(u8, request_json, "\"contents\"") != null);
    try testing.expect(std.mem.indexOf(u8, request_json, "\"parts\"") != null);
    try testing.expect(std.mem.indexOf(u8, request_json, "\"role\":\"user\"") != null);
    try testing.expect(std.mem.indexOf(u8, request_json, "\"text\":\"Hello\"") != null);
}

test "Google transformRequest with system instruction" {
    const allocator = testing.allocator;

    const params = chat.CreateChatCompletionParams{
        .model = "gemini-2.0-flash",
        .messages = &.{
            .{ .role = .system, .content = "You are a helpful assistant." },
            .{ .role = .user, .content = "Hello" },
        },
        .stream = false,
    };

    const request_json = try google.transformRequest(allocator, params);
    defer allocator.free(request_json);

    // Should contain systemInstruction
    try testing.expect(std.mem.indexOf(u8, request_json, "\"systemInstruction\"") != null);
    try testing.expect(std.mem.indexOf(u8, request_json, "You are a helpful assistant.") != null);
}

test "Google transformRequest with generation config" {
    const allocator = testing.allocator;

    const params = chat.CreateChatCompletionParams{
        .model = "gemini-2.0-flash",
        .messages = &.{
            .{ .role = .user, .content = "Hello" },
        },
        .stream = false,
        .temperature = 0.7,
        .max_tokens = 100,
    };

    const request_json = try google.transformRequest(allocator, params);
    defer allocator.free(request_json);

    // Should contain generationConfig
    try testing.expect(std.mem.indexOf(u8, request_json, "\"generationConfig\"") != null);
    try testing.expect(std.mem.indexOf(u8, request_json, "\"temperature\":0.7") != null);
    try testing.expect(std.mem.indexOf(u8, request_json, "\"maxOutputTokens\":100") != null);
}

// ============================================================================
// Response Parsing Tests
// ============================================================================

test "Google parseGeminiResponse parses native format" {
    const allocator = testing.allocator;

    const response =
        \\{"candidates":[{"content":{"parts":[{"text":"Hello! How can I help you?"}]}}]}
    ;

    const result = try google.parseResponse(allocator, response);
    defer {
        allocator.free(result.id);
        allocator.free(result.model);
        for (result.choices) |choice| {
            allocator.free(choice.message.content orelse "");
            allocator.free(choice.finish_reason);
        }
        allocator.free(result.choices);
    }

    try testing.expect(result.choices.len > 0);
    try testing.expect(result.choices[0].message.content != null);
}

test "Google parseGeminiResponse handles OpenAI fallback" {
    const allocator = testing.allocator;

    // OpenAI format response
    const response =
        \\{"id":"chatcmpl-123","object":"chat.completion","created":1234567890,"model":"gpt-4o","choices":[{"index":0,"message":{"role":"assistant","content":"Hello!"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}
    ;

    const result = try google.parseResponse(allocator, response);
    defer {
        allocator.free(result.id);
        allocator.free(result.model);
        for (result.choices) |choice| {
            allocator.free(choice.message.content orelse "");
            allocator.free(choice.finish_reason);
        }
        allocator.free(result.choices);
    }

    try testing.expect(result.choices.len > 0);
    try testing.expect(std.mem.eql(u8, result.id, "chatcmpl-123"));
}

// ============================================================================
// Endpoint Tests
// ============================================================================

test "Google getGenerateContentEndpoint returns correct path" {
    const endpoint = google.getGenerateContentEndpoint("gemini-2.0-flash");
    try testing.expect(std.mem.eql(u8, endpoint, "/models/gemini-2.0-flash:generateContent"));
}

test "Google getStreamGenerateContentEndpoint returns correct path" {
    const endpoint = google.getStreamGenerateContentEndpoint("gemini-2.0-flash");
    try testing.expect(std.mem.eql(u8, endpoint, "/models/gemini-2.0-flash:streamGenerateContent"));
}

// ============================================================================
// Streaming Handler Tests
// ============================================================================

test "GeminiStreamHandler parses single chunk" {
    const allocator = testing.allocator;

    var handler = google.GeminiStreamHandler.init(allocator);
    defer handler.deinit();

    const chunk_data = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hello\"}]}}]}\n\n";

    try handler.feed(chunk_data);

    try testing.expect(handler.isComplete() == false);
    const text = handler.getText();
    try testing.expect(std.mem.eql(u8, text, "Hello"));
}

test "GeminiStreamHandler parses multiple chunks" {
    const allocator = testing.allocator;

    var handler = google.GeminiStreamHandler.init(allocator);
    defer handler.deinit();

    const chunk1 = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hello\"}]}}]}\n\n";
    const chunk2 = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\" World\"}]}}]}\n\n";

    try handler.feed(chunk1);
    try handler.feed(chunk2);

    const text = handler.getText();
    try testing.expect(std.mem.eql(u8, text, "Hello World"));
}

test "GeminiStreamHandler handles done signal" {
    const allocator = testing.allocator;

    var handler = google.GeminiStreamHandler.init(allocator);
    defer handler.deinit();

    const chunk = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Done\"}]}}],\"done\":true}\n\n";

    try handler.feed(chunk);

    try testing.expect(handler.isComplete() == true);
}

// ============================================================================
// Embeddings Tests
// ============================================================================

test "Google transformGeminiEmbeddingRequest creates valid format" {
    const allocator = testing.allocator;

    const params = embedding.CreateEmbeddingParams{
        .input = .{ .string = "Hello world" },
        .model = "gemini-embedding",
    };

    const request_json = try embedding.transformGeminiEmbeddingRequest(allocator, params);
    defer allocator.free(request_json);

    // Should contain Gemini-native format
    try testing.expect(std.mem.indexOf(u8, request_json, "\"content\"") != null);
    try testing.expect(std.mem.indexOf(u8, request_json, "\"parts\"") != null);
    try testing.expect(std.mem.indexOf(u8, request_json, "\"text\":\"Hello world\"") != null);
}

test "Google transformGeminiEmbeddingRequest with array input" {
    const allocator = testing.allocator;

    const params = embedding.CreateEmbeddingParams{
        .input = .{ .array_of_strings = &.{ "Hello", "World" } },
        .model = "gemini-embedding",
    };

    const request_json = try embedding.transformGeminiEmbeddingRequest(allocator, params);
    defer allocator.free(request_json);

    // Should contain both strings
    try testing.expect(std.mem.indexOf(u8, request_json, "\"text\":\"Hello\"") != null);
    try testing.expect(std.mem.indexOf(u8, request_json, "\"text\":\"World\"") != null);
}

test "Google getGeminiEmbedEndpoint returns correct path" {
    const endpoint = embedding.getGeminiEmbedEndpoint("text-embedding-004");
    try testing.expect(std.mem.eql(u8, endpoint, "/models/text-embedding-004:embedContent"));
}

// ============================================================================
// Integration-Style Tests (with mock responses)
// ============================================================================

test "Google provider with Gemini native request and response cycle" {
    const allocator = testing.allocator;

    // Create a request
    const params = chat.CreateChatCompletionParams{
        .model = "gemini-2.0-flash",
        .messages = &.{
            .{ .role = .user, .content = "What is 2+2?" },
        },
        .stream = false,
        .temperature = 0.5,
    };

    // Transform request to Gemini format
    const request_json = try google.transformRequest(allocator, params);
    defer allocator.free(request_json);

    // Verify request structure
    try testing.expect(std.mem.indexOf(u8, request_json, "\"model\":\"gemini-2.0-flash\"") != null);
    try testing.expect(std.mem.indexOf(u8, request_json, "\"contents\"") != null);
    try testing.expect(std.mem.indexOf(u8, request_json, "\"temperature\":") != null);

    // Simulate a Gemini API response
    const mock_response =
        \\{"candidates":[{"content":{"parts":[{"text":"The answer is 4."}]}}]}
    ;

    // Parse the response
    const parsed = try google.parseResponse(allocator, mock_response);
    defer {
        allocator.free(parsed.id);
        allocator.free(parsed.model);
        for (parsed.choices) |choice| {
            allocator.free(choice.message.content orelse "");
            allocator.free(choice.finish_reason);
        }
        allocator.free(parsed.choices);
    }

    try testing.expect(parsed.choices.len > 0);
    try testing.expect(parsed.choices[0].message.content != null);
}
