//! Config - TOML Configuration for llmlite-cmd
//!
//! Supports basic TOML config file at ~/.config/llmlite/config.toml
//! Inspired by RTK's config.toml

const std = @import("std");
const fs = std.fs;

pub const Config = struct {
    tracking: TrackingConfig = .{},
    hooks: HooksConfig = .{},
    tee: TeeConfig = .{},
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

fn parseConfig(allocator: std.mem.Allocator, content: []const u8) !Config {
    var config = Config{};
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
            }
        }
    }

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
    var values = std.ArrayList([]const u8).init(allocator);
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
    ;

    const file = try fs.createFileAbsolute(config_path, .{});
    defer file.close();
    try file.writeAll(default_config);

    std.debug.print("Created config: {s}\n", .{config_path});
}
