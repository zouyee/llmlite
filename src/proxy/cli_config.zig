//! CLI Config Generator for llmlite Proxy
//!
//! Generates configuration files for various AI CLI tools:
//! - Claude Code (settings.json)
//! - Codex (config.json)
//! - Gemini CLI (config)
//! - OpenCode (config.yaml)
//! - OpenClaw (config.yaml)
//!
//! Supports atomic writes with backup for safe hot-switching.

const std = @import("std");
const preset = @import("proxy_preset");

pub const CliTool = preset.CliTool;
pub const ProviderPreset = preset.ProviderPreset;

/// Configuration file formats for different CLI tools
pub const CliConfigFormat = enum {
    claude_code_settings,
    claude_code_credentials,
    codex_config,
    gemini_cli_config,
    opencode_config,
    openclaw_config,
};

/// Target configuration with API key
pub const TargetConfig = struct {
    /// API key to use
    api_key: []const u8,
    /// Base URL for the API
    base_url: []const u8,
    /// Model to use
    model: []const u8,
    /// Optional additional config
    extra: ?std.StringArrayHashMap([]const u8) = null,
};

/// CLI Config Generator
pub const CliConfigGenerator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CliConfigGenerator {
        return .{ .allocator = allocator };
    }

    /// Generate configuration for Claude Code
    /// Claude Code uses ~/.claude/settings.json and ~/.claude/credentials.json
    pub fn generateClaudeCodeSettings(self: *CliConfigGenerator, config: *const TargetConfig) ![]u8 {
        var result = std.StringArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        try std.json.stringify(result.writer(), .{
            .analytics_enabled = false,
            .api_key = config.api_key,
            .base_url = config.base_url,
            .default_model = config.model,
            .extra = if (config.extra) |e| self.hashMapToObject(e) else null,
        }, .{ .whitespace = .indent_tab }) catch {
            // Fallback to manual JSON if std.json fails
            try result.appendSlice("{\n");
            try result.appendSlice("  \"analytics_enabled\": false,\n");
            try result.appendSlice("  \"api_key\": \"");
            try result.appendSlice(config.api_key);
            try result.appendSlice("\",\n");
            try result.appendSlice("  \"base_url\": \"");
            try result.appendSlice(config.base_url);
            try result.appendSlice("\",\n");
            try result.appendSlice("  \"default_model\": \"");
            try result.appendSlice(config.model);
            try result.appendSlice("\"\n");
            try result.appendSlice("}");
            return result.toOwnedSlice();
        };

        return result.toOwnedSlice();
    }

    pub fn generateClaudeCodeCredentials(self: *CliConfigGenerator, config: *const TargetConfig) ![]u8 {
        var result = std.StringArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        try std.json.stringify(result.writer(), .{
            .access_token = config.api_key,
            .refresh_token = "",
            .expires_at = null,
        }, .{ .whitespace = .indent_tab }) catch {
            try result.appendSlice("{\n");
            try result.appendSlice("  \"access_token\": \"");
            try result.appendSlice(config.api_key);
            try result.appendSlice("\",\n");
            try result.appendSlice("  \"refresh_token\": \"\",\n");
            try result.appendSlice("  \"expires_at\": null\n");
            try result.appendSlice("}");
            return result.toOwnedSlice();
        };

        return result.toOwnedSlice();
    }

    /// Generate configuration for OpenAI Codex
    /// Codex uses ~/.codex/config.json
    pub fn generateCodexConfig(self: *CliConfigGenerator, config: *const TargetConfig) ![]u8 {
        var result = std.StringArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        try result.appendSlice("{\n");
        try std.fmt.format(result.writer(), "  \"api_key\": \"{s}\",\n", .{config.api_key});
        try std.fmt.format(result.writer(), "  \"base_url\": \"{s}\",\n", .{config.base_url});
        try std.fmt.format(result.writer(), "  \"default_model\": \"{s}\",\n", .{config.model});
        try result.appendSlice("  \"timeout_ms\": 120000,\n");
        try result.appendSlice("  \"max_retries\": 3\n");
        try result.appendSlice("}");

        return result.toOwnedSlice();
    }

    /// Generate configuration for Google Gemini CLI
    /// Gemini CLI uses ~/.gemini/config.json
    pub fn generateGeminiCliConfig(self: *CliConfigGenerator, config: *const TargetConfig) ![]u8 {
        var result = std.StringArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        try result.appendSlice("{\n");
        try std.fmt.format(result.writer(), "  \"api_key\": \"{s}\",\n", .{config.api_key});
        try std.fmt.format(result.writer(), "  \"base_url\": \"{s}\",\n", .{config.base_url});
        try std.fmt.format(result.writer(), "  \"model\": \"{s}\",\n", .{config.model});
        try result.appendSlice("  \"location\": \"us-central1\",\n");
        try result.appendSlice("  \"project_id\": \"\"\n");
        try result.appendSlice("}");

        return result.toOwnedSlice();
    }

    /// Generate configuration for OpenCode
    /// OpenCode uses ~/.opencode/config.yaml
    pub fn generateOpenCodeConfig(self: *CliConfigGenerator, config: *const TargetConfig) ![]u8 {
        var result = std.StringArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        try result.appendSlice("version: \"1.0\"\n");
        try result.appendSlice("provider:\n");
        try std.fmt.format(result.writer(), "  api_key: {s}\n", .{config.api_key});
        try std.fmt.format(result.writer(), "  base_url: {s}\n", .{config.base_url});
        try result.appendSlice("model:\n");
        try std.fmt.format(result.writer(), "  default: {s}\n", .{config.model});
        try result.appendSlice("  temperature: 0.7\n");
        try result.appendSlice("  max_tokens: 4096\n");
        try result.appendSlice("proxy:\n");
        try result.appendSlice("  enabled: false\n");
        try result.appendSlice("  url: \"\"\n");
        try result.appendSlice("mcp:\n");
        try result.appendSlice("  enabled: true\n");
        try result.appendSlice("  servers: []\n");

        return result.toOwnedSlice();
    }

    /// Generate configuration for OpenClaw
    /// OpenClaw uses ~/.openclaw/config.yaml
    pub fn generateOpenClawConfig(self: *CliConfigGenerator, config: *const TargetConfig) ![]u8 {
        var result = std.StringArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        try result.appendSlice("version: \"1.0\"\n");
        try result.appendSlice("agent:\n");
        try result.appendSlice("  name: \"openclaw\"\n");
        try result.appendSlice("  model:\n");
        try std.fmt.format(result.writer(), "    provider: {s}\n", .{config.base_url});
        try std.fmt.format(result.writer(), "    name: {s}\n", .{config.model});
        try result.appendSlice("  auth:\n");
        try std.fmt.format(result.writer(), "    api_key: {s}\n", .{config.api_key});
        try result.appendSlice("soul:\n");
        try result.appendSlice("  enabled: true\n");
        try result.appendSlice("  file: ~/.openclaw/soul.md\n");
        try result.appendSlice("workspace:\n");
        try result.appendSlice("  auto_create: true\n");
        try result.appendSlice("mcp:\n");
        try result.appendSlice("  enabled: true\n");
        try result.appendSlice("  servers: []\n");
        try result.appendSlice("plugins:\n");
        try result.appendSlice("  enabled: true\n");

        return result.toOwnedSlice();
    }

    /// Generate configuration for a specific CLI tool
    pub fn generateForTool(
        self: *CliConfigGenerator,
        tool: CliTool,
        config: *const TargetConfig,
    ) ![]u8 {
        return switch (tool) {
            .claude_code => self.generateClaudeCodeSettings(config),
            .codex => self.generateCodexConfig(config),
            .gemini_cli => self.generateGeminiCliConfig(config),
            .opencode => self.generateOpenCodeConfig(config),
            .openclaw => self.generateOpenClawConfig(config),
        };
    }

    /// Get the config file path for a CLI tool
    pub fn getConfigPath(tool: CliTool) []const u8 {
        return switch (tool) {
            .claude_code => ".claude/settings.json",
            .codex => ".codex/config.json",
            .gemini_cli => ".gemini/config.json",
            .opencode => ".opencode/config.yaml",
            .openclaw => ".openclaw/config.yaml",
        };
    }

    /// Get the credentials file path (if separate from config)
    pub fn getCredentialsPath(tool: CliTool) ?[]const u8 {
        return switch (tool) {
            .claude_code => ".claude/credentials.json",
            else => null,
        };
    }

    /// Helper to convert StringHashMap to an object for JSON serialization
    fn hashMapToObject(_: *CliConfigGenerator, map: std.StringArrayHashMap([]const u8)) std.json.Value {
        // Note: In a full implementation, this would properly convert the map
        // For now, return an empty object since extra config is rarely used
        _ = map;
        const obj = std.json.Object.init(std.heap.page_allocator);
        return .{ .object = obj };
    }
};

