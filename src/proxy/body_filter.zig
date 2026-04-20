//! Body Filter for llmlite Proxy
//!
//! Filters private parameters (prefixed with `_`) from request bodies
//! before forwarding to upstream providers. Prevents internal info leakage.
//!
//! ## Filtering Rules
//! - Fields starting with `_` are considered private and recursively filtered
//! - Supports whitelist mechanism to allow specific `_` prefixed fields
//! - Supports nested objects and arrays with deep filtering
//!
//! ## Use Cases
//! - `_internal_id`: Internal tracking ID
//! - `_debug_mode`: Debug flag
//! - `_session_token`: Session token
//! - `_client_version`: Client version

const std = @import("std");
const json = std.json;

pub const BodyFilterConfig = struct {
    enabled: bool = true,
    whitelist: []const []const u8 = &.{},
};

/// Filter private parameters (fields starting with `_`) from JSON body
pub fn filterPrivateParams(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    return filterPrivateParamsWithWhitelist(allocator, body, &.{});
}

/// Filter private parameters with whitelist support
pub fn filterPrivateParamsWithWhitelist(allocator: std.mem.Allocator, body: []const u8, whitelist: []const []const u8) ![]u8 {
    var parsed = try json.parseFromSlice(json.Value, allocator, body, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const whitelist_set = try buildWhitelistSet(allocator, whitelist);
    defer allocator.free(whitelist_set);

    const filtered = filterRecursive(allocator, &parsed.value, whitelist_set);
    defer {
        // Clean up allocated strings in filtered
        cleanupStrings(allocator, &filtered);
    }

    var buf = std.array_list.Managed(u8).init(allocator);
    try json.stringify(filtered, .{ .whitespace = .indent_tab }, buf.writer());
    return buf.toOwnedSlice();
}

fn buildWhitelistSet(allocator: std.mem.Allocator, whitelist: []const []const u8) ![][]u8 {
    const result = try allocator.alloc([]u8, whitelist.len);
    for (whitelist, 0..) |item, i| {
        result[i] = try allocator.dupe(u8, item);
    }
    return result;
}

fn isWhitelisted(whitelist: [][]u8, key: []const u8) bool {
    for (whitelist) |item| {
        if (std.mem.eql(u8, item, key)) return true;
    }
    return false;
}

fn filterRecursive(allocator: std.mem.Allocator, value: *json.Value, whitelist: [][]u8) json.Value {
    switch (value.*) {
        .object => |*map| {
            var new_map = std.json.ObjectMap.init(allocator);
            var it = map.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                // Skip private fields not in whitelist
                if (key.len > 0 and key[0] == '_' and !isWhitelisted(whitelist, key)) {
                    // Skip this field
                    allocator.free(key);
                    continue;
                }
                const new_value = filterRecursive(allocator, entry.value_ptr, whitelist);
                new_map.putAssumeCapacity(key, new_value);
            }
            map.deinit();
            return json.Value{ .object = new_map };
        },
        .array => |*arr| {
            var new_arr = std.array_list.Managed(json.Value).init(allocator);
            for (arr.items) |*item| {
                new_arr.appendAssumeCapacity(filterRecursive(allocator, item, whitelist));
            }
            arr.deinit();
            return json.Value{ .array = new_arr };
        },
        else => {
            return value.*;
        },
    }
}

fn cleanupStrings(allocator: std.mem.Allocator, value: *json.Value) void {
    switch (value.*) {
        .object => |map| {
            var it = map.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                cleanupStrings(allocator, entry.value_ptr);
            }
            map.deinit();
        },
        .array => |arr| {
            for (arr.items) |*item| {
                cleanupStrings(allocator, item);
            }
            arr.deinit();
        },
        .string => |str| {
            allocator.free(str);
        },
        else => {},
    }
}

// ============================================================================
// TESTS
// ============================================================================

test "body_filter - filters top level private params" {
    const allocator = std.heap.page_allocator;
    const input =
        \\{"model":"claude-3","_internal_id":"abc123","_debug":true,"max_tokens":1024}
    ;

    const output = try filterPrivateParams(allocator, input);
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "_internal_id") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "_debug") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "model") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "max_tokens") != null);
}

test "body_filter - filters nested private params" {
    const allocator = std.heap.page_allocator;
    const input =
        \\{"model":"claude-3","messages":[{"role":"user","content":"hello","_session_token":"secret"}],"metadata":{"user_id":"user-1","_tracking_id":"track-1"}}
    ;

    const output = try filterPrivateParams(allocator, input);
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "_session_token") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "_tracking_id") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "user_id") != null);
}

test "body_filter - preserves non-private params" {
    const allocator = std.heap.page_allocator;
    const input =
        \\{"model":"claude-3","messages":[{"role":"user","content":"hello"}]}
    ;

    const output = try filterPrivateParams(allocator, input);
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "model") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "messages") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "role") != null);
}

test "body_filter - whitelist preserves specified private params" {
    const allocator = std.heap.page_allocator;
    const input =
        \\{"model":"claude-3","_metadata":{"key":"value"},"_internal_id":"abc123","_stream_options":{"include_usage":true}}
    ;
    const whitelist = &.{ "_metadata", "_stream_options" };

    const output = try filterPrivateParamsWithWhitelist(allocator, input, whitelist);
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "_metadata") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "_stream_options") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "_internal_id") == null);
}

test "body_filter - empty object" {
    const allocator = std.heap.page_allocator;
    const input = "{}";

    const output = try filterPrivateParams(allocator, input);
    defer allocator.free(output);

    try std.testing.expectEqualStrings("{}", output);
}

test "body_filter - array of objects with private fields" {
    const allocator = std.heap.page_allocator;
    const input =
        \\{"items":[{"id":1,"_secret":"a"},{"id":2,"_secret":"b"},{"id":3,"_secret":"c"}]}
    ;

    const output = try filterPrivateParams(allocator, input);
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "_secret") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"id\":2") != null);
}
