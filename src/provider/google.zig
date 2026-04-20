//! Google Provider - Google Gemini API Format Implementation
//!
//! Google Gemini API uses a different format from OpenAI:
//! - Endpoint: /v1beta/models/{model}:generateContent
//! - Auth: API Key as query parameter (?key=API_KEY)
//! - Request format: {"contents": [{"role": "user", "parts": [{"text": "..."}]}]}
//! - Response format: {"candidates": [{"content": {"parts": [{"text": "..."}]}}]}

const std = @import("std");
const types = @import("types");
const http_mod = @import("http");
const chat_pkg = @import("chat");

pub const ProviderType = types.ProviderType;
pub const ProviderConfig = types.ProviderConfig;

// ============================================================================
// Endpoint Helpers - Google Gemini API endpoints
// ============================================================================

/// Get the proper endpoint path for Google Gemini API
/// For non-streaming: /v1beta/models/{model}:generateContent
/// For streaming: /v1beta/models/{model}:streamGenerateContent
pub fn getEndpoint(model: []const u8, streaming: bool) []const u8 {
    if (streaming) {
        return std.fmt.comptimePrint("/models/{s}:streamGenerateContent", .{model});
    } else {
        return std.fmt.comptimePrint("/models/{s}:generateContent", .{model});
    }
}

/// Get the non-streaming endpoint
pub fn getGenerateContentEndpoint(model: []const u8) []const u8 {
    return "/models/" ++ model ++ ":generateContent";
}

/// Get the streaming endpoint
pub fn getStreamGenerateContentEndpoint(model: []const u8) []const u8 {
    return "/models/" ++ model ++ ":streamGenerateContent";
}

// ============================================================================
// Request Transformer - Google Gemini API Format
// ============================================================================

pub fn transformRequest(allocator: std.mem.Allocator, params: chat_pkg.CreateChatCompletionParams) ![]u8 {
    return transformGeminiRequest(allocator, params);
}

fn transformGeminiRequest(allocator: std.mem.Allocator, params: chat_pkg.CreateChatCompletionParams) ![]u8 {
    // Build contents array (Google Gemini format)
    var contents_json = std.ArrayListUnmanaged(u8){};
    defer contents_json.deinit(allocator);

    try contents_json.appendSlice(allocator, "[");

    var is_first = true;
    var system_instruction: ?[]const u8 = null;

    for (params.messages) |msg| {
        if (msg.role == .system and msg.content != null) {
            // Store system instruction for later
            system_instruction = msg.content;
            continue;
        }

        if (!is_first) try contents_json.appendSlice(allocator, ",");
        is_first = false;

        try contents_json.appendSlice(allocator, try serializeContentToJson(allocator, msg));
    }
    try contents_json.appendSlice(allocator, "]");

    // Build generation config if any parameters are set
    var gen_config_json: ?[]u8 = null;
    if (params.temperature != null or params.max_tokens != null or params.top_p != null) {
        gen_config_json = try buildGenerationConfig(allocator, params);
    }

    // Build the full JSON - Google Gemini native format
    var result = std.ArrayListUnmanaged(u8){};
    defer result.deinit(allocator);

    try result.appendSlice(allocator, "{\"contents\":");
    try result.appendSlice(allocator, try contents_json.toOwnedSlice(allocator));

    // Add system instruction if present
    if (system_instruction) |sys| {
        try result.appendSlice(allocator, ",\"systemInstruction\":{\"parts\":[{\"text\":\"");
        try result.appendSlice(allocator, sys);
        try result.appendSlice(allocator, "\"}]}");
    }

    // Add generation config if present
    if (gen_config_json) |gc| {
        try result.appendSlice(allocator, ",\"generationConfig\":");
        try result.appendSlice(allocator, gc);
    }

    try result.appendSlice(allocator, "}");

    return try result.toOwnedSlice(allocator);
}

