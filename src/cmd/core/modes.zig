//! Mode system - work context for CLI memory recording
//!
//! Supports four work modes that affect which memory categories
//! are recorded and which are downgraded to "other":
//!   code    - Daily coding (default)
//!   infra   - Deploy/scale/monitor
//!   data    - ETL/schema/query work
//!   writing - Documentation/writing

const std = @import("std");

/// Category enum matching MemoryCategory in memory/types.zig.
/// Defined locally to avoid module circular dependencies.
pub const Category = enum {
    fix,
    feat,
    refactor,
    config,
    learn,
    mistake,
    pattern,
    decision,
    err,
    other,
};

pub const WorkMode = enum {
    code,
    infra,
    data,
    writing,

    pub fn fromString(s: []const u8) ?WorkMode {
        if (std.mem.eql(u8, s, "code")) return .code;
        if (std.mem.eql(u8, s, "infra")) return .infra;
        if (std.mem.eql(u8, s, "data")) return .data;
        if (std.mem.eql(u8, s, "writing")) return .writing;
        return null;
    }

    pub fn asString(self: WorkMode) []const u8 {
        return switch (self) {
            .code => "code",
            .infra => "infra",
            .data => "data",
            .writing => "writing",
        };
    }
};

pub const ModeConfig = struct {
    name: []const u8,
    description: []const u8,
    focus: []const Category,
    ignore: []const Category,
};

/// Get the default configuration for a work mode.
/// Focus categories are prioritized for display; ignored categories
/// are downgraded to `.other` during recording.
pub fn getDefaultConfig(mode: WorkMode) ModeConfig {
    return switch (mode) {
        .code => .{
            .name = "code",
            .description = "Daily coding - records fixes, features, mistakes, and patterns",
            .focus = &.{ .fix, .feat, .mistake, .pattern },
            .ignore = &.{},
        },
        .infra => .{
            .name = "infra",
            .description = "Infrastructure work - records config changes, decisions, and deployment patterns",
            .focus = &.{ .config, .decision, .pattern },
            .ignore = &.{ .feat, .refactor },
        },
        .data => .{
            .name = "data",
            .description = "Data work - records schema changes, queries, and learned patterns",
            .focus = &.{ .config, .pattern, .learn },
            .ignore = &.{ .feat, .refactor },
        },
        .writing => .{
            .name = "writing",
            .description = "Documentation and writing - records decisions and learned patterns",
            .focus = &.{ .decision, .learn, .other },
            .ignore = &.{ .err, .mistake },
        },
    };
}

/// Check if a category is ignored (downgraded to `other`) in the given mode.
pub fn isIgnored(mode: WorkMode, category: Category) bool {
    const cfg = getDefaultConfig(mode);
    for (cfg.ignore) |ignored| {
        if (ignored == category) return true;
    }
    return false;
}

/// Check if a category is in the focus list for the given mode.
pub fn isFocused(mode: WorkMode, category: Category) bool {
    const cfg = getDefaultConfig(mode);
    for (cfg.focus) |focused| {
        if (focused == category) return true;
    }
    return false;
}

/// Downgrade a category if it's ignored in the current mode.
/// Returns the original category if not ignored, otherwise `.other`.
pub fn filterCategory(mode: WorkMode, category: Category) Category {
    if (isIgnored(mode, category)) return .other;
    return category;
}

// ------------------------------------------------------------------
// Config file I/O (self-contained, no dependency on config.zig)
// ------------------------------------------------------------------

fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch return error.HomeNotFound;
    defer allocator.free(home_dir);
    return std.fmt.allocPrint(allocator, "{s}/.config/llmlite/config.toml", .{home_dir});
}

/// Read the current work mode from config.toml.
/// Defaults to `.code` if not configured or file missing.
pub fn getCurrentMode(allocator: std.mem.Allocator) !WorkMode {
    const path = getConfigPath(allocator) catch return .code;
    defer allocator.free(path);

    const file = std.fs.openFileAbsolute(path, .{}) catch return .code;
    defer file.close();

    const content = file.readToEndAlloc(allocator, 8192) catch return .code;
    defer allocator.free(content);

    return parseModeFromToml(content);
}

