//! Embeddings API
//!
//! Supports OpenAI and Google Gemini embedding formats

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

    /// Creates an embedding vector for the input text.
    pub fn createEmbedding(self: *Service, params: CreateEmbeddingParams) !CreateEmbeddingResponse {
        const json_str = try self.serializeEmbeddingParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/embeddings", json_str);
        defer self.allocator.free(response);

        return try self.parseEmbeddingResponse(response);
    }

    fn serializeEmbeddingParams(self: *Service, params: CreateEmbeddingParams) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8).empty;
        defer buf.deinit(self.allocator);

        try buf.append(self.allocator, '{');
        try buf.appendSlice(self.allocator, "\"model\":\"");
        try buf.appendSlice(self.allocator, params.model);
        try buf.appendSlice(self.allocator, "\",\"input\":");

        switch (params.input) {
            .string => |s| {
                try buf.append(self.allocator, '"');
                try buf.appendSlice(self.allocator, s);
                try buf.append(self.allocator, '"');
            },
            .array_of_strings => |arr| {
                try buf.append(self.allocator, '[');
                for (arr, 0..) |item, i| {
                    if (i > 0) try buf.append(self.allocator, ',');
                    try buf.append(self.allocator, '"');
                    try buf.appendSlice(self.allocator, item);
                    try buf.append(self.allocator, '"');
                }
                try buf.append(self.allocator, ']');
            },
            else => {
                try buf.appendSlice(self.allocator, "\"\"");
            },
        }

        try buf.append(self.allocator, '}');
        return try buf.toOwnedSlice(self.allocator);
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

    fn parseEmbeddingResponse(self: *Service, response: []const u8) !CreateEmbeddingResponse {
        const model_str = parseJsonField(response, "model") orelse return error.ParseError;

        const usage_str = parseJsonField(response, "usage") orelse return error.ParseError;
        const prompt_tokens_str = parseJsonField(usage_str, "prompt_tokens") orelse "0";
        const total_tokens_str = parseJsonField(usage_str, "total_tokens") orelse "0";

        const usage = Usage{
            .prompt_tokens = std.fmt.parseInt(u32, prompt_tokens_str, 10) catch 0,
            .total_tokens = std.fmt.parseInt(u32, total_tokens_str, 10) catch 0,
        };

        const data_str = parseJsonField(response, "data") orelse return error.ParseError;

        var embedding_count: usize = 0;
        var search_pos: usize = 0;
        while (std.mem.indexOfPos(u8, data_str, search_pos, "\"embedding\":")) |idx| {
            _ = idx;
            embedding_count += 1;
            search_pos += 1;
        }

        if (embedding_count == 0) return error.ParseError;

        var data = try self.allocator.alloc(Embedding, embedding_count);
        errdefer self.allocator.free(data);

        var parsed_count: usize = 0;
        search_pos = 0;
        while (parsed_count < embedding_count) : (parsed_count += 1) {
            const obj_start = std.mem.indexOfPos(u8, data_str, search_pos, "{\"embedding\":") orelse break;
            const obj_end = obj_start + 1;
            var depth: u32 = 1;
            var i = obj_end;
            while (i < data_str.len and depth > 0) {
                if (data_str[i] == '{') depth += 1;
                if (data_str[i] == '}') depth -= 1;
                i += 1;
            }
            const obj_str = data_str[obj_start..i];

            const index_str = parseJsonField(obj_str, "index") orelse "0";
            const index = std.fmt.parseInt(u32, index_str, 10) catch 0;

            const emb_array_str = parseJsonField(obj_str, "embedding") orelse {
                data[parsed_count] = Embedding{
                    .embedding = &.{},
                    .index = index,
                };
                search_pos = i;
                continue;
            };

            var floats = std.ArrayListUnmanaged(f64).empty;
            errdefer floats.deinit(self.allocator);

            var float_start: usize = 0;
            for (emb_array_str, 0..) |c, fi| {
                if (c == ',' or c == ']') {
                    if (float_start < fi) {
                        const num_str = emb_array_str[float_start..fi];
                        if (std.fmt.parseFloat(f64, num_str)) |val| {
                            try floats.append(self.allocator, val);
                        } else |_| {}
                    }
                    float_start = fi + 1;
                }
            }

            data[parsed_count] = Embedding{
                .embedding = try floats.toOwnedSlice(self.allocator),
                .index = index,
            };
            search_pos = i;
        }

        return CreateEmbeddingResponse{
            .data = data,
            .model = try self.allocator.dupe(u8, model_str),
            .usage = usage,
        };
    }
};