fn serializeContentToJson(allocator: std.mem.Allocator, msg: chat_pkg.Message) ![]u8 {
    // Google Gemini uses "parts" instead of "content"
    // Role is either "user" or "model" (not "assistant")
    const role_str = switch (msg.role) {
        .user => "user",
        .assistant => "model",
        .system => "user", // System messages treated as user
        else => "user",
    };

    // For now, we only support text content
    // Image support would require inlineData parts
    if (msg.content) |c| {
        return try std.fmt.allocPrint(allocator, "{{\"role\":\"{s}\",\"parts\":[{{\"text\":\"{s}\"}}]}}", .{ role_str, c });
    } else {
        return try std.fmt.allocPrint(allocator, "{{\"role\":\"{s}\",\"parts\":[{{\"text\":\"\"}}]}}", .{role_str});
    }
}

fn buildGenerationConfig(allocator: std.mem.Allocator, params: chat_pkg.CreateChatCompletionParams) ![]u8 {
    var config = std.ArrayListUnmanaged(u8){};
    try config.appendSlice(allocator, "{");
    var has_field = false;

    if (params.temperature) |v| {
        if (has_field) try config.appendSlice(allocator, ",");
        try config.appendSlice(allocator, "\"temperature\":");
        try config.writer(allocator).print("{}", .{v});
        has_field = true;
    }

    if (params.max_tokens) |v| {
        if (has_field) try config.appendSlice(allocator, ",");
        try config.appendSlice(allocator, "\"maxOutputTokens\":");
        try config.writer(allocator).print("{d}", .{v});
        has_field = true;
    }

    if (params.top_p) |v| {
        if (has_field) try config.appendSlice(allocator, ",");
        try config.appendSlice(allocator, "\"topP\":");
        try config.writer(allocator).print("{}", .{v});
        has_field = true;
    }

    try config.appendSlice(allocator, "}");
    return try config.toOwnedSlice(allocator);
}

// ============================================================================
// Response Parser - Google Gemini API Format
// ============================================================================

pub fn parseResponse(allocator: std.mem.Allocator, response: []const u8) !chat_pkg.ChatCompletion {
    // Try Google Gemini native format first
    if (parseGeminiResponse(allocator, response)) |result| {
        return result;
    }

    // Fallback to OpenAI-compatible format
    return parseOpenAIResponse(allocator, response);
}

fn parseGeminiResponse(allocator: std.mem.Allocator, response: []const u8) !chat_pkg.ChatCompletion {
    // Google Gemini native response format:
    // {"candidates": [{"content": {"parts": [{"text": "..."}]}}]}

    // Parse candidates array
    const candidates_start = std.mem.indexOf(u8, response, "\"candidates\":") orelse return error.ParseError;
    const after_candidates = response[candidates_start..];

    // Find the first "content" object within candidates
    const content_start = std.mem.indexOf(u8, after_candidates, "\"content\":") orelse return error.ParseError;
    const after_content = after_candidates[content_start..];

    // Find "parts" array
    const parts_start = std.mem.indexOf(u8, after_content, "\"parts\":") orelse return error.ParseError;
    const after_parts = after_content[parts_start..];

    // Find the first "text" field
    const text_field_start = std.mem.indexOf(u8, after_parts, "\"text\":\"") orelse return error.ParseError;
    const text_value_start = text_field_start + 9; // length of "\"text\":\""
    const text_value_end = std.mem.indexOf(u8, after_parts[text_value_start..], "\"") orelse return error.ParseError;
    const text = after_parts[text_value_start .. text_value_start + text_value_end];

    // Parse usage if present
    var usage = chat_pkg.Usage{
        .prompt_tokens = 0,
        .completion_tokens = 0,
        .total_tokens = 0,
    };

    if (std.mem.indexOf(u8, response, "\"usage\":")) |usage_idx| {
        const after_usage = response[usage_idx..];
        const prompt_tokens = parseGeminiField(after_usage, "promptTokens") orelse "0";
        const completion_tokens = parseGeminiField(after_usage, "completionTokens") orelse "0";
        const total_tokens = parseGeminiField(after_usage, "totalTokens") orelse "0";

        usage.prompt_tokens = std.fmt.parseInt(u32, prompt_tokens, 10) catch 0;
        usage.completion_tokens = std.fmt.parseInt(u32, completion_tokens, 10) catch 0;
        usage.total_tokens = std.fmt.parseInt(u32, total_tokens, 10) catch 0;
    }

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

    // Generate a mock ID since Google doesn't provide one in this format
    const id = try std.fmt.allocPrint(allocator, "gemini-{}", .{std.time.nanoTimestamp()});

    return chat_pkg.ChatCompletion{
        .id = id,
        .choices = choices,
        .created = @intCast(std.time.timestamp()),
        .model = try allocator.dupe(u8, "gemini"),
        .usage = usage,
    };
}