fn parseModeFromToml(content: []const u8) WorkMode {
    var lines = std.mem.splitScalar(u8, content, '\n');
    var in_memory_section = false;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (trimmed[0] == '[') {
            in_memory_section = std.mem.eql(u8, trimmed, "[memory]");
            continue;
        }

        if (in_memory_section) {
            if (std.mem.startsWith(u8, trimmed, "mode")) {
                const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
                var value = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
                // Remove quotes
                if (value.len >= 2 and ((value[0] == '"' and value[value.len - 1] == '"') or
                    (value[0] == '\'' and value[value.len - 1] == '\'')))
                {
                    value = value[1 .. value.len - 1];
                }
                if (WorkMode.fromString(value)) |m| return m;
            }
        }
    }

    return .code;
}

/// Write the work mode to config.toml.
/// If `[memory]` section exists, adds/updates `mode = "..."` within it.
/// If not, appends a `[memory]` section at the end of the file.
pub fn setCurrentMode(allocator: std.mem.Allocator, mode: WorkMode) !void {
    const path = try getConfigPath(allocator);
    defer allocator.free(path);

    // Try to read existing file
    var content_buf: ?[]const u8 = null;
    if (std.fs.openFileAbsolute(path, .{})) |file| {
        defer file.close();
        content_buf = file.readToEndAlloc(allocator, 8192) catch null;
    } else |_| {}
    defer if (content_buf) |c| allocator.free(c);

    const content = content_buf orelse "";
    const new_content = try updateModeInToml(allocator, content, mode);
    defer allocator.free(new_content);

    // Ensure directory exists
    const dir = std.fs.path.dirname(path) orelse return error.InvalidPath;
    std.fs.makeDirAbsolute(dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();
    try file.writeAll(new_content);
}

fn updateModeInToml(allocator: std.mem.Allocator, content: []const u8, mode: WorkMode) ![]const u8 {
    const mode_line = try std.fmt.allocPrint(allocator, "mode = \"{s}\"", .{mode.asString()});
    defer allocator.free(mode_line);

    // Check if [memory] section exists
    var has_memory_section = false;
    var has_mode_key = false;
    var mode_key_line_idx: ?usize = null;
    var memory_section_start: ?usize = null;
    var memory_section_end: ?usize = null;

    var line_iter = std.mem.splitScalar(u8, content, '\n');
    var line_idx: usize = 0;
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len > 0 and trimmed[0] == '[') {
            if (memory_section_start != null and memory_section_end == null) {
                // Found next section after [memory]
                memory_section_end = line_idx;
            }
            if (std.mem.eql(u8, trimmed, "[memory]")) {
                has_memory_section = true;
                memory_section_start = line_idx;
            }
        }
        if (has_memory_section and memory_section_end == null) {
            if (std.mem.startsWith(u8, trimmed, "mode")) {
                has_mode_key = true;
                mode_key_line_idx = line_idx;
            }
        }
        line_idx += 1;
    }

    if (!has_memory_section) {
        // Append [memory] section at the end
        const needs_newline = content.len > 0 and content[content.len - 1] != '\n';
        const prefix = if (needs_newline) "\n" else "";
        return std.fmt.allocPrint(allocator, "{s}{s}\n[memory]\n{s}\n", .{ content, prefix, mode_line });
    }

    if (has_mode_key and mode_key_line_idx != null) {
        // Replace the existing mode line
        var result = std.array_list.Managed(u8).init(allocator);
        defer result.deinit();

        var current_line: usize = 0;
        var rest_iter = std.mem.splitScalar(u8, content, '\n');
        while (rest_iter.next()) |line| {
            if (current_line == mode_key_line_idx.?) {
                try result.appendSlice(mode_line);
            } else {
                try result.appendSlice(line);
            }
            if (rest_iter.rest().len > 0 or (current_line + 1 < line_idx)) {
                try result.append('\n');
            }
            current_line += 1;
        }
        return result.toOwnedSlice();
    }

    // Insert mode line right after [memory] section header
    var result = std.array_list.Managed(u8).init(allocator);
    defer result.deinit();

    var current_line: usize = 0;
    var rest_iter = std.mem.splitScalar(u8, content, '\n');
    while (rest_iter.next()) |line| {
        try result.appendSlice(line);
        if (rest_iter.rest().len > 0 or (current_line + 1 < line_idx)) {
            try result.append('\n');
        }
        if (current_line == memory_section_start.?) {
            try result.appendSlice(mode_line);
            try result.append('\n');
        }
        current_line += 1;
    }
    return result.toOwnedSlice();
}

