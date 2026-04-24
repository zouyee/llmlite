//! Provider Management Handler for llmlite Proxy
//!
//! Handles /api/providers/* API endpoints for provider CRUD operations

const std = @import("std");
const time_compat = @import("time_compat");

// Zig 0.16.0 compat: managed StringArrayHashMap wrapper
fn StringArrayHashMap(comptime V: type) type {
    return struct {
        const Self = @This();
        unmanaged: std.StringArrayHashMapUnmanaged(V),
        allocator: std.mem.Allocator,
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .unmanaged = .empty, .allocator = allocator };
        }
        pub fn deinit(self: *Self) void { self.unmanaged.deinit(self.allocator); }
        pub fn put(self: *Self, key: []const u8, value: V) !void { return self.unmanaged.put(self.allocator, key, value); }
        pub fn get(self: Self, key: []const u8) ?V { return self.unmanaged.get(key); }
        pub fn getPtr(self: Self, key: []const u8) ?*V { return self.unmanaged.getPtr(key); }
        pub fn getOrPut(self: *Self, key: []const u8) !std.StringArrayHashMapUnmanaged(V).GetOrPutResult { return self.unmanaged.getOrPut(self.allocator, key); }
        pub fn getOrPutValue(self: *Self, key: []const u8, value: V) !std.StringArrayHashMapUnmanaged(V).GetOrPutResult { return self.unmanaged.getOrPutValue(self.allocator, key, value); }
        pub fn contains(self: Self, key: []const u8) bool { return self.unmanaged.contains(key); }
        pub fn count(self: Self) usize { return self.unmanaged.count(); }
        pub fn iterator(self: Self) std.StringArrayHashMapUnmanaged(V).Iterator { return self.unmanaged.iterator(); }
        pub fn fetchSwapRemove(self: *Self, key: []const u8) ?std.StringArrayHashMapUnmanaged(V).KV { return self.unmanaged.fetchSwapRemove(key); }
        pub fn fetchRemove(self: *Self, key: []const u8) ?std.StringArrayHashMapUnmanaged(V).KV { return self.unmanaged.fetchSwapRemove(key); }
        pub fn swapRemove(self: *Self, key: []const u8) bool { return self.unmanaged.swapRemove(key); }
        pub fn keys(self: Self) [][]const u8 { return self.unmanaged.keys(); }
        pub fn values(self: Self) []V { return self.unmanaged.values(); }
    };
}
const types = @import("../types");

pub const AuthType = enum {
    bearer,
    api_key,
    none,
};

pub const Provider = struct {
    id: []const u8,
    name: []const u8,
    base_url: []const u8,
    auth_type: AuthType,
    api_key: ?[]const u8,
    default_model: []const u8,
    supports: [][]const u8,
    is_official: bool,
    enabled: bool,
    sort_order: u32,
    created_at: i64,
    updated_at: i64,
    metadata: ?[]const u8, // JSON string for extra data

    pub fn formatJson(self: *const Provider, allocator: std.mem.Allocator) ![]u8 {
        return std.json.Stringify.valueAlloc(allocator, .{
            .id = self.id,
            .name = self.name,
            .base_url = self.base_url,
            .auth_type = @tagName(self.auth_type),
            .api_key = self.api_key,
            .default_model = self.default_model,
            .supports = self.supports,
            .is_official = self.is_official,
            .enabled = self.enabled,
            .sort_order = self.sort_order,
            .created_at = self.created_at,
            .updated_at = self.updated_at,
            .metadata = self.metadata,
        }, .{});
    }
};