fn parseGeminiField(json_str: []const u8, field_name: []const u8) ?[]const u8 {
    const search_pattern = "\"" ++ field_name ++ "\":";
    const start_idx = std.mem.indexOf(u8, json_str, search_pattern) orelse return null;
    const value_start = start_idx + search_pattern.len;

    var i = value_start;
    while (i < json_str.len and (json_str[i] == ' ' or json_str[i] == '\n' or json_str[i] == '\t')) {
        i += 1;
    }

    if (i >= json_str.len) return null;

    if (json_str[i] == '"') {
        // String value
        i += 1;
        const str_start = i;
        while (i < json_str.len and json_str[i] != '"') {
            i += 1;
        }
        return json_str[str_start..i];
    } else {
        // Number value
        const num_start = i;
        while (i < json_str.len and (std.ascii.isDigit(json_str[i]) or json_str[i] == '.' or json_str[i] == '-')) {
            i += 1;
        }
        return json_str[num_start..i];
    }
}

fn parseOpenAIResponse(allocator: std.mem.Allocator, response: []const u8) !chat_pkg.ChatCompletion {
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

// ============================================================================
// Streaming Support - Google Gemini SSE parsing
// ============================================================================

/// Google Gemini streaming chunk
pub const GeminiStreamChunk = struct {
    text: []const u8,
    done: bool,
    usage: ?GeminiUsageMetadata = null,
};

/// Google Gemini usage metadata
pub const GeminiUsageMetadata = struct {
    prompt_tokens: u32 = 0,
    candidates_tokens: u32 = 0,
    total_tokens: u32 = 0,
};

/// Handler for Google Gemini SSE streaming responses
pub const GeminiStreamHandler = struct {
    allocator: std.mem.Allocator,
    accumulated_text: std.ArrayListUnmanaged(u8),
    chunks: std.ArrayListUnmanaged(GeminiStreamChunk),
    done: bool,

    pub fn init(allocator: std.mem.Allocator) GeminiStreamHandler {
        return .{
            .allocator = allocator,
            .accumulated_text = std.ArrayListUnmanaged(u8){},
            .chunks = std.ArrayListUnmanaged(GeminiStreamChunk){},
            .done = false,
        };
    }

    pub fn deinit(self: *GeminiStreamHandler) void {
        self.accumulated_text.deinit(self.allocator);
        for (self.chunks.items) |chunk| {
            self.allocator.free(chunk.text);
        }
        self.chunks.deinit(self.allocator);
    }

    /// Feed streaming data to the handler
    pub fn feed(self: *GeminiStreamHandler, data: []const u8) !void {
        // Parse SSE events from the data
        var lines = std.mem.split(u8, data, "\n");

        while (lines.next()) |line| {
            // Skip empty lines
            if (line.len == 0) continue;

            // Parse SSE data line
            if (std.mem.startsWith(u8, line, "data:")) {
                const json_data = line[5..];
                // Skip the [DONE] message
                if (std.mem.eql(u8, json_data, "[DONE]")) {
                    self.done = true;
                    continue;
                }

                // Parse the JSON chunk
                if (parseGeminiStreamChunk(self.allocator, json_data)) |chunk| {
                    if (chunk.text.len > 0) {
                        try self.accumulated_text.appendSlice(self.allocator, chunk.text);
                    }
                    if (chunk.done) {
                        self.done = true;
                    }
                    try self.chunks.append(self.allocator, chunk);
                }
            }
        }
    }

    /// Get accumulated text
    pub fn getText(self: *GeminiStreamHandler) []const u8 {
        return self.accumulated_text.items;
    }

    /// Get all chunks
    pub fn getChunks(self: *GeminiStreamHandler) []const GeminiStreamChunk {
        return self.chunks.items;
    }

    /// Check if streaming is complete
    pub fn isComplete(self: *GeminiStreamHandler) bool {
        return self.done;
    }
};

/// Parse a single Gemini streaming chunk
fn parseGeminiStreamChunk(allocator: std.mem.Allocator, json_data: []const u8) !?GeminiStreamChunk {
    // Check for "done" in the response
    const done = std.mem.indexOf(u8, json_data, "\"done\":true") != null;

    // Extract text from candidates[0].content.parts[0].text
    const text = extractGeminiTextDelta(allocator, json_data);

    if (text == null and !done) {
        return null;
    }

    return GeminiStreamChunk{
        .text = text orelse "",
        .done = done,
        .usage = null,
    };
}

/// Extract text delta from Gemini streaming JSON
fn extractGeminiTextDelta(allocator: std.mem.Allocator, json_data: []const u8) ?[]u8 {
    // Find "candidates"
    const candidates_start = std.mem.indexOf(u8, json_data, "\"candidates\":") orelse return null;
    const after_candidates = json_data[candidates_start + 13 ..];

    // Find "content"
    const content_start = std.mem.indexOf(u8, after_candidates, "\"content\":") orelse return null;
    const after_content = after_candidates[content_start + 11 ..];

    // Find "parts"
    const parts_start = std.mem.indexOf(u8, after_content, "\"parts\":") orelse return null;
    const after_parts = after_content[parts_start + 9 ..];

    // Find "text"
    const text_start = std.mem.indexOf(u8, after_parts, "\"text\":\"") orelse return null;
    const value_start = text_start + 9;
    var value_end = value_start;
    while (value_end < after_parts.len and after_parts[value_end] != '"') {
        value_end += 1;
    }

    const text = after_parts[value_start..value_end];
    if (text.len == 0) return null;

    return try allocator.dupe(u8, text);
}

// ============================================================================
// Gemini Native Chats API - Multi-turn conversations with history
// ============================================================================

/// Gemini native chat session
pub const GeminiChat = struct {
    name: []const u8,
    model: []const u8,
    history: []Content,
};

/// Content for chat messages
pub const Content = struct {
    role: []const u8,
    parts: []Part,
};

/// Part of a message
pub const Part = union(enum) {
    text: []const u8,
};

/// Create a new chat session
pub fn createChat(allocator: std.mem.Allocator, model: []const u8, config: ?*const GenerateContentConfig) !GeminiChat {
    // POST /v1beta/{model}:generateContent (with empty contents creates a new chat)
    const endpoint = try std.fmt.allocPrint(allocator, "/v1beta/{s}:generateContent", .{model});
    defer allocator.free(endpoint);

    // Empty contents to initialize chat
    _ = config;

    return GeminiChat{
        .name = try allocator.dupe(u8, endpoint),
        .model = try allocator.dupe(u8, model),
        .history = &.{},
    };
}

/// Send message to chat and get response (Gemini native format)
pub fn sendChatMessage(allocator: std.mem.Allocator, chat: *GeminiChat, message: []const u8, config: ?*const GenerateContentConfig) !ChatResponse {
    // Use the chat's model and append user message to history
    const user_content = Content{
        .role = "user",
        .parts = &.{.{ .text = message }},
    };

    // Build request with full history
    const request_body = try buildChatRequestBody(allocator, chat, user_content, config);
    defer allocator.free(request_body);

    // Parse response and append to history
    // This is a simplified version - actual implementation would call the API
    // In real implementation: call API with request_body and parse response

    return ChatResponse{
        .text = request_body, // Placeholder
        .done = true,
    };
}

/// Send message to chat and get streaming response (Gemini native format)
/// Returns SSE stream data that can be processed by GeminiStreamHandler
pub fn sendChatMessageStream(allocator: std.mem.Allocator, chat: *GeminiChat, message: []const u8, config: ?*const GenerateContentConfig) ![]u8 {
    // Use the chat's model and append user message to history
    const user_content = Content{
        .role = "user",
        .parts = &.{.{ .text = message }},
    };

    // Build request with full history
    const request_body = try buildChatRequestBody(allocator, chat, user_content, config);
    defer allocator.free(request_body);

    // Return the request body for streaming (actual HTTP call would be done by caller)
    // The caller should POST to the streaming endpoint and handle SSE
    return request_body;
}

/// Send message to chat with Part union (supports more than just text)
/// Returns SSE stream data for streaming response
pub fn sendStream(allocator: std.mem.Allocator, chat: *GeminiChat, parts: []Part, config: ?*const GenerateContentConfig) ![]u8 {
    const user_content = Content{
        .role = "user",
        .parts = parts,
    };

    // Build request with full history
    const request_body = try buildChatRequestBody(allocator, chat, user_content, config);
    defer allocator.free(request_body);

    // Return the request body for streaming (actual HTTP call would be done by caller)
    return request_body;
}

fn buildChatRequestBody(allocator: std.mem.Allocator, chat: *GeminiChat, new_content: Content, config: ?*const GenerateContentConfig) ![]u8 {
    var body = std.array_list.Managed(u8).init(allocator);
    defer body.deinit();

    try body.appendSlice(allocator, "{\"contents\":[");

    // Append existing history
    for (chat.history, 0..) |content, i| {
        if (i > 0) try body.appendSlice(allocator, ",");
        try body.appendSlice(allocator, try serializeContent(allocator, content));
    }

    // Append new message
    if (chat.history.len > 0) try body.appendSlice(allocator, ",");
    try body.appendSlice(allocator, try serializeContent(allocator, new_content));

    try body.appendSlice(allocator, "]");

    // Add generation config if provided
    if (config) |cfg| {
        try body.appendSlice(allocator, ",\"generationConfig\":{");
        var first = true;
        if (cfg.temperature) |t| {
            if (!first) try body.appendSlice(allocator, ",");
            try body.appendSlice(allocator, "\"temperature\":");
            try body.writer().print("{}", .{t});
            first = false;
        }
        if (cfg.max_output_tokens) |m| {
            if (!first) try body.appendSlice(allocator, ",");
            try body.appendSlice(allocator, "\"maxOutputTokens\":");
            try body.writer().print("{d}", .{m});
            first = false;
        }
        try body.appendSlice(allocator, "}");
    }

    try body.appendSlice(allocator, "}");
    return body.toOwnedSlice();
}

fn serializeContent(allocator: std.mem.Allocator, content: Content) ![]u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    defer result.deinit();

    try result.appendSlice(allocator, "{\"role\":\"");
    try result.appendSlice(allocator, content.role);
    try result.appendSlice(allocator, "\",\"parts\":[");

    for (content.parts, 0..) |part, i| {
        if (i > 0) try result.appendSlice(allocator, ",");
        switch (part) {
            .text => |t| {
                try result.appendSlice(allocator, "{\"text\":\"");
                try result.appendSlice(allocator, t);
                try result.appendSlice(allocator, "\"}");
            },
        }
    }

    try result.appendSlice(allocator, "]}");
    return result.toOwnedSlice();
}