// ============================================================================
// Embedding Input Type (Union)
// ============================================================================

pub const EmbeddingInput = union(enum) {
    string: []const u8,
    array_of_strings: [][]const u8,
    array_of_tokens: []i64,
    array_of_token_arrays: [][]i64,
};

// ============================================================================
// Request Params
// ============================================================================

pub const CreateEmbeddingParams = struct {
    input: EmbeddingInput,
    model: []const u8,
    dimensions: ?u32 = null,
    encoding_format: ?[]const u8 = null,
    user: ?[]const u8 = null,
};

// ============================================================================
// Response Types
// ============================================================================

pub const CreateEmbeddingResponse = struct {
    data: []Embedding,
    model: []const u8,
    object: []const u8 = "list",
    usage: Usage,
};

pub const Embedding = struct {
    embedding: []f64,
    index: u32,
    object: []const u8 = "embedding",
};

pub const Usage = struct {
    prompt_tokens: u32,
    total_tokens: u32,
};

// ============================================================================
// Model Constants
// ============================================================================

pub const EmbeddingModel = enum {
    TextEmbeddingAda002,
    TextEmbedding3Small,
    TextEmbedding3Large,

    pub fn toString(self: EmbeddingModel) []const u8 {
        return switch (self) {
            .TextEmbeddingAda002 => "text-embedding-ada-002",
            .TextEmbedding3Small => "text-embedding-3-small",
            .TextEmbedding3Large => "text-embedding-3-large",
        };
    }
};

// ============================================================================
// Google Gemini Embeddings Support
// ============================================================================

/// Google Gemini embedding response
pub const GeminiEmbeddingResponse = struct {
    embedding: []f64,
    model: []const u8,
};

/// Transform embedding params to Google Gemini format
pub fn transformGeminiEmbeddingRequest(allocator: std.mem.Allocator, params: CreateEmbeddingParams) ![]u8 {
    // Google Gemini embed content request format:
    // {"content": {"parts": [{"text": "..."}]}}

    var content = std.ArrayListUnmanaged(u8).empty;
    defer content.deinit(allocator);

    switch (params.input) {
        .string => |s| {
            try content.appendSlice(allocator, "{\"content\":{\"parts\":[{\"text\":\"");
            try content.appendSlice(allocator, s);
            try content.appendSlice(allocator, "\"}]}}");
        },
        .array_of_strings => |arr| {
            try content.appendSlice(allocator, "{\"content\":{\"parts\":[");
            for (arr, 0..) |item, i| {
                if (i > 0) try content.appendSlice(allocator, ",");
                try content.appendSlice(allocator, "{\"text\":\"");
                try content.appendSlice(allocator, item);
                try content.appendSlice(allocator, "\"}");
            }
            try content.appendSlice(allocator, "]}}");
        },
        else => {
            return error.UnsupportedInputType;
        },
    }

    return try content.toOwnedSlice(allocator);
}

/// Parse Google Gemini embedding response
pub fn parseGeminiEmbeddingResponse(allocator: std.mem.Allocator, response: []const u8) !GeminiEmbeddingResponse {
    // Gemini response format:
    // {"embedding": {"values": [...]}}

    const values_start = std.mem.indexOf(u8, response, "\"values\":") orelse return error.ParseError;
    const after_values = response[values_start + 9 ..];

    // Find the array bounds
    const array_start = std.mem.indexOf(u8, after_values, "[") orelse return error.ParseError;
    var depth: u32 = 1;
    var i = array_start + 1;
    while (i < after_values.len and depth > 0) {
        if (after_values[i] == '[') depth += 1;
        if (after_values[i] == ']') depth -= 1;
        i += 1;
    }
    const array_str = after_values[array_start..i];

    // Parse float array
    var floats = std.ArrayListUnmanaged(f64).empty;
    errdefer floats.deinit(allocator);

    var float_start: usize = 0;
    for (array_str, 0..) |c, fi| {
        if (c == ',' or c == ']') {
            if (float_start < fi and float_start < array_str.len and array_str[float_start] != ']') {
                const num_str = array_str[float_start..fi];
                if (std.fmt.parseFloat(f64, num_str)) |val| {
                    try floats.append(allocator, val);
                } else |_| {}
            }
            float_start = fi + 1;
        }
    }

    return GeminiEmbeddingResponse{
        .embedding = try floats.toOwnedSlice(allocator),
        .model = "gemini-embedding",
    };
}

/// Get Google Gemini embed content endpoint
pub fn getGeminiEmbedEndpoint(model: []const u8) []const u8 {
    return std.fmt.comptimePrint("/models/{s}:embedContent", .{model});
}