pub const ProviderStore = struct {
    allocator: std.mem.Allocator,
    providers: StringArrayHashMap(Provider),
    current_id: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) ProviderStore {
        return .{
            .allocator = allocator,
            .providers = StringArrayHashMap(Provider).init(allocator),
            .current_id = null,
        };
    }

    pub fn deinit(self: *ProviderStore) void {
        var it = self.providers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.id);
            self.allocator.free(entry.value_ptr.name);
            self.allocator.free(entry.value_ptr.base_url);
            if (entry.value_ptr.api_key) |key| self.allocator.free(key);
            self.allocator.free(entry.value_ptr.default_model);
            for (entry.value_ptr.supports) |s| self.allocator.free(s);
            self.allocator.free(entry.value_ptr.supports);
            if (entry.value_ptr.metadata) |m| self.allocator.free(m);
        }
        self.providers.deinit();
    }

    pub fn add(self: *ProviderStore, provider: Provider) !void {
        const id = try self.allocator.dupe(u8, provider.id);
        errdefer self.allocator.free(id);

        try self.providers.put(id, provider);
    }

    pub fn get(self: *const ProviderStore, id: []const u8) ?*const Provider {
        return self.providers.get(id);
    }

    pub fn getAll(self: *ProviderStore) []const *Provider {
        var result = self.allocator.alloc([]const *Provider, self.providers.count()) catch return &.{};
        var i: usize = 0;
        var it = self.providers.iterator();
        while (it.next()) |entry| {
            result[i] = entry.value_ptr;
            i += 1;
        }
        return result;
    }

    pub fn update(self: *ProviderStore, provider: Provider) !void {
        const existing = self.providers.get(provider.id) orelse return error.NotFound;

        // Free old strings
        self.allocator.free(existing.id);
        self.allocator.free(existing.name);
        self.allocator.free(existing.base_url);
        if (existing.api_key) |key| self.allocator.free(key);
        self.allocator.free(existing.default_model);
        for (existing.supports) |s| self.allocator.free(s);
        self.allocator.free(existing.supports);
        if (existing.metadata) |m| self.allocator.free(m);

        self.providers.put(provider.id, provider) catch return error.UpdateFailed;
    }

    pub fn delete(self: *ProviderStore, id: []const u8) bool {
        const entry = self.providers.fetchPut(id) catch return false;
        if (entry) |e| {
            self.allocator.free(e.key);
            self.allocator.free(e.value.id);
            self.allocator.free(e.value.name);
            self.allocator.free(e.value.base_url);
            if (e.value.api_key) |key| self.allocator.free(key);
            self.allocator.free(e.value.default_model);
            for (e.value.supports) |s| self.allocator.free(s);
            self.allocator.free(e.value.supports);
            if (e.value.metadata) |m| self.allocator.free(m);
            return true;
        }
        return false;
    }

    pub fn setCurrent(self: *ProviderStore, id: []const u8) void {
        if (self.current_id) |old| {
            self.allocator.free(old);
        }
        self.current_id = self.allocator.dupe(u8, id) catch null;
    }

    pub fn getCurrent(self: *const ProviderStore) ?*const Provider {
        if (self.current_id) |id| {
            return self.providers.get(id);
        }
        return null;
    }

    pub fn getSorted(self: *ProviderStore) []const *Provider {
        const count = self.providers.count();
        if (count == 0) return &.{};

        var sorted = self.allocator.alloc([]const *Provider, count) catch return &.{};
        var it = self.providers.iterator();
        var i: usize = 0;
        while (it.next()) |entry| {
            sorted[i] = entry.value_ptr;
            i += 1;
        }

        // Simple sort by sort_order
        for (sorted[0..count], 0..) |a, outer_i| {
            for (sorted[outer_i + 1 .. count], outer_i + 1..) |b, inner_j| {
                if (a.sort_order > b.sort_order) {
                    const tmp = sorted[outer_i];
                    sorted[outer_i] = sorted[inner_j];
                    sorted[inner_j] = tmp;
                }
            }
        }

        return sorted;
    }
};

