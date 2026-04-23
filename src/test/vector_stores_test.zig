//! Vector Stores and Tool Calling Tests
//!
//! Tests aligned with openai-go capabilities

const std = @import("std");
const testing = std.testing;

const chat = @import("chat");
const tool = @import("tool");

// ============================================================================
// Vector Stores Tests
// ============================================================================

test "VectorStoreCreateParams basic" {
    const params = @import("vector_stores").VectorStoreCreateParams{
        .name = "my-knowledge-base",
    };

    try testing.expect(params.name != null);
    try testing.expectEqualStrings("my-knowledge-base", params.name.?);
}

test "VectorStoreCreateParams with file_ids" {
    const file_ids = &.{ "file-abc123", "file-def456" };
    const params = @import("vector_stores").VectorStoreCreateParams{
        .file_ids = file_ids,
        .name = "test-store",
    };

    try testing.expect(params.file_ids != null);
    try testing.expectEqual(@as(usize, 2), params.file_ids.?.len);
}

test "VectorStoreSearchParams basic" {
    const params = @import("vector_stores").VectorStoreSearchParams{
        .query = "machine learning",
        .top_k = 5,
    };

    try testing.expectEqualStrings("machine learning", params.query);
    try testing.expectEqual(@as(u32, 5), params.top_k.?);
}

test "ChunkingStrategy" {
    const strategy = @import("vector_stores").ChunkingStrategy{
        .static = .{
            .chunk_size = 1024,
            .chunk_overlap = 128,
        },
    };

    try testing.expectEqual(@as(u32, 1024), strategy.static.chunk_size);
    try testing.expectEqual(@as(u32, 128), strategy.static.chunk_overlap);
}

// ============================================================================
// Tool Calling Tests
// ============================================================================

test "Tool definition basic" {
    const t = tool.Tool{
        .name = "get_weather",
        .description = "Get weather at the given location",
        .parameters = .{
            .type = "object",
            .properties = std.StringHashMap(@import("vector_stores").ToolProperty).init(testing.allocator),
            .required = &.{"location"},
        },
    };

    try testing.expectEqualStrings("get_weather", t.name);
    try testing.expectEqualStrings("get_weather", t.description);
}

test "ToolProperty with enum" {
    const prop = tool.ToolProperty{
        .type = "string",
        .description = "The city",
        .@"enum" = &.{ "beijing", "shanghai", "guangzhou" },
    };

    try testing.expectEqualStrings("string", prop.type);
    try testing.expect(prop.@"enum" != null);
    try testing.expectEqual(@as(usize, 3), prop.@"enum".?.len);
}

test "ToolResult creation" {
    const result = tool.ToolResult{
        .call_id = "call_abc123",
        .output = "Sunny, 25°C",
    };

    try testing.expectEqualStrings("call_abc123", result.call_id);
    try testing.expectEqualStrings("Sunny, 25°C", result.output);
}

test "Message with tool_call_id" {
    const msg = chat.Message{
        .role = .tool,
        .content = "The weather is sunny",
        .tool_call_id = "call_abc123",
    };

    try testing.expectEqual(chat.Role.tool, msg.role);
    try testing.expectEqualStrings("call_abc123", msg.tool_call_id.?);
    try testing.expectEqualStrings("The weather is sunny", msg.content.?);
}

test "Message with tool_calls" {
    var tool_calls_arr = [_]chat.ToolCall{
        .{
            .id = "call_123",
            .type = "function",
            .function = .{
                .name = "get_weather",
                .arguments = "{\"location\":\"Beijing\"}",
            },
        },
    };

    const msg = chat.Message{
        .role = .assistant,
        .content = null,
        .tool_calls = tool_calls_arr[0..],
    };

    try testing.expectEqual(chat.Role.assistant, msg.role);
    try testing.expect(msg.tool_calls != null);
    try testing.expectEqual(@as(usize, 1), msg.tool_calls.?.len);
    try testing.expectEqualStrings("call_123", msg.tool_calls.?[0].id);
    try testing.expectEqualStrings("get_weather", msg.tool_calls.?[0].function.name);
}

test "ChunkToolCall" {
    const chunk_tc = chat.ChunkToolCall{
        .index = 0,
        .id = "call_456",
        .function = .{
            .name = "get_weather",
            .arguments = "{\"location\":\"Shanghai\"}",
        },
    };

    try testing.expectEqual(@as(u32, 0), chunk_tc.index);
    try testing.expectEqualStrings("call_456", chunk_tc.id.?);
    try testing.expectEqualStrings("get_weather", chunk_tc.function.?.name.?);
}

// ============================================================================
// Tool Serialization Tests
// ============================================================================

test "buildToolMessage" {
    const result = tool.ToolResult{
        .call_id = "call_abc",
        .output = "Result: 42",
    };

    const json = try tool.buildToolMessage(testing.allocator, result.call_id, result.output);
    defer testing.allocator.free(json);

    try testing.expect(std.mem.find(u8, json, "call_abc") != null);
    try testing.expect(std.mem.find(u8, json, "Result: 42") != null);
}

// ============================================================================
// Integration Tests
// ============================================================================

test "Tool calling flow simulation" {
    // Simulate a tool calling flow:
    // 1. Assistant message with tool call request
    // 2. Tool message with result

    // Step 1: Assistant requests tool call
    var tool_calls = [_]chat.ToolCall{
        .{
            .id = "call_001",
            .type = "function",
            .function = .{
                .name = "get_weather",
                .arguments = "{\"location\":\"Tokyo\"}",
            },
        },
    };

    const assistant_msg = chat.Message{
        .role = .assistant,
        .content = "I'll check the weather for you.",
        .tool_calls = tool_calls[0..],
    };

    try testing.expectEqual(chat.Role.assistant, assistant_msg.role);
    try testing.expect(assistant_msg.tool_calls != null);

    // Step 2: Tool returns result
    const tool_msg = chat.Message{
        .role = .tool,
        .content = "The weather in Tokyo is sunny, 22°C",
        .tool_call_id = "call_001",
    };

    try testing.expectEqual(chat.Role.tool, tool_msg.role);
    try testing.expectEqualStrings("call_001", tool_msg.tool_call_id.?);
    try testing.expect(std.mem.find(u8, tool_msg.content.?, "Tokyo") != null);
}

test "Multiple tool calls in sequence" {
    var tool_calls = [_]chat.ToolCall{
        .{
            .id = "call_001",
            .type = "function",
            .function = .{
                .name = "get_weather",
                .arguments = "{\"location\":\"Beijing\"}",
            },
        },
        .{
            .id = "call_002",
            .type = "function",
            .function = .{
                .name = "get_time",
                .arguments = "{\"timezone\":\"Asia/Shanghai\"}",
            },
        },
    };

    const assistant_msg = chat.Message{
        .role = .assistant,
        .content = null,
        .tool_calls = tool_calls[0..],
    };

    try testing.expectEqual(@as(usize, 2), assistant_msg.tool_calls.?.len);
    try testing.expectEqualStrings("call_001", assistant_msg.tool_calls.?[0].id);
    try testing.expectEqualStrings("call_002", assistant_msg.tool_calls.?[1].id);
}
