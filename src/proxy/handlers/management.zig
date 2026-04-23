//! Management API Handler for llmlite Proxy
//!
//! Handles all management API endpoints:
//! - /presets/* - Provider preset management
//! - /config/* - CLI config generation and switching
//! - /mcp/* - MCP server management
//! - /sync/* - Sync engine management
//! - /sessions/* - Session history management
//! - /backup/* - Backup management

const std = @import("std");

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
const preset = @import("../../proxy/preset");
const cli_config = @import("../../proxy/cli_config");
const mcp_manager = @import("../../proxy/mcp_manager");
const sync_engine = @import("../../proxy/sync_engine");
const session_store = @import("../../proxy/session_store");
const deep_link = @import("../../proxy/deep_link");
const backup = @import("../../proxy/backup");

pub const PresetStore = preset.PresetStore;
pub const CliTool = preset.CliTool;
pub const ProviderPreset = preset.ProviderPreset;
pub const McpServerManager = mcp_manager.McpServerManager;
pub const McpServer = mcp_manager.McpServer;
pub const McpServerState = mcp_manager.McpServerState;
pub const SyncEngine = sync_engine.SyncEngine;
pub const SessionStore = session_store.SessionStore;
pub const SessionSummary = session_store.SessionSummary;

/// Management handler combining all management APIs
pub const ManagementHandler = struct {
    allocator: std.mem.Allocator,
    preset_store: *PresetStore,
    cli_switcher: *cli_config.AtomicConfigSwitcher,
    mcp_manager: *McpServerManager,
    sync_engine: *SyncEngine,
    session_store: *SessionStore,
    backup_manager: ?*backup.BackupManager,

    pub fn init(
        allocator: std.mem.Allocator,
        preset_store: *PresetStore,
        cli_switcher: *cli_config.AtomicConfigSwitcher,
        mcp_mgr: *McpServerManager,
        sync_eng: *SyncEngine,
        sess_store: *SessionStore,
    ) ManagementHandler {
        return .{
            .allocator = allocator,
            .preset_store = preset_store,
            .cli_switcher = cli_switcher,
            .mcp_manager = mcp_mgr,
            .sync_engine = sync_eng,
            .session_store = sess_store,
            .backup_manager = null,
        };
    }

    /// Set the backup manager after initialization
    pub fn setBackupManager(self: *ManagementHandler, bm: *backup.BackupManager) void {
        self.backup_manager = bm;
    }

    /// Route request to appropriate handler
    pub fn handle(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const path = request.path();

        // Presets API
        if (std.mem.startsWith(u8, path, "GET /presets")) {
            try self.handleListPresets(request);
        } else if (std.mem.startsWith(u8, path, "GET /presets/")) {
            try self.handleGetPreset(request);
        } else if (std.mem.startsWith(u8, path, "POST /presets/import")) {
            try self.handleImportPreset(request);
        } else if (std.mem.startsWith(u8, path, "POST /presets/export")) {
            try self.handleExportPreset(request);

            // Config API
        } else if (std.mem.startsWith(u8, path, "GET /config/current")) {
            try self.handleGetCurrentConfig(request);
        } else if (std.mem.startsWith(u8, path, "POST /config/switch")) {
            try self.handleSwitchConfig(request);
        } else if (std.mem.startsWith(u8, path, "POST /config/generate")) {
            try self.handleGenerateConfig(request);

            // MCP API
        } else if (std.mem.startsWith(u8, path, "GET /mcp/servers")) {
            try self.handleListMcpServers(request);
        } else if (std.mem.startsWith(u8, path, "POST /mcp/servers")) {
            try self.handleAddMcpServer(request);
        } else if (std.mem.startsWith(u8, path, "DELETE /mcp/servers/")) {
            try self.handleDeleteMcpServer(request);
        } else if (std.mem.startsWith(u8, path, "POST /mcp/servers/")) {
            try self.handleMcpServerAction(request);
        } else if (std.mem.startsWith(u8, path, "GET /mcp/config/")) {
            try self.handleGetMcpConfig(request);

            // Sync API
        } else if (std.mem.startsWith(u8, path, "GET /sync/items")) {
            try self.handleListSyncItems(request);
        } else if (std.mem.startsWith(u8, path, "POST /sync/items")) {
            try self.handleAddSyncItem(request);
        } else if (std.mem.startsWith(u8, path, "DELETE /sync/items/")) {
            try self.handleDeleteSyncItem(request);
        } else if (std.mem.startsWith(u8, path, "POST /sync/items/")) {
            try self.handleSyncItem(request);
        } else if (std.mem.startsWith(u8, path, "POST /sync/skills")) {
            try self.handleSyncSkills(request);
        } else if (std.mem.startsWith(u8, path, "POST /sync/prompts")) {
            try self.handleSyncPrompts(request);

            // Sessions API
        } else if (std.mem.startsWith(u8, path, "GET /sessions")) {
            try self.handleListSessions(request);
        } else if (std.mem.startsWith(u8, path, "GET /sessions/")) {
            try self.handleGetSession(request);
        } else if (std.mem.startsWith(u8, path, "DELETE /sessions/")) {
            try self.handleDeleteSession(request);
        } else if (std.mem.startsWith(u8, path, "POST /sessions/search")) {
            try self.handleSearchSessions(request);

            // Backup API
        } else if (std.mem.startsWith(u8, path, "GET /backup/list")) {
            try self.handleListBackups(request);
        } else if (std.mem.startsWith(u8, path, "POST /backup/create")) {
            try self.handleCreateBackup(request);
        } else if (std.mem.startsWith(u8, path, "POST /backup/restore")) {
            try self.handleRestoreBackup(request);
        } else if (std.mem.startsWith(u8, path, "POST /backup/backup-all")) {
            try self.handleBackupAll(request);

            // Deep Link API
        } else if (std.mem.startsWith(u8, path, "POST /deeplink/parse")) {
            try self.handleDeepLinkParse(request);
        } else {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Not Found\",\"type\":\"invalid_request_error\"}}",
            });
        }
    }

    // ==================== Presets API ====================

    fn handleListPresets(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const presets = self.preset_store.listPresets();

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

    fn handleGetPreset(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        const preset_id = path[13..]; // Skip "/presets/"

        const p = self.preset_store.getPreset(preset_id) orelse {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Preset not found\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };

        const response = try std.json.Stringify.valueAlloc(self.allocator, p, .{});
        defer self.allocator.free(response);
        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    fn handleImportPreset(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const body = try request.reader().allocRemaining(self.allocator, .limited(1_000_000));
        defer self.allocator.free(body);

        const import_req = std.json.parseFromSlice(
            ImportPresetRequest,
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
        defer import_req.deinit();

        try self.preset_store.exportAsPreset(
            import_req.value.id,
            import_req.value.name,
            import_req.value.base_url,
            import_req.value.auth_type,
            import_req.value.default_model,
            import_req.value.supports,
        );

        try request.respond(.{
            .status = .created,
            .content_type = .json,
            .body = "{\"imported\":true,\"id\":\"" ++ import_req.value.id ++ "\"}",
        });
    }

    fn handleExportPreset(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const body = try request.reader().allocRemaining(self.allocator, .limited(1_000_000));
        defer self.allocator.free(body);

        const export_req = std.json.parseFromSlice(
            ExportPresetRequest,
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
        defer export_req.deinit();

        // Get current config for the tool
        const current = self.cli_switcher.getCurrentConfig(export_req.value.tool) catch null;

        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .preset = current,
        }, .{});

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    // ==================== Config API ====================

    fn handleGetCurrentConfig(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        // Extract tool from query params if present
        const tool_name = std.mem.trim(u8, path[17..], "/"); // Skip "/config/current"

        const tool: CliTool = std.meta.stringToEnum(CliTool, tool_name) orelse .claude_code;

        const config = self.cli_switcher.getCurrentConfig(tool) catch null;

        if (config) |c| {
            const response = try std.json.Stringify.valueAlloc(self.allocator, c, .{});
            try request.respond(.{
                .status = .ok,
                .content_type = .json,
                .body = response,
            });
        } else {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"No config found\",\"type\":\"invalid_request_error\"}}",
            });
        }
    }

    fn handleSwitchConfig(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const body = try request.reader().allocRemaining(self.allocator, .limited(1_000_000));
        defer self.allocator.free(body);

        const switch_req = std.json.parseFromSlice(
            SwitchConfigRequest,
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
        defer switch_req.deinit();

        const target_config = cli_config.TargetConfig{
            .api_key = switch_req.value.api_key,
            .base_url = switch_req.value.base_url,
            .model = switch_req.value.model,
        };

        self.cli_switcher.switchConfig(switch_req.value.tool, &target_config) catch |e| {
            try request.respond(.{
                .status = .internal_server_error,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Switch failed\",\"type\":\"internal_error\"}}",
            });
            return;
        };

        // Update preset store to mark this as active
        self.preset_store.setActivePreset(switch_req.value.tool, switch_req.value.preset_id);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = "{\"switched\":true}",
        });
    }

    fn handleGenerateConfig(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const body = try request.reader().allocRemaining(self.allocator, .limited(1_000_000));
        defer self.allocator.free(body);

        const gen_req = std.json.parseFromSlice(
            GenerateConfigRequest,
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
        defer gen_req.deinit();

        const target_config = cli_config.TargetConfig{
            .api_key = gen_req.value.api_key,
            .base_url = gen_req.value.base_url,
            .model = gen_req.value.model,
        };

        const config_content = self.cli_switcher.generator.generateForTool(
            gen_req.value.tool,
            &target_config,
        ) catch |e| {
            try request.respond(.{
                .status = .internal_server_error,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Generation failed\",\"type\":\"internal_error\"}}",
            });
            return;
        };
        defer self.allocator.free(config_content);

        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .tool = gen_req.value.tool,
            .content = config_content,
            .path = cli_config.CliConfigGenerator.getConfigPath(gen_req.value.tool),
        }, .{});

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    // ==================== MCP API ====================

    fn handleListMcpServers(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        _ = request;
        const servers = self.mcp_manager.listServers();

        const resp = try std.json.Stringify.valueAlloc(self.allocator, .{
            .object = "list",
            .data = servers,
        }, .{});
        defer self.allocator.free(resp);
        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = resp,
        });
    }

    fn handleAddMcpServer(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const body = try request.reader().allocRemaining(self.allocator, .limited(1_000_000));
        defer self.allocator.free(body);

        const add_req = std.json.parseFromSlice(
            AddMcpServerRequest,
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
        defer add_req.deinit();

        var server = McpServer{
            .name = add_req.value.name,
            .command = add_req.value.command,
            .args = add_req.value.args,
            .env = StringArrayHashMap([]const u8).init(self.allocator),
            .auto_start = add_req.value.auto_start,
        };

        self.mcp_manager.addServer(server) catch |e| {
            try request.respond(.{
                .status = .internal_server_error,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Add failed\",\"type\":\"internal_error\"}}",
            });
            return;
        };

        try request.respond(.{
            .status = .created,
            .content_type = .json,
            .body = "{\"added\":true,\"name\":\"" ++ add_req.value.name ++ "\"}",
        });
    }

    fn handleDeleteMcpServer(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        const name = path[18..]; // Skip "/mcp/servers/"

        if (self.mcp_manager.removeServer(name)) {
            try request.respond(.{
                .status = .ok,
                .content_type = .json,
                .body = "{\"deleted\":true}",
            });
        } else {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Server not found\",\"type\":\"invalid_request_error\"}}",
            });
        }
    }

    fn handleMcpServerAction(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        // Extract name and action: /mcp/servers/{name}/{action}
        const rest = path[17..]; // Skip "/mcp/servers/"
        const slash_idx = std.mem.find(u8, rest, "/") orelse {
            try request.respond(.{
                .status = .bad_request,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Invalid path\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };

        const name = rest[0..slash_idx];
        const action = rest[slash_idx + 1 ..];

        const result: []const u8 = if (std.mem.eql(u8, action, "start")) {
            self.mcp_manager.startServer(name) catch return error.InternalError;
            "{\"started\":true}";
        } else if (std.mem.eql(u8, action, "stop")) {
            self.mcp_manager.stopServer(name) catch return error.InternalError;
            "{\"stopped\":true}";
        } else if (std.mem.eql(u8, action, "restart")) {
            self.mcp_manager.restartServer(name) catch return error.InternalError;
            "{\"restarted\":true}";
        } else {
            try request.respond(.{
                .status = .bad_request,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Unknown action\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = result,
        });
    }

    fn handleGetMcpConfig(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        const rest = path[13..]; // Skip "/mcp/config/"
        const tool_name = std.mem.trim(u8, rest, "/");

        const tool: CliTool = std.meta.stringToEnum(CliTool, tool_name) orelse .claude_code;

        const config = self.mcp_manager.generateConfigForTool(tool) catch |e| {
            _ = e;
            try request.respond(.{
                .status = .internal_server_error,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Failed to generate config\",\"type\":\"internal_error\"}}",
            });
            return;
        };

        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .tool = tool_name,
            .servers = config,
        }, .{});

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    // ==================== Sync API ====================

    fn handleListSyncItems(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        _ = request;
        const items = self.sync_engine.listItems();

        const resp = try std.json.Stringify.valueAlloc(self.allocator, .{
            .object = "list",
            .data = items,
        }, .{});
        defer self.allocator.free(resp);
        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = resp,
        });
    }

    fn handleAddSyncItem(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const body = try request.reader().allocRemaining(self.allocator, .limited(1_000_000));
        defer self.allocator.free(body);

        // Simplified - just return not implemented for now
        _ = body;
        try request.respond(.{
            .status = .not_implemented,
            .content_type = .json,
            .body = "{\"error\":{\"message\":\"Not implemented\",\"type\":\"invalid_request_error\"}}",
        });
    }

    fn handleDeleteSyncItem(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        const id = path[17..]; // Skip "/sync/items/"

        if (self.sync_engine.removeItem(id)) {
            try request.respond(.{
                .status = .ok,
                .content_type = .json,
                .body = "{\"deleted\":true}",
            });
        } else {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Item not found\",\"type\":\"invalid_request_error\"}}",
            });
        }
    }

    fn handleSyncItem(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        const rest = path[16..]; // Skip "/sync/items/"
        const slash_idx = std.mem.find(u8, rest, "/") orelse {
            try request.respond(.{
                .status = .bad_request,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Invalid path\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };

        const id = rest[0..slash_idx];
        const action = rest[slash_idx + 1 ..];

        if (!std.mem.eql(u8, action, "sync")) {
            try request.respond(.{
                .status = .bad_request,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Unknown action\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        }

        const result = self.sync_engine.syncItem(id) catch |e| {
            _ = e;
            try request.respond(.{
                .status = .internal_server_error,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Sync failed\",\"type\":\"internal_error\"}}",
            });
            return;
        };

        const response = try std.json.Stringify.valueAlloc(self.allocator, result, .{});
        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    fn handleSyncSkills(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const body = try request.reader().allocRemaining(self.allocator, .limited(1_000_000));
        defer self.allocator.free(body);

        const sync_req = std.json.parseFromSlice(
            SyncSkillsRequest,
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
        defer sync_req.deinit();

        const home_dir = std.c.getenv("HOME") orelse {
            try request.respond(.{
                .status = .internal_server_error,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"HOME not set\",\"type\":\"internal_error\"}}",
            });
            return;
        };

        if (std.mem.eql(u8, @tagName(sync_req.value.direction), "export")) {
            self.sync_engine.exportSkills(sync_req.value.tool, sync_req.value.target_dir, std.mem.sliceTo(home_dir, 0)) catch |e| {
                _ = e;
                try request.respond(.{
                    .status = .internal_server_error,
                    .content_type = .json,
                    .body = "{\"error\":{\"message\":\"Export failed\",\"type\":\"internal_error\"}}",
                });
                return;
            };
        } else {
            self.sync_engine.importSkills(sync_req.value.tool, sync_req.value.source_dir, std.mem.sliceTo(home_dir, 0)) catch |e| {
                _ = e;
                try request.respond(.{
                    .status = .internal_server_error,
                    .content_type = .json,
                    .body = "{\"error\":{\"message\":\"Import failed\",\"type\":\"internal_error\"}}",
                });
                return;
            };
        }

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = "{\"synced\":true}",
        });
    }

    fn handleSyncPrompts(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        _ = request;
        // Similar to sync skills but for prompts
        try request.respond(.{
            .status = .not_implemented,
            .content_type = .json,
            .body = "{\"error\":{\"message\":\"Not implemented\",\"type\":\"invalid_request_error\"}}",
        });
    }

    // ==================== Sessions API ====================

    fn handleListSessions(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        const query_start = std.mem.find(u8, path, "?") orelse path.len;
        const tool_part = path[10..query_start]; // Skip "/sessions"
        const tool_name = std.mem.trim(u8, tool_part, "/");

        const tool: CliTool = std.meta.stringToEnum(CliTool, tool_name) orelse .claude_code;

        // Parse pagination params from query string
        var limit: u32 = 20;
        var offset: u32 = 0;
        if (query_start < path.len) {
            const query = path[query_start + 1 ..];
            // Simple query param parsing
            var it = std.mem.splitScalar(u8, query, '&');
            while (it.next()) |param| {
                if (std.mem.startsWith(u8, param, "limit=")) {
                    limit = std.fmt.parseInt(u32, param[6..], 10) catch 20;
                } else if (std.mem.startsWith(u8, param, "offset=")) {
                    offset = std.fmt.parseInt(u32, param[7..], 10) catch 0;
                }
            }
        }

        const sessions = try self.session_store.listSessions(tool, limit, offset);

        const resp = try std.json.Stringify.valueAlloc(self.allocator, .{
            .object = "list",
            .data = sessions,
            .tool = @tagName(tool),
        }, .{});
        defer self.allocator.free(resp);
        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = resp,
        });
    }

    fn handleGetSession(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        const id = path[11..]; // Skip "/sessions/"

        const session = self.session_store.getSession(id) orelse {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Session not found\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };

        const response = try std.json.Stringify.valueAlloc(self.allocator, session, .{});
        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    fn handleDeleteSession(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        const id = path[17..]; // Skip "/sessions/DELETE/"

        if (self.session_store.deleteSession(id)) {
            try request.respond(.{
                .status = .ok,
                .content_type = .json,
                .body = "{\"deleted\":true}",
            });
        } else {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Session not found\",\"type\":\"invalid_request_error\"}}",
            });
        }
    }

    fn handleSearchSessions(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        const body = try request.reader().allocRemaining(self.allocator, .limited(1_000_000));
        defer self.allocator.free(body);

        const search_req = std.json.parseFromSlice(
            SearchSessionsRequest,
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
        defer search_req.deinit();

        const results = try self.session_store.searchSessions(search_req.value.query, search_req.value.limit);

        const resp = try std.json.Stringify.valueAlloc(self.allocator, .{
            .object = "list",
            .data = results,
        }, .{});
        defer self.allocator.free(resp);
        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = resp,
        });
    }

    // ==================== Deep Link API ====================

    fn handleDeepLinkParse(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        _ = self;
        const body = try request.reader().allocRemaining(self.allocator, .limited(1_000_000));
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice(
            DeepLinkParseRequest,
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
        defer parsed.deinit();

        const action = deep_link.parseDeepLink(parsed.value.url) catch |e| {
            try request.respond(.{
                .status = .bad_request,
                .content_type = .json,
                .body = try std.fmt.allocPrint(self.allocator, "{\"error\":{{\"message\":\"Failed to parse deep link: {s}\",\"type\":\"invalid_request_error\"}}}", .{@errorName(e)}),
            });
            return;
        };

        const resp = try std.json.Stringify.valueAlloc(self.allocator, .{
            .action_type = action.action_type,
            .url = action.url,
            .tool = action.tool,
            .provider = action.provider,
        }, .{});
        defer self.allocator.free(resp);
        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = resp,
        });
    }

    // ==================== Backup API ====================

    fn handleListBackups(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        if (self.backup_manager) |bm| {
            const category = extractQueryParam(request, "category") orelse "all";

            if (std.mem.eql(u8, category, "all")) {
                // List all backup categories
                const categories = &[_][]const u8{ "providers", "mcp_servers", "sync_items", "config" };
                var all_backups = StringArrayHashMap([]const []const u8).init(self.allocator);
                defer {
                    var it = all_backups.iterator();
                    while (it.next()) |entry| {
                        self.allocator.free(entry.value_ptr.*);
                    }
                    all_backups.deinit();
                }

                for (categories) |cat| {
                    const backups = bm.listBackups(cat) catch continue;
                    defer {
                        for (backups) |b| self.allocator.free(b);
                        self.allocator.free(backups);
                    }
                    try all_backups.put(try self.allocator.dupe(u8, cat), backups);
                }

                const resp = try std.json.Stringify.valueAlloc(self.allocator, .{
                    .backups = all_backups,
                }, .{});
                defer self.allocator.free(resp);
                try request.respond(.{
                    .status = .ok,
                    .content_type = .json,
                    .body = resp,
                });
            } else {
                const backups = bm.listBackups(category) catch |e| {
                    try request.respond(.{
                        .status = .internal_server_error,
                        .content_type = .json,
                        .body = try std.fmt.allocPrint(self.allocator, "{{\"error\":{{\"message\":\"Failed to list backups: {s}\"}}}}", .{@errorName(e)}),
                    });
                    return;
                };
                defer {
                    for (backups) |b| self.allocator.free(b);
                    self.allocator.free(backups);
                }

                const resp = try std.json.Stringify.valueAlloc(self.allocator, .{
                    .category = category,
                    .backups = backups,
                }, .{});
                defer self.allocator.free(resp);
                try request.respond(.{
                    .status = .ok,
                    .content_type = .json,
                    .body = resp,
                });
            }
        } else {
            try request.respond(.{
                .status = .service_unavailable,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Backup manager not initialized\",\"type\":\"backup_error\"}}",
            });
        }
    }

    fn handleCreateBackup(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        if (self.backup_manager) |bm| {
            const body = try request.reader().allocRemaining(self.allocator, .limited(1_000_000));
            defer self.allocator.free(body);

            const parsed = std.json.parseFromSlice(
                CreateBackupRequest,
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
            defer parsed.deinit();

            const backup_path = bm.backupFile(parsed.value.source_path, parsed.value.category) catch |e| {
                try request.respond(.{
                    .status = .internal_server_error,
                    .content_type = .json,
                    .body = try std.fmt.allocPrint(self.allocator, "{{\"error\":{{\"message\":\"Failed to create backup: {s}\"}}}}", .{@errorName(e)}),
                });
                return;
            };

            try request.respond(.{
                .status = .ok,
                .content_type = .json,
                .body = try std.fmt.allocPrint(self.allocator, "{{\"backup_path\":\"{s}\"}}", .{backup_path}),
            });
        } else {
            try request.respond(.{
                .status = .service_unavailable,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Backup manager not initialized\",\"type\":\"backup_error\"}}",
            });
        }
    }

    fn handleRestoreBackup(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        if (self.backup_manager) |bm| {
            const body = try request.reader().allocRemaining(self.allocator, .limited(1_000_000));
            defer self.allocator.free(body);

            const parsed = std.json.parseFromSlice(
                RestoreBackupRequest,
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
            defer parsed.deinit();

            bm.restoreBackup(parsed.value.backup_path, parsed.value.target_path) catch |e| {
                try request.respond(.{
                    .status = .internal_server_error,
                    .content_type = .json,
                    .body = try std.fmt.allocPrint(self.allocator, "{{\"error\":{{\"message\":\"Failed to restore backup: {s}\"}}}}", .{@errorName(e)}),
                });
                return;
            };

            try request.respond(.{
                .status = .ok,
                .content_type = .json,
                .body = "{\"message\":\"Backup restored successfully\"}",
            });
        } else {
            try request.respond(.{
                .status = .service_unavailable,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Backup manager not initialized\",\"type\":\"backup_error\"}}",
            });
        }
    }

    fn handleBackupAll(self: *ManagementHandler, request: *std.http.Server.Request) !void {
        if (self.backup_manager) |bm| {
            const body = try request.reader().allocRemaining(self.allocator, .limited(1_000_000));
            defer self.allocator.free(body);

            const parsed = std.json.parseFromSlice(
                BackupAllRequest,
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
            defer parsed.deinit();

            bm.backupAll(parsed.value.base_path) catch |e| {
                try request.respond(.{
                    .status = .internal_server_error,
                    .content_type = .json,
                    .body = try std.fmt.allocPrint(self.allocator, "{{\"error\":{{\"message\":\"Failed to backup all: {s}\"}}}}", .{@errorName(e)}),
                });
                return;
            };

            try request.respond(.{
                .status = .ok,
                .content_type = .json,
                .body = "{\"message\":\"All backups created successfully\"}",
            });
        } else {
            try request.respond(.{
                .status = .service_unavailable,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Backup manager not initialized\",\"type\":\"backup_error\"}}",
            });
        }
    }

    /// Extract query parameter from request URI
    fn extractQueryParam(request: *std.http.Server.Request, param: []const u8) ?[]const u8 {
        const path = request.path();
        const question_idx = std.mem.findScalar(u8, path, '?');
        if (question_idx) |q| {
            const query = path[q + 1 ..];
            var iter = std.mem.splitScalar(u8, query, '&');
            while (iter.next()) |pair| {
                if (std.mem.startsWith(u8, pair, param)) {
                    const eq_idx = std.mem.findScalar(u8, pair, '=');
                    if (eq_idx) |eq| {
                        return pair[eq + 1 ..];
                    }
                }
            }
        }
        return null;
    }
};

// ==================== Request Types ====================

pub const ImportPresetRequest = struct {
    id: []const u8,
    name: []const u8,
    base_url: []const u8,
    auth_type: preset.AuthType,
    default_model: []const u8,
    supports: [][]const u8,
};

pub const ExportPresetRequest = struct {
    tool: CliTool,
};

pub const SwitchConfigRequest = struct {
    tool: CliTool,
    preset_id: ?[]const u8,
    api_key: []const u8,
    base_url: []const u8,
    model: []const u8,
};

pub const GenerateConfigRequest = struct {
    tool: CliTool,
    api_key: []const u8,
    base_url: []const u8,
    model: []const u8,
};

pub const AddMcpServerRequest = struct {
    name: []const u8,
    command: []const u8,
    args: [][]const u8,
    auto_start: bool = false,
};

pub const SyncSkillsRequest = struct {
    tool: CliTool,
    direction: enum { to_remote, to_local },
    target_dir: []const u8,
    source_dir: []const u8,
};

pub const SearchSessionsRequest = struct {
    query: []const u8,
    limit: u32 = 20,
};

pub const DeepLinkParseRequest = struct {
    url: []const u8,
};

pub const CreateBackupRequest = struct {
    source_path: []const u8,
    category: []const u8,
};

pub const RestoreBackupRequest = struct {
    backup_path: []const u8,
    target_path: []const u8,
};

pub const BackupAllRequest = struct {
    base_path: []const u8,
};
