//! Trust System - TOML Filter Trust Verification
//!
//! Controls which project-local TOML filters are allowed to run.
//! Similar to RTK's trust.rs for project-local filters.
//!
//! `.llmlite/filters.toml` is loaded from CWD with highest priority.
//! An attacker can commit this file to a public repo to control what
//! an LLM sees - hiding malicious code, suppressing scanner output,
//! or rewriting command output entirely.
//!
//! This module implements a trust-before-load model:
//! - Untrusted filters are SKIPPED (not "loaded with warning")
//! - `llmlite trust` stores the SHA-256 hash after user review
//! - Content changes invalidate trust (re-review required)

const std = @import("std");
const time_compat = @import("time_compat");

// Global Io instance set by cmd.zig dispatch.
pub var g_io: std.Io = undefined;

// Zig 0.16.0 compat: replacement for removed _getEnvVarOwned
fn _getEnvVarOwned(allocator: std.mem.Allocator, key: [*:0]const u8) error{EnvironmentVariableNotFound, OutOfMemory}![]u8 {
    const ptr = std.c.getenv(key) orelse return error.EnvironmentVariableNotFound;
    const slice = std.mem.sliceTo(ptr, 0);
    return allocator.dupe(u8, slice);
}
const fs = std.fs;

pub const TrustStatus = enum {
    trusted,
    untrusted,
    content_changed,
    env_override,
};

pub const TrustEntry = struct {
    sha256: []const u8,
    trusted_at: i64,
};

pub const TrustStore = struct {
    version: u32 = 1,
    trusted: std.StringHashMap(TrustEntry),
};

var global_store: ?*TrustStore = null;

/// Get the trust store path
fn getStorePath(allocator: std.mem.Allocator) ![]const u8 {
    const home_dir = _getEnvVarOwned(allocator, "HOME") catch {
        return error.HomeNotFound;
    };
    defer allocator.free(home_dir);

    const data_dir = try std.fmt.allocPrint(allocator, "{s}/.local/share/llmlite", .{home_dir});
    defer allocator.free(data_dir);

    return std.fmt.allocPrint(allocator, "{s}/trusted_filters.json", .{data_dir});
}

/// Load the trust store from disk
pub fn loadStore(allocator: std.mem.Allocator) !TrustStore {
    const store_path = try getStorePath(allocator);
    defer allocator.free(store_path);

    const file = std.Io.Dir.openFileAbsolute(g_io, store_path, .{}) catch {
        return TrustStore{ .trusted = std.StringHashMap(TrustEntry).init(allocator) };
    };
    defer file.close(g_io);

    var reader_buf: [8192]u8 = undefined;
    var file_reader = file.reader(g_io, &reader_buf);
    const content = try file_reader.interface.allocRemaining(allocator, .limited(8192));
    defer allocator.free(content);

    // Simple JSON parsing - just look for the sha256 values
    var store = TrustStore{ .trusted = std.StringHashMap(TrustEntry).init(allocator) };

    // Parse JSON manually (simple approach)
    var i: usize = 0;
    while (i < content.len) : (i += 1) {
        if (std.mem.startsWith(u8, content[i..], "\"sha256\":")) {
            i += 9; // Skip "\"sha256\":"
            while (i < content.len and (content[i] == ' ' or content[i] == '"')) : (i += 1) {}

            // Extract sha256 value
            const start = i;
            while (i < content.len and content[i] != '"') : (i += 1) {}
            const sha256_value = content[start..i];

            // Find the path key
            var j = i;
            while (j > 0 and !std.mem.startsWith(u8, content[0..j], "\"path\":")) : (j -= 1) {}
            if (j > 0) {
                j += 8; // Skip "\"path\":"
                while (j < content.len and (content[j] == ' ' or content[j] == '"')) : (j += 1) {}
                const path_start = j;
                while (j < content.len and content[j] != '"') : (j += 1) {}
                const path_value = content[path_start..j];

                try store.trusted.put(path_value, .{
                    .sha256 = try allocator.dupe(u8, sha256_value),
                    .trusted_at = time_compat.timestamp(g_io),
                });
            }
        }
    }

    return store;
}

