//! Responses API - The new primary API for OpenAI
//!
//! Reference: https://platform.openai.com/docs/api-reference/responses
//!
//! The Responses API is the successor to the Chat Completions API, providing:
//! - Native tool calling support
//! - Structured outputs (JSON schema)
//! - Multi-turn conversations with state
//! - Better streaming support

const std = @import("std");
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

    // ============================================================================
    // Serialization
    // ============================================================================

    fn serializeParams(self: *Service, params: ResponseNewParams) ![]u8 {
        _ = self;
        var parts = std.ArrayListUnmanaged(u8){};
        defer parts.deinit(self.allocator);

        try parts.appendSlice(self.allocator, "{\"model\":\"");
        try parts.appendSlice(self.allocator, params.model);

        // Handle input - can be string or array of items
        try parts.appendSlice(self.allocator, "\",\"input\":");
        if (params.input) |input| {
            try parts.appendSlice(self.allocator, try serializeInput(self.allocator, input));
        } else {
            try parts.appendSlice(self.allocator, "[]");
        }

        // Add optional parameters
        if (params.stream) |stream| {
            try parts.appendSlice(self.allocator, ",\"stream\":");
            try parts.appendSlice(self.allocator, if (stream) "true" else "false");
        }

        if (params.stream_options) |opts| {
            try parts.appendSlice(self.allocator, ",\"stream_options\":");
            try parts.appendSlice(self.allocator, try serializeStreamOptions(self.allocator, opts));
        }

        if (params.max_output_tokens) |v| {
            try parts.appendSlice(self.allocator, try std.fmt.allocPrint(self.allocator, ",\"max_output_tokens\":{d}", .{v}));
        }

        if (params.temperature) |v| {
            try parts.appendSlice(self.allocator, try std.fmt.allocPrint(self.allocator, ",\"temperature\":{d}", .{v}));
        }

        if (params.top_p) |v| {
            try parts.appendSlice(self.allocator, try std.fmt.allocPrint(self.allocator, ",\"top_p\":{d}", .{v}));
        }

        if (params.tools) |tools| {
            try parts.appendSlice(self.allocator, ",\"tools\":");
            try parts.appendSlice(self.allocator, try serializeTools(self.allocator, tools));
        }

        if (params.tool_choice) |choice| {
            try parts.appendSlice(self.allocator, ",\"tool_choice\":");
            try parts.appendSlice(self.allocator, try serializeToolChoice(self.allocator, choice));
        }

        if (params.response_format) |format| {
            _ = format;
            try parts.appendSlice(self.allocator, ",\"response_format\":{}");
        }

        if (params.previous_response_id) |id| {
            try parts.appendSlice(self.allocator, ",\"previous_response_id\":\"");
            try parts.appendSlice(self.allocator, id);
            try parts.appendSlice(self.allocator, "\"");
        }

        if (params.store) |store| {
            try parts.appendSlice(self.allocator, ",\"store\":");
            try parts.appendSlice(self.allocator, if (store) "true" else "false");
        }

        try parts.appendSlice(self.allocator, "}");

        return try parts.toOwnedSlice(self.allocator);
    }

    fn serializeInput(allocator: std.mem.Allocator, input: ResponseInput) ![]u8 {
        return switch (input) {
            .string => |s| try std.fmt.allocPrint(allocator, "\"{s}\"", .{s}),
            .array => |items| serializeInputItems(allocator, items),
        };
    }

    fn serializeInputItems(allocator: std.mem.Allocator, items: []ResponseInputItem) ![]u8 {
        var result = std.ArrayListUnmanaged(u8){};
        defer result.deinit(allocator);

        try result.appendSlice(allocator, "[");
        for (items, 0..) |item, i| {
            if (i > 0) try result.appendSlice(allocator, ",");
            try result.appendSlice(allocator, try serializeInputItem(allocator, item));
        }
        try result.appendSlice(allocator, "]");

        return try result.toOwnedSlice(allocator);
    }

    fn serializeInputItem(allocator: std.mem.Allocator, item: ResponseInputItem) ![]u8 {
        return switch (item) {
            .text => |t| try std.fmt.allocPrint(allocator,
                "{{\"type\":\"input_text\",\"text\":\"{s}\"}}"
            , .{t}),
            .image => |img| try serializeInputImage(allocator, img),
        };
    }

    fn serializeInputImage(allocator: std.mem.Allocator, img: ResponseInputImage) ![]u8 {
        return switch (img.source) {
            .url => |u| try std.fmt.allocPrint(allocator,
                "{{\"type\":\"input_image\",\"source\":{{\"type\":\"url\",\"url\":\"{s}\"}}}}"
            , .{u}),
            .base64 => |b| try std.fmt.allocPrint(allocator,
                "{{\"type\":\"input_image\",\"source\":{{\"type\":\"base64\",\"data\":\"{s}\"}}}}"
            , .{b}),
        };
    }

    fn serializeStreamOptions(allocator: std.mem.Allocator, opts: ResponseStreamOptions) ![]u8 {
        var parts = std.ArrayListUnmanaged(u8){};
        defer parts.deinit(allocator);

        try parts.appendSlice(allocator, "{\"include\":");
        try parts.appendSlice(allocator, if (opts.include) "true" else "false");
        try parts.appendSlice(allocator, "}");

        return try parts.toOwnedSlice(allocator);
    }

    fn serializeTools(allocator: std.mem.Allocator, tools: []Tool) ![]u8 {
        var result = std.ArrayListUnmanaged(u8){};
        defer result.deinit(allocator);

        try result.appendSlice(allocator, "[");
        for (tools, 0..) |tool, i| {
            if (i > 0) try result.appendSlice(allocator, ",");
            try result.appendSlice(allocator, try serializeTool(allocator, tool));
        }
        try result.appendSlice(allocator, "]");

        return try result.toOwnedSlice(allocator);
    }

    fn serializeTool(allocator: std.mem.Allocator, tool: Tool) ![]u8 {
        return switch (tool) {
            .function => |f| try std.fmt.allocPrint(allocator,
                "{{\"type\":\"function\",\"name\":\"{s}\",\"description\":\"{s}\",\"parameters\":{s}}}"
            , .{
                f.name,
                if (f.description) |d| d else "",
                if (f.parameters) |p| p else "{}",
            }),
        };
    }

    fn serializeToolChoice(allocator: std.mem.Allocator, choice: ToolChoice) ![]u8 {
        return switch (choice) {
            .auto => try std.fmt.allocPrint(allocator, "\"auto\"", .{}),
            .none => try std.fmt.allocPrint(allocator, "\"none\"", .{}),
            .required => try std.fmt.allocPrint(allocator, "\"required\"", .{}),
            .function => |f| try std.fmt.allocPrint(allocator,
                "{{\"type\":\"function\",\"name\":\"{s}\"}}"
            , .{f}),
        };
    }



    // ============================================================================
    // Parsing
    // ============================================================================

    fn parseMessageItem(self: *Service, json_str: []const u8) !ResponseOutputMessage {
        const id = self.parseJsonField(json_str, "id") orelse return error.ParseError;
        const role = self.parseJsonField(json_str, "role") orelse return error.ParseError;
        const content_str = self.parseJsonField(json_str, "content") orelse return error.ParseError;

        // Parse content array to get text
        const text_start = std.mem.indexOf(u8, content_str, "\"text\":\"") orelse return error.ParseError;
        const text_value_start = text_start + 9;
        const text_end = std.mem.indexOf(u8, content_str[text_value_start..], "\"") orelse return error.ParseError;
        const text = content_str[text_value_start..text_value_start + text_end];

        return ResponseOutputMessage{
            .id = try self.allocator.dupe(u8, id),
            .role = try self.allocator.dupe(u8, role),
            .content = try self.allocator.dupe(u8, text),
        };
    }

    fn parseFunctionCallItem(self: *Service, json_str: []const u8) !ResponseOutputFunctionCall {
        const id = self.parseJsonField(json_str, "call_id") orelse return error.ParseError;
        const name = self.parseJsonField(json_str, "name") orelse return error.ParseError;
        const arguments_str = self.parseJsonField(json_str, "arguments") orelse return error.ParseError;

        return ResponseOutputFunctionCall{
            .id = try self.allocator.dupe(u8, id),
            .name = try self.allocator.dupe(u8, name),
            .arguments = try self.allocator.dupe(u8, arguments_str),
        };
    }

    fn parseReasoningItem(self: *Service, json_str: []const u8) !ResponseOutputReasoning {
        const id = self.parseJsonField(json_str, "id") orelse return error.ParseError;
        const summary_str = self.parseJsonField(json_str, "summary") orelse return error.ParseError;

        // Summary is an array, parse it
        const text_start = std.mem.indexOf(u8, summary_str, "\"text\":\"") orelse return error.ParseError;
        const text_value_start = text_start + 9;
        const text_end = std.mem.indexOf(u8, summary_str[text_value_start..], "\"") orelse return error.ParseError;
        const text = summary_str[text_value_start..text_value_start + text_end];

        return ResponseOutputReasoning{
            .id = try self.allocator.dupe(u8, id),
            .summary = try self.allocator.dupe(u8, text),
        };
    }

    fn parseUsage(self: *Service, response: []const u8) !ResponseUsage {
        const usage_str = self.parseJsonField(response, "usage") orelse return error.ParseError;

        const input_tokens_str = self.parseJsonField(usage_str, "input_tokens") orelse "0";
        const output_tokens_str = self.parseJsonField(usage_str, "output_tokens") orelse "0";
        const total_tokens_str = self.parseJsonField(usage_str, "total_tokens") orelse "0";

        return ResponseUsage{
            .input_tokens = std.fmt.parseInt(u32, input_tokens_str, 10) catch 0,
            .output_tokens = std.fmt.parseInt(u32, output_tokens_str, 10) catch 0,
            .total_tokens = std.fmt.parseInt(u32, total_tokens_str, 10) catch 0,
        };
    }

    fn freeOutputItem(self: *Service, item: ResponseOutputItem) void {
        switch (item) {
            .message => |msg| {
                self.allocator.free(msg.id);
                self.allocator.free(msg.role);
                self.allocator.free(msg.content);
            },
            .function_call => |fc| {
                self.allocator.free(fc.id);
                self.allocator.free(fc.name);
                self.allocator.free(fc.arguments);
            },
            .reasoning => |r| {
                self.allocator.free(r.id);
                self.allocator.free(r.summary);
            },
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
}

// ============================================================================
// Request Types
// ============================================================================

pub const ResponseNewParams = struct {
    model: []const u8,
    input: ?ResponseInput = null,
    stream: ?bool = false,
    stream_options: ?ResponseStreamOptions = null,
    max_output_tokens: ?u32 = null,
    temperature: ?f32 = null,
    top_p: ?f32 = null,
    tools: ?[]Tool = null,
    tool_choice: ?ToolChoice = null,
    response_format: ?ResponseFormat = null,
    previous_response_id: ?[]const u8 = null,
    store: ?bool = null,
};

pub const ResponseInput = union(enum) {
    string: []const u8,
    array: []ResponseInputItem,
};

pub const ResponseInputItem = union(enum) {
    text: []const u8,
    image: ResponseInputImage,
};

pub const ResponseInputImage = struct {
    source: ResponseInputImageSource,
};

pub const ResponseInputImageSource = union(enum) {
    url: []const u8,
    base64: []const u8,
};

pub const ResponseStreamOptions = struct {
    include: bool = false,
};

pub const Tool = union(enum) {
    function: ToolFunction,
};

pub const ToolFunction = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    parameters: ?[]const u8 = null,  // JSON schema as string
};

