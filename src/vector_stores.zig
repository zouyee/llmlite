//! Vector Stores API - RAG (Retrieval-Augmented Generation) support
//!
//! Reference: https://platform.openai.com/docs/api-reference/vector-stores
//!
//! Vector Stores API allows you to create and manage vector stores for semantic
//! search and retrieval. This is a core component of RAG systems.

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

    // =========================================================================
    // Vector Store Operations
    // =========================================================================

    /// Creates a vector store.
    pub fn create(self: *Service, params: VectorStoreCreateParams) !VectorStore {
        const json_str = try self.serializeCreateParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/vector_stores", json_str);
        defer self.allocator.free(response);

        return try self.parseVectorStore(response);
    }

    /// Retrieves a vector store.
    pub fn get(self: *Service, vector_store_id: []const u8) !VectorStore {
        const path = try std.fmt.allocPrint(self.allocator, "/vector_stores/{s}", .{vector_store_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseVectorStore(response);
    }

    /// Modifies a vector store.
    pub fn update(self: *Service, vector_store_id: []const u8, params: VectorStoreUpdateParams) !VectorStore {
        const path = try std.fmt.allocPrint(self.allocator, "/vector_stores/{s}", .{vector_store_id});
        defer self.allocator.free(path);

        const json_str = try self.serializeUpdateParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post(path, json_str);
        defer self.allocator.free(response);

        return try self.parseVectorStore(response);
    }

    /// Deletes a vector store.
    pub fn delete(self: *Service, vector_store_id: []const u8) !VectorStoreDeleted {
        const path = try std.fmt.allocPrint(self.allocator, "/vector_stores/{s}", .{vector_store_id});
        defer self.allocator.free(path);

        const response = try self.http_client.delete(path);
        defer self.allocator.free(response);

        return try self.parseDeleteResponse(response);
    }

    /// Lists vector stores.
    pub fn list(self: *Service, params: ?VectorStoreListParams) !VectorStoreListResponse {
        var path = std.array_list.Managed(u8).init(self.allocator);
        defer path.deinit(self.allocator);

        try path.appendSlice(self.allocator, "/vector_stores");

        if (params) |p| {
            var first = true;
            if (p.limit) |limit| {
                try path.appendSlice(self.allocator, "?limit=");
                try std.fmt.formatInt(limit, 10, .lower, .{}, path.writer());
                first = false;
            }
            if (p.order) |order| {
                if (first) {
                    try path.appendSlice(self.allocator, "?");
                } else {
                    try path.appendSlice(self.allocator, "&");
                }
                try path.appendSlice(self.allocator, "order=");
                try path.appendSlice(self.allocator, order);
                first = false;
            }
            if (p.after) |after| {
                if (first) {
                    try path.appendSlice(self.allocator, "?");
                } else {
                    try path.appendSlice(self.allocator, "&");
                }
                try path.appendSlice(self.allocator, "after=");
                try path.appendSlice(self.allocator, after);
            }
            if (p.before) |before| {
                if (first) {
                    try path.appendSlice(self.allocator, "?");
                } else {
                    try path.appendSlice(self.allocator, "&");
                }
                try path.appendSlice(self.allocator, "before=");
                try path.appendSlice(self.allocator, before);
            }
        }

        const response = try self.http_client.get(try path.toOwnedSlice(self.allocator));
        defer self.allocator.free(response);

        return try self.parseListResponse(response);
    }

    // =========================================================================
    // Vector Store File Operations
    // =========================================================================

    /// Adds a file to a vector store.
    pub fn createFile(self: *Service, vector_store_id: []const u8, params: VectorStoreFileCreateParams) !VectorStoreFile {
        const path = try std.fmt.allocPrint(self.allocator, "/vector_stores/{s}/files", .{vector_store_id});
        defer self.allocator.free(path);

        const json_str = try self.serializeFileCreateParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post(path, json_str);
        defer self.allocator.free(response);

        return try self.parseVectorStoreFile(response);
    }

    /// Retrieves a file from a vector store.
    pub fn getFile(self: *Service, vector_store_id: []const u8, file_id: []const u8) !VectorStoreFile {
        const path = try std.fmt.allocPrint(self.allocator, "/vector_stores/{s}/files/{s}", .{ vector_store_id, file_id });
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseVectorStoreFile(response);
    }

    /// Lists files in a vector store.
    pub fn listFiles(self: *Service, vector_store_id: []const u8, params: ?VectorStoreFileListParams) !VectorStoreFileListResponse {
        var path = std.array_list.Managed(u8).init(self.allocator);
        defer path.deinit(self.allocator);

        try std.fmt.format(path.writer(), "/vector_stores/{s}/files", .{vector_store_id});

        if (params) |p| {
            var first = true;
            if (p.limit) |limit| {
                try path.appendSlice(self.allocator, "?limit=");
                try std.fmt.formatInt(limit, 10, .lower, .{}, path.writer());
                first = false;
            }
            if (p.order) |order| {
                if (first) {
                    try path.appendSlice(self.allocator, "?");
                } else {
                    try path.appendSlice(self.allocator, "&");
                }
                try path.appendSlice(self.allocator, "order=");
                try path.appendSlice(self.allocator, order);
                first = false;
            }
            if (p.after) |after| {
                if (first) {
                    try path.appendSlice(self.allocator, "?");
                } else {
                    try path.appendSlice(self.allocator, "&");
                }
                try path.appendSlice(self.allocator, "after=");
                try path.appendSlice(self.allocator, after);
            }
        }

        const response = try self.http_client.get(try path.toOwnedSlice(self.allocator));
        defer self.allocator.free(response);

        return try self.parseFileListResponse(response);
    }

    /// Deletes a file from a vector store.
    pub fn deleteFile(self: *Service, vector_store_id: []const u8, file_id: []const u8) !VectorStoreFileDeleted {
        const path = try std.fmt.allocPrint(self.allocator, "/vector_stores/{s}/files/{s}", .{ vector_store_id, file_id });
        defer self.allocator.free(path);

        const response = try self.http_client.delete(path);
        defer self.allocator.free(response);

        return try self.parseFileDeleteResponse(response);
    }

    // =========================================================================
    // Search
    // =========================================================================

    /// Searches a vector store for relevant content.
    pub fn search(self: *Service, vector_store_id: []const u8, params: VectorStoreSearchParams) !VectorStoreSearchResponse {
        const path = try std.fmt.allocPrint(self.allocator, "/vector_stores/{s}/search", .{vector_store_id});
        defer self.allocator.free(path);

        const json_str = try self.serializeSearchParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post(path, json_str);
        defer self.allocator.free(response);

        return try self.parseSearchResponse(response);
    }

    // =========================================================================
    // Serialization
    // =========================================================================

    fn serializeCreateParams(self: *Service, params: VectorStoreCreateParams) ![]u8 {
        var buf = std.array_list.Managed(u8).init(self.allocator);
        defer buf.deinit(self.allocator);

        try buf.append(self.allocator, '{');

        var first = true;

        if (params.file_ids) |file_ids| {
            first = false;
            try buf.appendSlice(self.allocator, "\"file_ids\":[");
            for (file_ids, 0..) |id, i| {
                if (i > 0) try buf.append(self.allocator, ',');
                try buf.append(self.allocator, '"');
                try buf.appendSlice(self.allocator, id);
                try buf.append(self.allocator, '"');
            }
            try buf.append(self.allocator, ']');
        }

        if (params.name) |name| {
            if (!first) try buf.append(self.allocator, ',');
            first = false;
            try buf.appendSlice(self.allocator, "\"name\":\"");
            try buf.appendSlice(self.allocator, name);
            try buf.append(self.allocator, '"');
        }

        if (params.chunking_strategy) |strategy| {
            if (!first) try buf.append(self.allocator, ',');
            first = false;
            try buf.appendSlice(self.allocator, "\"chunking_strategy\":");
            try buf.appendSlice(self.allocator, try self.serializeChunkingStrategy(strategy));
        }

        if (params.metadata) |metadata| {
            if (!first) try buf.append(self.allocator, ',');
            try buf.appendSlice(self.allocator, "\"metadata\":");
            try buf.appendSlice(self.allocator, metadata);
        }

        try buf.append(self.allocator, '}');
        return try buf.toOwnedSlice(self.allocator);
    }

    fn serializeUpdateParams(self: *Service, params: VectorStoreUpdateParams) ![]u8 {
        var buf = std.array_list.Managed(u8).init(self.allocator);
        defer buf.deinit(self.allocator);

        try buf.append(self.allocator, '{');

        var first = true;

        if (params.name) |name| {
            first = false;
            try buf.appendSlice(self.allocator, "\"name\":\"");
            try buf.appendSlice(self.allocator, name);
            try buf.append(self.allocator, '"');
        }

        if (params.metadata) |metadata| {
            if (!first) try buf.append(self.allocator, ',');
            try buf.appendSlice(self.allocator, "\"metadata\":");
            try buf.appendSlice(self.allocator, metadata);
        }

        try buf.append(self.allocator, '}');
        return try buf.toOwnedSlice(self.allocator);
    }

    fn serializeFileCreateParams(self: *Service, params: VectorStoreFileCreateParams) ![]u8 {
        var buf = std.array_list.Managed(u8).init(self.allocator);
        defer buf.deinit(self.allocator);

        try buf.append(self.allocator, '{');

        var first = true;

        if (params.file_id) |file_id| {
            first = false;
            try buf.appendSlice(self.allocator, "\"file_id\":\"");
            try buf.appendSlice(self.allocator, file_id);
            try buf.append(self.allocator, '"');
        }

        if (params.chunking_strategy) |strategy| {
            if (!first) try buf.append(self.allocator, ',');
            try buf.appendSlice(self.allocator, "\"chunking_strategy\":");
            try buf.appendSlice(self.allocator, try self.serializeChunkingStrategy(strategy));
        }

        try buf.append(self.allocator, '}');
        return try buf.toOwnedSlice(self.allocator);
    }

    fn serializeSearchParams(self: *Service, params: VectorStoreSearchParams) ![]u8 {
        var buf = std.array_list.Managed(u8).init(self.allocator);
        defer buf.deinit(self.allocator);

        try buf.append(self.allocator, '{');

        var first = true;

        if (params.query) |query| {
            first = false;
            try buf.appendSlice(self.allocator, "\"query\":\"");
            try buf.appendSlice(self.allocator, query);
            try buf.append(self.allocator, '"');
        }

        if (params.top_k) |top_k| {
            if (!first) try buf.append(self.allocator, ',');
            first = false;
            try buf.appendSlice(self.allocator, "\"top_k\":");
            try std.fmt.formatInt(top_k, 10, .lower, .{}, buf.writer());
        }

        if (params.filter) |filter| {
            if (!first) try buf.append(self.allocator, ',');
            try buf.appendSlice(self.allocator, "\"filter\":");
            try buf.appendSlice(self.allocator, filter);
        }

        try buf.append(self.allocator, '}');
        return try buf.toOwnedSlice(self.allocator);
    }

    fn serializeChunkingStrategy(self: *Service, strategy: ChunkingStrategy) ![]u8 {
        var buf = std.array_list.Managed(u8).init(self.allocator);
        defer buf.deinit(self.allocator);

        try buf.appendSlice(self.allocator, "{\"type\":\"static\",\"static\":{");
        try buf.appendSlice(self.allocator, "\"chunk_size\":");
        try std.fmt.formatInt(strategy.static.chunk_size, 10, .lower, .{}, buf.writer());
        try buf.appendSlice(self.allocator, ",\"chunk_overlap\":");
        try std.fmt.formatInt(strategy.static.chunk_overlap, 10, .lower, .{}, buf.writer());
        try buf.appendSlice(self.allocator, "}}");

        return try buf.toOwnedSlice(self.allocator);
    }

    // =========================================================================
    // Parsing
    // =========================================================================

    fn parseVectorStore(self: *Service, response: []const u8) !VectorStore {
        const id = parseJsonField(response, "id") orelse return error.ParseError;
        const name = parseJsonField(response, "name") orelse "";
        const status = parseJsonField(response, "status") orelse "";

        return VectorStore{
            .id = try self.allocator.dupe(u8, id),
            .name = try self.allocator.dupe(u8, name),
            .status = try self.allocator.dupe(u8, status),
        };
    }

    fn parseDeleteResponse(self: *Service, response: []const u8) !VectorStoreDeleted {
        const id = parseJsonField(response, "id") orelse return error.ParseError;
        const deleted_str = parseJsonField(response, "deleted") orelse "false";

        return VectorStoreDeleted{
            .id = try self.allocator.dupe(u8, id),
            .deleted = std.mem.eql(u8, deleted_str, "true"),
        };
    }

    fn parseListResponse(self: *Service, response: []const u8) !VectorStoreListResponse {
        const data_str = parseJsonField(response, "data") orelse return error.ParseError;

        // Parse array of vector stores
        var stores = std.ArrayListUnmanaged(VectorStore){};
        errdefer {
            for (stores.items) |store| {
                self.allocator.free(store.id);
                self.allocator.free(store.name);
                self.allocator.free(store.status);
            }
            stores.deinit(self.allocator);
        }

        // Simple parsing - find each object
        var idx: usize = 0;
        while (idx < data_str.len) {
            const obj_start = std.mem.indexOfPos(u8, data_str, idx, "\"id\":\"") orelse break;
            const id_value_start = obj_start + 6;
            const id_end = std.mem.indexOfPos(u8, data_str, id_value_start, "\"") orelse break;

            const name_start = std.mem.indexOfPos(u8, data_str, id_end, "\"name\":\"") orelse {
                idx = id_end + 1;
                continue;
            };
            const name_value_start = name_start + 8;
            const name_end = std.mem.indexOfPos(u8, data_str, name_value_start, "\"") orelse {
                idx = id_end + 1;
                continue;
            };

            const status_start = std.mem.indexOfPos(u8, data_str, name_end, "\"status\":\"") orelse {
                idx = id_end + 1;
                continue;
            };
            const status_value_start = status_start + 10;
            const status_end = std.mem.indexOfPos(u8, data_str, status_value_start, "\"") orelse {
                idx = id_end + 1;
                continue;
            };

            try stores.append(self.allocator, .{
                .id = try self.allocator.dupe(u8, data_str[id_value_start..id_end]),
                .name = try self.allocator.dupe(u8, data_str[name_value_start..name_end]),
                .status = try self.allocator.dupe(u8, data_str[status_value_start..status_end]),
            });

            idx = status_end + 1;
        }

        const has_more_str = parseJsonField(response, "has_more") orelse "false";
        const has_more = std.mem.eql(u8, has_more_str, "true");

        return VectorStoreListResponse{
            .data = try stores.toOwnedSlice(self.allocator),
            .has_more = has_more,
        };
    }

    fn parseVectorStoreFile(self: *Service, response: []const u8) !VectorStoreFile {
        const id = parseJsonField(response, "id") orelse return error.ParseError;
        const vector_store_id = parseJsonField(response, "vector_store_id") orelse "";
        const status = parseJsonField(response, "status") orelse "";
        const filename = parseJsonField(response, "filename") orelse "";

        return VectorStoreFile{
            .id = try self.allocator.dupe(u8, id),
            .vector_store_id = try self.allocator.dupe(u8, vector_store_id),
            .status = try self.allocator.dupe(u8, status),
            .filename = try self.allocator.dupe(u8, filename),
        };
    }

    fn parseFileDeleteResponse(self: *Service, response: []const u8) !VectorStoreFileDeleted {
        const id = parseJsonField(response, "id") orelse return error.ParseError;
        const deleted_str = parseJsonField(response, "deleted") orelse "false";

        return VectorStoreFileDeleted{
            .id = try self.allocator.dupe(u8, id),
            .deleted = std.mem.eql(u8, deleted_str, "true"),
        };
    }

    fn parseFileListResponse(self: *Service, response: []const u8) !VectorStoreFileListResponse {
        const data_str = parseJsonField(response, "data") orelse return error.ParseError;

        var files = std.ArrayListUnmanaged(VectorStoreFile){};
        errdefer {
            for (files.items) |file| {
                self.allocator.free(file.id);
                self.allocator.free(file.vector_store_id);
                self.allocator.free(file.status);
                self.allocator.free(file.filename);
            }
            files.deinit(self.allocator);
        }

        // Simple parsing - find each object
        var idx: usize = 0;
        while (idx < data_str.len) {
            const obj_start = std.mem.indexOfPos(u8, data_str, idx, "\"id\":\"") orelse break;
            const id_value_start = obj_start + 6;
            const id_end = std.mem.indexOfPos(u8, data_str, id_value_start, "\"") orelse break;

            const vs_id_start = std.mem.indexOfPos(u8, data_str, id_end, "\"vector_store_id\":\"") orelse {
                idx = id_end + 1;
                continue;
            };
            const vs_id_value_start = vs_id_start + 18;
            const vs_id_end = std.mem.indexOfPos(u8, data_str, vs_id_value_start, "\"") orelse {
                idx = id_end + 1;
                continue;
            };

            const status_start = std.mem.indexOfPos(u8, data_str, vs_id_end, "\"status\":\"") orelse {
                idx = id_end + 1;
                continue;
            };
            const status_value_start = status_start + 10;
            const status_end = std.mem.indexOfPos(u8, data_str, status_value_start, "\"") orelse {
                idx = id_end + 1;
                continue;
            };

            const filename_start = std.mem.indexOfPos(u8, data_str, status_end, "\"filename\":\"") orelse {
                idx = id_end + 1;
                continue;
            };
            const filename_value_start = filename_start + 12;
            const filename_end = std.mem.indexOfPos(u8, data_str, filename_value_start, "\"") orelse {
                idx = id_end + 1;
                continue;
            };

            try files.append(self.allocator, .{
                .id = try self.allocator.dupe(u8, data_str[id_value_start..id_end]),
                .vector_store_id = try self.allocator.dupe(u8, data_str[vs_id_value_start..vs_id_end]),
                .status = try self.allocator.dupe(u8, data_str[status_value_start..status_end]),
                .filename = try self.allocator.dupe(u8, data_str[filename_value_start..filename_end]),
            });

            idx = filename_end + 1;
        }

        const has_more_str = parseJsonField(response, "has_more") orelse "false";
        const has_more = std.mem.eql(u8, has_more_str, "true");

        return VectorStoreFileListResponse{
            .data = try files.toOwnedSlice(self.allocator),
            .has_more = has_more,
        };
    }

    fn parseSearchResponse(self: *Service, response: []const u8) !VectorStoreSearchResponse {
        const data_str = parseJsonField(response, "data") orelse return error.ParseError;

        var results = std.ArrayListUnmanaged(VectorStoreSearchResult){};
        errdefer {
            for (results.items) |result| {
                self.allocator.free(result.text);
            }
            results.deinit(self.allocator);
        }

        // Simple parsing - find text content
        var idx: usize = 0;
        while (idx < data_str.len) {
            const text_start = std.mem.indexOfPos(u8, data_str, idx, "\"text\":\"") orelse break;
            const text_value_start = text_start + 8;
            const text_end = std.mem.indexOfPos(u8, data_str, text_value_start, "\"") orelse break;

            const score_start = std.mem.indexOfPos(u8, data_str, text_end, "\"score\":") orelse {
                idx = text_end + 1;
                continue;
            };
            const score_value_start = score_start + 8;
            var score_end = score_value_start;
            while (score_end < data_str.len and (std.ascii.isDigit(data_str[score_end]) or data_str[score_end] == '.')) {
                score_end += 1;
            }

            const score_text = data_str[score_value_start..score_end];
            const score = std.fmt.parseFloat(f32, score_text) catch 0;

            try results.append(self.allocator, .{
                .text = try self.allocator.dupe(u8, data_str[text_value_start..text_end]),
                .score = score,
            });

            idx = text_end + 1;
        }

        const has_more_str = parseJsonField(response, "has_more") orelse "false";
        const has_more = std.mem.eql(u8, has_more_str, "true");

        return VectorStoreSearchResponse{
            .data = try results.toOwnedSlice(self.allocator),
            .has_more = has_more,
        };
    }

    fn parseJsonField(self: *Service, json_str: []const u8, field_name: []const u8) ?[]const u8 {
        _ = self;
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
};

// ============================================================================
// Request Types
// ============================================================================

pub const VectorStoreCreateParams = struct {
    file_ids: ?[][]const u8 = null,
    name: ?[]const u8 = null,
    chunking_strategy: ?ChunkingStrategy = null,
    metadata: ?[]const u8 = null,
};

pub const VectorStoreUpdateParams = struct {
    name: ?[]const u8 = null,
    metadata: ?[]const u8 = null,
};

pub const VectorStoreListParams = struct {
    limit: ?u32 = null,
    order: ?[]const u8 = null,
    after: ?[]const u8 = null,
    before: ?[]const u8 = null,
};

pub const VectorStoreFileCreateParams = struct {
    file_id: ?[]const u8 = null,
    chunking_strategy: ?ChunkingStrategy = null,
};

pub const VectorStoreFileListParams = struct {
    limit: ?u32 = null,
    order: ?[]const u8 = null,
    after: ?[]const u8 = null,
};

pub const VectorStoreSearchParams = struct {
    query: []const u8,
    top_k: ?u32 = null,
    filter: ?[]const u8 = null,
};

pub const ChunkingStrategy = struct {
    static: StaticChunking,
};

pub const StaticChunking = struct {
    chunk_size: u32,
    chunk_overlap: u32,
};

// ============================================================================
// Response Types
// ============================================================================

pub const VectorStore = struct {
    id: []const u8,
    name: []const u8,
    status: []const u8,
    created_at: ?u64 = null,
    expires_at: ?u64 = null,
    file_counts: ?VectorStoreFileCounts = null,
};

pub const VectorStoreFileCounts = struct {
    in_progress: u32 = 0,
    completed: u32 = 0,
    failed: u32 = 0,
    total: u32 = 0,
};

pub const VectorStoreDeleted = struct {
    id: []const u8,
    deleted: bool,
};

pub const VectorStoreListResponse = struct {
    data: []VectorStore,
    has_more: bool,
};

pub const VectorStoreFile = struct {
    id: []const u8,
    vector_store_id: []const u8,
    status: []const u8,
    filename: []const u8,
    created_at: ?u64 = null,
    size_bytes: ?u64 = null,
};

pub const VectorStoreFileDeleted = struct {
    id: []const u8,
    deleted: bool,
};

pub const VectorStoreFileListResponse = struct {
    data: []VectorStoreFile,
    has_more: bool,
};

pub const VectorStoreSearchResult = struct {
    text: []const u8,
    score: f32,
    file_id: ?[]const u8 = null,
};

pub const VectorStoreSearchResponse = struct {
    data: []VectorStoreSearchResult,
    has_more: bool,
};