/// Save the trust store to disk
pub fn saveStore(allocator: std.mem.Allocator, store: *TrustStore) !void {
    const store_path = try getStorePath(allocator);
    defer allocator.free(store_path);

    // Create directory if needed
    const data_dir = std.fs.path.dirname(store_path) orelse return error.InvalidPath;
    try std.Io.Dir.createDirAbsolute(g_io, data_dir, .default_dir);

    // Build JSON manually
    var json = std.array_list.Managed(u8).init(allocator);
    defer json.deinit();

    try json.appendSlice("{\n  \"version\": 1,\n  \"trusted\": {\n");

    var it = store.trusted.iterator();
    var first = true;
    while (it.next()) |entry| {
        if (!first) try json.appendSlice(",\n");
        first = false;

        const line1 = try std.fmt.allocPrint(allocator, "    \"{s}\": {{\n", .{entry.key_ptr.*});
        defer allocator.free(line1);
        try json.appendSlice(line1);
        const line2 = try std.fmt.allocPrint(allocator, "      \"sha256\": \"{s}\",\n", .{entry.value_ptr.sha256});
        defer allocator.free(line2);
        try json.appendSlice(line2);
        const line3 = try std.fmt.allocPrint(allocator, "      \"trusted_at\": {d}\n", .{entry.value_ptr.trusted_at});
        defer allocator.free(line3);
        try json.appendSlice(line3);
        try json.appendSlice("    }");
    }

    try json.appendSlice("\n  }\n}\n");

    const file = try std.Io.Dir.createFileAbsolute(g_io, store_path, .{});
    defer file.close(g_io);
    try file.writeStreamingAll(g_io, json.items);
}

/// Check if a project-local filter file is trusted
pub fn checkTrust(allocator: std.mem.Allocator, filter_path: []const u8) !TrustStatus {
    // Fast path: env var override for CI pipelines
    if (_getEnvVarOwned(allocator, "LLMLITE_TRUST_PROJECT_FILTERS")) |env_val| {
        defer allocator.free(env_val);
        if (std.mem.eql(u8, env_val, "1")) {
            // Check if we're in CI
            if (_getEnvVarOwned(allocator, "CI")) |_| {
                return .env_override;
            }
        }
    } else |_| {}

    // Compute hash of the filter file
    const actual_hash = try computeFileHash(allocator, filter_path);
    defer allocator.free(actual_hash);

    // Load trust store
    const store = try loadStore(allocator);

    // Check if we have an entry
    if (store.trusted.get(filter_path)) |entry| {
        if (std.mem.eql(u8, entry.sha256, actual_hash)) {
            return .trusted;
        } else {
            return .content_changed;
        }
    }

    return .untrusted;
}

/// Compute SHA-256 hash of a file
fn computeFileHash(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.Io.Dir.openFileAbsolute(g_io, path, .{});
    defer file.close(g_io);

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
    return try allocator.dupe(u8, &hex);
}

/// Trust a project-local filter file
pub fn trustFilter(allocator: std.mem.Allocator, filter_path: []const u8) !void {
    // Compute hash
    const hash = try computeFileHash(allocator, filter_path);
    defer allocator.free(hash);

    // Load or create store
    var store = try loadStore(allocator);
    errdefer store.trusted.deinit();

    // Add/update entry
    try store.trusted.put(try allocator.dupe(u8, filter_path), .{
        .sha256 = hash,
        .trusted_at = time_compat.timestamp(g_io),
    });

    // Save store
    try saveStore(allocator, &store);
}

/// Untrust a project-local filter file
pub fn untrustFilter(allocator: std.mem.Allocator, filter_path: []const u8) !void {
    var store = try loadStore(allocator);
    errdefer store.trusted.deinit();

    _ = store.trusted.remove(filter_path);

    try saveStore(allocator, &store);
}

/// List all trusted filter files
pub fn listTrusted(allocator: std.mem.Allocator) ![]const []const u8 {
    const store = try loadStore(allocator);

    var result = try std.array_list.Managed([]const u8).initCapacity(allocator, 0);
    errdefer result.deinit();

    var it = store.trusted.iterator();
    while (it.next()) |entry| {
        try result.append(entry.key_ptr.*);
    }

    return result.toOwnedSlice();
}

/// Show trust status for a filter
pub fn showTrustStatus(allocator: std.mem.Allocator, filter_path: []const u8) !void {
    const status = checkTrust(allocator, filter_path) catch .untrusted;

    const status_str = switch (status) {
        .trusted => "TRUSTED",
        .untrusted => "UNTRUSTED",
        .content_changed => "CONTENT CHANGED",
        .env_override => "ENV OVERRIDE",
    };

    std.debug.print("Filter: {s}\n", .{filter_path});
    std.debug.print("Status: {s}\n", .{status_str});
}
