//! Completions API - Legacy text completion API
//!
//! Reference: https://platform.openai.com/docs/api-reference/completions

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

    /// Creates a completion for the given prompt.
    pub fn createCompletion(self: *Service, params: CreateCompletionParams) !Completion {
        const json_str = try self.serializeParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/completions", json_str);
        defer self.allocator.free(response);

        return try self.parseResponse(response);
    }

    /// Creates a streaming completion for the given prompt.
    pub fn createCompletionStream(self: *Service, params: CreateCompletionParams) !StreamingCompletion {
        var params_with_stream = params;
        params_with_stream.stream = true;

        const json_str = try self.serializeParams(params_with_stream);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/completions", json_str);
        defer self.allocator.free(response);

        return try StreamingCompletion.init(self.allocator, response);
    }

    fn serializeParams(self: *Service, params: CreateCompletionParams) ![]u8 {
        var parts = std.array_list.Managed(u8).init(self.allocator);
        errdefer parts.deinit();

        const base_json = try std.json.Stringify.valueAlloc(self.allocator, .{
            .model = params.model,
            .prompt = params.prompt,
            .stream = params.stream,
        }, .{});
        defer self.allocator.free(base_json);
        try parts.appendSlice(base_json);

        // Add optional fields
        if (params.max_tokens) |v| {
            try parts.appendSlice(",\"max_tokens\":");
            const v_json = try std.json.Stringify.valueAlloc(self.allocator, v, .{});
            defer self.allocator.free(v_json);
            try parts.appendSlice(v_json);
        }
        if (params.temperature) |v| {
            try parts.appendSlice(",\"temperature\":");
            const v_json = try std.json.Stringify.valueAlloc(self.allocator, v, .{});
            defer self.allocator.free(v_json);
            try parts.appendSlice(v_json);
        }
        if (params.top_p) |v| {
            try parts.appendSlice(",\"top_p\":");
            const v_json = try std.json.Stringify.valueAlloc(self.allocator, v, .{});
            defer self.allocator.free(v_json);
            try parts.appendSlice(v_json);
        }
        if (params.n) |v| {
            try parts.appendSlice(",\"n\":");
            const v_json = try std.json.Stringify.valueAlloc(self.allocator, v, .{});
            defer self.allocator.free(v_json);
            try parts.appendSlice(v_json);
        }
        if (params.stop) |v| {
            try parts.appendSlice(",\"stop\":");
            const v_json = try std.json.Stringify.valueAlloc(self.allocator, v, .{});
            defer self.allocator.free(v_json);
            try parts.appendSlice(v_json);
        }
        if (params.logprobs) |v| {
            try parts.appendSlice(",\"logprobs\":");
            const v_json = try std.json.Stringify.valueAlloc(self.allocator, v, .{});
            defer self.allocator.free(v_json);
            try parts.appendSlice(v_json);
        }
        if (params.echo) |v| {
            try parts.appendSlice(",\"echo\":");
            const v_json = try std.json.Stringify.valueAlloc(self.allocator, v, .{});
            defer self.allocator.free(v_json);
            try parts.appendSlice(v_json);
        }
        if (params.best_of) |v| {
            try parts.appendSlice(",\"best_of\":");
            const v_json = try std.json.Stringify.valueAlloc(self.allocator, v, .{});
            defer self.allocator.free(v_json);
            try parts.appendSlice(v_json);
        }
        if (params.frequency_penalty) |v| {
            try parts.appendSlice(",\"frequency_penalty\":");
            const v_json = try std.json.Stringify.valueAlloc(self.allocator, v, .{});
            defer self.allocator.free(v_json);
            try parts.appendSlice(v_json);
        }
        if (params.presence_penalty) |v| {
            try parts.appendSlice(",\"presence_penalty\":");
            const v_json = try std.json.Stringify.valueAlloc(self.allocator, v, .{});
            defer self.allocator.free(v_json);
            try parts.appendSlice(v_json);
        }
        if (params.seed) |v| {
            try parts.appendSlice(",\"seed\":");
            const v_json = try std.json.Stringify.valueAlloc(self.allocator, v, .{});
            defer self.allocator.free(v_json);
            try parts.appendSlice(v_json);
        }
        if (params.suffix) |v| {
            try parts.appendSlice(",\"suffix\":");
            const v_json = try std.json.Stringify.valueAlloc(self.allocator, v, .{});
            defer self.allocator.free(v_json);
            try parts.appendSlice(v_json);
        }
        if (params.user) |v| {
            try parts.appendSlice(",\"user\":");
            const v_json = try std.json.Stringify.valueAlloc(self.allocator, v, .{});
            defer self.allocator.free(v_json);
            try parts.appendSlice(v_json);
        }

        return parts.toOwnedSlice();
    }

    fn parseResponse(self: *Service, response: []const u8) !Completion {
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);

        const root = tree.root;
        const obj = root.object orelse return error.ParseError;

        const id = (obj.get("id") orelse return error.ParseError).string;
        const created = (obj.get("created") orelse return error.ParseError).integer;
        const model = (obj.get("model") orelse return error.ParseError).string;
        const object = (obj.get("object") orelse return error.ParseError).string;

        // Parse choices
        const choices_array = (obj.get("choices") orelse return error.ParseError).array;
        var choices = try self.allocator.alloc(CompletionChoice, choices_array.len);
        for (choices_array, 0..) |choice_val, i| {
            const choice_obj = choice_val.object orelse return error.ParseError;
            const text = (choice_obj.get("text") orelse return error.ParseError).string;
            const index = (choice_obj.get("index") orelse return error.ParseError).integer;
            const finish_reason = (choice_obj.get("finish_reason") orelse return error.ParseError).string;

            choices[i] = .{
                .text = try self.allocator.dupe(u8, text),
                .index = @intCast(index),
                .finish_reason = try self.allocator.dupe(u8, finish_reason),
            };
        }

        // Parse usage
        var usage: CompletionUsage = undefined;
        if (obj.get("usage")) |usage_val| {
            const usage_obj = usage_val.object orelse return error.ParseError;
            usage = .{
                .prompt_tokens = @intCast((usage_obj.get("prompt_tokens") orelse return error.ParseError).integer),
                .completion_tokens = @intCast((usage_obj.get("completion_tokens") orelse return error.ParseError).integer),
                .total_tokens = @intCast((usage_obj.get("total_tokens") orelse return error.ParseError).integer),
            };
        }

        return Completion{
            .id = try self.allocator.dupe(u8, id),
            .object = try self.allocator.dupe(u8, object),
            .created = @intCast(created),
            .model = try self.allocator.dupe(u8, model),
            .choices = choices,
            .usage = usage,
        };
    }
};