/// Chat response
pub const ChatResponse = struct {
    text: []const u8,
    done: bool,
};

/// Generate content configuration
pub const GenerateContentConfig = struct {
    temperature: ?f32 = null,
    max_output_tokens: ?i32 = null,
    top_p: ?f32 = null,
    top_k: ?i32 = null,
};

// ============================================================================
// Gemini Native Batch API - Batch processing with inline requests and GCS
// ============================================================================

/// Gemini batch job source
pub const BatchJobSource = union(enum) {
    /// Inline requests (Gemini API)
    inlined_requests: []const InlinedRequest,
    /// GCS URI for Vertex AI
    gcs_uri: []const []const u8,
};

/// Inlined request for batch
pub const InlinedRequest = struct {
    contents: []Content,
};

/// Create a batch job (Gemini native format)
pub fn createBatchJob(allocator: std.mem.Allocator, model: []const u8, source: BatchJobSource, display_name: ?[]const u8) ![]u8 {
    var body = std.array_list.Managed(u8).init(allocator);
    defer body.deinit();

    try body.appendSlice(allocator, "{\"model\":\"");
    try body.appendSlice(allocator, model);
    try body.appendSlice(allocator, "\",");

    // Add display name if provided
    if (display_name) |name| {
        try body.appendSlice(allocator, "\"displayName\":\"");
        try body.appendSlice(allocator, name);
        try body.appendSlice(allocator, "\",");
    }

    // Add request source
    switch (source) {
        .inlined_requests => |requests| {
            try body.appendSlice(allocator, "\"inlinedRequests\":[");
            for (requests, 0..) |req, i| {
                if (i > 0) try body.appendSlice(allocator, ",");
                try body.appendSlice(allocator, "{\"contents\":[");
                for (req.contents, 0..) |content, j| {
                    if (j > 0) try body.appendSlice(allocator, ",");
                    try body.appendSlice(allocator, try serializeContent(allocator, content));
                }
                try body.appendSlice(allocator, "]}");
            }
            try body.appendSlice(allocator, "]");
        },
        .gcs_uri => |uris| {
            try body.appendSlice(allocator, "\"gcsSource\":{\"uris\":[");
            for (uris, 0..) |uri, i| {
                if (i > 0) try body.appendSlice(allocator, ",");
                try body.appendSlice(allocator, "\"");
                try body.appendSlice(allocator, uri);
                try body.appendSlice(allocator, "\"");
            }
            try body.appendSlice(allocator, "]}}");
        },
    }

    try body.appendSlice(allocator, "}");
    return body.toOwnedSlice();
}

