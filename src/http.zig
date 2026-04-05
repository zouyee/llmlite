//! HTTP Client Wrapper
//! Supports multiple authentication methods: Bearer Token, API Key (URL param)

const std = @import("std");
const Http = std.http;
const Uri = std.Uri;

// ============================================================================
// Auth Type
// ============================================================================

/// Authentication type
pub const AuthType = enum {
    bearer, // Authorization: Bearer {key} (default)
    api_key, // URL query parameter ?key={key}
};

/// API error information
pub const ApiError = struct {
    message: []const u8,
    error_type: []const u8,

    pub fn fromJson(allocator: std.mem.Allocator, json_str: []const u8) !ApiError {
        const err_start = std.mem.indexOf(u8, json_str, "\"error\":{") orelse return error.ParseError;
        const obj_start_idx = err_start + 8;
        const obj_str = json_str[obj_start_idx..];

        const msg_key = "\"message\":\"";
        const msg_start = std.mem.indexOf(u8, obj_str, msg_key) orelse return error.ParseError;
        const msg_value_start = msg_start + msg_key.len;
        const msg_end = std.mem.indexOfPos(u8, obj_str, msg_value_start, "\"") orelse return error.ParseError;
        const message = try allocator.dupe(u8, obj_str[msg_value_start..msg_end]);

        const type_key = "\"type\":\"";
        const type_start = std.mem.indexOf(u8, obj_str, type_key) orelse return error.ParseError;
        const type_value_start = type_start + type_key.len;
        const type_end = std.mem.indexOfPos(u8, obj_str, type_value_start, "\"") orelse return error.ParseError;
        const error_type = try allocator.dupe(u8, obj_str[type_value_start..type_end]);

        return ApiError{
            .message = message,
            .error_type = error_type,
        };
    }
};

// ============================================================================
// HttpClient
// ============================================================================

pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    api_key: []const u8,
    organization: ?[]const u8,
    timeout_ms: u32,
    auth_type: AuthType,

    /// Default initialization (using Bearer auth)
    pub fn init(allocator: std.mem.Allocator, base_url: []const u8, api_key: []const u8, organization: ?[]const u8, timeout_ms: u32) HttpClient {
        return .{
            .allocator = allocator,
            .base_url = base_url,
            .api_key = api_key,
            .organization = organization,
            .timeout_ms = timeout_ms,
            .auth_type = .bearer,
        };
    }

    /// Initialize with specified auth type
    pub fn initWithAuthType(allocator: std.mem.Allocator, base_url: []const u8, api_key: []const u8, organization: ?[]const u8, timeout_ms: u32, auth_type: AuthType) HttpClient {
        return .{
            .allocator = allocator,
            .base_url = base_url,
            .api_key = api_key,
            .organization = organization,
            .timeout_ms = timeout_ms,
            .auth_type = auth_type,
        };
    }

    pub fn deinit(self: *HttpClient) void {
        _ = self;
    }

    pub fn post(self: *HttpClient, path: []const u8, body: []const u8) ![]u8 {
        return self.sendRequest("POST", path, body, "application/json");
    }

    pub fn postForm(self: *HttpClient, path: []const u8, body: []const u8) ![]u8 {
        return self.sendRequest("POST", path, body, "multipart/form-data");
    }

    pub fn postBinary(self: *HttpClient, path: []const u8, body: []const u8) ![]u8 {
        return self.sendRequest("POST", path, body, "application/json");
    }

    pub fn get(self: *HttpClient, path: []const u8) ![]u8 {
        return self.sendRequest("GET", path, "", "application/json");
    }

    pub fn delete(self: *HttpClient, path: []const u8) ![]u8 {
        return self.sendRequest("DELETE", path, "", "application/json");
    }
    fn sendRequest(self: *HttpClient, method: []const u8, path: []const u8, body: []const u8, content_type: []const u8) ![]u8 {
        // Build URL and headers based on auth type
        var url: []u8 = undefined;
        var headers: [2]Http.Header = undefined;
        var header_count: usize = 0;

        switch (self.auth_type) {
            .bearer => {
                // Bearer: Authorization header
                url = try std.mem.concat(self.allocator, u8, &.{ self.base_url, path });
                errdefer self.allocator.free(url);

                const auth_value = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
                errdefer self.allocator.free(auth_value);

                headers[0] = .{ .name = "Authorization", .value = auth_value };
                headers[1] = .{ .name = "Content-Type", .value = content_type };
                header_count = 2;
            },
            .api_key => {
                // API Key: URL query parameter (Google AI, etc.)
                url = try std.fmt.allocPrint(self.allocator, "{s}{s}?key={s}", .{ self.base_url, path, self.api_key });
                errdefer self.allocator.free(url);

                headers[0] = .{ .name = "Content-Type", .value = content_type };
                header_count = 1;
            },
        }

        const uri = Uri.parse(url) catch return error.InvalidUrl;
        defer self.allocator.free(url);

        var http_client = Http.Client{ .allocator = self.allocator };
        defer http_client.deinit();

        const http_method: Http.Method = if (std.mem.eql(u8, method, "GET"))
            .GET
        else if (std.mem.eql(u8, method, "POST"))
            .POST
        else if (std.mem.eql(u8, method, "DELETE"))
            .DELETE
        else if (std.mem.eql(u8, method, "PUT"))
            .PUT
        else if (std.mem.eql(u8, method, "PATCH"))
            .PATCH
        else
            return error.InvalidUrl;

        // Use Io.Writer.Allocating to capture the response body
        var response_writer = std.Io.Writer.Allocating.init(self.allocator);
        defer response_writer.deinit();

        const fetch_result = http_client.fetch(.{
            .location = .{ .uri = uri },
            .method = http_method,
            .payload = if (body.len > 0) body else null,
            .response_writer = &response_writer.writer,
            .extra_headers = headers[0..header_count],
        }) catch |e| {
            if (e == error.HttpContentEncodingUnsupported) {
                return error.InvalidResponse;
            }
            return e;
        };

        const status_code = @intFromEnum(fetch_result.status);

        if (status_code == 401) return error.AuthenticationError;
        if (status_code == 429) return error.RateLimitError;
        if (status_code >= 400 and status_code < 500) return error.ApiError;
        if (status_code >= 500) return error.ApiError;
        if (status_code < 200 or status_code >= 300) return error.InvalidResponse;

        return try self.allocator.dupe(u8, response_writer.written());
    }
};