// ============================================================================
// Types
// ============================================================================

/// Completion result
pub const Completion = struct {
    id: []const u8,
    object: []const u8,
    created: i64,
    model: []const u8,
    choices: []CompletionChoice,
    usage: CompletionUsage,

    pub fn deinit(self: *Completion) void {
        self.allocator.free(self.id);
        self.allocator.free(self.object);
        self.allocator.free(self.model);
        for (self.choices) |*choice| {
            choice.deinit();
        }
        self.allocator.free(self.choices);
    }
};

/// Completion choice
pub const CompletionChoice = struct {
    text: []const u8,
    index: i32,
    finish_reason: []const u8,

    pub fn deinit(self: *CompletionChoice) void {
        _ = self; // TODO: implement proper cleanup when allocator is stored
    }
};

/// Completion usage statistics
pub const CompletionUsage = struct {
    prompt_tokens: i32,
    completion_tokens: i32,
    total_tokens: i32,
};

/// Streaming completion handler
pub const StreamingCompletion = struct {
    allocator: std.mem.Allocator,
    chunks: std.ArrayListUnmanaged(u8),

    pub fn init(allocator: std.mem.Allocator, response: []const u8) !StreamingCompletion {
        _ = response; // TODO: parse SSE stream
        return StreamingCompletion{
            .allocator = allocator,
            .chunks = std.ArrayListUnmanaged(u8){},
        };
    }

    pub fn deinit(self: *StreamingCompletion) void {
        self.chunks.deinit(self.allocator);
    }

    /// Get the full completion text from all chunks
    pub fn text(self: *StreamingCompletion) []const u8 {
        return self.chunks.items;
    }
};

// ============================================================================
// Parameters
// ============================================================================

/// Parameters for creating a completion
pub const CreateCompletionParams = struct {
    model: []const u8,
    prompt: []const u8,
    stream: bool = false,
    max_tokens: ?i32 = null,
    temperature: ?f64 = null,
    top_p: ?f64 = null,
    n: ?i32 = null,
    stop: ?[]const u8 = null,
    logprobs: ?i32 = null,
    echo: ?bool = null,
    best_of: ?i32 = null,
    frequency_penalty: ?f64 = null,
    presence_penalty: ?f64 = null,
    seed: ?i64 = null,
    suffix: ?[]const u8 = null,
    user: ?[]const u8 = null,
};

// ============================================================================
// Model Constants
// ============================================================================

pub const Model = struct {
    pub const GPT3_5TurboInstruct = "gpt-3.5-turbo-instruct";
    pub const Davinci002 = "davinci-002";
    pub const Babbage002 = "babbage-002";
};
