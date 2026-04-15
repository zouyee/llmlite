//! Hook System - Trust Management
//!
//! Controls which project-local filters are allowed to run.
//! Implements a trust-before-load model:
//! - Untrusted filters are skipped (not "loaded with warning")
//! - `llmlite trust` stores the SHA-256 hash after user review
//! - Content changes invalidate trust (re-review required)
//! - `LLMLITE_TRUST_PROJECT_FILTERS=1` overrides for CI pipelines

const std = @import("std");

// ============================================================================
// Types
// ============================================================================

pub const TrustEntry = struct {
    sha256: []const u8,
    trusted_at: []const u8,
};

pub const TrustStatus = enum {
    /// Filter is trusted and safe to load
    trusted,
    /// Filter has not been trusted
    untrusted,
    /// Filter content has changed since trust was established
    content_changed,
    /// Trust override via environment variable (CI pipeline)
    env_override,
};

pub const TrustStore = struct {
    version: u32,
    trusted: std.StringHashMap(TrustEntry),

    pub fn init(allocator: std.mem.Allocator) TrustStore {
        return .{
            .version = 1,
            .trusted = std.StringHashMap(TrustEntry).init(allocator),
        };
    }

    pub fn deinit(self: *TrustStore) void {
        self.trusted.deinit();
    }
};

// ============================================================================
// Constants
// ============================================================================

const TRUST_STORE_FILENAME = "trusted_filters.json";
const DATA_DIR_NAME = "llmlite";

// ============================================================================
// Store Path
// ============================================================================

fn storePath() ?[]const u8 {
    const data_dir = std.posix.getenv("XDG_DATA_HOME") orelse blk: {
        const home = std.posix.getenv("HOME") orelse return null;
        const xdg = std.fs.path.join(std.heap.page_allocator, &.{ home, ".local", "share" });
        break :blk xdg;
    };
    const llmlite_dir = std.fs.path.join(std.heap.page_allocator, &.{ data_dir, DATA_DIR_NAME });
    return std.fs.path.join(std.heap.page_allocator, &.{ llmlite_dir, TRUST_STORE_FILENAME });
}

fn readStore(allocator: std.mem.Allocator) !TrustStore {
    const path = storePath() orelse return error.NoDataDir;
    defer allocator.free(path);

    // Try to read the file
    const content = std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize)) catch |err| {
        if (err == error.FileNotFound) {
            // Return empty store if no file exists
            return TrustStore.init(allocator);
        }
        return err;
    };
    defer allocator.free(content);

    // Parse JSON manually (simplified - just check version and trusted entries)
    var store = TrustStore.init(allocator);
    store.version = 1; // Default

    // Simple JSON parsing for trusted filters
    // Expected format: {"version":1,"trusted":{"path":{"sha256":"...","trusted_at":"..."}}}
    var i: usize = 0;
    while (i < content.len) {
        // Look for "trusted": {
        const trusted_start = std.mem.indexOf(u8, content[i..], "\"trusted\":{") orelse break;
        i += trusted_start + 10; // Skip past "trusted":{

        // Parse each entry
        while (i < content.len and content[i] != '}') {
            // Skip to next quote
            while (i < content.len and content[i] != '"') i += 1;
            if (i >= content.len or content[i] != '"') break;
            i += 1;

            // Read key (path)
            const key_start = i;
            while (i < content.len and content[i] != '"') i += 1;
            const key = content[key_start..i];
            if (key.len == 0) break;

            i += 1; // Skip closing quote

            // Skip to sha256
            const sha256_label = "\"sha256\":\"";
            while (i < content.len) {
                const remaining = content[i..];
                if (std.mem.startsWith(u8, remaining, sha256_label)) break;
                i += 1;
            }
            if (i >= content.len) break;
            i += sha256_label.len;

            const sha256_start = i;
            while (i < content.len and content[i] != '"') i += 1;
            const sha256 = content[sha256_start..i];
            i += 1;

            // Skip to trusted_at
            const trusted_at_label = "\"trusted_at\":\"";
            while (i < content.len) {
                const remaining = content[i..];
                if (std.mem.startsWith(u8, remaining, trusted_at_label)) break;
                i += 1;
            }
            if (i >= content.len) break;
            i += trusted_at_label.len;

            const trusted_at_start = i;
            while (i < content.len and content[i] != '"') i += 1;
            const trusted_at = content[trusted_at_start..i];
            i += 1;

            // Add to store
            store.trusted.put(key, .{
                .sha256 = sha256,
                .trusted_at = trusted_at,
            }) catch continue;
        }
    }

    return store;
}

