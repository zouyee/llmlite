//! Key Management - Manage llmlite-proxy virtual keys via API

const std = @import("std");

pub const KeyManager = struct {
    allocator: std.mem.Allocator,
    proxy_url: []const u8,

    pub fn init(allocator: std.mem.Allocator) KeyManager {
        return .{
            .allocator = allocator,
            .proxy_url = "http://localhost:4000",
        };
    }

    pub fn setProxyUrl(self: *KeyManager, url: []const u8) void {
        self.proxy_url = url;
    }

    /// List all virtual keys
    pub fn listKeys(self: *KeyManager) !void {
        const url = try std.mem.concat(self.allocator, u8, &.{ self.proxy_url, "/keys" });
        defer self.allocator.free(url);

        const response = try self.httpGet(url);
        defer self.allocator.free(response);

        // Parse and display keys
        std.debug.print("{s}\n", .{response});
    }

    /// Create a new virtual key
    pub fn createKey(self: *KeyManager, config: CreateKeyConfig) ![]const u8 {
        const url = try std.mem.concat(self.allocator, u8, &.{ self.proxy_url, "/key/create" });
        defer self.allocator.free(url);

        const body = try std.json.stringifyAlloc(self.allocator, .{
            .user_id = config.user_id,
            .team_id = config.team_id,
            .rate_limit = config.rate_limit,
            .allowed_models = config.allowed_models,
            .allowed_providers = config.allowed_providers,
            .expires_at = config.expires_at,
        }, .{});
        defer self.allocator.free(body);

        const response = try self.httpPost(url, body);
        defer self.allocator.free(response);

        // Parse response to get key
        const parsed = try std.json.parseFromSlice(struct {
            key: []const u8,
        }, self.allocator, response, .{});
        defer parsed.deinit();

        return parsed.value.key;
    }

    /// Revoke a virtual key
    pub fn revokeKey(self: *KeyManager, key: []const u8) !void {
        const url = try std.mem.concat(self.allocator, u8, &.{ self.proxy_url, "/key/revoke" });
        defer self.allocator.free(url);

        const body = try std.json.stringifyAlloc(self.allocator, .{
            .key = key,
        }, .{});
        defer self.allocator.free(body);

        const response = try self.httpPost(url, body);
        defer self.allocator.free(response);

        std.debug.print("{s}\n", .{response});
    }

    /// Get key info
    pub fn getKeyInfo(self: *KeyManager, key: []const u8) !void {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/key/{s}", .{ self.proxy_url, key });
        defer self.allocator.free(url);

        const response = try self.httpGet(url);
        defer self.allocator.free(response);

        std.debug.print("{s}\n", .{response});
    }

    fn httpGet(self: *KeyManager, url: []const u8) ![]u8 {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const uri = std.Uri.parse(url) catch return error.InvalidUrl;
        const response = try client.fetch(.{
            .location = uri,
            .method = .GET,
        });

        if (response.status != .ok) {
            return error.HttpError;
        }

        return response.body;
    }

    fn httpPost(self: *KeyManager, url: []const u8, body: []const u8) ![]u8 {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const uri = std.Uri.parse(url) catch return error.InvalidUrl;
        const response = try client.fetch(.{
            .location = uri,
            .method = .POST,
            .headers = .{
                .content_type = .json,
            },
            .body = .{
                .string = body,
            },
        });

        if (response.status != .ok and response.status != .created) {
            return error.HttpError;
        }

        return response.body;
    }
};

pub const CreateKeyConfig = struct {
    user_id: ?[]const u8 = null,
    team_id: ?[]const u8 = null,
    rate_limit: ?u32 = null,
    allowed_models: ?[][]const u8 = null,
    allowed_providers: ?[]const u8 = null,
    expires_at: ?i64 = null,
};
