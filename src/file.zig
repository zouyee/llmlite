//! Files API

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

    /// Upload a file that contains document(s) to be used across various endpoints.
    pub fn uploadFile(self: *Service, file_content: []const u8, filename: []const u8, purpose: FilePurpose) !FileObject {
        const form_data = try self.buildUploadFormData(file_content, filename, purpose);
        defer self.allocator.free(form_data);

        const response = try self.http_client.postForm("/files", form_data);
        defer self.allocator.free(response);

        return try self.parseFileResponse(response);
    }

    /// Upload a file from a local path.
    /// Reads the file content and uploads it to the API.
    pub fn uploadFromPath(self: *Service, local_path: []const u8, purpose: FilePurpose) !FileObject {
        // Read file content from local path
        const file = try std.Io.Dir.cwd().openFile(self.http_client.io, local_path, .{});
        defer file.close(self.http_client.io);

        const file_content = try blk: { var __buf: [8192]u8 = undefined; var __r = file.reader(self.http_client.io, &__buf); break :blk __r.interface.allocRemaining(self.allocator, .limited(std.math.maxInt(usize))); };
        errdefer self.allocator.free(file_content);

        // Extract filename from path
        const filename = std.fs.path.basename(local_path);

        return try self.uploadFile(file_content, filename, purpose);
    }

    fn buildUploadFormData(self: *Service, file_content: []const u8, filename: []const u8, purpose: FilePurpose) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8).empty;
        errdefer buf.deinit(self.allocator);

        // Add file
        try buf.appendSlice(self.allocator, "--form\n");
        try buf.appendSlice(self.allocator, "Content-Disposition: form-data; name=\"file\"; filename=\"");
        try buf.appendSlice(self.allocator, filename);
        try buf.appendSlice(self.allocator, "\"\r\n");
        try buf.appendSlice(self.allocator, "Content-Type: application/octet-stream\r\n\r\n");
        try buf.appendSlice(self.allocator, file_content);
        try buf.appendSlice(self.allocator, "\r\n");

        // Add purpose
        try buf.appendSlice(self.allocator, "--form\n");
        try buf.appendSlice(self.allocator, "Content-Disposition: form-data; name=\"purpose\"\r\n\r\n");
        try buf.appendSlice(self.allocator, purpose.toString());
        try buf.appendSlice(self.allocator, "\r\n");

        try buf.appendSlice(self.allocator, "--form--\r\n");

        return try buf.toOwnedSlice(self.allocator);
    }

    /// Returns information about a specific file.
    pub fn getFile(self: *Service, file_id: []const u8) !FileObject {
        const path = try std.fmt.allocPrint(self.allocator, "/files/{s}", .{file_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseFileResponse(response);
    }

    /// Returns a list of files that belong to the user's organization.
    pub fn listFiles(self: *Service) !FileList {
        const response = try self.http_client.get("/files");
        defer self.allocator.free(response);

        return try self.parseFileListResponse(response);
    }

    /// Delete a file.
    pub fn deleteFile(self: *Service, file_id: []const u8) !FileDeleted {
        const path = try std.fmt.allocPrint(self.allocator, "/files/{s}", .{file_id});
        defer self.allocator.free(path);

        const response = try self.http_client.delete(path);
        defer self.allocator.free(response);

        return try self.parseFileDeletedResponse(response);
    }

    /// Downloads the content of a file.
    pub fn downloadContent(self: *Service, file_id: []const u8) ![]u8 {
        const path = try std.fmt.allocPrint(self.allocator, "/files/{s}/content", .{file_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        return response;
    }

    /// Register files from GCS (Google Cloud Storage)
    /// POST /v1beta/files:register
    /// Note: This is a Gemini API specific endpoint for registering GCS files
    pub fn registerFiles(self: *Service, params: RegisterFilesParams) !FileObject {
        const json_str = try self.serializeRegisterParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/files:register", json_str);
        defer self.allocator.free(response);

        return try self.parseFileResponse(response);
    }

    fn serializeRegisterParams(self: *Service, params: RegisterFilesParams) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8).empty;
        defer buf.deinit(self.allocator);

        try buf.appendSlice(self.allocator, "{\"gcsFiles\":[");
        for (params.gcs_uris, 0..) |uri, i| {
            if (i > 0) try buf.appendSlice(self.allocator, ",");
            try buf.appendSlice(self.allocator, "{\"gcsUri\":\"");
            try buf.appendSlice(self.allocator, uri);
            try buf.appendSlice(self.allocator, "\"}");
        }
        try buf.appendSlice(self.allocator, "]}");

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

    fn parseFileResponse(self: *Service, response: []const u8) !FileObject {
        const id = parseJsonField(response, "id") orelse return error.ParseError;
        const bytes_str = parseJsonField(response, "bytes") orelse "0";
        const created_at_str = parseJsonField(response, "created_at") orelse "0";
        const filename = parseJsonField(response, "filename") orelse "unknown";
        const purpose = parseJsonField(response, "purpose") orelse "unknown";
        const status = parseJsonField(response, "status") orelse "unknown";

        return FileObject{
            .id = try self.allocator.dupe(u8, id),
            .bytes = std.fmt.parseInt(u32, bytes_str, 10) catch 0,
            .created_at = std.fmt.parseInt(u64, created_at_str, 10) catch 0,
            .filename = try self.allocator.dupe(u8, filename),
            .purpose = try self.allocator.dupe(u8, purpose),
            .status = try self.allocator.dupe(u8, status),
        };
    }

    fn parseFileListResponse(self: *Service, response: []const u8) !FileList {
        const data_str = parseJsonField(response, "data") orelse return error.ParseError;

        var file_count: usize = 0;
        var search_pos: usize = 0;
        while (std.mem.findPos(u8, data_str, search_pos, "\"id\":")) |_| {
            file_count += 1;
            search_pos += 1;
        }

        const files = try self.allocator.alloc(FileObject, file_count);
        errdefer self.allocator.free(files);

        return FileList{
            .data = files,
        };
    }

    fn parseFileDeletedResponse(self: *Service, response: []const u8) !FileDeleted {
        const id = parseJsonField(response, "id") orelse return error.ParseError;
        const deleted_str = parseJsonField(response, "deleted") orelse "false";

        return FileDeleted{
            .id = try self.allocator.dupe(u8, id),
            .deleted = std.mem.eql(u8, deleted_str, "true"),
        };
    }
};

// ============================================================================
// File Purpose
// ============================================================================

pub const FilePurpose = enum {
    assistants,
    batch,
    fine_tune,
    vision,
    user_data,
    // Kimi-specific purposes
    file_extract,
    image,
    video,

    pub fn toString(self: FilePurpose) []const u8 {
        return switch (self) {
            .assistants => "assistants",
            .batch => "batch",
            .fine_tune => "fine-tune",
            .vision => "vision",
            .user_data => "user_data",
            .file_extract => "file-extract",
            .image => "image",
            .video => "video",
        };
    }
};

// ============================================================================
// File Object
// ============================================================================

pub const FileObject = struct {
    id: []const u8,
    object: []const u8 = "file",
    bytes: u32,
    created_at: u64,
    filename: []const u8,
    purpose: []const u8,
    status: []const u8,
    status_details: ?[]const u8 = null,
};

// ============================================================================
// File List Response
// ============================================================================

pub const FileList = struct {
    object: []const u8 = "list",
    data: []FileObject,
};

// ============================================================================
// File Deleted
// ============================================================================

pub const FileDeleted = struct {
    id: []const u8,
    object: []const u8 = "file",
    deleted: bool,
};

// ============================================================================
// File Content Response (raw bytes)
// ============================================================================

pub const FileContent = struct {
    data: []u8,
    filename: []const u8,
};

// ============================================================================
// Register Files Params (GCS)
// ============================================================================

pub const RegisterFilesParams = struct {
    gcs_uris: []const []const u8,
};