pub const ProviderHandler = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *ProviderStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *ProviderStore) ProviderHandler {
        return .{
            .allocator = allocator,
            .io = io,
            .store = store,
        };
    }

    /// Route request to appropriate handler
    pub fn handle(self: *ProviderHandler, request: *std.http.Server.Request) !void {
        const path = request.path();

        // List providers
        if (std.mem.startsWith(u8, path, "GET /api/providers")) {
            if (path.len == 15 or std.mem.eql(u8, path[0..15], "GET /api/providers")) {
                // Check if it's /api/providers/presets
                if (path.len > 15) {
                    const remainder = path[15..];
                    if (std.mem.startsWith(u8, remainder, "/presets")) {
                        try self.handleListPresets(request);
                        return;
                    }
                }
                try self.handleListProviders(request);
            }
        }
        // Create provider
        else if (std.mem.startsWith(u8, path, "POST /api/providers")) {
            if (path.len > 16 and std.mem.startsWith(u8, path[16..], "/presets/")) {
                // POST /api/providers/presets/:id/import
                try self.handleImportPreset(request);
            } else {
                try self.handleCreateProvider(request);
            }
        }
        // Get/Update/Delete provider by ID
        else if (std.mem.startsWith(u8, path, "GET /api/providers/")) {
            try self.handleGetProvider(request);
        } else if (std.mem.startsWith(u8, path, "PUT /api/providers/")) {
            try self.handleUpdateProvider(request);
        } else if (std.mem.startsWith(u8, path, "DELETE /api/providers/")) {
            try self.handleDeleteProvider(request);
        }
        // Provider actions
        else if (std.mem.startsWith(u8, path, "POST /api/providers/")) {
            try self.handleProviderAction(request);
        } else {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Not Found\",\"type\":\"invalid_request_error\"}}",
            });
        }
    }

    // ==================== Provider CRUD ====================

    fn handleListProviders(self: *ProviderHandler, request: *std.http.Server.Request) !void {
        const sorted = self.store.getSorted();

        var items = std.array_list.Managed([]const u8).init(self.allocator);
        defer {
            for (items.items) |item| self.allocator.free(item);
            items.deinit();
        }

        for (sorted) |provider| {
            const json = try provider.formatJson(self.allocator);
            try items.append(json);
        }

        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .object = "list",
            .data = items.items,
            .current = self.store.getCurrent(),
        }, .{});
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    fn handleCreateProvider(self: *ProviderHandler, request: *std.http.Server.Request) !void {
        const body = try request.reader().allocRemaining(self.allocator, .limited(1_000_000));
        defer self.allocator.free(body);

        const create_req = std.json.parseFromSlice(
            CreateProviderRequest,
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

        const now = time_compat.timestamp(self.io);
        const provider = Provider{
            .id = create_req.value.id,
            .name = create_req.value.name,
            .base_url = create_req.value.base_url,
            .auth_type = if (std.mem.eql(u8, create_req.value.auth_type, "bearer")) .bearer else if (std.mem.eql(u8, create_req.value.auth_type, "api_key")) .api_key else .none,
            .api_key = create_req.value.api_key,
            .default_model = create_req.value.default_model,
            .supports = create_req.value.supports,
            .is_official = create_req.value.is_official,
            .enabled = create_req.value.enabled,
            .sort_order = create_req.value.sort_order,
            .created_at = now,
            .updated_at = now,
            .metadata = null,
        };

        self.store.add(provider) catch {
            try request.respond(.{
                .status = .internal_server_error,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Failed to add provider\",\"type\":\"internal_error\"}}",
            });
            return;
        };

        const response = try provider.formatJson(self.allocator);
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .created,
            .content_type = .json,
            .body = response,
        });
    }

    fn handleGetProvider(self: *ProviderHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        const id = path[16..]; // Skip "/api/providers/"

        const provider = self.store.get(id) orelse {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Provider not found\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };

        const response = try provider.formatJson(self.allocator);
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    fn handleUpdateProvider(self: *ProviderHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        const id_start = std.mem.find(u8, path, "/").?;
        const id = path[id_start + 1 ..];

        const existing = self.store.get(id) orelse {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Provider not found\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };

        const body = try request.reader().allocRemaining(self.allocator, .limited(1_000_000));
        defer self.allocator.free(body);

        const update_req = std.json.parseFromSlice(
            UpdateProviderRequest,
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
        defer update_req.deinit();

        const updated = Provider{
            .id = existing.id,
            .name = update_req.value.name orelse existing.name,
            .base_url = update_req.value.base_url orelse existing.base_url,
            .auth_type = if (update_req.value.auth_type) |at|
                if (std.mem.eql(u8, at, "bearer")) .bearer else if (std.mem.eql(u8, at, "api_key")) .api_key else .none
            else
                existing.auth_type,
            .api_key = update_req.value.api_key orelse existing.api_key,
            .default_model = update_req.value.default_model orelse existing.default_model,
            .supports = update_req.value.supports orelse existing.supports,
            .is_official = update_req.value.is_official orelse existing.is_official,
            .enabled = update_req.value.enabled orelse existing.enabled,
            .sort_order = update_req.value.sort_order orelse existing.sort_order,
            .created_at = existing.created_at,
            .updated_at = time_compat.timestamp(self.io),
            .metadata = update_req.value.metadata orelse existing.metadata,
        };

        self.store.update(updated) catch {
            try request.respond(.{
                .status = .internal_server_error,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Failed to update provider\",\"type\":\"internal_error\"}}",
            });
            return;
        };

        const response = try updated.formatJson(self.allocator);
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    fn handleDeleteProvider(self: *ProviderHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        const id = path[18..]; // Skip "/api/providers/"

        if (self.store.delete(id)) {
            try request.respond(.{
                .status = .ok,
                .content_type = .json,
                .body = "{\"deleted\":true,\"id\":\"" ++ id ++ "\"}",
            });
        } else {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Provider not found\",\"type\":\"invalid_request_error\"}}",
            });
        }
    }

    fn handleProviderAction(self: *ProviderHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        const remainder = path[17..]; // Skip "/api/providers/"

        // Parse: /api/providers/{id}/action
        const slash_idx = std.mem.find(u8, remainder, "/") orelse {
            try request.respond(.{
                .status = .bad_request,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Invalid path\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };

        const id = remainder[0..slash_idx];
        const action = remainder[slash_idx + 1 ..];

        if (std.mem.eql(u8, action, "switch")) {
            try self.handleSwitchProvider(request, id);
        } else if (std.mem.eql(u8, action, "test")) {
            try self.handleTestProvider(request, id);
        } else if (std.mem.eql(u8, action, "sort")) {
            try self.handleSortProviders(request);
        } else {
            try request.respond(.{
                .status = .bad_request,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Unknown action\",\"type\":\"invalid_request_error\"}}",
            });
        }
    }

    fn handleSwitchProvider(self: *ProviderHandler, request: *std.http.Server.Request, id: []const u8) !void {
        const provider = self.store.get(id) orelse {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Provider not found\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };

        self.store.setCurrent(id);

        const response = try provider.formatJson(self.allocator);
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = "{\"switched\":true,\"provider\":" ++ response ++ "}",
        });
    }

    fn handleTestProvider(self: *ProviderHandler, request: *std.http.Server.Request, id: []const u8) !void {
        const provider = self.store.get(id) orelse {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Provider not found\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };

        // Simple connectivity test - just check if base_url responds
        const start_time = time_compat.timestamp(self.io);

        // For now, return a mock success response
        // TODO: Actually test the connection by making a real HTTP request
        _ = provider;

        const latency_ms = @as(u64, @intCast(time_compat.timestamp(self.io) - start_time));

        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .success = true,
            .latency_ms = latency_ms,
            .provider_id = id,
        }, .{});
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    fn handleSortProviders(self: *ProviderHandler, request: *std.http.Server.Request) !void {
        const body = try request.reader().allocRemaining(self.allocator, .limited(1_000_000));
        defer self.allocator.free(body);

        const sort_req = std.json.parseFromSlice(
            SortProvidersRequest,
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
        defer sort_req.deinit();

        // Update sort_order for each provider based on position in array
        for (sort_req.value.ids, 0..) |id, index| {
            if (self.store.get(id)) |provider| {
                var updated = provider.*;
                updated.sort_order = @intCast(index);
                self.store.update(updated) catch continue;
            }
        }

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = "{\"sorted\":true}",
        });
    }

    // ==================== Presets ====================

    fn handleListPresets(self: *ProviderHandler, request: *std.http.Server.Request) !void {
        // Return built-in provider presets
        const presets = &[_]ProviderPreset{
            .{
                .id = "openai",
                .name = "OpenAI",
                .provider_type = "openai",
                .base_url = "https://api.openai.com",
                .auth_type = "bearer",
                .default_models = &.{ "gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo" },
                .features = &.{ "chat", "embeddings", "images" },
                .website = "https://openai.com",
                .description = "OpenAI GPT models",
            },
            .{
                .id = "anthropic",
                .name = "Anthropic",
                .provider_type = "anthropic",
                .base_url = "https://api.anthropic.com",
                .auth_type = "bearer",
                .default_models = &.{ "claude-3-5-sonnet", "claude-3-opus", "claude-3-haiku" },
                .features = &.{"chat"},
                .website = "https://anthropic.com",
                .description = "Claude models by Anthropic",
            },
            .{
                .id = "google",
                .name = "Google Gemini",
                .provider_type = "google",
                .base_url = "https://generativelanguage.googleapis.com",
                .auth_type = "api_key",
                .default_models = &.{ "gemini-2.0-flash", "gemini-1.5-pro", "gemini-1.5-flash" },
                .features = &.{ "chat", "embeddings" },
                .website = "https://ai.google.dev",
                .description = "Google Gemini models",
            },
            .{
                .id = "moonshot",
                .name = "Moonshot (Kimi)",
                .provider_type = "moonshot",
                .base_url = "https://api.moonshot.cn",
                .auth_type = "bearer",
                .default_models = &.{ "moonshot-v1-8k", "moonshot-v1-32k", "moonshot-v1-128k" },
                .features = &.{"chat"},
                .website = "https://platform.moonshot.cn",
                .description = "Moonshot AI Kimi models",
            },
            .{
                .id = "minimax",
                .name = "Minimax",
                .provider_type = "minimax",
                .base_url = "https://api.minimax.chat",
                .auth_type = "bearer",
                .default_models = &.{ "abab6-chat", "abab5.5-chat" },
                .features = &.{ "chat", "embeddings", "tts" },
                .website = "https://www.minimax.chat",
                .description = "Minimax AI models",
            },
            .{
                .id = "deepseek",
                .name = "DeepSeek",
                .provider_type = "deepseek",
                .base_url = "https://api.deepseek.com",
                .auth_type = "bearer",
                .default_models = &.{ "deepseek-v4-flash", "deepseek-v4-pro", "deepseek-chat", "deepseek-coder" },
                .features = &.{"chat"},
                .website = "https://deepseek.com",
                .description = "DeepSeek models",
            },
        };

        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .object = "list",
            .data = presets,
        }, .{});
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    fn handleImportPreset(self: *ProviderHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        // /api/providers/presets/:id/import
        const remainder = path[21..]; // Skip "/api/providers/presets/"
        const slash_idx = std.mem.find(u8, remainder, "/") orelse {
            try request.respond(.{
                .status = .bad_request,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Invalid path\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };
        const preset_id = remainder[0..slash_idx];

        // Find preset and create provider from it
        const presets = [_]ProviderPreset{
            .{ .id = "openai", .name = "OpenAI", .provider_type = "openai", .base_url = "https://api.openai.com", .auth_type = "bearer", .default_models = &.{"gpt-4o"}, .features = &.{"chat"}, .website = "https://openai.com", .description = "OpenAI" },
            .{ .id = "anthropic", .name = "Anthropic", .provider_type = "anthropic", .base_url = "https://api.anthropic.com", .auth_type = "bearer", .default_models = &.{"claude-3-5-sonnet"}, .features = &.{"chat"}, .website = "https://anthropic.com", .description = "Anthropic" },
            .{ .id = "google", .name = "Google Gemini", .provider_type = "google", .base_url = "https://generativelanguage.googleapis.com", .auth_type = "api_key", .default_models = &.{"gemini-2.0-flash"}, .features = &.{"chat"}, .website = "https://ai.google.dev", .description = "Google" },
            .{ .id = "moonshot", .name = "Moonshot (Kimi)", .provider_type = "moonshot", .base_url = "https://api.moonshot.cn", .auth_type = "bearer", .default_models = &.{"moonshot-v1-8k"}, .features = &.{"chat"}, .website = "https://platform.moonshot.cn", .description = "Moonshot" },
            .{ .id = "minimax", .name = "Minimax", .provider_type = "minimax", .base_url = "https://api.minimax.chat", .auth_type = "bearer", .default_models = &.{"abab6-chat"}, .features = &.{"chat"}, .website = "https://www.minimax.chat", .description = "Minimax" },
            .{ .id = "deepseek", .name = "DeepSeek", .provider_type = "deepseek", .base_url = "https://api.deepseek.com", .auth_type = "bearer", .default_models = &.{"deepseek-v4-flash", "deepseek-v4-pro", "deepseek-chat"}, .features = &.{"chat"}, .website = "https://deepseek.com", .description = "DeepSeek V4" },
        };

        var found_preset: ?ProviderPreset = null;
        for (presets) |preset| {
            if (std.mem.eql(u8, preset.id, preset_id)) {
                found_preset = preset;
                break;
            }
        }

        const preset = found_preset orelse {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Preset not found\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };

        // Create provider from preset
        const now = time_compat.timestamp(self.io);
        const provider = Provider{
            .id = preset.id,
            .name = preset.name,
            .base_url = preset.base_url,
            .auth_type = if (std.mem.eql(u8, preset.auth_type, "bearer")) .bearer else .api_key,
            .api_key = null,
            .default_model = preset.default_models[0],
            .supports = preset.features,
            .is_official = true,
            .enabled = true,
            .sort_order = 0,
            .created_at = now,
            .updated_at = now,
            .metadata = null,
        };

        self.store.add(provider) catch {
            try request.respond(.{
                .status = .internal_server_error,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Failed to import preset\",\"type\":\"internal_error\"}}",
            });
            return;
        };

        const response = try provider.formatJson(self.allocator);
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .created,
            .content_type = .json,
            .body = "{\"imported\":true,\"provider\":" ++ response ++ "}",
        });
    }
};

// ==================== Request/Response Types ====================

pub const ProviderPreset = struct {
    id: []const u8,
    name: []const u8,
    provider_type: []const u8,
    base_url: []const u8,
    auth_type: []const u8,
    default_models: [][]const u8,
    features: [][]const u8,
    website: []const u8,
    description: []const u8,
};

pub const CreateProviderRequest = struct {
    id: []const u8,
    name: []const u8,
    base_url: []const u8,
    auth_type: []const u8,
    api_key: ?[]const u8,
    default_model: []const u8,
    supports: [][]const u8,
    is_official: bool,
    enabled: bool,
    sort_order: u32,
};

pub const UpdateProviderRequest = struct {
    name: ?[]const u8,
    base_url: ?[]const u8,
    auth_type: ?[]const u8,
    api_key: ?[]const u8,
    default_model: ?[]const u8,
    supports: ?[][]const u8,
    is_official: ?bool,
    enabled: ?bool,
    sort_order: ?u32,
    metadata: ?[]const u8,
};

pub const SortProvidersRequest = struct {
    ids: [][]const u8,
};
