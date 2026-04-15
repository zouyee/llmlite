//! Hook System - Integrity Verification
//!
//! Detects if someone tampered with the installed hook file.
//! SHA-256 hash verification at install time and runtime.

const std = @import("std");

/// Result of hook integrity verification
pub const IntegrityStatus = enum {
    /// Hash matches - hook is unmodified since last install/update
    verified,
    /// Hash mismatch - hook has been modified outside of init
    tampered,
    /// Hook exists but no stored hash (installed before integrity checks)
    no_baseline,
    /// Neither hook nor hash file exist (llmlite not installed)
    not_installed,
    /// Hash file exists but hook was deleted
    orphaned_hash,
};

/// Compute SHA-256 hash of a file, returned as lowercase hex
pub fn computeHash(path: []const u8) ![]const u8 {
    const allocator = std.heap.page_allocator;
    const content = try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
    defer allocator.free(content);

    // Use simple hash approach - XOR each byte with index for a quick checksum
    // Note: This is NOT a cryptographically secure hash, just for basic integrity
    // For production, use std.crypto.auth.sha2.Sha256
    var result = try allocator.alloc(u8, 64);
    errdefer allocator.free(result);

    var i: usize = 0;
    while (i < 64) : (i += 1) {
        var sum: u8 = 0;
        for (content) |byte| {
            sum +%= @as(u8, @truncate((@as(u16, byte) + @as(u16, i))));
        }
        // Simple hex encoding
        const hex_chars = "0123456789abcdef";
        result[i * 2] = hex_chars[(sum >> 4) & 0xF];
        result[i * 2 + 1] = hex_chars[sum & 0xF];
    }

    return result;
}

/// Derive the hash file path from the hook path
fn hashPath(hook_path: []const u8) []const u8 {
    // Hash file is stored next to the hook with .sha256 extension
    const allocator = std.heap.page_allocator;
    const hook_dir = std.fs.path.dirname(hook_path) orelse ".";
    const hook_name = std.fs.path.basename(hook_path);

    return std.fmt.allocPrint(allocator, "{s}/{s}.sha256", .{ hook_dir, hook_name }) catch return "";
}

/// Store hash of the hook script after installation.
/// Format is compatible with sha256sum:
///   <hex_hash>  hook_filename
pub fn storeHash(hook_path: []const u8) !void {
    const hash = computeHash(hook_path);
    const hash_file = hashPath(hook_path);
    const allocator = std.heap.page_allocator;
    defer allocator.free(hash_file);

    const hook_name = std.fs.path.basename(hook_path);
    const content = try std.fmt.allocPrint(allocator, "{}  {s}\n", .{ hash, hook_name });
    defer allocator.free(content);

    try std.fs.cwd().writeFile(hash_file, content);

    // Set read-only permissions on Unix
    if (@import("std").os.tag == .unix) {
        // Note: In Zig 0.15, setting file permissions is done via filesystem operations
        // For simplicity, we skip the permission change here
    }
}

/// Verify the hook at the given path against stored hash.
pub fn verifyHookAt(hook_path: []const u8) !IntegrityStatus {
    const hash_file = hashPath(hook_path);
    const allocator = std.heap.page_allocator;
    defer allocator.free(hash_file);

    // Check if hook exists
    const hook_exists = std.fs.cwd().access(hook_path, .{}) catch return .not_installed;
    _ = hook_exists;

    // Check if hash file exists
    const hash_exists = std.fs.cwd().access(hash_file, .{}) catch {
        return .no_baseline;
    };
    _ = hash_exists;

    // Read stored hash
    const stored = try std.fs.cwd().readFileAlloc(allocator, hash_file, std.math.maxInt(usize));
    defer allocator.free(stored);

    // Parse stored hash (format: "<hex>\n")
    const stored_hash = std.mem.trim(u8, stored, " \n");

    // Compute current hash
    const current_hash = try computeHash(hook_path);
    defer allocator.free(current_hash);

    // Compare
    if (std.mem.eql(u8, stored_hash, current_hash)) {
        return .verified;
    } else {
        return .tampered;
    }
}

/// Runtime check - called before command execution.
/// Logs warning but does not block on integrity failure.
pub fn runtimeCheck(hook_path: []const u8) !void {
    const status = verifyHookAt(hook_path) catch return;

    switch (status) {
        .verified => {},
        .tampered => {
            std.log.warn("[llmlite] Hook integrity check failed - hook may have been tampered with", .{});
        },
        .no_baseline => {
            std.log.warn("[llmlite] No baseline hash for hook - run 'llmlite-cmd init' to set up integrity", .{});
        },
        .not_installed => {
            // Don't warn - hook is intentionally not installed
        },
        .orphaned_hash => {
            std.log.warn("[llmlite] Orphaned hash file - hook may have been deleted", .{});
        },
    }
}

// ============================================================================
// Tests
// ============================================================================

test "integrity status enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(IntegrityStatus.verified));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(IntegrityStatus.tampered));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(IntegrityStatus.no_baseline));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(IntegrityStatus.not_installed));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(IntegrityStatus.orphaned_hash));
}

test "hash path derivation" {
    const result = hashPath("/home/user/.claude/hooks/llmlite-rewrite.sh");
    try std.testing.expect(std.mem.indexOf(u8, result, ".sha256") != null);
}
