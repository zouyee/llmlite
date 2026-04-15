//! Copilot Optimizer for llmlite Proxy
//!
//! Classifies GitHub Copilot requests to determine the `x-initiator` header value.
//! - "user": Counts as a premium interaction (deducts quota)
//! - "agent": Continuation of previous interaction (no extra charge)
//!
//! Reference: https://github.com/caozhiyuan/copilot-api

const std = @import("std");
const json = std.json;

pub const CopilotConfig = struct {
    enabled: bool = false,
    compact_detection: bool = true,
    request_classification: bool = true,
    tool_result_merging: bool = true,
    deterministic_request_id: bool = true,
    warmup_downgrade: bool = false,
    warmup_model: []const u8 = "gpt-4o-mini",
};

/// Request classification result
pub const CopilotClassification = struct {
    /// "user" or "agent" - maps to x-initiator header
    initiator: []const u8,
    /// Whether this is a warmup/probe request (can downgrade to smaller model)
    is_warmup: bool,
    /// Whether this is a context compression request
    is_compact: bool,
};

/// Classify Anthropic-format request body to determine Copilot request headers.
///
/// Classification algorithm (checks last message only, aligned with caozhiyuan/copilot-api):
/// 1. No messages → "user" (safe default, first request)
/// 2. Last message role=user:
///    - Content has non-tool_result blocks → "user"
///    - Content is all tool_result → "agent"
///    - Matches compact pattern → "agent"
/// 3. Last message role non-user → "user" (safe default)
///
/// Warmup detection:
/// - Request has `anthropic-beta` header + no tools + non-compact → warmup
pub fn classifyRequest(body: *const json.Value, has_anthropic_beta: bool, compact_detection: bool) CopilotClassification {
    const is_compact = compact_detection and isCompactRequest(body);

    const messages = body.object.get("messages") orelse {
        return CopilotClassification{
            .initiator = "user",
            .is_warmup = isWarmupRequest(body, has_anthropic_beta, false),
            .is_compact = false,
        };
    };

    const msg_array = messages.array orelse {
        return CopilotClassification{
            .initiator = "user",
            .is_warmup = isWarmupRequest(body, has_anthropic_beta, false),
            .is_compact = false,
        };
    };

    if (msg_array.items.len == 0) {
        return CopilotClassification{
            .initiator = "user",
            .is_warmup = isWarmupRequest(body, has_anthropic_beta, false),
            .is_compact = false,
        };
    }

    const last_msg = &msg_array.items[msg_array.items.len - 1];
    const role = last_msg.object.get("role") orelse {
        return CopilotClassification{ .initiator = "user", .is_warmup = false, .is_compact = is_compact };
    };
    const role_str = role.string;

    // Only role=user messages need detailed classification
    if (!std.mem.eql(u8, role_str, "user")) {
        return CopilotClassification{ .initiator = "user", .is_warmup = false, .is_compact = is_compact };
    }

    // Check content type
    const content = last_msg.object.get("content");
    var is_user_initiated = false;

    if (content) |c| {
        if (c == .array) {
            // Content is array - check if any block is non-tool_result
            for (c.array.items) |block| {
                const block_type = block.object.get("type") orelse continue;
                if (block_type == .string and !std.mem.eql(u8, block_type.string, "tool_result")) {
                    is_user_initiated = true;
                    break;
                }
            }
        } else if (c == .string) {
            // Content is string → user initiated
            is_user_initiated = true;
        }
    }

    const initiator = if (!is_user_initiated or is_compact) "agent" else "user";

    const is_warmup = std.mem.eql(u8, initiator, "user") and isWarmupRequest(body, has_anthropic_beta, is_compact);

    return CopilotClassification{
        .initiator = initiator,
        .is_warmup = is_warmup,
        .is_compact = is_compact,
    };
}

/// Detect if this is a warmup/probe request (suitable for downgrading to smaller model)
fn isWarmupRequest(body: *const json.Value, has_anthropic_beta: bool, is_compact: bool) bool {
    // Warmup: has anthropic-beta header, no tools, non-compact
    if (has_anthropic_beta and !is_compact) {
        // Check if no tools in request
        const tools = body.object.get("tools");
        if (tools == null or tools == .null) {
            return true;
        }
        if (tools == .array and tools.array.items.len == 0) {
            return true;
        }
    }
    return false;
}

