//! Chat Completions API

const std = @import("std");
const json = std.json;
const http = @import("http");

// ============================================================================
// Service
// ============================================================================

pub const Service = struct {
    allocator: std.mem.Allocator,
    http_client: *http.HttpClient,

    pub fn init(allocator: std.mem.Allocator, http_client: *http.HttpClient) Service {
        return .{
            .allocator = allocator,
            .http_client = http_client,
        };
    }

    pub fn deinit(self: *Service) void {
        _ = self;
    }

    /// Creates a model response for the given chat conversation.
    pub fn createChatCompletion(self: *Service, params: CreateChatCompletionParams) !ChatCompletion {
        const json_str = try self.serializeChatParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/chat/completions", json_str);
        defer self.allocator.free(response);

        return try self.parseChatResponse(response);
    }

    /// Retrieves a chat completion by ID.
    pub fn getChatCompletion(self: *Service, completion_id: []const u8) !ChatCompletion {
        const path = try std.fmt.allocPrint(self.allocator, "/chat/completions/{s}", .{completion_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseChatResponse(response);
    }

    /// Deletes a chat completion by ID.
    pub fn deleteChatCompletion(self: *Service, completion_id: []const u8) !ChatCompletionDeleted {
        const path = try std.fmt.allocPrint(self.allocator, "/chat/completions/{s}", .{completion_id});
        defer self.allocator.free(path);

        const response = try self.http_client.delete(path);
        defer self.allocator.free(response);

        return try self.parseDeleteResponse(response);
    }

    fn parseDeleteResponse(self: *Service, response: []const u8) !ChatCompletionDeleted {
        const id = self.parseJsonField(response, "id") orelse return error.ParseError;
        const deleted_str = self.parseJsonField(response, "deleted") orelse "false";

        return ChatCompletionDeleted{
            .id = try self.allocator.dupe(u8, id),
            .deleted = std.mem.eql(u8, deleted_str, "true"),
        };
    }

    fn serializeChatParams(self: *Service, params: CreateChatCompletionParams) ![]u8 {
        // Build messages array first
        var messages_json = std.ArrayListUnmanaged(u8){};
        defer messages_json.deinit(self.allocator);

        try messages_json.appendSlice(self.allocator, "[");
        for (params.messages, 0..) |msg, i| {
            if (i > 0) try messages_json.appendSlice(self.allocator, ",");
            try messages_json.appendSlice(self.allocator, try serializeMessageToString(self.allocator, msg));
        }
        try messages_json.appendSlice(self.allocator, "]");

        // Build the full JSON
        const result = try std.fmt.allocPrint(self.allocator,
            \\{{"model":"{s}","messages":{s},"stream":{s}{s}{s}}}
        , .{
            params.model,
            try messages_json.toOwnedSlice(self.allocator),
            if (params.stream) "true" else "false",
            if (params.temperature) |v| try std.fmt.allocPrint(self.allocator, ",\"temperature\":{d}", .{v}) else "",
            if (params.max_tokens) |v| try std.fmt.allocPrint(self.allocator, ",\"max_tokens\":{d}", .{v}) else "",
        });
        return result;
    }

    fn serializeMessageToString(allocator: std.mem.Allocator, msg: Message) ![]u8 {
        // Handle tool messages with tool_call_id
        if (msg.tool_call_id) |tool_id| {
            const content = msg.content orelse "";
            return std.fmt.allocPrint(allocator, "{{\"role\":\"{s}\",\"tool_call_id\":\"{s}\",\"content\":\"{s}\"}}", .{ msg.role.toString(), tool_id, content });
        }

        // Handle messages with tool_calls
        if (msg.tool_calls) |calls| {
            // For assistant messages with tool calls, we need to serialize them properly
            var calls_json = std.ArrayList(u8).empty;
            defer calls_json.deinit(allocator);

            try calls_json.appendSlice(allocator, "[");
            for (calls, 0..) |call, i| {
                if (i > 0) try calls_json.appendSlice(allocator, ",");
                try std.fmt.format(calls_json.writer(),
                    \\{{"id":"{s}","type":"function","function":{{"name":"{s}","arguments":"{s}"}}}
                , .{
                    call.id,
                    call.function.name,
                    call.function.arguments,
                });
            }
            try calls_json.appendSlice(allocator, "]");

            if (msg.content) |c| {
                return std.fmt.allocPrint(allocator, "{{\"role\":\"{s}\",\"content\":\"{s}\",\"tool_calls\":{s}}}", .{ msg.role.toString(), c, try calls_json.toOwnedSlice(allocator) });
            } else {
                return std.fmt.allocPrint(allocator, "{{\"role\":\"{s}\",\"tool_calls\":{s}}}", .{ msg.role.toString(), try calls_json.toOwnedSlice(allocator) });
            }
        }

        // Handle regular messages
        if (msg.content) |c| {
            return std.fmt.allocPrint(allocator, "{{\"role\":\"{s}\",\"content\":\"{s}\"}}", .{ msg.role.toString(), c });
        } else {
            return std.fmt.allocPrint(allocator, "{{\"role\":\"{s}\"}}", .{msg.role.toString()});
        }
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

    fn parseChatResponse(self: *Service, response: []const u8) !ChatCompletion {
        const id = parseJsonField(response, "id") orelse return error.ParseError;
        const model_str = parseJsonField(response, "model") orelse return error.ParseError;
        const created_str = parseJsonField(response, "created") orelse return error.ParseError;
        const created = std.fmt.parseInt(u64, created_str, 10) catch return error.ParseError;

        const usage_str = parseJsonField(response, "usage") orelse return error.ParseError;
        const prompt_tokens_str = parseJsonField(usage_str, "prompt_tokens") orelse "0";
        const completion_tokens_str = parseJsonField(usage_str, "completion_tokens") orelse "0";
        const total_tokens_str = parseJsonField(usage_str, "total_tokens") orelse "0";

        const usage = Usage{
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

        var choices = try self.allocator.alloc(ChatCompletionChoice, 1);
        errdefer self.allocator.free(choices);

        choices[0] = ChatCompletionChoice{
            .finish_reason = try self.allocator.dupe(u8, "stop"),
            .index = 0,
            .logprobs = null,
            .message = Message{
                .role = .assistant,
                .content = try self.allocator.dupe(u8, content_str),
            },
        };

        return ChatCompletion{
            .id = try self.allocator.dupe(u8, id),
            .choices = choices,
            .created = created,
            .model = try self.allocator.dupe(u8, model_str),
            .usage = usage,
        };
    }
};

// ============================================================================
// Message Role
// ============================================================================

pub const Role = enum {
    system,
    user,
    assistant,
    tool,
    developer,

    pub fn toString(self: Role) []const u8 {
        return switch (self) {
            .system => "system",
            .user => "user",
            .assistant => "assistant",
            .tool => "tool",
            .developer => "developer",
        };
    }
};

// ============================================================================
// Message Content Parts (for Vision with images/video)
// ============================================================================

pub const MessageContentPartType = enum {
    text,
    image_url,
    video_url,
    refusal,
};

pub const ImageUrlPart = struct {
    type: []const u8 = "image_url",
    image_url: ImageUrl,
};

pub const ImageUrl = struct {
    url: []const u8, // base64 data URI or ms://<file_id>
};

pub const VideoUrlPart = struct {
    type: []const u8 = "video_url",
    video_url: VideoUrl,
};

pub const VideoUrl = struct {
    url: []const u8, // base64 data URI or ms://<file_id>
};

pub const TextPart = struct {
    type: []const u8 = "text",
    text: []const u8,
};

pub const RefusalPart = struct {
    type: []const u8 = "refusal",
    refusal: []const u8,
};

pub const MessageContentPart = union(MessageContentPartType) {
    text: TextPart,
    image_url: ImageUrlPart,
    video_url: VideoUrlPart,
    refusal: RefusalPart,
};

// ============================================================================
// Chat Message
// ============================================================================

pub const Message = struct {
    role: Role,
    /// Simple text content (for backward compatibility)
    /// Use .parts for Vision content with images/video
    content: ?[]const u8 = null,
    /// Vision content parts: array of image_url, video_url, and/or text parts
    /// When set, .content should be null
    parts: ?[]MessageContentPart = null,
    name: ?[]const u8 = null,
    audio: ?AudioContent = null,
    tool_calls: ?[]ToolCall = null,
    tool_call_id: ?[]const u8 = null,
    /// Partial mode (Kimi-specific): when true, guides model output
    /// Used for JSON Mode, role-playing, and controlling output format
    partial: bool = false,
    /// Reasoning content (Kimi K2.5): chain of thought from model's thinking process
    reasoning_content: ?[]const u8 = null,
};

pub const AudioContent = struct {
    id: []const u8,
};

pub const ToolCall = struct {
    id: []const u8,
    type: []const u8 = "function",
    function: FunctionCall,
};

pub const FunctionCall = struct {
    name: []const u8,
    arguments: []const u8,
};

// ============================================================================
// Streaming Response Delta
// ============================================================================

pub const ChunkDelta = struct {
    content: ?[]const u8 = null,
    role: ?[]const u8 = null,
    refusal: ?[]const u8 = null,
    tool_calls: ?[]ChunkToolCall = null,
};

pub const ChunkToolCall = struct {
    index: u32,
    id: ?[]const u8 = null,
    function: ?ChunkFunctionCall = null,
};

pub const ChunkFunctionCall = struct {
    name: ?[]const u8 = null,
    arguments: ?[]const u8 = null,
};

// ============================================================================
// Request Parameters
// ============================================================================

pub const CreateChatCompletionParams = struct {
    messages: []const Message,
    model: []const u8,
    frequency_penalty: ?f32 = null,
    function_call: ?[]const u8 = null,
    functions: ?[]FunctionDefinition = null,
    logit_bias: ?[]i32 = null,
    logprobs: bool = false,
    top_logprobs: ?u32 = null,
    max_tokens: ?u32 = null,
    max_completion_tokens: ?u32 = null, // Kimi uses this instead of max_tokens
    n: ?u32 = 1,
    presence_penalty: ?f32 = null,
    response_format: ?ResponseFormat = null,
    seed: ?i64 = null,
    service_tier: ?[]const u8 = null,
    stop: ?[]const u8 = null,
    stream: bool = false,
    stream_options: ?StreamOptions = null,
    temperature: ?f32 = null,
    tool_choice: ?ToolChoice = null,
    tools: ?[]ToolDefinition = null,
    top_p: ?f32 = null,
    user: ?[]const u8 = null,
    store: bool = false,
    metadata: ?[]const u8 = null,
    /// Kimi-specific: thinking mode for K2.5 models
    thinking: ?ThinkingConfig = null,
};

/// Kimi-specific thinking configuration for K2.5 models
pub const ThinkingConfig = struct {
    type: []const u8, // "enabled" or "disabled"
};

pub const FunctionDefinition = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    parameters: ?[:0]const u8 = null,
};

pub const ResponseFormat = union(enum) {
    text: void,
    json_object: void,
    json_schema: JSONSchemaFormat,
};

pub const JSONSchemaFormat = struct {
    name: []const u8,
    schema: ?[:0]const u8 = null,
    strict: ?bool = null,
};

pub const StreamOptions = struct {
    include_usage: bool = true,
    persistent_predictions: ?bool = null,
};

pub const ToolChoice = union(enum) {
    auto: void,
    none: void,
    required: void,
    function: ToolChoiceFunction,
};

pub const ToolChoiceFunction = struct {
    name: []const u8,
};

pub const ToolDefinition = struct {
    type: []const u8 = "function",
    function: FunctionDefinition,
};

// ============================================================================
// Response Types
// ============================================================================

pub const ChatCompletion = struct {
    id: []const u8,
    choices: []ChatCompletionChoice,
    created: u64,
    model: []const u8,
    object: []const u8 = "chat.completion",
    service_tier: ?[]const u8 = null,
    system_fingerprint: ?[]const u8 = null,
    usage: Usage,
};

pub const ChatCompletionDeleted = struct {
    id: []const u8,
    object: []const u8 = "chat.completion.deleted",
    deleted: bool,
};

pub const ChatCompletionChoice = struct {
    finish_reason: []const u8,
    index: u32,
    logprobs: ?ChatCompletionLogprobs = null,
    message: Message,
};

pub const ChatCompletionLogprobs = struct {
    content: ?[]Logprob = null,
    refusal: ?[]Logprob = null,
};

pub const Logprob = struct {
    token: []const u8,
    logprob: f32,
    bytes: ?[]u8 = null,
    top_logprob: ?f32 = null,
};

pub const Usage = struct {
    prompt_tokens: u32,
    completion_tokens: u32,
    total_tokens: u32,
};

pub const ChatCompletionChunk = struct {
    id: []const u8,
    choices: []ChatCompletionChunkChoice,
    created: u64,
    model: []const u8,
    object: []const u8 = "chat.completion.chunk",
    service_tier: ?[]const u8 = null,
    system_fingerprint: ?[]const u8 = null,
    usage: ?Usage = null,
};

pub const ChatCompletionChunkChoice = struct {
    delta: ChunkDelta,
    finish_reason: ?[]const u8 = null,
    index: u32,
    logprobs: ?ChatCompletionLogprobs = null,
};
