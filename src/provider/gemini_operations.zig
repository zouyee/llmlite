//! Operations API - Google Gemini Async Operations
//!
//! Reference: https://ai.google.dev/gemini-api/docs/operations
//!
//! Operations API allows you to check the status of long-running
//! operations like tuning jobs, batch imports, etc.

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

    /// Get an operation by name
    /// GET /v1beta/{name}
    pub fn get(self: *Service, name: []const u8) !Operation {
        const path = try std.fmt.allocPrint(self.allocator, "/{s}", .{name});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseOperation(response);
    }

    /// List operations
    /// GET /v1beta/{parent}/operations
    pub fn list(self: *Service, parent: []const u8, params: ?ListOperationsParams) !ListOperationsResponse {
        var path = std.array_list.Managed(u8).init(self.allocator);
        defer path.deinit();

        try path.appendSlice("/");
        try path.appendSlice(parent);
        try path.appendSlice("/operations");

        if (params) |p| {
            var first = true;
            if (p.filter) |filter| {
                try path.appendSlice(if (first) "?" else "&");
                try path.appendSlice("filter=");
                try path.appendSlice(filter);
                first = false;
            }
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

    /// Cancel an operation
    /// POST /v1beta/{name}:cancel
    pub fn cancel(self: *Service, name: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/{s}:cancel", .{name});
        defer self.allocator.free(path);

        const response = try self.http_client.post(path, "{}");
        defer self.allocator.free(response);
    }

    /// Delete an operation (for completed operations)
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

    fn parseOperation(self: *Service, response: []const u8) !Operation {
        const name = self.parseField(response, "name") orelse return error.ParseError;
        const done_str = self.parseField(response, "done") orelse "false";
        const done = std.mem.eql(u8, done_str, "true");

        // Parse metadata if present
        const metadata_str = self.parseField(response, "metadata");

        // Parse error if present (currently unused but available for future use)
        const err_str = self.parseField(response, "error");
        _ = err_str; // Available for future use when error details are needed

        // Parse result (could be any JSON value)
        const result_str = self.parseField(response, "response");

        // Allocate strings
        const name_alloc = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_alloc);

        var metadata_alloc: ?[]const u8 = null;
        if (metadata_str) |m| {
            metadata_alloc = try self.allocator.dupe(u8, m);
        }

        var result_alloc: ?[]const u8 = null;
        if (result_str) |r| {
            result_alloc = try self.allocator.dupe(u8, r);
        }

        return Operation{
            .name = name_alloc,
            .done = done,
            .metadata = metadata_alloc,
            .err = null,
            .result = result_alloc,
        };
    }

    fn parseListResponse(self: *Service, response: []const u8) !ListOperationsResponse {
        const data_str = self.parseField(response, "operations") orelse return error.ParseError;
        const next_page_token = self.parseField(response, "nextPageToken");

        var items = std.ArrayListUnmanaged(Operation){};
        errdefer {
            for (items.items) |op| self.freeOperation(op);
            items.deinit(self.allocator);
        }

        // Parse array
        var search_idx: usize = 0;
        while (search_idx < data_str.len) {
            const obj_start = std.mem.indexOf(u8, data_str[search_idx..], "{") orelse break;
            const obj_end = findMatchingBrace(data_str[search_idx + obj_start ..]) orelse break;
            const obj_json = data_str[search_idx + obj_start .. search_idx + obj_start + obj_end + 1];

            const item = self.parseOperation(obj_json) catch continue;
            try items.append(self.allocator, item);

            search_idx += obj_start + obj_end + 1;
        }

        return ListOperationsResponse{
            .operations = try items.toOwnedSlice(self.allocator),
            .next_page_token = if (next_page_token) |t| try self.allocator.dupe(u8, t) else null,
        };
    }

    fn freeOperation(self: *Service, op: Operation) void {
        self.allocator.free(op.name);
        if (op.metadata) |m| self.allocator.free(m);
        if (op.err) |e| self.allocator.free(e.message);
        if (op.result) |r| self.allocator.free(r);
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
            while (i < json_str.len and (std.ascii.isDigit(json_str[i]) or json_str[i] == '.' or json_str[i] == '-' or json_str[i] == 'e' or json_str[i] == 'E' or json_str[i] == 'n' or json_str[i] == 'u' or json_str[i] == 'l' or json_str[i] == 'a')) {
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

pub const ListOperationsParams = struct {
    filter: ?[]const u8 = null,
    page_size: ?i32 = null,
    page_token: ?[]const u8 = null,
};

// ============================================================================
// Response Types
// ============================================================================

pub const OperationError = struct {
    code: i32,
    message: []const u8,
};

pub const Operation = struct {
    name: []const u8,
    done: bool,
    metadata: ?[]const u8 = null,
    err: ?OperationError = null,
    result: ?[]const u8 = null,
};

pub const ListOperationsResponse = struct {
    operations: []Operation,
    next_page_token: ?[]const u8 = null,
};
