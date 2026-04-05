//! FileSearchStores API - Google Gemini Vector Search Store
//!
//! Reference: https://ai.google.dev/gemini-api/docs/vector-search
//!
//! FileSearchStores API allows you to create and manage vector search stores
//! for semantic search over your documents.

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

    /// Create a new file search store
    /// POST /v1beta/filesearchStores
    pub fn create(self: *Service, params: CreateFileSearchStoreParams) !FileSearchStore {
        const json_str = try self.serializeCreateParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/filesearchStores", json_str);
        defer self.allocator.free(response);

        return try self.parseFileSearchStore(response);
    }

    /// Get a file search store by name
    /// GET /v1beta/{name}
    pub fn get(self: *Service, name: []const u8) !FileSearchStore {
        const path = try std.fmt.allocPrint(self.allocator, "/{s}", .{name});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseFileSearchStore(response);
    }

    /// List file search stores
    /// GET /v1beta/filesearchStores
    pub fn list(self: *Service, params: ?ListFileSearchStoresParams) !ListFileSearchStoresResponse {
        var path = std.ArrayList(u8).init(self.allocator);
        defer path.deinit();

        try path.appendSlice("/filesearchStores");

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

    /// Delete a file search store
    /// DELETE /v1beta/{name}
    pub fn delete(self: *Service, name: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/{s}", .{name});
        defer self.allocator.free(path);

        const response = try self.http_client.delete(path);
        defer self.allocator.free(response);
    }

    /// Upload files to a store
    /// POST /v1beta/{name}:uploadFiles
    pub fn uploadFiles(self: *Service, name: []const u8, params: UploadFilesParams) !Operation {
        const path = try std.fmt.allocPrint(self.allocator, "/{s}:uploadFiles", .{name});
        defer self.allocator.free(path);

        const json_str = try self.serializeUploadParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post(path, json_str);
        defer self.allocator.free(response);

        return try self.parseOperation(response);
    }

    /// Upload a single file directly to a store (binary upload)
    /// POST /v1beta/{name}:uploadFiles
    /// Takes raw file bytes instead of GCS URIs
    pub fn uploadToFileSearchStore(self: *Service, name: []const u8, file_data: []const u8, mime_type: []const u8) !Operation {
        const path = try std.fmt.allocPrint(self.allocator, "/{s}:uploadFiles", .{name});
        defer self.allocator.free(path);

        // Build multipart form data manually
        const form_data = try self.buildBinaryUploadFormData(file_data, mime_type);
        defer self.allocator.free(form_data);

        const response = try self.http_client.postForm(path, form_data);
        defer self.allocator.free(response);

        return try self.parseOperation(response);
    }

    /// Upload a file from a local path to a store
    /// Reads the file and uploads it directly
    pub fn uploadToFileSearchStoreFromPath(self: *Service, name: []const u8, local_path: []const u8, mime_type: []const u8) !Operation {
        // Read file content from local path
        const file = try std.fs.cwd().openFile(local_path, .{});
        defer file.close();

        const file_data = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        errdefer self.allocator.free(file_data);

        return try self.uploadToFileSearchStore(name, file_data, mime_type);
    }

    /// Import files from GCS to a store
    /// POST /v1beta/{name}:importFiles
    pub fn importFiles(self: *Service, name: []const u8, params: ImportFilesParams) !Operation {
        const path = try std.fmt.allocPrint(self.allocator, "/{s}:importFiles", .{name});
        defer self.allocator.free(path);

        const json_str = try self.serializeImportParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post(path, json_str);
        defer self.allocator.free(response);

        return try self.parseOperation(response);
    }

    // ============================================================================
    // Serialization
    // ============================================================================

    fn buildBinaryUploadFormData(self: *Service, file_data: []const u8, mime_type: []const u8) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8).empty;
        errdefer buf.deinit(self.allocator);

        try buf.appendSlice(self.allocator, "--form\n");
        try buf.appendSlice(self.allocator, "Content-Disposition: form-data; name=\"file\"; filename=\"upload\"\r\n");
        try buf.appendSlice(self.allocator, "Content-Type: ");
        try buf.appendSlice(self.allocator, mime_type);
        try buf.appendSlice(self.allocator, "\r\n\r\n");
        try buf.appendSlice(self.allocator, file_data);
        try buf.appendSlice(self.allocator, "\r\n--form--\r\n");

        return try buf.toOwnedSlice(self.allocator);
    }

    fn serializeCreateParams(self: *Service, params: CreateFileSearchStoreParams) ![]u8 {
        var parts = std.ArrayListUnmanaged(u8){};
        defer parts.deinit(self.allocator);

        try parts.appendSlice(self.allocator, "{\"displayName\":\"");
        try parts.appendSlice(self.allocator, params.display_name);
        try parts.appendSlice(self.allocator, "\",\"embeddingModel\":\"");
        try parts.appendSlice(self.allocator, params.embedding_model);
        try parts.appendSlice(self.allocator, "\"");

        if (params.description) |desc| {
            try parts.appendSlice(self.allocator, ",\"description\":\"");
            try parts.appendSlice(self.allocator, desc);
            try parts.appendSlice(self.allocator, "\"");
        }

        if (params.labels) |labels| {
            try parts.appendSlice(self.allocator, ",\"labels\":{");
            var first = true;
            var it = labels.iterator();
            while (it.next()) |entry| {
                if (!first) try parts.appendSlice(self.allocator, ",");
                first = false;
                try parts.appendSlice(self.allocator, "\"");
                try parts.appendSlice(self.allocator, entry.key_ptr.*);
                try parts.appendSlice(self.allocator, "\":\"");
                try parts.appendSlice(self.allocator, entry.value_ptr.*);
                try parts.appendSlice(self.allocator, "\"");
            }
            try parts.appendSlice(self.allocator, "}");
        }

        try parts.appendSlice(self.allocator, "}");
        return try parts.toOwnedSlice(self.allocator);
    }

    fn serializeUploadParams(self: *Service, params: UploadFilesParams) ![]u8 {
        var parts = std.ArrayListUnmanaged(u8){};
        defer parts.deinit(self.allocator);

        try parts.appendSlice(self.allocator, "{\"files\":[");
        for (params.files, 0..) |file, i| {
            if (i > 0) try parts.appendSlice(self.allocator, ",");
            try parts.appendSlice(self.allocator, "{\"gcsSource\":{\"uri\":\"");
            try parts.appendSlice(self.allocator, file);
            try parts.appendSlice(self.allocator, "\"}}");
        }
        try parts.appendSlice(self.allocator, "]}");

        return try parts.toOwnedSlice(self.allocator);
    }

    fn serializeImportParams(self: *Service, params: ImportFilesParams) ![]u8 {
        var parts = std.ArrayListUnmanaged(u8){};
        defer parts.deinit(self.allocator);

        try parts.appendSlice(self.allocator, "{\"gcsSource\":{\"uris\":[");
        for (params.gcs_uris, 0..) |uri, i| {
            if (i > 0) try parts.appendSlice(self.allocator, ",");
            try parts.appendSlice(self.allocator, "\"");
            try parts.appendSlice(self.allocator, uri);
            try parts.appendSlice(self.allocator, "\"");
        }
        try parts.appendSlice(self.allocator, "],\"mimeType\":\"");
        try parts.appendSlice(self.allocator, params.mime_type);
        try parts.appendSlice(self.allocator, "\"}}");

        return try parts.toOwnedSlice(self.allocator);
    }

    // ============================================================================
    // Parsing
    // ============================================================================

    fn parseFileSearchStore(self: *Service, response: []const u8) !FileSearchStore {
        const name = self.parseField(response, "name") orelse return error.ParseError;
        const display_name = self.parseField(response, "displayName") orelse return error.ParseError;
        const embedding_model = self.parseField(response, "embeddingModel") orelse return error.ParseError;
        const description = self.parseField(response, "description");
        const state_str = self.parseField(response, "state") orelse "STATE_UNSPECIFIED";
        const state = self.parseStoreState(state_str);

        const create_time = self.parseField(response, "createTime");
        const update_time = self.parseField(response, "updateTime");

        // Vector count
        const vector_count_str = self.parseField(response, "vectorCount") orelse "0";
        const vector_count = std.fmt.parseInt(i64, vector_count_str, 10) catch 0;

        // Dimensions
        const dimensions_str = self.parseField(response, "dimensions") orelse "0";
        const dimensions = std.fmt.parseInt(i32, dimensions_str, 10) catch 0;

        return FileSearchStore{
            .name = try self.allocator.dupe(u8, name),
            .display_name = try self.allocator.dupe(u8, display_name),
            .embedding_model = try self.allocator.dupe(u8, embedding_model),
            .description = if (description) |d| try self.allocator.dupe(u8, d) else null,
            .state = state,
            .create_time = if (create_time) |t| try self.allocator.dupe(u8, t) else null,
            .update_time = if (update_time) |t| try self.allocator.dupe(u8, t) else null,
            .vector_count = vector_count,
            .dimensions = dimensions,
        };
    }

    fn parseStoreState(state_str: []const u8) FileSearchStoreState {
        if (std.mem.indexOf(u8, state_str, "ACTIVE")) |_| return .active;
        if (std.mem.indexOf(u8, state_str, "CREATING")) |_| return .creating;
        if (std.mem.indexOf(u8, state_str, "FAILED")) |_| return .failed;
        if (std.mem.indexOf(u8, state_str, "DELETING")) |_| return .deleting;
        if (std.mem.indexOf(u8, state_str, "UPDATING")) |_| return .updating;
        return .unspecified;
    }

    fn parseOperation(self: *Service, response: []const u8) !Operation {
        const done_str = self.parseField(response, "done") orelse "false";
        const done = std.mem.eql(u8, done_str, "true");

        var result: ?FileSearchStore = null;
        if (self.parseField(response, "response")) |resp_str| {
            result = self.parseFileSearchStore(resp_str) catch null;
        }

        var error_msg: ?[]const u8 = null;
        if (self.parseField(response, "error")) |err_str| {
            error_msg = self.parseField(err_str, "message");
        }

        return Operation{
            .done = done,
            .result = result,
            .error_message = if (error_msg) |e| try self.allocator.dupe(u8, e) else null,
        };
    }

    fn parseListResponse(self: *Service, response: []const u8) !ListFileSearchStoresResponse {
        const data_str = self.parseField(response, "fileSearchStores") orelse return error.ParseError;
        const next_page_token = self.parseField(response, "nextPageToken");

        var items = std.ArrayListUnmanaged(FileSearchStore){};
        errdefer {
            for (items.items) |item| self.freeFileSearchStore(item);
            items.deinit(self.allocator);
        }

        // Parse array
        var search_idx: usize = 0;
        while (search_idx < data_str.len) {
            const obj_start = std.mem.indexOf(u8, data_str[search_idx..], "{") orelse break;
            const obj_end = findMatchingBrace(data_str[search_idx + obj_start ..]) orelse break;
            const obj_json = data_str[search_idx + obj_start .. search_idx + obj_start + obj_end + 1];

            const item = self.parseFileSearchStore(obj_json) catch continue;
            try items.append(self.allocator, item);

            search_idx += obj_start + obj_end + 1;
        }

        return ListFileSearchStoresResponse{
            .file_search_stores = try items.toOwnedSlice(self.allocator),
            .next_page_token = if (next_page_token) |t| try self.allocator.dupe(u8, t) else null,
        };
    }

    fn freeFileSearchStore(self: *Service, store: FileSearchStore) void {
        self.allocator.free(store.name);
        self.allocator.free(store.display_name);
        self.allocator.free(store.embedding_model);
        if (store.description) |d| self.allocator.free(d);
        if (store.create_time) |t| self.allocator.free(t);
        if (store.update_time) |t| self.allocator.free(t);
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

pub const CreateFileSearchStoreParams = struct {
    display_name: []const u8,
    embedding_model: []const u8,
    description: ?[]const u8 = null,
    labels: ?std.StringHashMap([]const u8) = null,
};

pub const ListFileSearchStoresParams = struct {
    page_size: ?i32 = null,
    page_token: ?[]const u8 = null,
};

pub const UploadFilesParams = struct {
    files: []const []const u8,
};

pub const ImportFilesParams = struct {
    gcs_uris: []const []const u8,
    mime_type: []const u8,
};

// ============================================================================
// Store State
// ============================================================================

pub const FileSearchStoreState = enum {
    unspecified,
    creating,
    active,
    failed,
    deleting,
    updating,

    pub fn toString(self: FileSearchStoreState) []const u8 {
        return switch (self) {
            .unspecified => "STATE_UNSPECIFIED",
            .creating => "CREATING",
            .active => "ACTIVE",
            .failed => "FAILED",
            .deleting => "DELETING",
            .updating => "UPDATING",
        };
    }
};

// ============================================================================
// Response Types
// ============================================================================

pub const FileSearchStore = struct {
    name: []const u8,
    display_name: []const u8,
    embedding_model: []const u8,
    description: ?[]const u8 = null,
    state: FileSearchStoreState = .unspecified,
    create_time: ?[]const u8 = null,
    update_time: ?[]const u8 = null,
    vector_count: i64 = 0,
    dimensions: i32 = 0,
};

pub const Operation = struct {
    done: bool,
    result: ?FileSearchStore,
    error_message: ?[]const u8 = null,
};

pub const ListFileSearchStoresResponse = struct {
    file_search_stores: []FileSearchStore,
    next_page_token: ?[]const u8 = null,
};