/// Batch job destination
pub const BatchJobDestination = struct {
    gcs_uri: []const u8,
    format: []const u8 = "jsonl",
};

/// Batch job state
pub const BatchJobState = enum {
    unspecified,
    queuing,
    preparing,
    running,
    succeeded,
    failed,
    cancelled,
    cancelling,

    pub fn toString(self: BatchJobState) []const u8 {
        return switch (self) {
            .unspecified => "JOB_STATE_UNSPECIFIED",
            .queuing => "QUEUING",
            .preparing => "PREPARING",
            .running => "RUNNING",
            .succeeded => "SUCCEEDED",
            .failed => "FAILED",
            .cancelled => "CANCELLED",
            .cancelling => "CANCELLING",
        };
    }
};

/// Batch job response
pub const BatchJob = struct {
    name: []const u8,
    state: BatchJobState,
    display_name: ?[]const u8,
    create_time: ?[]const u8,
    update_time: ?[]const u8,
    completed_time: ?[]const u8,
};

// ============================================================================
// Gemini Native Live API - WebSocket-based real-time communication
// ============================================================================

/// Live client for WebSocket communication
pub const GeminiLiveClient = struct {
    allocator: std.mem.Allocator,
    model: []const u8,
    api_key: []const u8,
    ws_url: []const u8,
    connected: bool = false,

    pub fn init(allocator: std.mem.Allocator, model: []const u8, api_key: []const u8) GeminiLiveClient {
        const ws_url = std.fmt.allocPrint(allocator, "wss://generativelanguage.googleapis.com/v1beta/{s}:streamGenerateContent?key={s}", .{ model, api_key }) catch unreachable;

        return .{
            .allocator = allocator,
            .model = model,
            .api_key = api_key,
            .ws_url = ws_url,
            .connected = false,
        };
    }

    pub fn deinit(self: *GeminiLiveClient) void {
        self.allocator.free(self.ws_url);
    }

    /// Connect to the Live API
    pub fn connect(self: *GeminiLiveClient) !void {
        // In full implementation, this would establish WebSocket connection
        self.connected = true;
    }

    /// Disconnect from the Live API
    pub fn disconnect(self: *GeminiLiveClient) void {
        self.connected = false;
    }

    /// Send a message (text or audio)
    pub fn send(self: *GeminiLiveClient, content: []const u8) !void {
        if (!self.connected) return error.NotConnected;
        _ = content;
    }

    /// Receive a response
    pub fn receive(self: *GeminiLiveClient) ![]u8 {
        if (!self.connected) return error.NotConnected;
        return "";
    }
};

/// Live API message types
pub const LiveMessage = union(enum) {
    text: TextMessage,
    audio: AudioMessage,
};

pub const TextMessage = struct {
    text: []const u8,
};

pub const AudioMessage = struct {
    data: []const u8,
    mime_type: []const u8,
};

/// Live client configuration
pub const LiveConfig = struct {
    modalities: []const []const u8 = &.{"text"},
    voice: ?[]const u8 = null,
    temperature: ?f32 = null,
};
