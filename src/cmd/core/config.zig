//! Config - TOML Configuration for llmlite-cmd
//!
//! Supports basic TOML config file at ~/.config/llmlite/config.toml
//! Inspired by RTK's config.toml

const std = @import("std");
const fs = std.fs;
const modes = @import("modes");

pub const Config = struct {
    tracking: TrackingConfig = .{},
    hooks: HooksConfig = .{},
    tee: TeeConfig = .{},
    memory: MemoryConfig = .{},
    analytics: AnalyticsConfig = .{},
    analytics_proxy: AnalyticsProxyConfig = .{},
};

pub const AnalyticsConfig = struct {
    enabled: bool = true,
    retention_days: u32 = 90,
    sync_interval_secs: u32 = 300,
};

pub const AnalyticsProxyConfig = struct {
    host: []const u8 = "localhost",
    port: u16 = 4001,
};

pub const TrackingConfig = struct {
    database_path: ?[]const u8 = null,
};

pub const HooksConfig = struct {
    exclude_commands: []const []const u8 = &.{},
};

pub const TeeConfig = struct {
    enabled: bool = true,
    mode: enum { failures, always, never } = .failures,
    max_files: u32 = 20,
};

pub const MemoryConfig = struct {
    enabled: bool = true,
    auto_record: bool = true,
    max_context_length: u32 = 2000,
    dedup_window_secs: u32 = 30,
    mode: modes.WorkMode = .code,
    privacy: PrivacyConfig = .{},
};

pub const PrivacyConfig = struct {
    mode: enum { normal, private } = .normal,
    excluded_patterns: []const []const u8 = &.{},
};

pub fn loadConfig(allocator: std.mem.Allocator) !?Config {
    const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch return null;
    defer allocator.free(home_dir);

    const config_dir = try std.fmt.allocPrint(allocator, "{s}/.config/llmlite", .{home_dir});
    defer allocator.free(config_dir);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/config.toml", .{config_dir});
    defer allocator.free(config_path);

    const file = std.fs.openFileAbsolute(config_path, .{}) catch return null;
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 8192);
    defer allocator.free(content);

    return try parseConfig(allocator, content);
}

pub fn parseConfig(allocator: std.mem.Allocator, content: []const u8) !Config {
    var config = Config{
        .analytics_proxy = .{
            .host = try allocator.dupe(u8, "localhost"),
        },
    };
    var current_section: ?[]const u8 = null;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        // Skip empty lines and comments
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Check for section headers
        if (trimmed[0] == '[') {
            const end = std.mem.indexOfScalar(u8, trimmed, ']') orelse continue;
            current_section = trimmed[1..end];
            continue;
        }

        // Parse key = value
        if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_idx| {
            const key = std.mem.trim(u8, trimmed[0..eq_idx], " \t");
            const value = std.mem.trim(u8, trimmed[eq_idx + 1 ..], " \t");

            if (std.mem.eql(u8, current_section orelse "", "tracking")) {
                if (std.mem.eql(u8, key, "database_path")) {
                    config.tracking.database_path = try parseString(allocator, value);
                }
            } else if (std.mem.eql(u8, current_section orelse "", "hooks")) {
                if (std.mem.eql(u8, key, "exclude_commands")) {
                    config.hooks.exclude_commands = try parseStringArray(allocator, value);
                }
            } else if (std.mem.eql(u8, current_section orelse "", "tee")) {
                if (std.mem.eql(u8, key, "enabled")) {
                    config.tee.enabled = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "mode")) {
                    config.tee.mode = if (std.mem.eql(u8, value, "always"))
                        .always
                    else if (std.mem.eql(u8, value, "never"))
                        .never
                    else
                        .failures;
                } else if (std.mem.eql(u8, key, "max_files")) {
                    config.tee.max_files = std.fmt.parseInt(u32, value, 10) catch 20;
                }
            } else if (std.mem.eql(u8, current_section orelse "", "memory")) {
                if (std.mem.eql(u8, key, "enabled")) {
                    config.memory.enabled = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "auto_record")) {
                    config.memory.auto_record = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "max_context_length")) {
                    config.memory.max_context_length = std.fmt.parseInt(u32, value, 10) catch 2000;
                } else if (std.mem.eql(u8, key, "dedup_window_secs")) {
                    config.memory.dedup_window_secs = std.fmt.parseInt(u32, value, 10) catch 30;
                } else if (std.mem.eql(u8, key, "mode")) {
                    if (modes.WorkMode.fromString(value)) |m| {
                        config.memory.mode = m;
                    }
                }
            } else if (std.mem.eql(u8, current_section orelse "", "memory.privacy")) {
                if (std.mem.eql(u8, key, "mode")) {
                    config.memory.privacy.mode = if (std.mem.eql(u8, value, "private"))
                        .private
                    else
                        .normal;
                } else if (std.mem.eql(u8, key, "excluded_patterns")) {
                    config.memory.privacy.excluded_patterns = try parseStringArray(allocator, value);
                }
            } else if (std.mem.eql(u8, current_section orelse "", "analytics")) {
                if (std.mem.eql(u8, key, "enabled")) {
                    config.analytics.enabled = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "retention_days")) {
                    config.analytics.retention_days = std.fmt.parseInt(u32, value, 10) catch 90;
                } else if (std.mem.eql(u8, key, "sync_interval_secs")) {
                    config.analytics.sync_interval_secs = std.fmt.parseInt(u32, value, 10) catch 300;
                }
            } else if (std.mem.eql(u8, current_section orelse "", "analytics.proxy")) {
                if (std.mem.eql(u8, key, "host")) {
                    allocator.free(config.analytics_proxy.host);
                    config.analytics_proxy.host = try parseString(allocator, value);
                } else if (std.mem.eql(u8, key, "port")) {
                    config.analytics_proxy.port = std.fmt.parseInt(u16, value, 10) catch 4001;
                }
            }
        }
    }

    // Environment variable overrides
    if (std.process.getEnvVarOwned(allocator, "LLMLITE_PROXY_HOST")) |env_host| {
        allocator.free(config.analytics_proxy.host);
        config.analytics_proxy.host = env_host;
    } else |_| {}
    if (std.process.getEnvVarOwned(allocator, "LLMLITE_PROXY_PORT")) |env_port_str| {
        defer allocator.free(env_port_str);
        if (std.fmt.parseInt(u16, env_port_str, 10)) |env_port| {
            config.analytics_proxy.port = env_port;
        } else |_| {}
    } else |_| {}

    return config;
}

