//! Batch API - Asynchronous batch processing
//!
//! Reference: https://platform.openai.com/docs/api-reference/batch
//!
//! The Batch API allows you to process multiple requests asynchronously,
//! which is more efficient than making individual API calls.

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

    /// Creates a batch of completion requests.
    pub fn createBatch(self: *Service, params: BatchCreateParams) !Batch {
        const json_str = try self.serializeParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/batches", json_str);
        defer self.allocator.free(response);

        return try self.parseBatch(response);
    }

    /// Retrieves a batch by ID.
    pub fn getBatch(self: *Service, batch_id: []const u8) !Batch {
        const path = try std.fmt.allocPrint(self.allocator, "/batches/{s}", .{batch_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseBatch(response);
    }

    /// Cancels a batch in progress.
    pub fn cancelBatch(self: *Service, batch_id: []const u8) !Batch {
        const path = try std.fmt.allocPrint(self.allocator, "/batches/{s}/cancel", .{batch_id});
        defer self.allocator.free(path);

        const response = try self.http_client.post(path, "{}");
        defer self.allocator.free(response);

        return try self.parseBatch(response);
    }

    /// Lists all batches.
    pub fn listBatches(self: *Service, params: ?BatchListParams) !BatchListResponse {
        var path = std.ArrayList(u8).init(self.allocator);
        defer path.deinit();

        try path.appendSlice("/batches");

        if (params) |p| {
            var first = true;
            if (p.after) |after| {
                try path.appendSlice(if (first) "?" else "&");
                try path.appendSlice("after=");
                try path.appendSlice(after);
                first = false;
            }
            if (p.limit) |limit| {
                try path.appendSlice(if (first) "?" else "&");
                try path.writer().print("limit={d}", .{limit});
            }
        }

        const response = try self.http_client.get(try path.toOwnedSlice());
        defer self.allocator.free(response);

        return try self.parseBatchListResponse(response);
    }

    // ============================================================================
    // Serialization
    // ============================================================================

    fn serializeParams(self: *Service, params: BatchCreateParams) ![]u8 {
        var parts = std.ArrayListUnmanaged(u8){};
        defer parts.deinit(self.allocator);

        try parts.appendSlice(self.allocator, "{\"input_file_id\":\"");
        try parts.appendSlice(self.allocator, params.input_file_id);
        try parts.appendSlice(self.allocator, "\",\"endpoint\":\"");
        try parts.appendSlice(self.allocator, params.endpoint);
        try parts.appendSlice(self.allocator, "\"");

        if (params.completion_window) |w| {
            try parts.appendSlice(self.allocator, ",\"completion_window\":\"");
            try parts.appendSlice(self.allocator, w);
            try parts.appendSlice(self.allocator, "\"");
        }

        if (params.metadata) |m| {
            try parts.appendSlice(self.allocator, ",\"metadata\":{\"");
            var first = true;
            var it = m.iterator();
            while (it.next()) |entry| {
                if (!first) try parts.appendSlice(self.allocator, "\",\"");
                first = false;
                try parts.appendSlice(self.allocator, entry.key_ptr.*);
                try parts.appendSlice(self.allocator, "\":\"");
                try parts.appendSlice(self.allocator, entry.value_ptr.*);
            }
            try parts.appendSlice(self.allocator, "\"}");
        }

        try parts.appendSlice(self.allocator, "}");

        return try parts.toOwnedSlice(self.allocator);
    }

    // ============================================================================
    // Parsing
    // ============================================================================

    fn parseBatch(self: *Service, response: []const u8) !Batch {
        const id = self.parseJsonField(response, "id") orelse return error.ParseError;
        const object = self.parseJsonField(response, "object") orelse return error.ParseError;
        const status = self.parseJsonField(response, "status") orelse return error.ParseError;

        const created_at_str = self.parseJsonField(response, "created_at") orelse "0";
        const created_at = std.fmt.parseInt(i64, created_at_str, 10) catch 0;

        const completed_at_str = self.parseJsonField(response, "completed_at") orelse "0";
        const completed_at = std.fmt.parseInt(i64, completed_at_str, 10) catch 0;

        const expires_at_str = self.parseJsonField(response, "expires_at") orelse "0";
        const expires_at = std.fmt.parseInt(i64, expires_at_str, 10) catch 0;

        const request_stats_str = self.parseJsonField(response, "request_stats");
        const request_counts_str = self.parseJsonField(response, "request_counts");
        const output_file_id = self.parseJsonField(response, "output_file_id");
        const error_file_id = self.parseJsonField(response, "error_file_id");
        const final_metadata = self.parseJsonField(response, "metadata");

        return Batch{
            .id = try self.allocator.dupe(u8, id),
            .object = try self.allocator.dupe(u8, object),
            .status = try self.allocator.dupe(u8, status),
            .created_at = created_at,
            .completed_at = completed_at,
            .expires_at = expires_at,
            .request_stats = if (request_stats_str) |s| try self.parseRequestStats(s) else null,
            .request_counts = if (request_counts_str) |s| try self.parseRequestCounts(s) else null,
            .output_file_id = if (output_file_id) |s| try self.allocator.dupe(u8, s) else null,
            .error_file_id = if (error_file_id) |s| try self.allocator.dupe(u8, s) else null,
            .final_metadata = if (final_metadata) |s| try self.allocator.dupe(u8, s) else null,
        };
    }

    fn parseRequestStats(self: *Service, json_str: []const u8) !BatchRequestStats {
        const total_tokens_str = self.parseJsonField(json_str, "total_tokens") orelse "0";
        const successful_requests_str = self.parseJsonField(json_str, "successful_requests") orelse "0";

        return BatchRequestStats{
            .total_tokens = std.fmt.parseInt(u64, total_tokens_str, 10) catch 0,
            .successful_requests = std.fmt.parseInt(u32, successful_requests_str, 10) catch 0,
        };
    }

    fn parseRequestCounts(self: *Service, json_str: []const u8) !BatchRequestCounts {
        const completed_str = self.parseJsonField(json_str, "completed") orelse "0";
        const failed_str = self.parseJsonField(json_str, "failed") orelse "0";
        const total_str = self.parseJsonField(json_str, "total") orelse "0";

        return BatchRequestCounts{
            .completed = std.fmt.parseInt(u32, completed_str, 10) catch 0,
            .failed = std.fmt.parseInt(u32, failed_str, 10) catch 0,
            .total = std.fmt.parseInt(u32, total_str, 10) catch 0,
        };
    }

    fn parseBatchListResponse(self: *Service, response: []const u8) !BatchListResponse {
        const data_str = self.parseJsonField(response, "data") orelse return error.ParseError;
        const has_more_str = self.parseJsonField(response, "has_more") orelse "false";
        const has_more = std.mem.eql(u8, has_more_str, "true");

        // Parse array of batches
        var batches = std.ArrayListUnmanaged(Batch){};
        errdefer {
            for (batches.items) |batch| self.freeBatch(batch);
            batches.deinit(self.allocator);
        }

        var search_idx: usize = 0;
        while (search_idx < data_str.len) {
            const obj_start = std.mem.indexOf(u8, data_str[search_idx..], "{") orelse break;
            const obj_end = findMatchingBrace(data_str[search_idx + obj_start ..]) orelse break;
            const batch_json = data_str[search_idx + obj_start .. search_idx + obj_start + obj_end + 1];

            const batch = try self.parseBatch(batch_json);
            try batches.append(self.allocator, batch);

            search_idx += obj_start + obj_end + 1;
        }

        return BatchListResponse{
            .data = try batches.toOwnedSlice(self.allocator),
            .has_more = has_more,
        };
    }

    fn freeBatch(self: *Service, batch: Batch) void {
        self.allocator.free(batch.id);
        self.allocator.free(batch.object);
        self.allocator.free(batch.status);
        if (batch.output_file_id) |id| self.allocator.free(id);
        if (batch.error_file_id) |id| self.allocator.free(id);
        if (batch.final_metadata) |m| self.allocator.free(m);
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
};

fn findMatchingBrace(data: []const u8) ?usize {
    if (data.len == 0 or data[0] != '{') return null;
    var depth: u32 = 1;
    var i: usize = 1;
    while (i < data.len and depth > 0) {
        if (data[i] == '{') depth += 1;
        if (data[i] == '}') depth -= 1;
        i += 1;
    }
    if (depth == 0) return i - 1;
    return null;
}

// ============================================================================
// Request Types
// ============================================================================

pub const BatchCreateParams = struct {
    input_file_id: []const u8,
    endpoint: []const u8,
    completion_window: ?[]const u8 = "24h",
    metadata: ?std.StringHashMap([]const u8) = null,
};

pub const BatchListParams = struct {
    after: ?[]const u8 = null,
    limit: ?u32 = null,
};

// ============================================================================
// Response Types
// ============================================================================

pub const Batch = struct {
    id: []const u8,
    object: []const u8,
    status: []const u8,
    created_at: i64,
    completed_at: i64,
    expires_at: i64,
    request_stats: ?BatchRequestStats = null,
    request_counts: ?BatchRequestCounts = null,
    output_file_id: ?[]const u8 = null,
    error_file_id: ?[]const u8 = null,
    final_metadata: ?[]const u8 = null,
};

pub const BatchRequestStats = struct {
    total_tokens: u64,
    successful_requests: u32,
};

pub const BatchRequestCounts = struct {
    completed: u32,
    failed: u32,
    total: u32,
};

pub const BatchListResponse = struct {
    data: []Batch,
    has_more: bool,
};

/// Batch status values
pub const BatchStatus = enum {
    validating,
    failed,
    in_progress,
    finalizing,
    completed,
    expired,
    cancelling,
    cancelled,

    pub fn toString(self: BatchStatus) []const u8 {
        return switch (self) {
            .validating => "validating",
            .failed => "failed",
            .in_progress => "in_progress",
            .finalizing => "finalizing",
            .completed => "completed",
            .expired => "expired",
            .cancelling => "cancelling",
            .cancelled => "cancelled",
        };
    }
};