pub const ToolChoice = union(enum) {
    auto: void,
    none: void,
    required: void,
    function: []const u8,
};

pub const ResponseFormat = union(enum) {
    text: void,
    json_object: void,
    json_schema: ResponseFormatJsonSchema,
};

pub const ResponseFormatJsonSchema = struct {
    name: []const u8,
    schema: []const u8,
};

// ============================================================================
// Response Types
// ============================================================================

pub const Response = struct {
    id: []const u8,
    model: []const u8,
    output: []ResponseOutputItem,
    usage: ResponseUsage,
};

pub const ResponseDeleted = struct {
    id: []const u8,
    deleted: bool,
};

pub const ResponseOutputItem = union(enum) {
    message: ResponseOutputMessage,
    function_call: ResponseOutputFunctionCall,
    reasoning: ResponseOutputReasoning,
};

pub const ResponseOutputMessage = struct {
    id: []const u8,
    role: []const u8,
    content: []const u8,
};

pub const ResponseOutputFunctionCall = struct {
    id: []const u8,
    name: []const u8,
    arguments: []const u8,
};

pub const ResponseOutputReasoning = struct {
    id: []const u8,
    summary: []const u8,
};

pub const ResponseUsage = struct {
    input_tokens: u32,
    output_tokens: u32,
    total_tokens: u32,
};

