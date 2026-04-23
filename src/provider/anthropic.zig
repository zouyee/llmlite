//! Anthropic Provider - Anthropic-Specific Format Implementation
//!
//! Anthropic API uses different message format and authentication

const std = @import("std");
const types = @import("types");
const http_mod = @import("http");
const chat_pkg = @import("chat");

pub const ProviderType = types.ProviderType;
pub const ProviderConfig = types.ProviderConfig;

// ============================================================================
// Request Transformer - Anthropic Format
// ============================================================================

pub fn transformRequest(allocator: std.mem.Allocator, params: chat_pkg.CreateChatCompletionParams) ![]u8 {
    // Anthropic uses a different format: messages are in "messages" array,
    // with system prompt in "system" field

    var system_prompt: ?[]const u8 = null;
    var messages_json: std.ArrayListUnmanaged(u8) = .empty;
    defer messages_json.deinit(allocator);

    try messages_json.appendSlice(allocator, "[");
    for (params.messages, 0..) |msg, i| {
        if (i > 0) try messages_json.appendSlice(allocator, ",");

        // Extract system prompt
        if (msg.role == .system) {
            system_prompt = msg.content;
        } else {
            try messages_json.appendSlice(allocator, try serializeMessageToJson(allocator, msg));
        }
    }
    try messages_json.appendSlice(allocator, "]");

    // Anthropic requires anthropic-version header, and max_tokens is mandatory
    const max_tokens = params.max_tokens orelse 1024;

    // Build the request with optional system prompt
    if (system_prompt) |sys| {
        const result = try std.fmt.allocPrint(allocator,
            \\{{"model":"{s}","system":"{s}","messages":{s},"max_tokens":{d}{s}}}
        , .{
            params.model,
            sys,
            try messages_json.toOwnedSlice(allocator),
            max_tokens,
            if (params.temperature) |v| try std.fmt.allocPrint(allocator, ",\"temperature\":{d}", .{v}) else "",
        });
        return result;
    } else {
        const result = try std.fmt.allocPrint(allocator,
            \\{{"model":"{s}","messages":{s},"max_tokens":{d}{s}}}
        , .{
            params.model,
            try messages_json.toOwnedSlice(allocator),
            max_tokens,
            if (params.temperature) |v| try std.fmt.allocPrint(allocator, ",\"temperature\":{d}", .{v}) else "",
        });
        return result;
    }
}

fn serializeMessageToJson(allocator: std.mem.Allocator, msg: chat_pkg.Message) ![]u8 {
    // Anthropic role format: "user" or "assistant"
    const role_str = switch (msg.role) {
        .user => "user",
        .assistant => "assistant",
        else => "user", // Default to user for unknown roles
    };

    if (msg.content) |c| {
        return std.fmt.allocPrint(allocator, "{{\"role\":\"{s}\",\"content\":\"{s}\"}}", .{ role_str, c });
    } else {
        return std.fmt.allocPrint(allocator, "{{\"role\":\"{s}\"}}", .{role_str});
    }
}

// ============================================================================
// Response Parser - Anthropic Format
// ============================================================================

pub fn parseResponse(allocator: std.mem.Allocator, response: []const u8) !chat_pkg.ChatCompletion {
    // Anthropic response format:
    // {"id":"...","type":"message","model":"claude-...","content":[{"type":"text","text":"..."}],"stop_reason":"end_turn"}

    const id = parseJsonField(response, "id") orelse return error.ParseError;
    const model_str = parseJsonField(response, "model") orelse return error.ParseError;

    // Anthropic uses "content" array instead of "choices"
    const content_str = parseJsonField(response, "content") orelse return error.ParseError;

    // Parse the content array to get the text
    const text_start = std.mem.find(u8, content_str, "\"text\":\"") orelse return error.ParseError;
    const text_value_start = text_start + 8;
    const text_end = std.mem.find(u8, content_str[text_value_start..], "\"") orelse return error.ParseError;
    const text = content_str[text_value_start .. text_value_start + text_end];

    const usage_str = parseJsonField(response, "usage") orelse return error.ParseError;
    const input_tokens_str = parseJsonField(usage_str, "input_tokens") orelse "0";
    const output_tokens_str = parseJsonField(usage_str, "output_tokens") orelse "0";

    const usage = chat_pkg.Usage{
        .prompt_tokens = std.fmt.parseInt(u32, input_tokens_str, 10) catch 0,
        .completion_tokens = std.fmt.parseInt(u32, output_tokens_str, 10) catch 0,
        .total_tokens = 0, // Anthropic doesn't provide this
    };

    var choices = try allocator.alloc(chat_pkg.ChatCompletionChoice, 1);
    errdefer allocator.free(choices);

    choices[0] = chat_pkg.ChatCompletionChoice{
        .finish_reason = try allocator.dupe(u8, "stop"),
        .index = 0,
        .logprobs = null,
        .message = chat_pkg.Message{
            .role = .assistant,
            .content = try allocator.dupe(u8, text),
        },
    };

    return chat_pkg.ChatCompletion{
        .id = try allocator.dupe(u8, id),
        .choices = choices,
        .created = 0, // Anthropic doesn't provide this
        .model = try allocator.dupe(u8, model_str),
        .usage = usage,
    };
}

fn parseJsonField(json_str: []const u8, field_name: []const u8) ?[]const u8 {
    const search_pattern_len = field_name.len + 3;
    var search_pattern_buf: [128]u8 = undefined;
    if (search_pattern_len >= search_pattern_buf.len) return null;

    var buf = search_pattern_buf[0..search_pattern_len];
    buf[0] = '"';
    @memcpy(buf[1..][0..field_name.len], field_name);
    buf[field_name.len + 1] = '"';
    buf[field_name.len + 2] = ':';

    const start_idx = std.mem.find(u8, json_str, buf) orelse return null;
    const value_start = start_idx + search_pattern_len;

    var i = value_start;
    while (i < json_str.len and (json_str[i] == ' ' or json_str[i] == '\n' or json_str[i] == '\t')) {
        i += 1;
    }

    if (i >= json_str.len) return null;

    if (json_str[i] == '"') {
        i += 1;
        const str_start = i;
        while (i < json_str.len and json_str[i] != '"') {
            i += 1;
        }
        return json_str[str_start..i];
    } else if (json_str[i] == '{') {
        var depth: u32 = 1;
        i += 1;
        while (i < json_str.len and depth > 0) {
            if (json_str[i] == '{') depth += 1;
            if (json_str[i] == '}') depth -= 1;
            i += 1;
        }
        return json_str[value_start..i];
    } else if (json_str[i] == '[') {
        var depth: u32 = 1;
        i += 1;
        while (i < json_str.len and depth > 0) {
            if (json_str[i] == '[') depth += 1;
            if (json_str[i] == ']') depth -= 1;
            i += 1;
        }
        return json_str[value_start..i];
    } else {
        const num_start = i;
        while (i < json_str.len and (std.ascii.isDigit(json_str[i]) or json_str[i] == '.' or json_str[i] == '-' or json_str[i] == 'e' or json_str[i] == 'E')) {
            i += 1;
        }
        return json_str[num_start..i];
    }
}
