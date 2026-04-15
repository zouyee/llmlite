//! Hook System - Hook Status Checking
//!
//! Detects whether llmlite hooks are installed and warns if they are outdated.

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

const CURRENT_HOOK_VERSION: u8 = 3;
const WARN_INTERVAL_SECS: u64 = 24 * 3600;

/// Hook status for diagnostics and `llmlite gain`.
pub const HookStatus = enum {
    /// Hook is installed and up to date.
    ok,
    /// Hook exists but is outdated or unreadable.
    outdated,
    /// No hook file found (but Claude Code is installed).
    missing,
};

// ============================================================================
// Public Functions
// ============================================================================

/// Return the current hook status without printing anything.
/// Returns `ok` if no Claude Code is detected (not applicable).
pub fn status() HookStatus {
    // Don't warn users who don't have Claude Code installed
    const home = std.posix.getenv("HOME") orelse return .ok;
    const claude_dir = std.fs.path.join(std.heap.page_allocator, &.{ home, ".claude" });
    defer std.heap.page_allocator.free(claude_dir);

    const claude_dir_path = std.fs.path.byteSliceOwned(claude_dir);
    if (!exists(claude_dir_path)) {
        return .ok;
    }

    const hook_path = hookInstalledPath() orelse return .missing;

    const content = readFileString(hook_path) catch return .outdated; // exists but unreadable
    if (parseHookVersion(content) >= CURRENT_HOOK_VERSION) {
        return .ok;
    } else {
        return .outdated;
    }
}

/// Check if the installed hook is missing or outdated, warn once per day.
pub fn maybeWarn() void {
    // Don't block startup — fail silently on any error
    checkAndWarn() catch return;
}

/// Parse the hook version from hook file content.
/// Returns the version number found, or 0 if no version tag is present.
pub fn parseHookVersion(content: []const u8) u8 {
    // Version tag must be in the first 5 lines (shebang + header convention)
    var lines: u8 = 0;
    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |line| {
        if (lines >= 5) break;
        lines += 1;

        const prefix = "# llmlite-hook-version:";
        if (std.mem.startsWith(u8, line, prefix)) {
            const rest = line[prefix.len..];
            const trimmed = std.mem.trim(u8, rest, " \t");
            // Parse integer from string
            var result: u8 = 0;
            for (trimmed) |c| {
                if (c < '0' or c > '9') break;
                result = result * 10 + (c - '0');
            }
            if (trimmed.len > 0) {
                return result;
            }
        }
    }
    return 0; // No version tag = version 0 (outdated)
}

// ============================================================================
// Private Functions
// ============================================================================

/// Single source of truth: delegates to `status()` then rate-limits the warning.
fn checkAndWarn() !void {
    const warning: []const u8 = switch (status()) {
        .ok => return,
        .missing => "[llmlite] /!\\ No hook installed — run `llmlite-cmd init -g` for automatic token savings",
        .outdated => "[llmlite] /!\\ Hook outdated — run `llmlite-cmd init -g` to update",
    };

    // Rate limit: warn once per day
    const marker = warnMarkerPath() orelse return;
    if (try fileExists(marker)) {
        const meta = std.fs.cwd().statFile(marker) catch return;
        const modified = meta.mtime();
        const now = std.time.timestamp();
        if (now - @as(i64, @intCast(modified)) < @as(i64, @intCast(WARN_INTERVAL_SECS))) {
            return;
        }
    }

    std.debug.print("{s}\n", .{warning});

    // Touch marker after warning is printed
    const marker_dir = std.fs.path.dirname(marker);
    if (marker_dir) |dir| {
        std.fs.cwd().makeDir(dir) catch {};
    }
    std.fs.cwd().writeFile(marker, "") catch return;
}

fn hookInstalledPath() ?[]const u8 {
    const home = std.posix.getenv("HOME") orelse return null;
    const path = std.fs.path.join(std.heap.page_allocator, &.{ home, ".claude", "hooks", "llmlite-rewrite.sh" });
    errdefer std.heap.page_allocator.free(path);

    if (exists(path)) {
        return path;
    }
    return null;
}

fn warnMarkerPath() ?[]const u8 {
    const data_dir = std.posix.getenv("XDG_DATA_HOME") orelse blk: {
        const home = std.posix.getenv("HOME") orelse return null;
        const xdg = std.fs.path.join(std.heap.page_allocator, &.{ home, ".local", "share" });
        errdefer std.heap.page_allocator.free(xdg);
        break :blk xdg;
    };
    const rtk_dir = std.fs.path.join(std.heap.page_allocator, &.{ data_dir, "llmlite" });
    errdefer std.heap.page_allocator.free(rtk_dir);
    return std.fs.path.join(std.heap.page_allocator, &.{ rtk_dir, ".hook_warn_last" });
}

// ============================================================================
// Helper Functions
// ============================================================================

fn exists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn readFileString(path: []const u8) ![]const u8 {
    return std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, std.math.maxInt(usize));
}

fn fileExists(path: []const u8) !bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

// ============================================================================
// Tests
// ============================================================================

test "parseHookVersion present" {
    const content = "#!/usr/bin/env bash\n# llmlite-hook-version: 2\n# some comment\n";
    try std.testing.expectEqual(@as(u8, 2), parseHookVersion(content));
}

test "parseHookVersion missing" {
    const content = "#!/usr/bin/env bash\n# old hook without version\n";
    try std.testing.expectEqual(@as(u8, 0), parseHookVersion(content));
}

test "parseHookVersion future" {
    const content = "#!/usr/bin/env bash\n# llmlite-hook-version: 5\n";
    try std.testing.expectEqual(@as(u8, 5), parseHookVersion(content));
}

test "parseHookVersion no tag" {
    try std.testing.expectEqual(@as(u8, 0), parseHookVersion("no version here"));
    try std.testing.expectEqual(@as(u8, 0), parseHookVersion(""));
}

test "hookStatus enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(HookStatus.ok));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(HookStatus.outdated));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(HookStatus.missing));
}

test "hookStatus enum equality" {
    try std.testing.expectEqual(HookStatus.ok, HookStatus.ok);
    try std.testing.expectEqual(HookStatus.missing, HookStatus.missing);
    try std.testing.expectEqual(HookStatus.outdated, HookStatus.outdated);
    try std.testing.expect(HookStatus.ok != HookStatus.missing);
}

test "CURRENT_HOOK_VERSION is 3" {
    try std.testing.expectEqual(@as(u8, 3), CURRENT_HOOK_VERSION);
}

test "WARN_INTERVAL_SECS is 24 hours" {
    try std.testing.expectEqual(@as(u64, 86400), WARN_INTERVAL_SECS);
}
