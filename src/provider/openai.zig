//! OpenAI Provider - OpenAI Compatible Format Implementation
//!
//! OpenAI, Moonshot, MiniMax, DeepSeek, Cohere, Fireworks, Cerebras, Groq, Mistral, Perplexity
//! all use OpenAI-compatible API format

const std = @import("std");
const types = @import("types");
const http_mod = @import("http");
const chat_pkg = @import("chat");

pub const ProviderType = types.ProviderType;
pub const ProviderConfig = types.ProviderConfig;

// ============================================================================
// Request Transformer - OpenAI Compatible Format
// ============================================================================

pub fn transformRequest(allocator: std.mem.Allocator, params: chat_pkg.CreateChatCompletionParams) ![]u8 {
    // Build messages array first
    var messages_json = std.ArrayListUnmanaged(u8){};
    defer messages_json.deinit(allocator);

    try messages_json.appendSlice(allocator, "[");
    for (params.messages, 0..) |msg, i| {
        if (i > 0) try messages_json.appendSlice(allocator, ",");
        try messages_json.appendSlice(allocator, try serializeMessageToJson(allocator, msg));
    }
    try messages_json.appendSlice(allocator, "]");

    // Build the full JSON
    const result = try std.fmt.allocPrint(allocator,
        \\{{"model":"{s}","messages":{s},"stream":{s}{s}{s}}}
    , .{
        params.model,
        try messages_json.toOwnedSlice(allocator),
        if (params.stream) "true" else "false",
        if (params.temperature) |v| try std.fmt.allocPrint(allocator, ",\"temperature\":{d}", .{v}) else "",
        if (params.max_tokens) |v| try std.fmt.allocPrint(allocator, ",\"max_tokens\":{d}", .{v}) else "",
    });
    return result;
}

fn serializeMessageToJson(allocator: std.mem.Allocator, msg: chat_pkg.Message) ![]u8 {
    if (msg.content) |c| {
        return std.fmt.allocPrint(allocator, "{{\"role\":\"{s}\",\"content\":\"{s}\"}}", .{ msg.role.toString(), c });
    } else {
        return std.fmt.allocPrint(allocator, "{{\"role\":\"{s}\"}}", .{msg.role.toString()});
    }
}

// ============================================================================
// Response Parser - OpenAI Compatible Format
// ============================================================================

pub fn parseResponse(allocator: std.mem.Allocator, response: []const u8) !chat_pkg.ChatCompletion {
    const id = parseJsonField(response, "id") orelse return error.ParseError;
    const model_str = parseJsonField(response, "model") orelse return error.ParseError;
    const created_str = parseJsonField(response, "created") orelse return error.ParseError;
    const created = std.fmt.parseInt(u64, created_str, 10) catch return error.ParseError;

    const usage_str = parseJsonField(response, "usage") orelse return error.ParseError;
    const prompt_tokens_str = parseJsonField(usage_str, "prompt_tokens") orelse "0";
    const completion_tokens_str = parseJsonField(usage_str, "completion_tokens") orelse "0";
    const total_tokens_str = parseJsonField(usage_str, "total_tokens") orelse "0";

    const usage = chat_pkg.Usage{
        .prompt_tokens = std.fmt.parseInt(u32, prompt_tokens_str, 10) catch 0,
        .completion_tokens = std.fmt.parseInt(u32, completion_tokens_str, 10) catch 0,
        .total_tokens = std.fmt.parseInt(u32, total_tokens_str, 10) catch 0,
    };

    const choices_start = std.mem.indexOf(u8, response, "\"choices\":") orelse return error.ParseError;
    const after_choices = response[choices_start..];
    const first_content = std.mem.indexOf(u8, after_choices, "\"content\":\"") orelse return error.ParseError;
    const content_start = first_content + 11;
    const content_end = std.mem.indexOf(u8, after_choices[content_start..], "\"") orelse return error.ParseError;
    const content_str = after_choices[content_start .. content_start + content_end];

    var choices = try allocator.alloc(chat_pkg.ChatCompletionChoice, 1);
    errdefer allocator.free(choices);

    choices[0] = chat_pkg.ChatCompletionChoice{
        .finish_reason = try allocator.dupe(u8, "stop"),
        .index = 0,
        .logprobs = null,
        .message = chat_pkg.Message{
            .role = .assistant,
            .content = try allocator.dupe(u8, content_str),
        },
    };

    return chat_pkg.ChatCompletion{
        .id = try allocator.dupe(u8, id),
        .choices = choices,
        .created = created,
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

    const start_idx = std.mem.indexOf(u8, json_str, buf) orelse return null;
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