/// Detect if this is a context compression request
fn isCompactRequest(body: *const json.Value) bool {
    // Look for compact-related patterns in messages
    const messages = body.object.get("messages") orelse return false;
    const msg_array = messages.array orelse return false;

    for (msg_array.items) |msg| {
        const content = msg.object.get("content") orelse continue;

        if (content == .string) {
            const text = content.string;
            // Check for compact-related keywords
            if (std.mem.containsAtLeast(u8, text, 1, "compact") or
                std.mem.containsAtLeast(u8, text, 1, "compress"))
            {
                return true;
            }
        }
    }
    return false;
}

/// Get the x-initiator header value for Copilot
pub fn getInitiatorHeader(classification: CopilotClassification) []const u8 {
    return classification.initiator;
}

/// Check if request should be downgraded (warmup requests)
pub fn shouldDowngrade(classification: CopilotClassification) bool {
    return classification.is_warmup;
}

// ============================================================================
// MERGE TOOL RESULTS
// ============================================================================

/// Merge tool results in a Copilot request body
///
/// Phase 1: Within a message - merge text blocks into tool_result blocks
/// Phase 2: Across messages - merge consecutive tool_result-only user messages
pub fn mergeToolResults(allocator: std.mem.Allocator, body: *json.Value) !void {
    const messages = body.object.get("messages") orelse return;
    const msg_array = messages.array orelse return;
    if (msg_array.items.len == 0) return;

    // Phase 1: Within message merging
    for (msg_array.items) |*msg| {
        const role = msg.object.get("role") orelse continue;
        if (role != .string or !std.mem.eql(u8, role.string, "user")) continue;

        const content = msg.object.get("content") orelse continue;
        if (content != .array) continue;

        // Separate tool_result and text blocks
        var tool_results = std.json.Array.init(allocator);
        var text_blocks = std.json.Array.init(allocator);
        var valid = true;

        for (content.array.items) |block| {
            const block_type = block.object.get("type") orelse {
                valid = false;
                break;
            };
            if (block_type != .string) {
                valid = false;
                break;
            }
            if (std.mem.eql(u8, block_type.string, "tool_result")) {
                try tool_results.append(block.*);
            } else if (std.mem.eql(u8, block_type.string, "text")) {
                try text_blocks.append(block.*);
            } else {
                valid = false;
                break;
            }
        }

        if (!valid or tool_results.items.len == 0 or text_blocks.items.len == 0) continue;

        // Merge text blocks into tool_results
        const merged = try mergeBlocksIntoToolResults(allocator, tool_results, text_blocks);
        msg.object.put("content", json.Value{ .array = merged }) catch return;
    }

    // Phase 2: Cross-message merging
    const messages_copy = try json.deepCloneAlloc(allocator, body.object.get("messages").?, .{});
    defer messages_copy.destroy(allocator);
    const copy_array = messages_copy.array orelse return;
    if (copy_array.items.len <= 1) return;

    var merged_msgs = std.json.Array.init(allocator);
    var i: usize = 0;
    while (i < copy_array.items.len) {
        if (isToolResultOnlyMessage(&copy_array.items[i])) {
            var combined_content = std.json.Array.init(allocator);
            while (i < copy_array.items.len and isToolResultOnlyMessage(&copy_array.items[i])) {
                const content = copy_array.items[i].object.get("content") orelse {
                    i += 1;
                    continue;
                };
                if (content == .array) {
                    for (content.array.items) |block| {
                        try combined_content.append(block.*);
                    }
                }
                i += 1;
            }
            if (combined_content.items.len > 0) {
                var new_msg = std.json.ObjectMap.init(allocator);
                try new_msg.put("role", json.Value{ .string = "user" });
                try new_msg.put("content", json.Value{ .array = combined_content });
                try merged_msgs.append(json.Value{ .object = new_msg });
            }
        } else {
            try merged_msgs.append(copy_array.items[i].*);
            i += 1;
        }
    }

    body.object.put("messages", json.Value{ .array = merged_msgs }) catch return;
}

/// Merge text blocks into tool_result blocks
fn mergeBlocksIntoToolResults(allocator: std.mem.Allocator, tool_results: std.json.Array, text_blocks: std.json.Array) !std.json.Array {
    var result = std.json.Array.init(allocator);
    
    if (tool_results.items.len == text_blocks.items.len) {
        // 1:1 merge
        for (tool_results.items, 0..) |tr, idx| {
            var merged = tr;
            appendTextToToolResult(allocator, &mut merged, &text_blocks.items[idx]);
            try result.append(merged);
        }
    } else {
        // All text appended to last tool_result
        if (tool_results.items.len > 0) {
            for (0..tool_results.items.len - 1) |idx| {
                try result.append(tool_results.items[idx]);
            }
            var last_tr = tool_results.items[tool_results.items.len - 1];
            for (text_blocks.items) |tb| {
                appendTextToToolResult(allocator, &mut last_tr, &tb);
            }
            try result.append(last_tr);
        }
    }
    return result;
}

