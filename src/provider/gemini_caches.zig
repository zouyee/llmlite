//! Caches API - Google Gemini Context Caching
//!
//! Reference: https://ai.google.dev/gemini-api/docs/caching
//!
//! Context caching allows you to reuse content across requests,
//! reducing costs and latency for large context scenarios.

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

    /// Create a new cached content
    /// POST /v1beta/cachedContents
    pub fn create(self: *Service, params: CreateCachedContentParams) !CachedContent {
        const json_str = try self.serializeCreateParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/cachedContents", json_str);
        defer self.allocator.free(response);

        return try self.parseCachedContent(response);
    }

    /// Get a cached content by name
    /// GET /v1beta/{name}
    pub fn get(self: *Service, name: []const u8) !CachedContent {
        const path = try std.fmt.allocPrint(self.allocator, "/cachedContents/{s}", .{name});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseCachedContent(response);
    }

    /// List all cached contents
    /// GET /v1beta/cachedContents
    pub fn list(self: *Service, params: ?ListCachedContentsParams) !ListCachedContentsResponse {
        var path = std.array_list.Managed(u8).init(self.allocator);
        defer path.deinit();

        try path.appendSlice("/cachedContents");

        if (params) |p| {
            var first = true;
            if (p.page_size) |size| {
                try path.appendSlice(if (first) "?" else "&");
                try path.writer().print("pageSize={d}", .{size});
                first = false;
            }
            if (p.page_token) |token| {
                try path.appendSlice(if (first) "?" else "&");
                try path.appendSlice("pageToken=");
                try path.appendSlice(token);
            }
        }

        const response = try self.http_client.get(try path.toOwnedSlice());
        defer self.allocator.free(response);

        return try self.parseListResponse(response);
    }

    /// Update cached content TTL
    /// PATCH /v1beta/{name}
    pub fn update(self: *Service, name: []const u8, params: UpdateCachedContentParams) !CachedContent {
        const path = try std.fmt.allocPrint(self.allocator, "/cachedContents/{s}", .{name});
        defer self.allocator.free(path);

        const json_str = try self.serializeUpdateParams(params);
        defer self.allocator.free(json_str);

        // Note: Zig's HTTP client may not support PATCH, use POST with _http_method override
        const response = try self.http_client.post(path, json_str);
        defer self.allocator.free(response);

        return try self.parseCachedContent(response);
    }

    /// Delete cached content
    /// DELETE /v1beta/{name}
    pub fn delete(self: *Service, name: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/cachedContents/{s}", .{name});
        defer self.allocator.free(path);

        const response = try self.http_client.delete(path);
        defer self.allocator.free(response);
    }

    // ============================================================================
    // Serialization
    // ============================================================================

    fn serializeCreateParams(self: *Service, params: CreateCachedContentParams) ![]u8 {
        var parts = std.ArrayListUnmanaged(u8){};
        defer parts.deinit(self.allocator);

        try parts.appendSlice(self.allocator, "{\"model\":\"");
        try parts.appendSlice(self.allocator, params.model);
        try parts.appendSlice(self.allocator, "\",");

        // Contents
        try parts.appendSlice(self.allocator, "\"contents\":[");
        for (params.contents, 0..) |content, i| {
            if (i > 0) try parts.appendSlice(self.allocator, ",");
            try parts.appendSlice(self.allocator, try self.serializeContent(content));
        }
        try parts.appendSlice(self.allocator, "],");

        // Display name
        if (params.display_name) |name| {
            try parts.appendSlice(self.allocator, "\"displayName\":\"");
            try parts.appendSlice(self.allocator, name);
            try parts.appendSlice(self.allocator, "\",");
        }

        // TTL
        if (params.ttl) |ttl| {
            try parts.appendSlice(self.allocator, "\"ttl\":\"");
            try parts.appendSlice(self.allocator, ttl);
            try parts.appendSlice(self.allocator, "\",");
        }

        // Expires after
        if (params.expires_after_seconds) |seconds| {
            try parts.appendSlice(self.allocator, "\"expiresAfter\":");
            try parts.writer(self.allocator).print("{d}", .{seconds});
            try parts.appendSlice(self.allocator, ",");
        }

        // System instruction
        if (params.system_instruction) |instruction| {
            try parts.appendSlice(self.allocator, "\"systemInstruction\":");
            try parts.appendSlice(self.allocator, try self.serializeContent(instruction));
            try parts.appendSlice(self.allocator, ",");
        }

        // Remove trailing comma
        if (parts.items.len > 0 and parts.items[parts.items.len - 1] == ',') {
            parts.items.len -= 1;
        }

        try parts.appendSlice(self.allocator, "}");
        return try parts.toOwnedSlice(self.allocator);
    }

    fn serializeContent(self: *Service, content: Content) ![]u8 {
        var parts = std.ArrayListUnmanaged(u8){};
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

    fn serializeUpdateParams(self: *Service, params: UpdateCachedContentParams) ![]u8 {
        var parts = std.ArrayListUnmanaged(u8){};
        defer parts.deinit(self.allocator);

        if (params.ttl) |ttl| {
            try parts.appendSlice(self.allocator, "{\"ttl\":\"");
            try parts.appendSlice(self.allocator, ttl);
            try parts.appendSlice(self.allocator, "\"}");
        } else if (params.expires_after_seconds) |seconds| {
            try parts.appendSlice(self.allocator, "{\"expiresAfter\":");
            try parts.writer(self.allocator).print("{d}", .{seconds});
            try parts.appendSlice(self.allocator, "}");
        } else {
            try parts.appendSlice(self.allocator, "{}");
        }

        return try parts.toOwnedSlice(self.allocator);
    }

    // ============================================================================
    // Parsing
    // ============================================================================

    fn parseCachedContent(self: *Service, response: []const u8) !CachedContent {
        const name = self.parseField(response, "name") orelse return error.ParseError;
        const model = self.parseField(response, "model") orelse return error.ParseError;
        const display_name = self.parseField(response, "displayName");

        // Parse size in bytes
        const size_bytes_str = self.parseField(response, "sizeBytes") orelse "0";
        const size_bytes = std.fmt.parseInt(i64, size_bytes_str, 10) catch 0;

        // Parse create time
        const create_time = self.parseField(response, "createTime");
        const update_time = self.parseField(response, "updateTime");
        const expire_time = self.parseField(response, "expireTime");

        // Parse TTL
        const ttl = self.parseField(response, "ttl");

        // Parse usage metadata
        var usage_metadata: ?UsageMetadata = null;
        if (self.parseField(response, "usageMetadata")) |um_str| {
            const prompt_tokens_str = self.parseField(um_str, "promptTokenCount") orelse "0";
            const total_tokens_str = self.parseField(um_str, "totalTokenCount") orelse "0";
            usage_metadata = .{
                .prompt_token_count = std.fmt.parseInt(u32, prompt_tokens_str, 10) catch 0,
                .total_token_count = std.fmt.parseInt(u32, total_tokens_str, 10) catch 0,
            };
        }

        return CachedContent{
            .name = try self.allocator.dupe(u8, name),
            .model = try self.allocator.dupe(u8, model),
            .display_name = if (display_name) |d| try self.allocator.dupe(u8, d) else null,
            .size_bytes = size_bytes,
            .create_time = if (create_time) |t| try self.allocator.dupe(u8, t) else null,
            .update_time = if (update_time) |t| try self.allocator.dupe(u8, t) else null,
            .expire_time = if (expire_time) |t| try self.allocator.dupe(u8, t) else null,
            .ttl = if (ttl) |t| try self.allocator.dupe(u8, t) else null,
            .usage_metadata = usage_metadata,
        };
    }

    fn parseListResponse(self: *Service, response: []const u8) !ListCachedContentsResponse {
        const data_str = self.parseField(response, "cachedContents") orelse return error.ParseError;
        const next_page_token = self.parseField(response, "nextPageToken");

        var items = std.ArrayListUnmanaged(CachedContent){};
        errdefer {
            for (items.items) |item| self.freeCachedContent(item);
            items.deinit(self.allocator);
        }

        // Parse array of cached contents
        var search_idx: usize = 0;
        while (search_idx < data_str.len) {
            const obj_start = std.mem.indexOf(u8, data_str[search_idx..], "{") orelse break;
            const obj_end = findMatchingBrace(data_str[search_idx + obj_start ..]) orelse break;
            const obj_json = data_str[search_idx + obj_start .. search_idx + obj_start + obj_end + 1];

            const item = try self.parseCachedContent(obj_json);
            try items.append(self.allocator, item);

            search_idx += obj_start + obj_end + 1;
        }

        return ListCachedContentsResponse{
            .cached_contents = try items.toOwnedSlice(self.allocator),
            .next_page_token = if (next_page_token) |t| try self.allocator.dupe(u8, t) else null,
        };
    }

    fn freeCachedContent(self: *Service, content: CachedContent) void {
        self.allocator.free(content.name);
        self.allocator.free(content.model);
        if (content.display_name) |d| self.allocator.free(d);
        if (content.create_time) |t| self.allocator.free(t);
        if (content.update_time) |t| self.allocator.free(t);
        if (content.expire_time) |t| self.allocator.free(t);
        if (content.ttl) |t| self.allocator.free(t);
    }

    fn parseField(self: *Service, json_str: []const u8, field_name: []const u8) ?[]const u8 {
        _ = self;
        const search_pattern = "\"" ++ field_name ++ "\":";
        const start_idx = std.mem.indexOf(u8, json_str, search_pattern) orelse return null;
        const value_start = start_idx + search_pattern.len;

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
        } else if (json_str[i] == '{' or json_str[i] == '[') {
            var depth: u32 = 1;
            i += 1;
            while (i < json_str.len and depth > 0) {
                if (json_str[i] == '{' or json_str[i] == '[') depth += 1;
                if (json_str[i] == '}' or json_str[i] == ']') depth -= 1;
                i += 1;
            }
            return json_str[value_start..i];
        } else {
            const num_start = i;
            while (i < json_str.len and (std.ascii.isDigit(json_str[i]) or json_str[i] == '.' or json_str[i] == '-' or json_str[i] == 'e' or json_str[i] == 'E' or json_str[i] == 'n')) {
                i += 1;
            }
            return json_str[num_start..i];
        }
    }
};