fn parseString(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    // Remove quotes if present
    if (value.len >= 2) {
        if ((value[0] == '"' and value[value.len - 1] == '"') or
            (value[0] == '\'' and value[value.len - 1] == '\''))
        {
            return allocator.dupe(u8, value[1 .. value.len - 1]);
        }
    }
    return allocator.dupe(u8, value);
}

fn parseStringArray(allocator: std.mem.Allocator, value: []const u8) ![]const []const u8 {
    // Parse comma-separated values like ["a", "b", "c"]
    var values = std.array_list.Managed([]const u8).init(allocator);
    defer values.deinit();

    // Skip brackets
    var content = value;
    if (content.len >= 2 and content[0] == '[') content = content[1..];
    if (content.len >= 1 and content[content.len - 1] == ']') content = content[0 .. content.len - 1];

    var items = std.mem.splitScalar(u8, content, ',');
    while (items.next()) |item| {
        const trimmed = std.mem.trim(u8, item, " \t");
        if (trimmed.len > 0) {
            try values.append(try parseString(allocator, trimmed));
        }
    }

    return try values.toOwnedSlice();
}

pub fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch return error.HomeNotFound;
    defer allocator.free(home_dir);
    return std.fmt.allocPrint(allocator, "{s}/.config/llmlite/config.toml", .{home_dir});
}

pub fn createDefaultConfig(allocator: std.mem.Allocator) !void {
    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);

    // Check if already exists
    if (fs.openFileAbsolute(config_path, .{ .mode = .read_only })) |_| {
        std.debug.print("Config already exists: {s}\n", .{config_path});
        return;
    } else |_| {}

    // Create directory if needed
    const dir = std.fs.path.dirname(config_path) orelse return error.InvalidPath;
    try fs.makeDirAbsolute(dir);

    const default_config =
        \\# llmlite-cmd Configuration
        \\#
        \\# See https://github.com/llmlite/llmlite/blob/main/docs/config.md
        \\
        \\[tracking]
        \\# Path to tracking database (default: ~/.local/share/llmlite/history.db)
        \\# database_path = "/custom/path/history.db"
        \\
        \\[display]
        \\# Enable colors in output (default: true)
        \\colors = true
        \\# Enable emoji in output (default: true)
        \\emoji = true
        \\# Maximum output width (default: 120)
        \\max_width = 120
        \\
        \\[tee]
        \\# Enable tee output (default: true)
        \\enabled = true
        \\# Tee mode: failures, always, never (default: failures)
        \\mode = "failures"
        \\# Maximum tee files (default: 20)
        \\max_files = 20
        \\
        \\[hooks]
        \\# Commands to exclude from auto-rewrite
        \\exclude_commands = ["curl", "playwright"]
        \\
        \\# [memory]
        \\# Enable memory recording (default: true)
        \\# enabled = true
        \\# Auto-record command executions (default: true)
        \\# auto_record = true
        \\# Maximum context length to store (default: 2000)
        \\# max_context_length = 2000
        \\# Deduplication window in seconds (default: 30)
        \\# dedup_window_secs = 30
        \\# Work mode: code, infra, data, writing (default: code)
        \\# mode = "code"
        \\
        \\# [memory.privacy]
        \\# Privacy mode: normal or private (default: normal)
        \\# In private mode, no commands are recorded
        \\# mode = "normal"
        \\# Glob patterns for commands to exclude from recording
        \\# excluded_patterns = ["*password*", "*secret*", "*token*"]
    ;

    const file = try fs.createFileAbsolute(config_path, .{});
    defer file.close();
    try file.writeAll(default_config);

    std.debug.print("Created config: {s}\n", .{config_path});
}
