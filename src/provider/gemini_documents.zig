//! Documents API - Google Gemini Document Management
//!
//! Reference: https://ai.google.dev/gemini-api/docs/documents
//!
//! Documents API allows you to upload and manage documents
//! for use with Gemini's file search capabilities.

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

    /// List documents
    /// GET /v1beta/documents
    pub fn list(self: *Service, params: ?ListDocumentsParams) !ListDocumentsResponse {
        var path = std.array_list.Managed(u8).init(self.allocator);
        defer path.deinit();

        try path.appendSlice("/documents");

        if (params) |p| {
            var first = true;
            if (p.page_size) |size| {
                try path.appendSlice(if (first) "?" else "&");
                try path.print("pageSize={d}", .{size});
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

    /// Get a document by name
    /// GET /v1beta/{name}
    pub fn get(self: *Service, name: []const u8) !Document {
        const path = try std.fmt.allocPrint(self.allocator, "/{s}", .{name});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseDocument(response);
    }

    /// Delete a document
    /// DELETE /v1beta/{name}
    pub fn delete(self: *Service, name: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/{s}", .{name});
        defer self.allocator.free(path);

        const response = try self.http_client.delete(path);
        defer self.allocator.free(response);
    }

    // ============================================================================
    // Parsing
    // ============================================================================

    fn parseDocument(self: *Service, response: []const u8) !Document {
        const name = self.parseField(response, "name") orelse return error.ParseError;
        const display_name = self.parseField(response, "displayName");
        const mime_type = self.parseField(response, "mimeType");

        // Size in bytes
        const size_str = self.parseField(response, "sizeBytes") orelse "0";
        const size_bytes = std.fmt.parseInt(i64, size_str, 10) catch 0;

        // Create time
        const create_time = self.parseField(response, "createTime");
        const update_time = self.parseField(response, "updateTime");

        // Expiration
        const expire_time = self.parseField(response, "expireTime");

        // chunks info
        const chunks_info = self.parseField(response, "chunksInfo");

        return Document{
            .name = try self.allocator.dupe(u8, name),
            .display_name = if (display_name) |d| try self.allocator.dupe(u8, d) else null,
            .mime_type = if (mime_type) |m| try self.allocator.dupe(u8, m) else null,
            .size_bytes = size_bytes,
            .create_time = if (create_time) |t| try self.allocator.dupe(u8, t) else null,
            .update_time = if (update_time) |t| try self.allocator.dupe(u8, t) else null,
            .expire_time = if (expire_time) |t| try self.allocator.dupe(u8, t) else null,
            .chunks_info = if (chunks_info) |c| try self.allocator.dupe(u8, c) else null,
        };
    }

    fn parseListResponse(self: *Service, response: []const u8) !ListDocumentsResponse {
        const data_str = self.parseField(response, "documents") orelse return error.ParseError;
        const next_page_token = self.parseField(response, "nextPageToken");

        var items: std.ArrayListUnmanaged(Document) = .empty;
        errdefer {
            for (items.items) |item| self.freeDocument(item);
            items.deinit(self.allocator);
        }

        // Parse array
        var search_idx: usize = 0;
        while (search_idx < data_str.len) {
            const obj_start = std.mem.find(u8, data_str[search_idx..], "{") orelse break;
            const obj_end = findMatchingBrace(data_str[search_idx + obj_start ..]) orelse break;
            const obj_json = data_str[search_idx + obj_start .. search_idx + obj_start + obj_end + 1];

            const item = self.parseDocument(obj_json) catch continue;
            try items.append(self.allocator, item);

            search_idx += obj_start + obj_end + 1;
        }

        return ListDocumentsResponse{
            .documents = try items.toOwnedSlice(self.allocator),
            .next_page_token = if (next_page_token) |t| try self.allocator.dupe(u8, t) else null,
        };
    }

    fn freeDocument(self: *Service, doc: Document) void {
        self.allocator.free(doc.name);
        if (doc.display_name) |d| self.allocator.free(d);
        if (doc.mime_type) |m| self.allocator.free(m);
        if (doc.create_time) |t| self.allocator.free(t);
        if (doc.update_time) |t| self.allocator.free(t);
        if (doc.expire_time) |t| self.allocator.free(t);
        if (doc.chunks_info) |c| self.allocator.free(c);
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

pub const ListDocumentsParams = struct {
    page_size: ?i32 = null,
    page_token: ?[]const u8 = null,
};

// ============================================================================
// Response Types
// ============================================================================

pub const Document = struct {
    name: []const u8,
    display_name: ?[]const u8 = null,
    mime_type: ?[]const u8 = null,
    size_bytes: i64 = 0,
    create_time: ?[]const u8 = null,
    update_time: ?[]const u8 = null,
    expire_time: ?[]const u8 = null,
    chunks_info: ?[]const u8 = null,
};

pub const ListDocumentsResponse = struct {
    documents: []Document,
    next_page_token: ?[]const u8 = null,
};
