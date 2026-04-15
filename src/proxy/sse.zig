//! SSE (Server-Sent Events) Utilities for llmlite Proxy
//!
//! Provides utilities for handling SSE data streams.

const std = @import("std");

/// Strip SSE field from a line
///
/// Example: stripSseField("data: {\"ok\":true}", "data") => Some("{\"ok\":true}")
pub fn stripSseField(line: []const u8, field: []const u8) ?[]const u8 {
    const prefix1 = field ++ ": ";
    const prefix2 = field ++ ":";

    if (std.mem.startsWith(u8, line, prefix1)) {
        return std.mem.trimLeft(u8, line[prefix1.len..], " ");
    }
    if (std.mem.startsWith(u8, line, prefix2)) {
        return std.mem.trimLeft(u8, line[prefix2.len..], " ");
    }
    return null;
}

/// Append UTF-8 safe bytes to buffer
///
/// Handles multi-byte characters split across chunk boundaries.
/// `remainder` accumulates trailing bytes from previous chunk that form an
/// incomplete UTF-8 sequence (at most 3 bytes).
pub fn appendUtf8Safe(buffer: *std.ArrayList(u8), remainder: *std.ArrayList(u8), new_bytes: []const u8) void {
    // Build combined bytes: prepend remainder to new_bytes
    var combined = std.ArrayList(u8).init(buffer.allocator);
    defer combined.deinit();

    if (remainder.items.len > 0) {
        // Defensive guard: if remainder > 3 bytes, flush it and start fresh
        if (remainder.items.len > 3) {
            // Append replacement character for each invalid byte
            for (0..remainder.items.len) |_| {
                buffer.appendAssumeCapacity('\u{FFFD}');
            }
            remainder.clearRetainingCapacity();
        }
        combined.appendSliceAssumeCapacity(remainder.items);
    }
    combined.appendSliceAssumeCapacity(new_bytes);

    // Decode loop: consume all valid UTF-8, leaving trailing incomplete sequence in remainder
    var pos: usize = 0;
    while (pos < combined.items.len) {
        const remaining = combined.items[pos..];
        const decoded = std.unicode.utf8Decode(remaining);
        if (decoded == .overflow) {
            // Incomplete sequence at end - save to remainder
            remainder.appendSliceAssumeCapacity(combined.items[pos..]);
            return;
        }
        if (decoded == .empty) {
            // Empty - save to remainder
            remainder.appendSliceAssumeCapacity(combined.items[pos..]);
            return;
        }
        const cp = decoded.value;
        buffer.appendAssumeCapacity(@as(u8, @intCast(cp)));
        // Handle multi-byte codepoints
        const len = std.unicode.utf8CodepointSequenceLength(cp) catch 1;
        pos += len;
    }
}

/// Check if a message contains only tool_result blocks
fn isToolResultOnlyMessage(msg: *const std.json.Value) bool {
    const role = msg.object.get("role") orelse return false;
    if (role != .string or !std.mem.eql(u8, role.string, "user")) return false;

    const content = msg.object.get("content") orelse return false;
    if (content != .array) return false;

    for (content.array.items) |block| {
        const block_type = block.object.get("type") orelse return false;
        if (block_type != .string or !std.mem.eql(u8, block_type.string, "tool_result")) {
            return false;
        }
    }
    return content.array.items.len > 0;
}

// ============================================================================
// TESTS
// ============================================================================

test "sse - strip sse field with space" {
    const result = stripSseField("data: {\"ok\":true}", "data");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("{\"ok\":true}", result.?);
}

test "sse - strip sse field without space" {
    const result = stripSseField("data:{\"ok\":true}", "data");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("{\"ok\":true}", result.?);
}

test "sse - strip sse field with event" {
    const result = stripSseField("event: message_start", "event");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("message_start", result.?);
}

test "sse - strip sse field no match" {
    const result = stripSseField("id:1", "data");
    try std.testing.expect(result == null);
}

test "sse - is tool result only message - true" {
    const allocator = std.heap.page_allocator;
    var msg = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer msg.object.deinit();

    try msg.object.put("role", std.json.Value{ .string = "user" });
    var content_arr = std.json.Array.init(allocator);
    var tool_result = std.json.ObjectMap.init(allocator);
    try tool_result.put("type", std.json.Value{ .string = "tool_result" });
    try content_arr.append(std.json.Value{ .object = tool_result });
    try msg.object.put("content", std.json.Value{ .array = content_arr });

    try std.testing.expect(isToolResultOnlyMessage(&msg));
}

test "sse - is tool result only message - false with text" {
    const allocator = std.heap.page_allocator;
    var msg = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer msg.object.deinit();

    try msg.object.put("role", std.json.Value{ .string = "user" });
    var content_arr = std.json.Array.init(allocator);
    var tool_result = std.json.ObjectMap.init(allocator);
    try tool_result.put("type", std.json.Value{ .string = "tool_result" });
    try content_arr.append(std.json.Value{ .object = tool_result });
    var text_block = std.json.ObjectMap.init(allocator);
    try text_block.put("type", std.json.Value{ .string = "text" });
    try text_block.put("text", std.json.Value{ .string = "hello" });
    try content_arr.append(std.json.Value{ .object = text_block });
    try msg.object.put("content", std.json.Value{ .array = content_arr });

    try std.testing.expect(!isToolResultOnlyMessage(&msg));
}

test "sse - is tool result only message - false with role" {
    const allocator = std.heap.page_allocator;
    var msg = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer msg.object.deinit();

    try msg.object.put("role", std.json.Value{ .string = "assistant" });
    var content_arr = std.json.Array.init(allocator);
    var tool_result = std.json.ObjectMap.init(allocator);
    try tool_result.put("type", std.json.Value{ .string = "tool_result" });
    try content_arr.append(std.json.Value{ .object = tool_result });
    try msg.object.put("content", std.json.Value{ .array = content_arr });

    try std.testing.expect(!isToolResultOnlyMessage(&msg));
}