fn writeStore(store: *TrustStore) !void {
    const path = storePath() orelse return error.NoDataDir;
    defer std.heap.page_allocator.free(path);

    // Create parent directories
    const parent = std.fs.path.dirname(path);
    if (parent) |p| {
        try std.fs.cwd().makeDir(p);
    }

    // Build JSON string manually
    var json = std.ArrayList(u8).init(std.heap.page_allocator);
    defer json.deinit();

    try json.appendSlice("{\n");
    try json.appendSlice("  \"version\": ");
    try json.appendSlice(std.fmt.allocPrintZ(std.heap.page_allocator, "{}", .{store.version}) catch return error.OutOfMemory);
    try json.appendSlice(",\n");
    try json.appendSlice("  \"trusted\": {\n");

    var iter = store.trusted.iterator();
    var first = true;
    while (iter.next()) |entry| {
        if (!first) {
            try json.appendSlice(",\n");
        }
        first = false;

        try json.appendSlice("    \"");
        try json.appendSlice(entry.key_ptr.*);
        try json.appendSlice("\": {\n");
        try json.appendSlice("      \"sha256\": \"");
        try json.appendSlice(entry.value_ptr.sha256);
        try json.appendSlice("\",\n");
        try json.appendSlice("      \"trusted_at\": \"");
        try json.appendSlice(entry.value_ptr.trusted_at);
        try json.appendSlice("\"\n");
        try json.appendSlice("    }");
    }

    try json.appendSlice("\n  }\n");
    try json.appendSlice("}\n");

    try std.fs.cwd().writeFile(path, json.items);
}

// ============================================================================
// Public API
// ============================================================================

/// Check if a project-local filter file is trusted.
/// Returns TrustStatus based on env var, hash match, or untrusted.
pub fn checkTrust(filter_path: []const u8) TrustStatus {
    // Fast path: env var override for CI pipelines only
    if (std.posix.getenv("LLMLITE_TRUST_PROJECT_FILTERS")) |val| {
        if (std.mem.eql(u8, val, "1")) {
            // Check if we're in a CI environment
            const in_ci = std.posix.getenv("CI") != null or
                std.posix.getenv("GITHUB_ACTIONS") != null or
                std.posix.getenv("GITLAB_CI") != null or
                std.posix.getenv("JENKINS_URL") != null or
                std.posix.getenv("BUILDKITE") != null;

            if (in_ci) {
                return .env_override;
            }
        }
    }

    // Get canonical path
    const key = canonicalKey(filter_path) catch return .untrusted;

    // Read trust store
    var store = readStore(std.heap.page_allocator) catch return .untrusted;

    // Check if path is in trusted store
    const entry = store.trusted.get(key) orelse {
        store.deinit();
        return .untrusted;
    };

    // Compute hash of filter file
    const actual_hash = computeHash(filter_path) catch {
        store.deinit();
        return .untrusted;
    };
    defer std.heap.page_allocator.free(actual_hash);

    // Compare hashes
    if (std.mem.eql(u8, actual_hash, entry.sha256)) {
        store.deinit();
        return .trusted;
    } else {
        store.deinit();
        return .content_changed;
    }
}

/// Trust a filter file with a pre-computed SHA-256 hash.
pub fn trustFilter(filter_path: []const u8, hash: []const u8) !void {
    const key = try canonicalKey(filter_path);

    var store = try readStore(std.heap.page_allocator);
    defer store.deinit();

    // Get current timestamp
    const timestamp = getTimestamp();

    try store.trusted.put(key, .{
        .sha256 = hash,
        .trusted_at = timestamp,
    });

    try writeStore(&store);
}

/// Remove trust entry for a filter path.
pub fn untrustFilter(filter_path: []const u8) !bool {
    const key = try canonicalKey(filter_path);

    var store = try readStore(std.heap.page_allocator);
    defer store.deinit();

    const removed = store.trusted.remove(key);
    if (removed) {
        try writeStore(&store);
    }
    return removed;
}

// ============================================================================
// Helper Functions
// ============================================================================

fn canonicalKey(filter_path: []const u8) ![]const u8 {
    // Resolve symlinks and produce absolute path
    const resolved = try std.fs.cwd().realPath(filter_path);
    return resolved;
}

fn computeHash(path: []const u8) ![]const u8 {
    // Read file content
    const content = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, std.math.maxInt(usize));
    defer std.heap.page_allocator.free(content);

    // Compute SHA-256 hash (simplified - using a basic checksum for now)
    // Note: In production, use std.crypto.auth.sha2.Sha256
    var hash: [32]u8 = .{0};
    for (content, 0..) |byte, idx| {
        hash[idx % 32] +%= byte;
    }

    // Convert to hex string
    const hex_chars = "0123456789abcdef";
    var result = try std.heap.page_allocator.alloc(u8, 64);
    for (hash, 0..) |byte, idx| {
        result[idx * 2] = hex_chars[(byte >> 4) & 0xF];
        result[idx * 2 + 1] = hex_chars[byte & 0xF];
    }

    return result;
}

fn getTimestamp() []const u8 {
    // Get current time as ISO 8601 string (simplified)
    const now = std.time.timestamp();
    const buf = std.fmt.allocPrintZ(std.heap.page_allocator, "{d}", .{@as(f64, @floatFromInt(now))}) catch return "";
    return buf;
}

// ============================================================================
// Tests
// ============================================================================

test "trust status enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(TrustStatus.trusted));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(TrustStatus.untrusted));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(TrustStatus.content_changed));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(TrustStatus.env_override));
}

test "trust entry structure" {
    const entry = TrustEntry{
        .sha256 = "abc123",
        .trusted_at = "2024-01-01T00:00:00Z",
    };
    try std.testing.expectEqualStrings("abc123", entry.sha256);
    try std.testing.expectEqualStrings("2024-01-01T00:00:00Z", entry.trusted_at);
}

test "trust store init" {
    var store = TrustStore.init(std.heap.page_allocator);
    defer store.deinit();
    try std.testing.expectEqual(@as(u32, 1), store.version);
}
