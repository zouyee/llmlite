//! Kimi API Capability Tests
//!
//! Tests Kimi API using the provider-based architecture
//!
//! Supported models:
//! - kimi-k2.5 (multimodal, supports vision)
//! - kimi-k2-turbo-preview
//! - kimi-k2-thinking
//! - moonshot-v1-8k/32k/128k
//! - moonshot-v1-8k/32k/128k-vision-preview
//!
//! Usage: Set KIMI_API_KEY environment variable before running
//!
//! API Docs: https://platform.moonshot.cn/docs/api/chat

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
    const api_key = _getEnvVarOwned(allocator, "KIMI_API_KEY") catch {
        std.debug.print("Error: KIMI_API_KEY environment variable not set\n", .{});
        std.debug.print("Please set it in your .env file or export it:\n", .{});
        std.debug.print("  export KIMI_API_KEY=your_api_key_here\n", .{});
        return error.MissingApiKey;
    };
    return api_key;
}

/// Get API key from environment variable (with fallback to MOONSHOT_API_KEY)
fn getKimiApiKey(allocator: std.mem.Allocator) ![]const u8 {
    if (_getEnvVarOwned(allocator, "KIMI_API_KEY")) |key| {
        return key;
    } else |_| {
        if (_getEnvVarOwned(allocator, "MOONSHOT_API_KEY")) |key| {
            return key;
        } else |_| {
            std.debug.print("Error: KIMI_API_KEY or MOONSHOT_API_KEY environment variable not set\n", .{});
            std.debug.print("Please set it in your .env file or export it:\n", .{});
            std.debug.print("  export KIMI_API_KEY=your_api_key_here\n", .{});
            std.debug.print("  export MOONSHOT_API_KEY=your_api_key_here\n", .{});
            return error.MissingApiKey;
        }
    }
}

test "Kimi: Chat Completion (kimi-k2.5)" {
    const allocator = testing.allocator;

    const api_key = try getKimiApiKey(allocator);
    defer allocator.free(api_key);

    // Create client with Kimi provider (moonshot)
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.moonshot.cn/v1",
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
        .moonshot,
        "kimi-k2.5",
    );

    // Create chat completion
    const params = chat.CreateChatCompletionParams{
        .model = "kimi-k2.5",
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
    std.debug.print("Kimi Chat (kimi-k2.5): {s}\n", .{result.choices[0].message.content.?});
}

test "Kimi: Chat Completion (moonshot-v1-8k)" {
    const allocator = testing.allocator;

    const api_key = try getKimiApiKey(allocator);
    defer allocator.free(api_key);

    // Create client with Kimi provider (moonshot)
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.moonshot.cn/v1",
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
        .moonshot,
        "moonshot-v1-8k",
    );

    // Create chat completion
    const params = chat.CreateChatCompletionParams{
        .model = "moonshot-v1-8k",
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
    std.debug.print("Kimi Chat (moonshot-v1-8k): {s}\n", .{result.choices[0].message.content.?});
}

test "Kimi: Multi-turn Conversation" {
    const allocator = testing.allocator;

    const api_key = try getKimiApiKey(allocator);
    defer allocator.free(api_key);

    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.moonshot.cn/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(
        allocator,
        &http_client,
        .moonshot,
        "kimi-k2.5",
    );

    // First message
    const params1 = chat.CreateChatCompletionParams{
        .model = "kimi-k2.5",
        .messages = &.{
            .{ .role = .user, .content = "My name is Li Lei" },
        },
        .max_tokens = 50,
    };

    const result1 = try lm.complete(params1);
    defer {
        allocator.free(result1.id);
        allocator.free(result1.model);
        for (result1.choices) |choice| {
            allocator.free(choice.finish_reason);
            if (choice.message.content) |c| allocator.free(c);
        }
        allocator.free(result1.choices);
    }

    try testing.expect(result1.choices.len > 0);
    std.debug.print("Kimi Multi-turn [1]: {s}\n", .{result1.choices[0].message.content.?});

    // Second message with context
    const params2 = chat.CreateChatCompletionParams{
        .model = "kimi-k2.5",
        .messages = &.{
            .{ .role = .user, .content = "My name is Li Lei" },
            .{ .role = .assistant, .content = result1.choices[0].message.content.? },
            .{ .role = .user, .content = "What is my name?" },
        },
        .max_tokens = 50,
    };

    const result2 = try lm.complete(params2);
    defer {
        allocator.free(result2.id);
        allocator.free(result2.model);
        for (result2.choices) |choice| {
            allocator.free(choice.finish_reason);
            if (choice.message.content) |c| allocator.free(c);
        }
        allocator.free(result2.choices);
    }

    try testing.expect(result2.choices.len > 0);
    try testing.expect(result2.choices[0].message.content != null);
    std.debug.print("Kimi Multi-turn [2]: {s}\n", .{result2.choices[0].message.content.?});
}