/// Append text block content to tool_result
fn appendTextToToolResult(allocator: std.mem.Allocator, tool_result: *json.Value, text_block: *const json.Value) void {
    const text = text_block.object.get("text") orelse return;
    if (text != .string) return;
    const text_str = text.string;
    if (text_str.len == 0) return;

    const content = tool_result.object.get("content") orelse {
        // content missing - set directly
        tool_result.object.put("content", json.Value{ .string = text_str }) catch return;
        return;
    };

    switch (content) {
        .string => |existing| {
            const new_content = std.fmt.allocPrint(allocator, "{s}\n{s}", .{ existing, text_str }) catch return;
            tool_result.object.put("content", json.Value{ .string = new_content }) catch return;
        },
        .array => |arr| {
            var new_arr = std.json.Array.init(allocator);
            for (arr.items) |item| {
                try new_arr.append(item.*);
            }
            var text_obj = std.json.ObjectMap.init(allocator);
            text_obj.put("type", json.Value{ .string = "text" }) catch return;
            text_obj.put("text", json.Value{ .string = text_str }) catch return;
            try new_arr.append(json.Value{ .object = text_obj });
            tool_result.object.put("content", json.Value{ .array = new_arr }) catch return;
        },
        else => {
            tool_result.object.put("content", json.Value{ .string = text_str }) catch return;
        },
    }
}

/// Check if message is a tool_result-only user message
fn isToolResultOnlyMessage(msg: *const json.Value) bool {
    const role = msg.object.get("role") orelse return false;
    if (role != .string or !std.mem.eql(u8, role.string, "user")) return false;

    const content = msg.object.get("content") orelse return false;
    if (content != .array) return false;
    if (content.array.items.len == 0) return false;

    for (content.array.items) |block| {
        const block_type = block.object.get("type") orelse return false;
        if (block_type != .string or !std.mem.eql(u8, block_type.string, "tool_result")) {
            return false;
        }
    }
    return true;
}

// ============================================================================
// DETERMINISTIC REQUEST ID
// ============================================================================

/// Generate deterministic request ID using SHA256
///
/// Uses session_id + last user content (excluding tool_result and cache_control)
/// Falls back to random UUID if no user content found
pub fn deterministicRequestId(allocator: std.mem.Allocator, body: *const json.Value, session_id: []const u8) ![]u8 {
    const last_user_content = findLastUserContent(allocator, body);

    if (last_user_content) |content| {
        defer allocator.free(content);

        // Hash: SHA256(session_id || content)
        var hasher = std.crypto.hash.sha256.Sha256.init();
        hasher.update(session_id);
        hasher.update(content);
        const hash = hasher.finalize();

        // Take first 16 bytes and set UUID v4 version/variant bits
        var uuid_bytes: [16]u8 = undefined;
        @memcpy(uuid_bytes[0..], hash[0..16]);
        uuid_bytes[6] = (uuid_bytes[6] & 0x0f) | 0x40; // version 4
        uuid_bytes[8] = (uuid_bytes[8] & 0x3f) | 0x80;  // variant

        // Format as UUID string
        const uuid_str = try fmtUuid(&uuid_bytes);
        return uuid_str;
    } else {
        // Fallback: random UUID
        return randomUuid(allocator);
    }
}

/// Format 16 bytes as UUID string
fn fmtUuid(bytes: *const [16]u8) ![]u8 {
    const fmt = "-{}-{}-{}-{}-{}";
    return try std.fmt.allocPrint(std.heap.page_allocator, fmt, .{
        bytes[0..4],
        bytes[4..6],
        bytes[6..8],
        bytes[8..10],
        bytes[10..16],
    });
}

/// Generate random UUID v4
fn randomUuid(allocator: std.mem.Allocator) ![]u8 {
    var bytes: [16]u8 = undefined;
    std.crypto.random.bytes(bytes[0..]);
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80;  // variant
    return fmtUuid(&bytes);
}

