//! Tokens API - Google Gemini Token Counting
//!
//! Reference: https://ai.google.dev/gemini-api/docs/tokens
//!
//! Token counting API allows you to count the number of tokens
//! in a piece of text or content before sending it to the model.

const std = @import("std");
const http = @import("http");

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

    /// Count tokens in text content
    /// POST /v1beta/{model}:countTokens
    pub fn countTokens(self: *Service, model: []const u8, params: CountTokensParams) !CountTokensResult {
        const json_str = try self.serializeParams(params);
        defer self.allocator.free(json_str);

        const path = try std.fmt.allocPrint(self.allocator, "/models/{s}:countTokens", .{model});
        defer self.allocator.free(path);

        const response = try self.http_client.post(path, json_str);
        defer self.allocator.free(response);

        return try self.parseResponse(response);
    }

    // ============================================================================
    // Serialization
    // ============================================================================

    fn serializeParams(self: *Service, params: CountTokensParams) ![]u8 {
        var parts: std.ArrayListUnmanaged(u8) = .empty;
        defer parts.deinit(self.allocator);

        // Contents
        try parts.appendSlice(self.allocator, "{\"contents\":[");
        for (params.contents, 0..) |content, i| {
            if (i > 0) try parts.appendSlice(self.allocator, ",");
            try parts.appendSlice(self.allocator, try self.serializeContent(content));
        }
        try parts.appendSlice(self.allocator, "]");

        // System instruction
        if (params.system_instruction) |instruction| {
            try parts.appendSlice(self.allocator, ",\"systemInstruction\":");
            try parts.appendSlice(self.allocator, try self.serializeContent(instruction));
        }

        // Model
        if (params.model) |m| {
            try parts.appendSlice(self.allocator, ",\"model\":\"");
            try parts.appendSlice(self.allocator, m);
            try parts.appendSlice(self.allocator, "\"");
        }

        try parts.appendSlice(self.allocator, "}");
        return try parts.toOwnedSlice(self.allocator);
    }

    fn serializeContent(self: *Service, content: Content) ![]u8 {
        var parts: std.ArrayListUnmanaged(u8) = .empty;
        defer parts.deinit(self.allocator);

        try parts.appendSlice(self.allocator, "{\"role\":\"");
        try parts.appendSlice(self.allocator, content.role);
        try parts.appendSlice(self.allocator, "\",\"parts\":[");

        for (content.parts, 0..) |part, i| {
            if (i > 0) try parts.appendSlice(self.allocator, ",");
            try parts.appendSlice(self.allocator, try self.serializePart(part));
        }

        try parts.appendSlice(self.allocator, "]}");
        return try parts.toOwnedSlice(self.allocator);
    }

    fn serializePart(self: *Service, part: Part) ![]u8 {
        return switch (part) {
            .text => |t| try std.fmt.allocPrint(self.allocator, "{{\"text\":\"{s}\"}}", .{t}),
            .file_data => |f| try std.fmt.allocPrint(self.allocator,
                \\{{"fileData":{{"mimeType":"{s}","fileUri":"{s}"}}}}
            , .{ f.mime_type, f.file_uri }),
        };
    }

    // ============================================================================
    // Parsing
    // ============================================================================

    fn parseResponse(self: *Service, response: []const u8) !CountTokensResult {
        const total_tokens_str = self.parseField(response, "totalTokens") orelse "0";
        const total_tokens = std.fmt.parseInt(u32, total_tokens_str, 10) catch 0;

        const total_billable_characters_str = self.parseField(response, "totalBillableCharacters") orelse "0";
        const total_billable_characters = std.fmt.parseInt(u32, total_billable_characters_str, 10) catch 0;

        return CountTokensResult{
            .total_tokens = total_tokens,
            .total_billable_characters = total_billable_characters,
        };
    }

    fn parseField(self: *Service, json_str: []const u8, field_name: []const u8) ?[]const u8 {
        _ = self;
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
        } else {
            const num_start = i;
            while (i < json_str.len and (std.ascii.isDigit(json_str[i]) or json_str[i] == '.' or json_str[i] == '-' or json_str[i] == 'e' or json_str[i] == 'E')) {
                i += 1;
            }
            return json_str[num_start..i];
        }
    }
};

// ============================================================================
// Request Types
// ============================================================================

pub const CountTokensParams = struct {
    contents: []Content,
    system_instruction: ?Content = null,
    model: ?[]const u8 = null,
};

// ============================================================================
// Content Types
// ============================================================================

pub const Content = struct {
    role: []const u8,
    parts: []Part,
};

pub const Part = union(enum) {
    text: []const u8,
    file_data: FileData,
};

pub const FileData = struct {
    mime_type: []const u8,
    file_uri: []const u8,
};

// ============================================================================
// Response Types
// ============================================================================

pub const CountTokensResult = struct {
    total_tokens: u32,
    total_billable_characters: u32,
};