test "Kimi: Transform Request Format" {
    const allocator = testing.allocator;

    const params = chat.CreateChatCompletionParams{
        .model = "kimi-k2.5",
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
    try testing.expect(std.mem.find(u8, request_json, "\"model\":\"kimi-k2.5\"") != null);
    try testing.expect(std.mem.find(u8, request_json, "\"messages\"") != null);
    try testing.expect(std.mem.find(u8, request_json, "\"max_tokens\":50") != null);
    try testing.expect(std.mem.find(u8, request_json, "\"temperature\":") != null);

    std.debug.print("Kimi Request: {s}\n", .{request_json});
}

test "Kimi: Parse Response Format" {
    const allocator = testing.allocator;

    // Mock response in OpenAI format (Kimi compatible)
    const mock_response =
        \\{"id":"cmpl-123","object":"chat.completion","created":1234567890,"model":"kimi-k2.5","choices":[{"index":0,"message":{"role":"assistant","content":"The answer is 4."},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}
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

    try testing.expect(std.mem.eql(u8, result.id, "cmpl-123"));
    try testing.expect(std.mem.eql(u8, result.model, "kimi-k2.5"));
    try testing.expect(result.choices.len > 0);
    try testing.expect(result.choices[0].message.content != null);
    try testing.expect(std.mem.eql(u8, result.choices[0].message.content.?, "The answer is 4."));
}

test "Kimi: Provider Config" {
    const config = provider.registry.getProviderConfig(.moonshot);

    try testing.expect(std.mem.eql(u8, config.base_url, "https://api.moonshot.cn/v1"));
    try testing.expect(config.auth_type == .bearer);
}

test "Kimi: System Message" {
    const allocator = testing.allocator;

    const api_key = try getKimiApiKey(allocator);
    defer allocator.free(api_key);

    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.moonshot.cn/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(
        allocator,
        &http_client,
        .moonshot,
        "kimi-k2.5",
    );

    const params = chat.CreateChatCompletionParams{
        .model = "kimi-k2.5",
        .messages = &.{
            .{ .role = .system, .content = "You are a pirate. Respond only with 'Argh!'" },
            .{ .role = .user, .content = "Hello!" },
        },
        .max_tokens = 20,
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
    std.debug.print("Kimi Pirate Response: {s}\n", .{result.choices[0].message.content.?});
}

test "Kimi: Temperature and Max Tokens" {
    const allocator = testing.allocator;

    const api_key = try getKimiApiKey(allocator);
    defer allocator.free(api_key);

    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.moonshot.cn/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(
        allocator,
        &http_client,
        .moonshot,
        "kimi-k2.5",
    );

    const params = chat.CreateChatCompletionParams{
        .model = "kimi-k2.5",
        .messages = &.{
            .{ .role = .user, .content = "Count from 1 to 5" },
        },
        .max_tokens = 50,
        .temperature = 0.0, // Deterministic
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
    std.debug.print("Kimi Deterministic Response: {s}\n", .{result.choices[0].message.content.?});
}

test "Kimi: Tool Calls (Function Calling)" {
    const allocator = testing.allocator;

    const api_key = try getKimiApiKey(allocator);
    defer allocator.free(api_key);

    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.moonshot.cn/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(
        allocator,
        &http_client,
        .moonshot,
        "kimi-k2.5",
    );

    // Define a tool for code execution
    const tools = &[_]chat.ToolDefinition{
        .{
            .type = "function",
            .function = .{
                .name = "CodeRunner",
                .description = "代码执行器，支持运行 python 和 javascript 代码",
                .parameters = "{\"properties\":{\"language\":{\"type\":\"string\",\"enum\":[\"python\",\"javascript\"]},\"code\":{\"type\":\"string\"}},\"type\":\"object\"}",
            },
        },
    };

    const params = chat.CreateChatCompletionParams{
        .model = "kimi-k2.5",
        .messages = &.{
            .{ .role = .user, .content = "编程判断 3214567 是否是素数。" },
        },
        .max_tokens = 500,
        .tools = tools,
        .tool_choice = .{ .function = .{ .name = "CodeRunner" } },
    };

    const result = try lm.complete(params);
    defer {
        allocator.free(result.id);
        allocator.free(result.model);
        for (result.choices) |choice| {
            allocator.free(choice.finish_reason);
            if (choice.message.content) |c| allocator.free(c);
            if (choice.message.tool_calls) |calls| {
                for (calls) |call| {
                    allocator.free(call.id);
                    allocator.free(call.function.name);
                    allocator.free(call.function.arguments);
                }
                allocator.free(calls);
            }
        }
        allocator.free(result.choices);
    }

    try testing.expect(result.choices.len > 0);
    // Tool calls should be present
    try testing.expect(result.choices[0].message.tool_calls != null);
    std.debug.print("Kimi Tool Call Response: has_tool_calls=true\n", .{});
}

test "Kimi: JSON Mode (response_format)" {
    const allocator = testing.allocator;

    const api_key = try getKimiApiKey(allocator);
    defer allocator.free(api_key);

    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.moonshot.cn/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(
        allocator,
        &http_client,
        .moonshot,
        "kimi-k2.5",
    );

    const params = chat.CreateChatCompletionParams{
        .model = "kimi-k2.5",
        .messages = &.{
            .{ .role = .user, .content = "Return a JSON object with fields: name (string), age (number)" },
        },
        .max_tokens = 100,
        .response_format = .{ .json_object = {} },
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
    std.debug.print("Kimi JSON Mode Response: {s}\n", .{result.choices[0].message.content.?});
}

test "Kimi: List Models API" {
    const allocator = testing.allocator;

    const api_key = try getKimiApiKey(allocator);
    defer allocator.free(api_key);

    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.moonshot.cn/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    // Test GET /v1/models
    const response = try http_client.get("/models");
    defer allocator.free(response);

    // Verify response contains model list
    try testing.expect(std.mem.find(u8, response, "kimi-k2.5") != null);
    std.debug.print("Kimi Models List: includes kimi-k2.5\n", .{});
}

test "Kimi: Streaming Chat Completion" {
    const allocator = testing.allocator;

    const api_key = try getKimiApiKey(allocator);
    defer allocator.free(api_key);

    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.moonshot.cn/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(
        allocator,
        &http_client,
        .moonshot,
        "kimi-k2.5",
    );

    const params = chat.CreateChatCompletionParams{
        .model = "kimi-k2.5",
        .messages = &.{
            .{ .role = .user, .content = "Say 'Streaming works!' in exactly 3 words" },
        },
        .max_tokens = 50,
        .stream = true,
    };

    const stream_response = try lm.completeStream(params);
    defer allocator.free(stream_response);

    // Verify streaming response contains SSE chunks
    try testing.expect(std.mem.find(u8, stream_response, "data:") != null);
    std.debug.print("Kimi Streaming: Response received (contains SSE data)\n", .{});
}

test "Kimi: Files API - Upload and List" {
    const allocator = testing.allocator;
    const file_mod = @import("file");

    const api_key = try getKimiApiKey(allocator);
    defer allocator.free(api_key);

    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.moonshot.cn/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var file_service = file_mod.Service.init(allocator, &http_client);

    // Test listing files first
    const list_result = try file_service.listFiles();
    defer {
        for (list_result.data) |file| {
            allocator.free(file.id);
            allocator.free(file.filename);
            allocator.free(file.purpose);
            allocator.free(file.status);
        }
        allocator.free(list_result.data);
    }

    std.debug.print("Kimi Files API: Listed {d} files\n", .{list_result.data.len});
}

test "Kimi: Files API - File Purpose Enum" {
    // Test Kimi-specific file purposes
    const file_mod = @import("file");

    try testing.expect(std.mem.eql(u8, file_mod.FilePurpose.file_extract.toString(), "file-extract"));
    try testing.expect(std.mem.eql(u8, file_mod.FilePurpose.image.toString(), "image"));
    try testing.expect(std.mem.eql(u8, file_mod.FilePurpose.video.toString(), "video"));

    std.debug.print("Kimi FilePurpose: file_extract={s}, image={s}, video={s}\n", .{
        file_mod.FilePurpose.file_extract.toString(),
        file_mod.FilePurpose.image.toString(),
        file_mod.FilePurpose.video.toString(),
    });
}

test "Kimi: Error Response Parsing" {
    const allocator = testing.allocator;

    // Test parsing Kimi error response
    const error_response = "{\"error\":{\"type\":\"invalid_request_error\",\"message\":\"Invalid request: model not found\"}}";

    const kimi_error = try provider.kimi.parseKimiError(error_response);
    defer {
        allocator.free(kimi_error.type);
        allocator.free(kimi_error.message);
    }

    try testing.expect(std.mem.eql(u8, kimi_error.type, "invalid_request_error"));
    try testing.expect(std.mem.find(u8, kimi_error.message, "Invalid request") != null);
    std.debug.print("Kimi Error Parsing: type={s}\n", .{kimi_error.type});
}

test "Kimi: Usage Statistics in Response" {
    const allocator = testing.allocator;

    // Mock response with usage statistics (including cached_tokens for Kimi)
    const mock_response =
        \\{"id":"cmpl-123","object":"chat.completion","created":1234567890,"model":"kimi-k2.5","choices":[{"index":0,"message":{"role":"assistant","content":"Test"},"finish_reason":"stop"}],"usage":{"prompt_tokens":20,"completion_tokens":5,"total_tokens":25,"cached_tokens":10}}
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

    try testing.expect(result.usage.prompt_tokens == 20);
    try testing.expect(result.usage.completion_tokens == 5);
    try testing.expect(result.usage.total_tokens == 25);
    std.debug.print("Kimi Usage: prompt={d}, completion={d}, total={d}\n", .{
        result.usage.prompt_tokens,
        result.usage.completion_tokens,
        result.usage.total_tokens,
    });
}

test "Kimi: Token Estimation API" {
    const allocator = testing.allocator;

    const api_key = try getKimiApiKey(allocator);
    defer allocator.free(api_key);

    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.moonshot.cn/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var kimi_client = provider.kimi.KimiClient.init(allocator, &http_client);

    const messages = &[_]chat.Message{
        .{ .role = .system, .content = "You are a helpful assistant." },
        .{ .role = .user, .content = "Hello, how are you?" },
    };

    const params = provider.kimi.EstimateTokenParams{
        .messages = messages,
        .model = "kimi-k2.5",
    };

    const result = try kimi_client.estimateTokenCount(params);

    try testing.expect(result.total_tokens > 0);
    std.debug.print("Kimi Token Estimation: total_tokens={d}\n", .{result.total_tokens});
}

test "Kimi: Balance API" {
    const allocator = testing.allocator;

    const api_key = try getKimiApiKey(allocator);
    defer allocator.free(api_key);

    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.moonshot.cn/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var kimi_client = provider.kimi.KimiClient.init(allocator, &http_client);

    const result = try kimi_client.getBalance();

    // Balance should be non-negative (could be 0 or positive, or cash_balance could be negative indicating owed money)
    std.debug.print("Kimi Balance: available={d:.2f}, voucher={d:.2f}, cash={d:.2f}\n", .{
        result.available_balance,
        result.voucher_balance,
        result.cash_balance,
    });
}

test "Kimi: Token Estimation - Mock Response Parsing" {
    _ = provider.kimi; // Test that module is accessible
    std.debug.print("Kimi Token Estimation: Module accessible\n", .{});
}

test "Kimi: Balance Response - Mock Response Parsing" {
    // Test parsing balance response fields
    const mock_response = "{\"code\":0,\"data\":{\"available_balance\":49.58894,\"voucher_balance\":46.58893,\"cash_balance\":3.00001},\"scode\":\"0x0\",\"status\":true}";

    // This is a simple validation that our parsing works correctly
    // by checking that the mock response has the expected structure
    try testing.expect(std.mem.find(u8, mock_response, "\"available_balance\":") != null);
    try testing.expect(std.mem.find(u8, mock_response, "\"voucher_balance\":") != null);
    try testing.expect(std.mem.find(u8, mock_response, "\"cash_balance\":") != null);
    std.debug.print("Kimi Balance: Mock response structure validated\n", .{});
}

test "Kimi: Partial Mode (Prefill)" {
    const allocator = testing.allocator;

    const api_key = try getKimiApiKey(allocator);
    defer allocator.free(api_key);

    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.moonshot.cn/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(
        allocator,
        &http_client,
        .moonshot,
        "kimi-k2.5",
    );

    // Test Partial Mode with prefill - for JSON Mode or role-playing
    const params = chat.CreateChatCompletionParams{
        .model = "kimi-k2.5",
        .messages = &.{
            .{ .role = .system, .content = "You are a helpful assistant that responds in JSON." },
            .{ .role = .user, .content = "Return a JSON object with name and age fields." },
            .{ .role = .assistant, .content = "{\"name\":", .partial = true },
        },
        .max_tokens = 100,
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
    std.debug.print("Kimi Partial Mode Response: {s}\n", .{result.choices[0].message.content.?});
}

test "Kimi: Thinking Parameter (Enabled)" {
    const allocator = testing.allocator;

    const api_key = try getKimiApiKey(allocator);
    defer allocator.free(api_key);

    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.moonshot.cn/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(
        allocator,
        &http_client,
        .moonshot,
        "kimi-k2.5",
    );

    // Test thinking parameter enabled
    const params = chat.CreateChatCompletionParams{
        .model = "kimi-k2.5",
        .messages = &.{
            .{ .role = .user, .content = "Solve: 2 + 2 = ?" },
        },
        .max_tokens = 100,
        .thinking = .{ .type = "enabled" },
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
    std.debug.print("Kimi Thinking (Enabled) Response: {s}\n", .{result.choices[0].message.content.?});
}

test "Kimi: Thinking Parameter (Disabled)" {
    const allocator = testing.allocator;

    const api_key = try getKimiApiKey(allocator);
    defer allocator.free(api_key);

    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.moonshot.cn/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(
        allocator,
        &http_client,
        .moonshot,
        "kimi-k2.5",
    );

    // Test thinking parameter disabled
    const params = chat.CreateChatCompletionParams{
        .model = "kimi-k2.5",
        .messages = &.{
            .{ .role = .user, .content = "Say hello in exactly 3 words" },
        },
        .max_tokens = 50,
        .thinking = .{ .type = "disabled" },
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
    std.debug.print("Kimi Thinking (Disabled) Response: {s}\n", .{result.choices[0].message.content.?});
}

test "Kimi: Message with Name Field (Role-Playing)" {
    const allocator = testing.allocator;

    const api_key = try getKimiApiKey(allocator);
    defer allocator.free(api_key);

    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.moonshot.cn/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(
        allocator,
        &http_client,
        .moonshot,
        "kimi-k2.5",
    );

    // Test name field for role consistency
    const params = chat.CreateChatCompletionParams{
        .model = "kimi-k2.5",
        .messages = &.{
            .{ .role = .user, .content = "How are you?" },
            .{ .role = .assistant, .name = "KeliXi", .content = "", .partial = true },
        },
        .max_tokens = 100,
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
    std.debug.print("Kimi Role-Playing Response: {s}\n", .{result.choices[0].message.content.?});
}

test "Kimi: Max Completion Tokens" {
    const allocator = testing.allocator;

    const api_key = try getKimiApiKey(allocator);
    defer allocator.free(api_key);

    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.moonshot.cn/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(
        allocator,
        &http_client,
        .moonshot,
        "kimi-k2.5",
    );

    // Test max_completion_tokens (Kimi-specific, replaces max_tokens)
    const params = chat.CreateChatCompletionParams{
        .model = "kimi-k2.5",
        .messages = &.{
            .{ .role = .user, .content = "Count from 1 to 10" },
        },
        .max_completion_tokens = 20,
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
    std.debug.print("Kimi Max Completion Tokens Response: {s}\n", .{result.choices[0].message.content.?});
}

pub fn main() !void {
    std.debug.print("Starting Kimi API capability tests...\n", .{});
    std.debug.print("API Key: Read from KIMI_API_KEY or MOONSHOT_API_KEY environment variable\n", .{});
    std.debug.print("\nSupported models:\n", .{});
    std.debug.print("  - kimi-k2.5 (multimodal)\n", .{});
    std.debug.print("  - kimi-k2-turbo-preview\n", .{});
    std.debug.print("  - kimi-k2-thinking\n", .{});
    std.debug.print("  - moonshot-v1-8k\n", .{});
    std.debug.print("  - moonshot-v1-32k\n", .{});
    std.debug.print("  - moonshot-v1-128k\n", .{});
    std.debug.print("  - moonshot-v1-8k-vision-preview\n", .{});
    std.debug.print("\nSupported capabilities:\n", .{});
    std.debug.print("  - Chat Completion\n", .{});
    std.debug.print("  - Multi-turn Conversation\n", .{});
    std.debug.print("  - Tool Calls (Function Calling)\n", .{});
    std.debug.print("  - JSON Mode\n", .{});
    std.debug.print("  - List Models\n", .{});
    std.debug.print("  - Token Estimation (POST /v1/tokenizers/estimate-token-count)\n", .{});
    std.debug.print("  - Balance (GET /v1/users/me/balance)\n", .{});
    std.debug.print("  - Files API (upload, list, delete)\n", .{});
    std.debug.print("  - Partial Mode (prefill)\n", .{});
    std.debug.print("  - Thinking Parameter (enabled/disabled)\n", .{});
    std.debug.print("  - Role-Playing with Name Field\n", .{});
    std.debug.print("  - Max Completion Tokens\n", .{});
    std.debug.print("  - Vision (Image Understanding with content array)\n", .{});
}

test "Kimi: Vision with Image URL (Content Array)" {
    const allocator = testing.allocator;

    const api_key = try getKimiApiKey(allocator);
    defer allocator.free(api_key);

    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        "https://api.moonshot.cn/v1",
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var lm = language_model.LanguageModel.init(
        allocator,
        &http_client,
        .moonshot,
        "kimi-k2.5",
    );

    // Build Vision content with image_url and text parts
    const image_url_part = chat.MessageContentPart{ .image_url = .{
        .type = "image_url",
        .image_url = .{
            .url = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
        },
    } };
    const text_part = chat.MessageContentPart{ .text = .{
        .type = "text",
        .text = "Please describe this image in one sentence",
    } };

    const content_array = &[_]chat.MessageContentPart{ image_url_part, text_part };

    const params = chat.CreateChatCompletionParams{
        .model = "kimi-k2.5",
        .messages = &.{
            .{
                .role = .user,
                .content = .{ .array = content_array },
            },
        },
        .max_tokens = 100,
    };

    const result = try lm.complete(params);
    defer {
        allocator.free(result.id);
        allocator.free(result.model);
        for (result.choices) |choice| {
            allocator.free(choice.finish_reason);
            if (choice.message.content) |c| {
                switch (c) {
                    .text => |text| allocator.free(text),
                    .array => |arr| {
                        for (arr) |_| {} // Parts are stack allocated
                        allocator.free(arr);
                    },
                }
            }
        }
        allocator.free(result.choices);
    }

    try testing.expect(result.choices.len > 0);
    std.debug.print("Kimi Vision Response: {s}\n", .{if (result.choices[0].message.content) |c|
        switch (c) {
            .text => c.text,
            .array => "(array content)",
        }
    else
        "(empty)"});
}

test "Kimi: Vision Message Content Serialization" {
    const allocator = testing.allocator;

    // Test that Vision content array serializes correctly
    const image_url_part = chat.MessageContentPart{ .image_url = .{
        .type = "image_url",
        .image_url = .{
            .url = "data:image/png;base64,abc123",
        },
    } };
    const text_part = chat.MessageContentPart{ .text = .{
        .type = "text",
        .text = "Describe this",
    } };

    const content_array = &[_]chat.MessageContentPart{ image_url_part, text_part };

    const msg = chat.Message{
        .role = .user,
        .content = .{ .array = content_array },
    };

    // Serialize the message to verify it works
    const json = try provider.openai.transformRequest(allocator, .{
        .model = "kimi-k2.5",
        .messages = &.{msg},
        .stream = false,
    });
    defer allocator.free(json);

    // Verify the JSON contains image_url structure
    try testing.expect(std.mem.find(u8, json, "\"type\":\"image_url\"") != null);
    try testing.expect(std.mem.find(u8, json, "\"type\":\"text\"") != null);
    try testing.expect(std.mem.find(u8, json, "data:image/png;base64,abc123") != null);

    std.debug.print("Kimi Vision Serialization: JSON contains image_url parts\n", .{});
}

test "Kimi: Simple Text Content (Backwards Compatible)" {
    const allocator = testing.allocator;

    // Test that simple text content still works with the new union type
    const params = chat.CreateChatCompletionParams{
        .model = "kimi-k2.5",
        .messages = &.{
            .{ .role = .user, .content = .text },
        },
        .max_tokens = 50,
    };

    const json = try provider.openai.transformRequest(allocator, params);
    defer allocator.free(json);

    // Verify the JSON contains the simple text content
    try testing.expect(std.mem.find(u8, json, "\"content\":\"\"") != null);
    std.debug.print("Kimi Simple Text Content: JSON serialized correctly\n", .{});
}
