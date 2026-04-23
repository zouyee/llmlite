//! Integrity Verification - SHA-256 based hook integrity checking
//!
//! Prevents unauthorized hook modifications:
//! - At install: stores SHA-256 hash of hook file
//! - At runtime: verifies hash before allowing hook execution
//! - On demand: 'llmlite verify' command shows verification status

const std = @import("std");

// Global Io instance set by cmd.zig dispatch.
pub var g_io: std.Io = undefined;

// Zig 0.16.0 compat: replacement for removed _getEnvVarOwned
fn _getEnvVarOwned(allocator: std.mem.Allocator, key: [*:0]const u8) error{EnvironmentVariableNotFound, OutOfMemory}![]u8 {
    const ptr = std.c.getenv(key) orelse return error.EnvironmentVariableNotFound;
    const slice = std.mem.sliceTo(ptr, 0);
    return allocator.dupe(u8, slice);
}
const fs = std.fs;

fn fileExists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.accessAbsolute(io, path, .{}) catch return false;
    return true;
}

pub const IntegrityStatus = enum {
    verified,
    tampered,
    no_baseline,
    not_installed,
    orphaned_hash,
};

pub const IntegrityResult = struct {
    status: IntegrityStatus,
    expected_hash: ?[]const u8,
    actual_hash: ?[]const u8,
    hook_path: []const u8,
};

pub fn verifyHook(io: std.Io, allocator: std.mem.Allocator, tool: []const u8) !IntegrityResult {
    const hook_path = try getHookPath(allocator, tool);
    defer allocator.free(hook_path);

    const hash_path = try getHashPath(allocator, tool);
    defer allocator.free(hash_path);

    // Check if hook exists
    const hook_exists = fileExists(io, hook_path);
    const hash_exists = fileExists(io, hash_path);

    if (!hook_exists and !hash_exists) {
        return IntegrityResult{
            .status = .not_installed,
            .expected_hash = null,
            .actual_hash = null,
            .hook_path = hook_path,
        };
    }

    if (!hook_exists and hash_exists) {
        return IntegrityResult{
            .status = .orphaned_hash,
            .expected_hash = try readHashFile(g_io, allocator, hash_path),
            .actual_hash = null,
            .hook_path = hook_path,
        };
    }

    // Hook exists, compute hash
    const actual_hash = try computeFileHash(io, allocator, hook_path);
    errdefer allocator.free(actual_hash);

    if (!hash_exists) {
        return IntegrityResult{
            .status = .no_baseline,
            .expected_hash = null,
            .actual_hash = actual_hash,
            .hook_path = hook_path,
        };
    }

    const expected_hash = try readHashFile(io, allocator, hash_path);
    errdefer allocator.free(expected_hash);

    const is_match = std.mem.eql(u8, expected_hash, actual_hash);

    return IntegrityResult{
        .status = if (is_match) .verified else .tampered,
        .expected_hash = expected_hash,
        .actual_hash = actual_hash,
        .hook_path = hook_path,
    };
}

pub fn storeHookHash(io: std.Io, allocator: std.mem.Allocator, tool: []const u8) !void {
    const hook_path = try getHookPath(allocator, tool);
    defer allocator.free(hook_path);

    const hash_path = try getHashPath(allocator, tool);
    defer allocator.free(hash_path);

    // Compute hash
    const hash = try computeFileHash(io, allocator, hook_path);
    errdefer allocator.free(hash);

    // Create hash file (read-only for security)
    const hash_dir = std.fs.path.dirname(hash_path) orelse return error.InvalidPath;
    try std.Io.Dir.createDirAbsolute(io, hash_dir, .{});

    const file = try std.Io.Dir.createFileAbsolute(io, hash_path, .{});
    defer file.close(io);

    try file.writeStreamingAll(g_io, io, hash);
    // Note: In production, set permissions to 0o444 (read-only)
}

