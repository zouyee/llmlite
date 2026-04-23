//! MCP Server Manager for llmlite Proxy
//!
//! Manages MCP (Model Context Protocol) server lifecycle:
//! - Installation from GitHub repos or ZIP files
//! - Configuration management
//! - Process lifecycle (start/stop)
//! - Bidirectional sync across CLI tools
//!
//! MCP servers can be used by AI agents like Claude Code, Codex, and OpenClaw.

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
const preset = @import("proxy_preset");

pub const CliTool = preset.CliTool;

/// MCP server state
pub const McpServerState = enum {
    stopped,
    starting,
    running,
    stopping,
    error_state,
};

/// MCP server definition
pub const McpServer = struct {
    /// Unique name of the server
    name: []const u8,
    /// Command to execute (e.g., "npx", "python")
    command: []const u8,
    /// Arguments to pass
    args: [][]const u8,
    /// Environment variables
    env: StringArrayHashMap([]const u8),
    /// Config schema (JSON schema for server config)
    config_schema: ?[]const u8 = null,
    /// Current state
    state: McpServerState = .stopped,
    /// PID if running
    pid: ?u32 = null,
    /// Last error message
    last_error: ?[]const u8 = null,
    /// Enabled for which CLI tools
    enabled_for: []const CliTool = &.{},
    /// Auto-start on proxy startup
    auto_start: bool = false,
};

/// MCP server installation source
pub const McpServerSource = union(enum) {
    /// Install from a GitHub repository
    github: struct {
        repo: []const u8,
        branch: []const u8 = "main",
    },
    /// Install from a ZIP file URL
    zip_url: []const u8,
    /// Use a local installation
    local: []const u8,
    /// Built-in server
    builtin: void,
};

