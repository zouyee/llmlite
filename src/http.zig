const std = @import("std");
const Http = std.http;
const Uri = std.Uri;

pub const AuthType = enum {
    bearer,
    api_key,
};

pub const ApiError = struct {
    message: []const u8,
    error_type: []const u8,

    pub fn fromJson(allocator: std.mem.Allocator, json_str: []const u8) !ApiError {
        const err_start = std.mem.find(u8, json_str, "\"error\":{") orelse return error.ParseError;
        const obj_start_idx = err_start + 8;
        const obj_str = json_str[obj_start_idx..];

        const msg_key = "\"message\":\"";
        const msg_start = std.mem.find(u8, obj_str, msg_key) orelse return error.ParseError;
        const msg_value_start = msg_start + msg_key.len;
        const msg_end = std.mem.findPos(u8, obj_str, msg_value_start, "\"") orelse return error.ParseError;
        const message = try allocator.dupe(u8, obj_str[msg_value_start..msg_end]);

        const type_key = "\"type\":\"";
        const type_start = std.mem.find(u8, obj_str, type_key) orelse return error.ParseError;
        const type_value_start = type_start + type_key.len;
        const type_end = std.mem.findPos(u8, obj_str, type_value_start, "\"") orelse return error.ParseError;
        const error_type = try allocator.dupe(u8, obj_str[type_value_start..type_end]);

        return ApiError{
            .message = message,
            .error_type = error_type,
        };
    }
};

pub const HttpResponse = struct {
    body: []u8,
    status_code: u32,
};

pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    base_url: []const u8,
    api_key: []const u8,
    organization: ?[]const u8,
    timeout_ms: u32,
    auth_type: AuthType,
    /// Lazily-allocated persistent auth header (freed in deinit)
    auth_header: ?[]u8 = null,
    /// Reusable HTTP client for connection pooling
    client: Http.Client,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, base_url: []const u8, api_key: []const u8, organization: ?[]const u8, timeout_ms: u32) HttpClient {
        return .{
            .allocator = allocator,
            .io = io,
            .base_url = base_url,
            .api_key = api_key,
            .organization = organization,
            .timeout_ms = timeout_ms,
            .auth_type = .bearer,
            .auth_header = null,
            .client = Http.Client{ .allocator = allocator, .io = io },
        };
    }

    pub fn initWithAuthType(allocator: std.mem.Allocator, io: std.Io, base_url: []const u8, api_key: []const u8, organization: ?[]const u8, timeout_ms: u32, auth_type: AuthType) HttpClient {
        return .{
            .allocator = allocator,
            .io = io,
            .base_url = base_url,
            .api_key = api_key,
            .organization = organization,
            .timeout_ms = timeout_ms,
            .auth_type = auth_type,
            .auth_header = null,
            .client = Http.Client{ .allocator = allocator, .io = io },
        };
    }

    pub fn deinit(self: *HttpClient) void {
        if (self.auth_header) |h| {
            self.allocator.free(h);
        }
        self.client.deinit();
    }

    /// Ensure auth_header is allocated (lazy initialization)
    fn ensureAuthHeader(self: *HttpClient) !void {
        if (self.auth_type == .bearer and self.auth_header == null) {
            self.auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        }
    }

    pub fn post(self: *HttpClient, path: []const u8, body: []const u8) ![]u8 {
        return self.sendRequest("POST", path, body, "application/json");
    }

    pub fn postForm(self: *HttpClient, path: []const u8, body: []const u8) ![]u8 {
        return self.sendRequest("POST", path, body, "multipart/form-data");
    }

    pub fn postBinary(self: *HttpClient, path: []const u8, body: []const u8) ![]u8 {
        return self.sendRequest("POST", path, body, "application/octet-stream");
    }

    pub fn get(self: *HttpClient, path: []const u8) ![]u8 {
        return self.sendRequest("GET", path, "", "application/json");
    }

    pub fn delete(self: *HttpClient, path: []const u8) ![]u8 {
        return self.sendRequest("DELETE", path, "", "application/json");
    }

    pub fn getResponse(self: *HttpClient, path: []const u8) !HttpResponse {
        return self.sendRequestWithStatus("GET", path, "", "application/json");
    }

    fn sendRequest(self: *HttpClient, method: []const u8, path: []const u8, body: []const u8, content_type: []const u8) ![]u8 {
        const response = try self.sendRequestWithStatus(method, path, body, content_type);
        return response.body;
    }

    fn sendRequestWithStatus(self: *HttpClient, method: []const u8, path: []const u8, body: []const u8, content_type: []const u8) !HttpResponse {
        try self.ensureAuthHeader();

        const url = switch (self.auth_type) {
            .bearer => try std.mem.concat(self.allocator, u8, &.{ self.base_url, path }),
            .api_key => try std.fmt.allocPrint(self.allocator, "{s}{s}?key={s}", .{ self.base_url, path, self.api_key }),
        };
        defer self.allocator.free(url);

        const uri = Uri.parse(url) catch return error.InvalidUrl;

        var headers: [2]Http.Header = undefined;
        var header_count: usize = 0;

        switch (self.auth_type) {
            .bearer => {
                headers[0] = .{ .name = "Authorization", .value = self.auth_header.? };
                headers[1] = .{ .name = "Content-Type", .value = content_type };
                header_count = 2;
            },
            .api_key => {
                headers[0] = .{ .name = "Content-Type", .value = content_type };
                header_count = 1;
            },
        }

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

        var response_writer = std.Io.Writer.Allocating.init(self.allocator);
        defer response_writer.deinit();

        const fetch_result = self.client.fetch(.{
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

        return HttpResponse{
            .body = try self.allocator.dupe(u8, response_writer.written()),
            .status_code = status_code,
        };
    }
};
