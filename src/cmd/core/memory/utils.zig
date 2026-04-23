//! Memory utilities - hashing, project detection, tag extraction

const std = @import("std");

// Global Io instance set by cmd.zig dispatch.
pub var g_io: std.Io = undefined;

/// Compute SHA256 content hash for deduplication
pub fn computeContentHash(session_id: []const u8, summary: []const u8, commands: [][]const u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(session_id);
    hasher.update(summary);
    for (commands) |cmd| hasher.update(cmd);
    var result: [32]u8 = undefined;
    hasher.final(&result);
    return result;
}

/// Detect project identifier from git or cwd
pub fn detectProject(allocator: std.mem.Allocator) ![]const u8 {
    // Priority 1: Git repo root directory name
    const git_root = getGitRoot(allocator) catch null;
    if (git_root) |root| {
        defer allocator.free(root);
        const basename = std.fs.path.basename(root);
        if (basename.len > 0) {
            return try allocator.dupe(u8, basename);
        }
    }

    // Priority 2: Current working directory name
    const cwd = std.process.currentPathAlloc(g_io, allocator) catch {
        return try allocator.dupe(u8, "unknown");
    };
    defer allocator.free(cwd);
    const basename = std.fs.path.basename(cwd);
    return try allocator.dupe(u8, if (basename.len > 0) basename else "unknown");
}

fn getGitRoot(allocator: std.mem.Allocator) ![]const u8 {
    const result = std.process.run(allocator, g_io, .{
        .argv = &.{ "git", "rev-parse", "--show-toplevel" },
    }) catch return error.NoGit;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) return error.NoGit;

    const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
    return try allocator.dupe(u8, trimmed);
}

/// Extract tags from command and output
pub fn extractTags(allocator: std.mem.Allocator, command: []const u8, _: []const u8) ![][]const u8 {
    var tags = std.ArrayList([]const u8).empty;
    errdefer {
        for (tags.items) |t| allocator.free(t);
        tags.deinit(allocator);
    }

    // Extract base command as tag
    const base = extractBaseCommand(command);
    if (base.len > 0) {
        try tags.append(allocator, try allocator.dupe(u8, base));
    }

    // Extract file extensions from command args
    var iter = std.mem.tokenizeScalar(u8, command, ' ');
    while (iter.next()) |token| {
        if (std.mem.findScalar(u8, token, '.')) |dot| {
            const ext = token[dot + 1 ..];
            if (ext.len > 0 and ext.len < 10) {
                const ext_tag = try std.fmt.allocPrint(allocator, "ext:{s}", .{ext});
                try tags.append(allocator, ext_tag);
            }
        }
    }

    // Detect common patterns (skip if already added as base command)
    const patterns = [_]struct { needle: []const u8, tag: []const u8 }{
        .{ .needle = "test", .tag = "test" },
        .{ .needle = "build", .tag = "build" },
        .{ .needle = "deploy", .tag = "deploy" },
        .{ .needle = "docker", .tag = "docker" },
        .{ .needle = "git", .tag = "git" },
    };
    for (patterns) |p| {
        if (std.mem.find(u8, command, p.needle) != null) {
            // Check if already in tags
            var found = false;
            for (tags.items) |existing| {
                if (std.mem.eql(u8, existing, p.tag)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                try tags.append(allocator, try allocator.dupe(u8, p.tag));
            }
        }
    }

    return tags.toOwnedSlice(allocator);
}

/// Extract base command (first token)
fn extractBaseCommand(cmd: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, cmd, " \t\r\n");
    if (trimmed.len == 0) return trimmed;

    var i: usize = 0;
    while (i < trimmed.len and trimmed[i] != ' ') : (i += 1) {}
    return trimmed[0..i];
}

/// Generate a unique session ID
pub fn generateSessionId(allocator: std.mem.Allocator) ![]const u8 {
    const timestamp = @import("time_compat").timestamp(g_io);
    var rng_source = std.Random.IoSource{ .io = g_io };
    const random = rng_source.interface().int(u32);
    return try std.fmt.allocPrint(allocator, "session-{d}-{d}", .{ timestamp, random });
}