fn findMatchingBrace(data: []const u8) ?usize {
    if (data.len == 0 or data[0] != '{') return null;
    var depth: u32 = 1;
    var i: usize = 1;
    while (i < data.len and depth > 0) {
        if (data[i] == '{' or data[i] == '[') depth += 1;
        if (data[i] == '}' or data[i] == ']') depth -= 1;
        i += 1;
    }
    if (depth == 0) return i - 1;
    return null;
}

// ============================================================================
// Request Types
// ============================================================================

pub const CreateCachedContentParams = struct {
    model: []const u8,
    contents: []Content,
    display_name: ?[]const u8 = null,
    ttl: ?[]const u8 = null,
    expires_after_seconds: ?i64 = null,
    system_instruction: ?Content = null,
};

pub const UpdateCachedContentParams = struct {
    ttl: ?[]const u8 = null,
    expires_after_seconds: ?i64 = null,
};

pub const ListCachedContentsParams = struct {
    page_size: ?i32 = null,
    page_token: ?[]const u8 = null,
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

pub const CachedContent = struct {
    name: []const u8,
    model: []const u8,
    display_name: ?[]const u8 = null,
    size_bytes: i64 = 0,
    create_time: ?[]const u8 = null,
    update_time: ?[]const u8 = null,
    expire_time: ?[]const u8 = null,
    ttl: ?[]const u8 = null,
    usage_metadata: ?UsageMetadata = null,
};

pub const UsageMetadata = struct {
    prompt_token_count: u32 = 0,
    total_token_count: u32 = 0,
};

pub const ListCachedContentsResponse = struct {
    cached_contents: []CachedContent,
    next_page_token: ?[]const u8 = null,
};

// ============================================================================
// Endpoint Helpers
// ============================================================================

pub const getCachedContentsListEndpoint = "/cachedContents";
