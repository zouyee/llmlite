//! Container API - For running fine-tuned models in containers
//!
//! Reference: https://platform.openai.com/docs/api-reference/containers

const std = @import("std");
const json = std.json;
const http = @import("http");

// ============================================================================
// Container Service
// ============================================================================

pub const ContainerService = struct {
    allocator: std.mem.Allocator,
    http_client: *http.HttpClient,

    pub fn init(allocator: std.mem.Allocator, http_client: *http.HttpClient) ContainerService {
        return .{
            .allocator = allocator,
            .http_client = http_client,
        };
    }

    pub fn deinit(self: *ContainerService) void {
        _ = self;
    }

    /// Create a new container
    pub fn create(self: *ContainerService, params: CreateContainerParams) !Container {
        const json_str = try self.serializeParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/containers", json_str);
        defer self.allocator.free(response);

        return try self.parseResponse(response);
    }

    /// Retrieve a container by ID
    pub fn get(self: *ContainerService, container_id: []const u8) !Container {
        const path = try std.fmt.allocPrint(self.allocator, "/containers/{s}", .{container_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseResponse(response);
    }

    /// List containers
    pub fn list(self: *ContainerService, params: ListContainersParams) !ContainerListResponse {
        const json_str = try self.serializeListParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.get("/containers");
        defer self.allocator.free(response);

        return try self.parseListResponse(response);
    }

    /// Delete a container
    pub fn delete(self: *ContainerService, container_id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/containers/{s}", .{container_id});
        defer self.allocator.free(path);

        _ = try self.http_client.delete(path);
    }

    fn serializeParams(self: *ContainerService, params: CreateContainerParams) ![]u8 {
        var parts = std.ArrayList(u8).init(self.allocator);
        errdefer parts.deinit();

        try std.json.stringify(.{
            .name = params.name,
        }, .{}, parts.writer());

        if (params.expires_after) |v| {
            try parts.appendSlice(",\"expires_after\":");
            try std.json.stringify(.{ .anchor = v.anchor, .minutes = v.minutes }, .{}, parts.writer());
        }
        if (params.file_ids) |v| {
            try parts.appendSlice(",\"file_ids\":");
            try std.json.stringify(v, .{}, parts.writer());
        }
        if (params.memory_limit) |v| {
            try parts.appendSlice(",\"memory_limit\":");
            try std.json.stringify(v, .{}, parts.writer());
        }
        if (params.network_policy) |v| {
            try parts.appendSlice(",\"network_policy\":");
            try std.json.stringify(v, .{}, parts.writer());
        }

        return parts.toOwnedSlice();
    }

    fn serializeListParams(self: *ContainerService, params: ListContainersParams) ![]u8 {
        var parts = std.ArrayList(u8).init(self.allocator);
        errdefer parts.deinit();

        try parts.appendSlice("?");
        if (params.limit) |v| {
            try std.json.stringify(.{ .limit = v }, .{}, parts.writer());
        }
        if (params.after) |v| {
            if (parts.items.len > 1) try parts.appendSlice("&");
            try parts.appendSlice("after=");
            try parts.appendSlice(v);
        }
        if (params.order) |v| {
            if (parts.items.len > 1) try parts.appendSlice("&");
            try parts.appendSlice("order=");
            try parts.appendSlice(v);
        }

        return parts.toOwnedSlice();
    }

    fn parseResponse(self: *ContainerService, response: []const u8) !Container {
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        const id = (root.get("id") orelse return error.ParseError).string;
        const name = (root.get("name") orelse return error.ParseError).string;
        const status = (root.get("status") orelse return error.ParseError).string;
        const created_at = (root.get("created_at") orelse return error.ParseError).integer;

        return Container{
            .id = try self.allocator.dupe(u8, id),
            .name = try self.allocator.dupe(u8, name),
            .status = try self.allocator.dupe(u8, status),
            .created_at = @intCast(created_at),
        };
    }

    fn parseListResponse(self: *ContainerService, response: []const u8) !ContainerListResponse {
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        const data_array = (root.get("data") orelse return error.ParseError).array;
        var containers = try self.allocator.alloc(Container, data_array.len);

        for (data_array, 0..) |item, i| {
            const obj = item.object orelse return error.ParseError;
            containers[i] = .{
                .id = try self.allocator.dupe(u8, (obj.get("id") orelse return error.ParseError).string),
                .name = try self.allocator.dupe(u8, (obj.get("name") orelse return error.ParseError).string),
                .status = try self.allocator.dupe(u8, (obj.get("status") orelse return error.ParseError).string),
                .created_at = @intCast((obj.get("created_at") orelse return error.ParseError).integer),
            };
        }

        return ContainerListResponse{
            .data = containers,
            .has_more = root.get("has_more").?.bool,
        };
    }
};

// ============================================================================
// Container File Service
// ============================================================================

pub const ContainerFileService = struct {
    allocator: std.mem.Allocator,
    http_client: *http.HttpClient,

    pub fn init(allocator: std.mem.Allocator, http_client: *http.HttpClient) ContainerFileService {
        return .{
            .allocator = allocator,
            .http_client = http_client,
        };
    }

    /// Upload a file to a container
    pub fn create(self: *ContainerFileService, container_id: []const u8, file_data: []const u8, filename: []const u8) !ContainerFile {
        const path = try std.fmt.allocPrint(self.allocator, "/containers/{s}/files", .{container_id});
        defer self.allocator.free(path);

        // TODO: Implement multipart form upload
        _ = file_data;
        _ = filename;

        const response = try self.http_client.post(path, "{}");
        defer self.allocator.free(response);

        return try self.parseFileResponse(response);
    }

    /// Get a file from a container
    pub fn get(self: *ContainerFileService, container_id: []const u8, file_id: []const u8) !ContainerFile {
        const path = try std.fmt.allocPrint(self.allocator, "/containers/{s}/files/{s}", .{ container_id, file_id });
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseFileResponse(response);
    }

    /// List files in a container
    pub fn list(self: *ContainerFileService, container_id: []const u8) !ContainerFileListResponse {
        const path = try std.fmt.allocPrint(self.allocator, "/containers/{s}/files", .{container_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseFileListResponse(response);
    }

    fn parseFileResponse(self: *ContainerFileService, response: []const u8) !ContainerFile {
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        return ContainerFile{
            .id = try self.allocator.dupe(u8, (root.get("id") orelse return error.ParseError).string),
            .object = try self.allocator.dupe(u8, (root.get("object") orelse return error.ParseError).string),
            .created_at = @intCast((root.get("created_at") orelse return error.ParseError).integer),
        };
    }

    fn parseFileListResponse(self: *ContainerFileService, response: []const u8) !ContainerFileListResponse {
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        const data_array = (root.get("data") orelse return error.ParseError).array;
        var files = try self.allocator.alloc(ContainerFile, data_array.len);

        for (data_array, 0..) |item, i| {
            const obj = item.object orelse return error.ParseError;
            files[i] = .{
                .id = try self.allocator.dupe(u8, (obj.get("id") orelse return error.ParseError).string),
                .object = try self.allocator.dupe(u8, (obj.get("object") orelse return error.ParseError).string),
                .created_at = @intCast((obj.get("created_at") orelse return error.ParseError).integer),
            };
        }

        return ContainerFileListResponse{
            .data = files,
        };
    }
};

// ============================================================================
// Types
// ============================================================================

/// Container object
pub const Container = struct {
    id: []const u8,
    name: []const u8,
    status: []const u8,
    created_at: i64,
};

/// Container file object
pub const ContainerFile = struct {
    id: []const u8,
    object: []const u8,
    created_at: i64,
};

/// Container list response
pub const ContainerListResponse = struct {
    data: []Container,
    has_more: bool,
};

/// Container file list response
pub const ContainerFileListResponse = struct {
    data: []ContainerFile,
};

// ============================================================================
// Parameters
// ============================================================================

/// Parameters for creating a container
pub const CreateContainerParams = struct {
    name: []const u8,
    expires_after: ?ExpiresAfter = null,
    file_ids: ?[]const []const u8 = null,
    memory_limit: ?MemoryLimit = null,
    network_policy: ?NetworkPolicy = null,
};

/// Expiration configuration
pub const ExpiresAfter = struct {
    anchor: []const u8, // "last_active_at"
    minutes: i64,
};

/// Memory limit options
pub const MemoryLimit = enum([]const u8) {
    @"1g" = "1g",
    @"4g" = "4g",
    @"16g" = "16g",
    @"64g" = "64g",
};

/// Network policy
pub const NetworkPolicy = struct {
    type: []const u8, // "disabled" or "allowlist"
    allowed_domains: ?[]const []const u8 = null,
};

/// Parameters for listing containers
pub const ListContainersParams = struct {
    limit: ?i32 = null,
    after: ?[]const u8 = null,
    order: ?[]const u8 = null, // "asc" or "desc"
};