// ------------------------------------------------------------------
// Tests
// ------------------------------------------------------------------

test "WorkMode fromString/asString round-trip" {
    const modes = &[_]WorkMode{ .code, .infra, .data, .writing };
    for (modes) |mode| {
        const s = mode.asString();
        const parsed = WorkMode.fromString(s);
        try std.testing.expectEqual(mode, parsed.?);
    }
    try std.testing.expectEqual(null, WorkMode.fromString("unknown"));
}

test "code mode ignores nothing" {
    const all_categories = &[_]Category{
        .fix, .feat, .refactor, .config, .learn,
        .mistake, .pattern, .decision, .err, .other,
    };
    for (all_categories) |cat| {
        try std.testing.expect(!isIgnored(.code, cat));
    }
}

test "infra mode ignores feat and refactor" {
    try std.testing.expect(isIgnored(.infra, .feat));
    try std.testing.expect(isIgnored(.infra, .refactor));
    try std.testing.expect(!isIgnored(.infra, .config));
    try std.testing.expect(!isIgnored(.infra, .decision));
}

test "data mode ignores feat and refactor" {
    try std.testing.expect(isIgnored(.data, .feat));
    try std.testing.expect(isIgnored(.data, .refactor));
    try std.testing.expect(!isIgnored(.data, .config));
    try std.testing.expect(!isIgnored(.data, .learn));
}

test "writing mode ignores err and mistake" {
    try std.testing.expect(isIgnored(.writing, .err));
    try std.testing.expect(isIgnored(.writing, .mistake));
    try std.testing.expect(!isIgnored(.writing, .decision));
    try std.testing.expect(!isIgnored(.writing, .learn));
}

test "filterCategory downgrade" {
    try std.testing.expectEqual(Category.other, filterCategory(.infra, .feat));
    try std.testing.expectEqual(Category.config, filterCategory(.infra, .config));
    try std.testing.expectEqual(Category.fix, filterCategory(.code, .fix));
}

test "parseModeFromToml" {
    const toml1 =
        \\[tracking]
        \\ndatabase_path = "/tmp/db"
        \\
        \\[memory]
        \\mode = "infra"
        \\enabled = true
    ;
    try std.testing.expectEqual(WorkMode.infra, parseModeFromToml(toml1));

    const toml2 =
        \\[memory]
        \\enabled = true
    ;
    try std.testing.expectEqual(WorkMode.code, parseModeFromToml(toml2));

    const toml3 = "[other]\nkey = \"value\"";
    try std.testing.expectEqual(WorkMode.code, parseModeFromToml(toml3));
}

test "updateModeInToml add section" {
    const allocator = std.testing.allocator;
    const result = try updateModeInToml(allocator, "[tracking]\n", .infra);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "[memory]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "mode = \"infra\"") != null);
}

test "updateModeInToml replace existing" {
    const allocator = std.testing.allocator;
    const content = "[memory]\nmode = \"code\"\nenabled = true\n";
    const result = try updateModeInToml(allocator, content, .data);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "mode = \"data\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "enabled = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "mode = \"code\"") == null);
}

test "updateModeInToml insert into existing section" {
    const allocator = std.testing.allocator;
    const content = "[memory]\nenabled = true\n";
    const result = try updateModeInToml(allocator, content, .writing);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "mode = \"writing\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "enabled = true") != null);
}
