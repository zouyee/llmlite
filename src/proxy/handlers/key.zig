//! Key Management Handler for llmlite Proxy
//!
//! Handles /key/* API endpoints for virtual key CRUD operations

const std = @import("std");
const virtual_key = @import("../virtual_key");

pub const KeyHandler = struct {
    allocator: std.mem.Allocator,
    key_store: *virtual_key.VirtualKeyStore,

    pub fn init(allocator: std.mem.Allocator, key_store: *virtual_key.VirtualKeyStore) KeyHandler {
        return .{
            .allocator = allocator,
            .key_store = key_store,
        };
    }

    /// Handle key management request
    pub fn handle(self: *KeyHandler, request: *std.http.Server.Request) !void {
        const path = request.path();

        // Route based on method and path
        if (std.mem.startsWith(u8, path, "POST /key/create")) {
            try self.handleCreate(request);
        } else if (std.mem.startsWith(u8, path, "DELETE /key/")) {
            try self.handleDelete(request);
        } else if (std.mem.startsWith(u8, path, "GET /key/")) {
            try self.handleGet(request);
        } else if (std.mem.startsWith(u8, path, "GET /keys")) {
            try self.handleList(request);
        } else if (std.mem.startsWith(u8, path, "POST /key/revoke")) {
            try self.handleRevoke(request);
        } else {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Not Found\",\"type\":\"invalid_request_error\"}}",
            });
        }
    }

    /// POST /key/create - Create a new virtual key
    fn handleCreate(self: *KeyHandler, request: *std.http.Server.Request) !void {
        const body = try request.reader().readAllAlloc(self.allocator, 1_000_000);
        defer self.allocator.free(body);

        const create_req = std.json.parseFromSlice(
            CreateKeyRequest,
            self.allocator,
            body,
            .{},
        ) catch {
            try request.respond(.{
                .status = .bad_request,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Invalid request body\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };
        defer create_req.deinit();

        const config = virtual_key.VirtualKeyConfig{
            .user_id = create_req.value.user_id,
            .team_id = create_req.value.team_id,
            .rate_limit = create_req.value.rate_limit,
            .allowed_models = create_req.value.allowed_models,
            .allowed_providers = create_req.value.allowed_providers,
            .expires_at = create_req.value.expires_at,
        };

        const key = self.key_store.generateKey(config) catch {
            try request.respond(.{
                .status = .internal_server_error,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Failed to generate key\",\"type\":\"internal_error\"}}",
            });
            return;
        };
        defer self.allocator.free(key);

        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .id = key,
            .key = key,
            .object = "virtual_key",
            .created_at = std.time.timestamp(),
        }, .{});
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .created,
            .content_type = .json,
            .body = response,
        });
    }

    /// DELETE /key/:id - Delete a virtual key
    fn handleDelete(self: *KeyHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        // Extract key id from path: /key/sk-xxx
        const key_id = path[8..]; // Skip "/key/"
        if (key_id.len == 0) {
            try request.respond(.{
                .status = .bad_request,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Key ID required\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        }

        if (self.key_store.delete(key_id)) {
            try request.respond(.{
                .status = .ok,
                .content_type = .json,
                .body = "{\"deleted\":true,\"id\":\"" ++ key_id ++ "\"}",
            });
        } else {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Key not found\",\"type\":\"invalid_request_error\"}}",
            });
        }
    }

    /// GET /key/:id - Get virtual key info
    fn handleGet(self: *KeyHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        // Extract key id from path: /key/sk-xxx
        const key_id = path[8..]; // Skip "/key/"
        if (key_id.len == 0) {
            try request.respond(.{
                .status = .bad_request,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Key ID required\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        }

        const vk = self.key_store.get(key_id) orelse {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Key not found\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };

        const response = try self.formatKeyInfo(vk);
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    /// GET /keys - List all virtual keys
    fn handleList(self: *KeyHandler, request: *std.http.Server.Request) !void {
        _ = request;
        var keys_array = std.array_list.Managed([]const u8).init(self.allocator);
        defer {
            for (keys_array.items) |item| self.allocator.free(item);
            keys_array.deinit();
        }

        var it = self.key_store.keys.iterator();
        while (it.next()) |entry| {
            const info = try self.formatKeyInfo(entry.value_ptr);
            try keys_array.append(info);
        }

        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .object = "list",
            .data = keys_array.items,
        }, .{});
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    /// POST /key/revoke - Revoke a virtual key (soft delete)
    fn handleRevoke(self: *KeyHandler, request: *std.http.Server.Request) !void {
        const body = try request.reader().readAllAlloc(self.allocator, 1_000_000);
        defer self.allocator.free(body);

        const revoke_req = std.json.parseFromSlice(
            RevokeKeyRequest,
            self.allocator,
            body,
            .{},
        ) catch {
            try request.respond(.{
                .status = .bad_request,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Invalid request body\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };
        defer revoke_req.deinit();

        self.key_store.revoke(revoke_req.value.key) catch {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Key not found\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = "{\"revoked\":true,\"id\":\"" ++ revoke_req.value.key ++ "\"}",
        });
    }

    fn formatKeyInfo(self: *KeyHandler, vk: *const virtual_key.VirtualKey) ![]u8 {
        return std.json.Stringify.valueAlloc(self.allocator, .{
            .id = vk.id,
            .object = "virtual_key",
            .key_hash = vk.key_hash,
            .user_id = vk.user_id,
            .team_id = vk.team_id,
            .rate_limit = vk.rate_limit,
            .allowed_models = vk.allowed_models,
            .allowed_providers = vk.allowed_providers,
            .created_at = vk.created_at,
            .expires_at = vk.expires_at,
            .spend = vk.spend,
            .request_count = vk.request_count,
            .last_used = vk.last_used,
            .active = vk.active,
        }, .{});
    }
};

pub const CreateKeyRequest = struct {
    user_id: ?[]const u8 = null,
    team_id: ?[]const u8 = null,
    rate_limit: ?u32 = null,
    allowed_models: ?[][]const u8 = null,
    allowed_providers: ?[]const u8 = null,
    expires_at: ?i64 = null,
};

pub const RevokeKeyRequest = struct {
    key: []const u8,
};