/// MCP server manager
pub const McpServerManager = struct {
    allocator: std.mem.Allocator,
    servers: StringArrayHashMap(McpServer),
    install_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator) McpServerManager {
        return .{
            .allocator = allocator,
            .servers = StringArrayHashMap(McpServer).init(allocator),
            .install_dir = undefined, // Will be set from home directory
        };
    }

    pub fn deinit(self: *McpServerManager) void {
        var it = self.servers.iterator();
        while (it.next()) |entry| {
            self.freeServer(entry.value_ptr);
        }
        self.servers.deinit();
        if (self.install_dir.len > 0) {
            self.allocator.free(self.install_dir);
        }
    }

    fn freeServer(self: *McpServerManager, server: *McpServer) void {
        self.allocator.free(server.name);
        self.allocator.free(server.command);
        for (server.args) |arg| self.allocator.free(arg);
        self.allocator.free(server.args);
        {
            var it = server.env.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            server.env.deinit();
        }
        if (server.config_schema) |cs| self.allocator.free(cs);
        for (server.enabled_for) |tool| self.allocator.free(self.cliToolToString(tool));
        self.allocator.free(server.enabled_for);
        if (server.last_error) |le| self.allocator.free(le);
    }

    fn cliToolToString(self: *McpServerManager, tool: CliTool) []const u8 {
        _ = self;
        return switch (tool) {
            .claude_code => "claude_code",
            .codex => "codex",
            .gemini_cli => "gemini_cli",
            .opencode => "opencode",
            .openclaw => "openclaw",
        };
    }

    /// Add a new MCP server
    pub fn addServer(self: *McpServerManager, server: McpServer) !void {
        const name = try self.allocator.dupe(u8, server.name);
        errdefer self.allocator.free(name);

        var server_copy = server;
        server_copy.name = name;
        server_copy.command = try self.allocator.dupe(u8, server.command);
        errdefer self.allocator.free(server_copy.command);

        {
            const args_copy = try self.allocator.alloc([]const u8, server.args.len);
            errdefer for (args_copy) |arg| self.allocator.free(arg);
            errdefer self.allocator.free(args_copy);
            for (server.args, 0..) |arg, i| {
                args_copy[i] = try self.allocator.dupe(u8, arg);
            }
            server_copy.args = args_copy;
        }

        server_copy.env = StringArrayHashMap([]const u8).init(self.allocator);
        {
            var it = server.env.iterator();
            while (it.next()) |entry| {
                try server_copy.env.put(
                    try self.allocator.dupe(u8, entry.key_ptr.*),
                    try self.allocator.dupe(u8, entry.value_ptr.*),
                );
            }
        }

        if (server.config_schema) |cs| {
            server_copy.config_schema = try self.allocator.dupe(u8, cs);
        }

        {
            const tools_copy = try self.allocator.alloc(CliTool, server.enabled_for.len);
            for (server.enabled_for, 0..) |tool, i| {
                tools_copy[i] = tool;
            }
            server_copy.enabled_for = tools_copy;
        }

        try self.servers.put(name, server_copy);
    }

    /// Remove an MCP server
    pub fn removeServer(self: *McpServerManager, name: []const u8) bool {
        if (self.servers.fetchRemove(name)) |entry| {
            self.freeServer(entry.value);
            return true;
        }
        return false;
    }

    /// Get a server by name
    pub fn getServer(self: *McpServerManager, name: []const u8) ?*McpServer {
        return self.servers.get(name);
    }

    /// List all servers
    pub fn listServers(self: *McpServerManager) []McpServer {
        return self.servers.values();
    }

    /// Start an MCP server
    pub fn startServer(self: *McpServerManager, name: []const u8) !void {
        const server = self.servers.get(name) orelse {
            return error.ServerNotFound;
        };

        if (server.state == .running) {
            return error.ServerAlreadyRunning;
        }

        // Build command as a slice
        const cmd_len = 1 + server.args.len;
        const cmd_slice = try self.allocator.alloc([]const u8, cmd_len);
        defer self.allocator.free(cmd_slice);
        cmd_slice[0] = server.command;
        for (server.args, 1..) |arg, i| {
            cmd_slice[i] = arg;
        }

        // Build environment
        var env_map = std.process.EnvMap.init(self.allocator);
        defer env_map.deinit();
        {
            var it = server.env.iterator();
            while (it.next()) |entry| {
                try env_map.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        // Spawn the process
        var child = std.process.Child.init(cmd_slice, self.allocator);
        child.env_map = &env_map;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        try child.spawn();

        // Update server state
        var server_mut = self.servers.get(name).?;
        server_mut.state = .running;
        server_mut.pid = @as(u32, @intCast(child.id));
        server_mut.last_error = null;

        std.log.info("started MCP server '{s}' with PID {d}", .{ name, child.id });
    }

    /// Stop an MCP server
    pub fn stopServer(self: *McpServerManager, name: []const u8) !void {
        const server = self.servers.get(name) orelse {
            return error.ServerNotFound;
        };

        if (server.state != .running) {
            return error.ServerNotRunning;
        }

        // Note: In Zig 0.15+, process killing requires the ChildProcess object.
        // For now, we just mark it as stopped. The process may still be running.
        std.log.warn("stopServer: process termination not fully implemented in Zig 0.15+", .{});

        // Update server state
        var server_mut = self.servers.get(name).?;
        server_mut.state = .stopped;
        server_mut.pid = null;

        std.log.info("stopped MCP server '{s}'", .{name});
    }

    /// Restart an MCP server
    pub fn restartServer(self: *McpServerManager, name: []const u8) !void {
        try self.stopServer(name);
        try self.startServer(name);
    }

    /// Enable a server for a specific CLI tool
    pub fn enableForTool(self: *McpServerManager, name: []const u8, tool: CliTool) !void {
        const server = self.servers.get(name) orelse {
            return error.ServerNotFound;
        };

        // Check if already enabled
        for (server.enabled_for) |t| {
            if (t == tool) return;
        }

        // Add to enabled list
        const new_list = try self.allocator.alloc(CliTool, server.enabled_for.len + 1);
        for (server.enabled_for, 0..) |t, i| {
            new_list[i] = t;
        }
        new_list[server.enabled_for.len] = tool;

        var server_mut = self.servers.get(name).?;
        server_mut.enabled_for = new_list;
    }

    /// Disable a server for a specific CLI tool
    pub fn disableForTool(self: *McpServerManager, name: []const u8, tool: CliTool) void {
        const server = self.servers.get(name) orelse return;

        // Find and remove
        var new_len: usize = 0;
        for (server.enabled_for) |t| {
            if (t != tool) new_len += 1;
        }

        if (new_len == server.enabled_for.len) return; // Not found

        var new_list = self.allocator.alloc(CliTool, new_len) catch return;
        var j: usize = 0;
        for (server.enabled_for) |t| {
            if (t != tool) {
                new_list[j] = t;
                j += 1;
            }
        }

        var server_mut = self.servers.get(name).?;
        server_mut.enabled_for = new_list;
    }

    /// Generate MCP configuration for a CLI tool
    pub fn generateConfigForTool(self: *McpServerManager, tool: CliTool) ![]u8 {
        var servers_config = std.array_list.Managed(u8).init(self.allocator);
        defer servers_config.deinit();

        var it = self.servers.iterator();
        var first = true;
        while (it.next()) |entry| {
            const server = entry.value_ptr;
            if (server.state != .running) continue;

            // Check if enabled for this tool
            var enabled = false;
            for (server.enabled_for) |t| {
                if (t == tool) {
                    enabled = true;
                    break;
                }
            }
            if (!enabled) continue;

            if (!first) try servers_config.appendSlice(",\n");
            first = false;

            try std.fmt.format(servers_config.writer(), "{{\"name\":\"{s}\",\"command\":\"{s}\",\"args\":[", .{
                server.name,
                server.command,
            });

            for (server.args, 0..) |arg, i| {
                if (i > 0) try servers_config.appendSlice(",");
                try std.fmt.format(servers_config.writer(), "\"{s}\"", .{arg});
            }

            try servers_config.appendSlice("]}");
        }

        return servers_config.toOwnedSlice();
    }

    /// Install server from GitHub repo
    pub fn installFromGitHub(self: *McpServerManager, name: []const u8, repo: []const u8) !void {
        // Clone the repository
        const install_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ self.install_dir, name },
        );
        defer self.allocator.free(install_path);

        // Use git to clone
        const args = &.{ "clone", "--depth", "1", repo, install_path };
        const result = std.process.Child.run(.{
            .argv = &.{ "git", args[0], args[1], args[2], args[3], args[4] },
        }) catch {
            return error.GitCloneFailed;
        };

        if (result.term != .Exited or result.term.Exited != 0) {
            return error.GitCloneFailed;
        }

        // Look for package.json or entry point
        const package_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/package.json",
            .{install_path},
        );
        defer self.allocator.free(package_path);

        const pkg_file = std.Io.Dir.openFileAbsolute(self.io, package_path, .{}) catch {
            // No package.json, look for other entry points
            return error.NoPackageJson;
        };
        defer pkg_file.close(self.io);

        // Read and parse package.json
        const content = try blk: { var __buf: [8192]u8 = undefined; var __reader = pkg_file.reader(self.io, &__buf); break :blk __reader.interface.allocRemaining(self.allocator, .limited(65536)); };
        defer self.allocator.free(content);

        const parsed = std.json.parseFromSlice(
            struct {
                name: []const u8,
                bin: ?struct {
                    name: []const u8,
                } = null,
            },
            self.allocator,
            content,
            .{},
        ) catch {
            return error.InvalidPackageJson;
        };
        defer parsed.deinit();

        // Create server definition
        const server = McpServer{
            .name = try self.allocator.dupe(u8, name),
            .command = "node",
            .args = &.{try std.fmt.allocPrint(self.allocator, "{s}/dist/index.js", .{install_path})},
            .env = StringArrayHashMap([]const u8).init(self.allocator),
        };

        try self.addServer(server);
    }

    /// Start all servers marked as auto_start
    pub fn startAutoStartServers(self: *McpServerManager) void {
        var it = self.servers.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.auto_start and entry.value_ptr.state == .stopped) {
                self.startServer(entry.key_ptr.*) catch {
                    std.log.warn("failed to auto-start MCP server '{s}'", .{entry.key_ptr.*});
                };
            }
        }
    }

    /// Stop all running servers
    pub fn stopAllServers(self: *McpServerManager) void {
        var it = self.servers.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.state == .running) {
                self.stopServer(entry.key_ptr.*) catch {
                    std.log.warn("failed to stop MCP server '{s}'", .{entry.key_ptr.*});
                };
            }
        }
    }

    /// Get server status
    pub fn getServerStatus(self: *McpServerManager, name: []const u8) ?struct {
        state: McpServerState,
        pid: ?u32,
        last_error: ?[]const u8,
    } {
        const server = self.servers.get(name) orelse return null;
        return .{
            .state = server.state,
            .pid = server.pid,
            .last_error = server.last_error,
        };
    }
};