/// Find last user message's non-tool_result content
fn findLastUserContent(allocator: std.mem.Allocator, body: *const json.Value) !?[]u8 {
    const messages = body.object.get("messages") orelse return null;
    const msg_array = messages.array orelse return null;

    for (msg_array.items) |msg| {
        const role = msg.object.get("role") orelse continue;
        if (role != .string or !std.mem.eql(u8, role.string, "user")) continue;

        const content = msg.object.get("content") orelse continue;

        if (content == .string) {
            return try allocator.dupe(u8, content.string);
        }

        if (content == .array) {
            // Filter out tool_result blocks, remove cache_control, serialize rest
            var filtered = std.json.Array.init(allocator);
            for (content.array.items) |block| {
                const block_type = block.object.get("type") orelse continue;
                if (block_type != .string) continue;
                if (std.mem.eql(u8, block_type.string, "tool_result")) continue;

                // Clone block without cache_control
                var new_block = std.json.ObjectMap.init(allocator);
                for (block.object.keys()) |key| {
                    if (std.mem.eql(u8, key, "cache_control")) continue;
                    if (block.object.get(key)) |val| {
                        try new_block.put(key, val);
                    }
                }
                try filtered.append(json.Value{ .object = new_block });
            }

            if (filtered.items.len > 0) {
                const serialized = try json.stringifyAlloc(allocator, json.Value{ .array = filtered }, .{});
                return serialized;
            }
        }
    }
    return null;
}

// ============================================================================
// TESTS
// ============================================================================

test "copilot_optimizer - empty messages returns user" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer body.object.deinit();

    const result = classifyRequest(&body, false, true);
    try std.testing.expectEqualStrings("user", result.initiator);
    try std.testing.expect(!result.is_warmup);
}

test "copilot_optimizer - role assistant returns user" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer body.object.deinit();

    var messages = std.json.ArrayList(json.Value).init(allocator);
    defer messages.deinit();

    var msg = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    msg.object.putAssumeCapacity("role", json.Value{ .string = "assistant" });
    msg.object.putAssumeCapacity("content", json.Value{ .string = "hello" });
    messages.appendAssumeCapacity(msg);

    body.object.putAssumeCapacity("messages", json.Value{ .array = messages });

    const result = classifyRequest(&body, false, true);
    try std.testing.expectEqualStrings("user", result.initiator);
}

test "copilot_optimizer - user role with text content returns user" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer body.object.deinit();

    var messages = std.json.ArrayList(json.Value).init(allocator);
    defer messages.deinit();

    var msg = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    msg.object.putAssumeCapacity("role", json.Value{ .string = "user" });
    msg.object.putAssumeCapacity("content", json.Value{ .string = "hello" });
    messages.appendAssumeCapacity(msg);

    body.object.putAssumeCapacity("messages", json.Value{ .array = messages });

    const result = classifyRequest(&body, false, true);
    try std.testing.expectEqualStrings("user", result.initiator);
}

test "copilot_optimizer - user role with only tool_result returns agent" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer body.object.deinit();

    var messages = std.json.ArrayList(json.Value).init(allocator);
    defer messages.deinit();

    var msg = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    msg.object.putAssumeCapacity("role", json.Value{ .string = "user" });

    var content_arr = std.json.ArrayList(json.Value).init(allocator);
    var tool_result = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    tool_result.object.putAssumeCapacity("type", json.Value{ .string = "tool_result" });
    content_arr.appendAssumeCapacity(tool_result);
    msg.object.putAssumeCapacity("content", json.Value{ .array = content_arr });

    messages.appendAssumeCapacity(msg);
    body.object.putAssumeCapacity("messages", json.Value{ .array = messages });

    const result = classifyRequest(&body, false, true);
    try std.testing.expectEqualStrings("agent", result.initiator);
}

test "copilot_optimizer - warmup detection with anthropic_beta and no tools" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer body.object.deinit();

    var messages = std.json.ArrayList(json.Value).init(allocator);
    defer messages.deinit();

    var msg = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    msg.object.putAssumeCapacity("role", json.Value{ .string = "user" });
    msg.object.putAssumeCapacity("content", json.Value{ .string = "hello" });
    messages.appendAssumeCapacity(msg);

    body.object.putAssumeCapacity("messages", json.Value{ .array = messages });
    // No tools field = warmup candidate when has_anthropic_beta=true

    const result = classifyRequest(&body, true, true);
    try std.testing.expect(result.is_warmup);
}

test "copilot_optimizer - compact detection" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer body.object.deinit();

    var messages = std.json.ArrayList(json.Value).init(allocator);
    defer messages.deinit();

    var msg = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    msg.object.putAssumeCapacity("role", json.Value{ .string = "user" });
    msg.object.putAssumeCapacity("content", json.Value{ .string = "please compact the context" });
    messages.appendAssumeCapacity(msg);

    body.object.putAssumeCapacity("messages", json.Value{ .array = messages });

    const result = classifyRequest(&body, false, true);
    try std.testing.expect(result.is_compact);
    try std.testing.expectEqualStrings("agent", result.initiator);
}