pub fn showVerificationStatus(io: std.Io, allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== llmlite Hook Integrity Verification ===\n\n", .{});

    const tools = &[_][]const u8{
        "claude_code",
        "cursor",
        "gemini",
        "opencode",
        "windsurf",
        "cline",
        "codex",
        "zsh",
        "fish",
    };

    var all_verified = true;

    for (tools) |tool| {
        const result = verifyHook(io, allocator, tool) catch continue;

        const status_str = switch (result.status) {
            .verified => "✓ VERIFIED",
            .tampered => "✗ TAMPERED",
            .no_baseline => "⚠ NO BASELINE",
            .not_installed => "○ NOT INSTALLED",
            .orphaned_hash => "⚠ ORPHANED HASH",
        };

        std.debug.print("{s}: {s}\n", .{ tool, status_str });

        if (result.status != .verified and result.status != .not_installed) {
            all_verified = false;
        }

        if (result.actual_hash) |h| {
            std.debug.print("  Hash: {s}\n", .{h});
        }
    }

    std.debug.print("\n", .{});

    if (all_verified) {
        std.debug.print("All installed hooks are verified.\n", .{});
    } else {
        std.debug.print("Warning: Some hooks may be modified. Run 'llmlite hook install' to reinstall.\n", .{});
    }
}

fn getHookPath(allocator: std.mem.Allocator, tool: []const u8) ![]u8 {
    const home = _getEnvVarOwned(allocator, "HOME") catch return error.HomeNotFound;
    defer allocator.free(home);

    if (std.mem.eql(u8, tool, "claude_code")) {
        return std.fmt.allocPrint(allocator, "{s}/.claude/hooks/llmlite-rewrite.bash", .{home});
    } else if (std.mem.eql(u8, tool, "cursor")) {
        return std.fmt.allocPrint(allocator, "{s}/.cursor/hooks/llmlite-rewrite.bash", .{home});
    } else if (std.mem.eql(u8, tool, "gemini")) {
        return std.fmt.allocPrint(allocator, "{s}/.gemini/hooks/llmlite-hook-gemini.bash", .{home});
    } else if (std.mem.eql(u8, tool, "opencode")) {
        return std.fmt.allocPrint(allocator, "{s}/.config/opencode/plugins/llmlite-plugin.ts", .{home});
    } else if (std.mem.eql(u8, tool, "windsurf")) {
        return std.fmt.allocPrint(allocator, "{s}/.windsurfrules", .{home});
    } else if (std.mem.eql(u8, tool, "cline")) {
        return std.fmt.allocPrint(allocator, "{s}/.clinerules", .{home});
    } else if (std.mem.eql(u8, tool, "codex")) {
        return std.fmt.allocPrint(allocator, "{s}/.codexrules", .{home});
    } else if (std.mem.eql(u8, tool, "zsh")) {
        return std.fmt.allocPrint(allocator, "{s}/.zshrc.d/llmlite-hook.zsh", .{home});
    } else if (std.mem.eql(u8, tool, "fish")) {
        return std.fmt.allocPrint(allocator, "{s}/.config/fish/functions/llmlite-hook.fish", .{home});
    }

    return error.UnknownTool;
}

fn getHashPath(allocator: std.mem.Allocator, tool: []const u8) ![]u8 {
    const home = _getEnvVarOwned(allocator, "HOME") catch return error.HomeNotFound;
    defer allocator.free(home);

    return std.fmt.allocPrint(allocator, "{s}/.local/share/llmlite/hooks/{s}.sha256", .{ home, tool });
}

fn computeFileHash(io: std.Io, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.Io.Dir.openFileAbsolute(io, path, .{});
    defer file.close(io);

    const Sha256 = std.crypto.hash.sha2.Sha256;
    var hasher = Sha256.init(.{});
    const buffer_size = 8192;
    var buffer: [buffer_size]u8 = undefined;

    while (true) {
        const bytes_read = try file.readPositional(g_io, &.{&buffer}, 0);
        if (bytes_read == 0) break;
        hasher.update(buffer[0..bytes_read]);
    }

    var hash: [Sha256.digest_length]u8 = undefined;
    hasher.final(&hash);
    const hex = std.fmt.bytesToHex(&hash, .lower);
    return std.fmt.allocPrint(allocator, "{s}", .{hex});
}

fn readHashFile(io: std.Io, _allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    _ = _allocator; // Not needed for simple file read
    const file = try std.Io.Dir.openFileAbsolute(io, path, .{});
    defer file.close(io);

    var content: [64]u8 = undefined;
    const bytes_read = try file.readPositionalAll(g_io, &content, 0);
    const trimmed = std.mem.trim(u8, content[0..bytes_read], " \n\r");
    return @constCast(trimmed);
}