// ============================================================================
// Streaming Types
// ============================================================================

pub const ResponseStreamEvent = union(enum) {
    response_output_item_done: ResponseOutputItemDoneEvent,
    response_text_delta: ResponseTextDeltaEvent,
    response_content_part_done: ResponseContentPartDoneEvent,
    response_done: ResponseDoneEvent,
};

pub const ResponseOutputItemDoneEvent = struct {
    item: ResponseOutputItem,
};

pub const ResponseTextDeltaEvent = struct {
    index: u32,
    delta: []const u8,
};

pub const ResponseContentPartDoneEvent = struct {
    index: u32,
    part: ResponseContentPart,
};

pub const ResponseDoneEvent = struct {
    response: Response,
};

pub const ResponseContentPart = union(enum) {
    text: ResponseContentTextPart,
    image: ResponseContentImagePart,
};

pub const ResponseContentTextPart = struct {
    text: []const u8,
};

pub const ResponseContentImagePart = struct {
    index: u32,
    image_bytes: []const u8,
};

// ============================================================================
// Conversations API Types (for multi-turn state)
// ============================================================================

pub const Conversation = struct {
    id: []const u8,
    object: []const u8 = "conversation",
};

pub const ConversationItem = struct {
    id: []const u8,
    type: []const u8,
    status: ?[]const u8 = null,
};

// ============================================================================
// Pagination
// ============================================================================

pub const ListParams = struct {
    after: ?[]const u8 = null,
    limit: ?u32 = null,
};

pub const Page = struct {
    data: []Response,
    has_more: bool,
    first_id: ?[]const u8,
    last_id: ?[]const u8,
};