/// Atomic config switcher with backup support
pub const AtomicConfigSwitcher = struct {
    allocator: std.mem.Allocator,
    generator: CliConfigGenerator,
    backup_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, backup_dir: []const u8) AtomicConfigSwitcher {
        return .{
            .allocator = allocator,
            .generator = CliConfigGenerator.init(allocator),
            .backup_dir = backup_dir,
        };
    }

    pub fn deinit(self: *AtomicConfigSwitcher) void {
        self.allocator.free(self.backup_dir);
    }

    /// Atomically switch configuration for a CLI tool
    /// Uses temp file + rename for atomicity
    pub fn switchConfig(
        self: *AtomicConfigSwitcher,
        tool: CliTool,
        config: *const TargetConfig,
    ) !void {
        const home_dir = std.os.getenv("HOME") orelse {
            return error.HomeDirectoryNotFound;
        };

        const config_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ home_dir, CliConfigGenerator.getConfigPath(tool) },
        );
        defer self.allocator.free(config_path);

        // Generate new config
        const new_config = try self.generator.generateForTool(tool, config);
        defer self.allocator.free(new_config);

        // Create backup if old file exists
        try self.createBackup(config_path);

        // Write to temp file first
        const temp_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}.tmp.{d}",
            .{ config_path, std.time.timestamp() },
        );
        defer self.allocator.free(temp_path);

        try self.writeFile(temp_path, new_config);

        // Atomic rename
        try std.fs.rename(self.allocator, temp_path, config_path);

        std.log.info("switched {s} config: {s}", .{ @tagName(tool), config_path });
    }

    /// Create a backup of the existing config
    fn createBackup(self: *AtomicConfigSwitcher, config_path: []const u8) !void {
        const file = std.fs.openFileAbsolute(config_path, .{}) catch return;
        defer file.close();

        // Create backup directory if needed
        const home_dir = std.os.getenv("HOME") orelse return error.HomeDirectoryNotFound;
        const backup_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}/{s}.{d}",
            .{ home_dir, self.backup_dir, "settings.json", std.time.timestamp() },
        );
        defer self.allocator.free(backup_path);

        // Create backup dir
        const backup_dir = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ home_dir, self.backup_dir },
        );
        defer self.allocator.free(backup_dir);

        try std.fs.makeDirAbsolute(backup_dir);

        // Read and write backup
        const content = try file.readToEndAlloc(self.allocator, 1_000_000);
        defer self.allocator.free(content);
        try self.writeFile(backup_path, content);
    }

    /// Write content to a file
    fn writeFile(_: *AtomicConfigSwitcher, path: []const u8, content: []const u8) !void {
        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();
        try file.writeAll(content);
    }

    /// Get current active configuration from a file
    pub fn getCurrentConfig(self: *AtomicConfigSwitcher, tool: CliTool) !?TargetConfig {
        const home_dir = std.process.getEnvVarOwned(self.allocator, "HOME") catch |err| {
            if (err == error.EnvironmentVariableNotFound) {
                return error.HomeDirectoryNotFound;
            }
            return err;
        };
        defer self.allocator.free(home_dir);

        const config_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ home_dir, CliConfigGenerator.getConfigPath(tool) },
        );
        defer self.allocator.free(config_path);

        const file = std.fs.openFileAbsolute(config_path, .{}) catch return null;
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1_000_000);
        defer self.allocator.free(content);

        // Parse based on tool
        return switch (tool) {
            .claude_code => try self.parseClaudeCodeConfig(content),
            .codex => try self.parseCodexConfig(content),
            .gemini_cli => try self.parseGeminiCliConfig(content),
            .opencode => try self.parseOpenCodeConfig(content),
            .openclaw => try self.parseOpenClawConfig(content),
        };
    }

    fn parseClaudeCodeConfig(self: *AtomicConfigSwitcher, content: []const u8) !TargetConfig {
        const parsed = std.json.parseFromSlice(
            struct {
                api_key: []const u8,
                base_url: []const u8,
                default_model: []const u8,
            },
            self.allocator,
            content,
            .{},
        ) catch {
            return error.InvalidConfig;
        };
        defer parsed.deinit();

        return TargetConfig{
            .api_key = parsed.value.api_key,
            .base_url = parsed.value.base_url,
            .model = parsed.value.default_model,
        };
    }

    fn parseCodexConfig(self: *AtomicConfigSwitcher, content: []const u8) !TargetConfig {
        const parsed = std.json.parseFromSlice(
            struct {
                api_key: []const u8,
                base_url: []const u8,
                default_model: []const u8,
            },
            self.allocator,
            content,
            .{},
        ) catch {
            return error.InvalidConfig;
        };
        defer parsed.deinit();

        return TargetConfig{
            .api_key = parsed.value.api_key,
            .base_url = parsed.value.base_url,
            .model = parsed.value.default_model,
        };
    }

    fn parseGeminiCliConfig(self: *AtomicConfigSwitcher, content: []const u8) !TargetConfig {
        const parsed = std.json.parseFromSlice(
            struct {
                api_key: []const u8,
                base_url: []const u8,
                model: []const u8,
            },
            self.allocator,
            content,
            .{},
        ) catch {
            return error.InvalidConfig;
        };
        defer parsed.deinit();

        return TargetConfig{
            .api_key = parsed.value.api_key,
            .base_url = parsed.value.base_url,
            .model = parsed.value.model,
        };
    }

    fn parseOpenCodeConfig(self: *AtomicConfigSwitcher, content: []const u8) !TargetConfig {
        // Simple YAML parsing for OpenCode config.yaml
        // Extracts: provider.api_key, provider.base_url, model.default
        _ = self; // self unused but signature required

        var api_key: []const u8 = "";
        var base_url: []const u8 = "";
        var model: []const u8 = "";

        var lines = std.mem.splitScalar(u8, content, '\n');
        var in_provider = false;
        var in_model = false;

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");

            if (std.mem.startsWith(u8, trimmed, "provider:")) {
                in_provider = true;
                in_model = false;
            } else if (std.mem.startsWith(u8, trimmed, "model:")) {
                in_provider = false;
                in_model = true;
            } else if (std.mem.startsWith(u8, trimmed, "api_key:")) {
                if (in_provider) {
                    api_key = try extractYamlValue(trimmed);
                }
            } else if (std.mem.startsWith(u8, trimmed, "base_url:")) {
                if (in_provider) {
                    base_url = try extractYamlValue(trimmed);
                }
            } else if (std.mem.startsWith(u8, trimmed, "default:")) {
                if (in_model) {
                    model = try extractYamlValue(trimmed);
                }
            }
        }

        if (api_key.len == 0) {
            return error.ParseError;
        }

        return TargetConfig{
            .api_key = api_key,
            .base_url = base_url,
            .model = model,
        };
    }

    fn parseOpenClawConfig(self: *AtomicConfigSwitcher, content: []const u8) !TargetConfig {
        // Simple YAML parsing for OpenClaw config.yaml
        // Extracts: agent.auth.api_key, agent.model.provider, agent.model.name
        _ = self; // self unused but signature required

        var api_key: []const u8 = "";
        var base_url: []const u8 = "";
        var model: []const u8 = "";

        var lines = std.mem.splitScalar(u8, content, '\n');
        var in_agent = false;
        var in_auth = false;
        var in_agent_model = false;

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");

            if (std.mem.startsWith(u8, trimmed, "agent:")) {
                in_agent = true;
                in_auth = false;
                in_agent_model = false;
            } else if (std.mem.startsWith(u8, trimmed, "auth:")) {
                in_auth = true;
                in_agent_model = false;
            } else if (std.mem.startsWith(u8, trimmed, "model:") and in_agent) {
                in_agent_model = true;
                in_auth = false;
            } else if (std.mem.startsWith(u8, trimmed, "api_key:")) {
                if (in_auth) {
                    api_key = try extractYamlValue(trimmed);
                }
            } else if (std.mem.startsWith(u8, trimmed, "provider:") and in_agent_model) {
                base_url = try extractYamlValue(trimmed);
            } else if (std.mem.startsWith(u8, trimmed, "name:") and in_agent_model) {
                model = try extractYamlValue(trimmed);
            }
        }

        if (api_key.len == 0) {
            return error.ParseError;
        }

        return TargetConfig{
            .api_key = api_key,
            .base_url = base_url,
            .model = model,
        };
    }

    /// Extract value from YAML line like "  key: value" or "key: value"
    fn extractYamlValue(line: []const u8) ![]const u8 {
        const colon_idx = std.mem.indexOfScalar(u8, line, ':') orelse return error.ParseError;
        var value = std.mem.trim(u8, line[colon_idx + 1 ..], " \t\"");
        // Remove trailing comment if present
        if (std.mem.indexOf(u8, value, " #")) |idx| {
            value = std.mem.trim(u8, value[0..idx], " \t");
        }
        return value;
    }
};
