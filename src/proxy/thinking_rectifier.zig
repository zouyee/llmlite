//! Thinking Signature Rectifier for llmlite Proxy
//!
//! Automatically fixes requests that fail due to thinking signature issues.
//! When upstream API returns signature-related errors, the system automatically
//! removes problematic signature fields and retries.

const std = @import("std");
const json = std.json;

pub const RectifierConfig = struct {
    enabled: bool = true,
    request_thinking_signature: bool = true,
    request_thinking_budget: bool = true,
};

/// Rectification result
pub const RectifyResult = struct {
    applied: bool,
    removed_thinking_blocks: usize,
    removed_redacted_thinking_blocks: usize,
    removed_signature_fields: usize,
};

/// Check if thinking signature rectification should be triggered
///
/// Returns true if error message matches known signature error patterns.
pub fn shouldRectifyThinkingSignature(error_message: ?[]const u8, config: *const RectifierConfig) bool {
    // Check master switch
    if (!config.enabled) return false;
    // Check sub switch
    if (!config.request_thinking_signature) return false;

    const msg = error_message orelse return false;
    const lower = std.ascii.lowerString(msg);

    // Scenario 1: Invalid 'signature' in 'thinking' block
    if (std.mem.containsAtLeast(u8, lower, 1, "invalid") and
        std.mem.containsAtLeast(u8, lower, 1, "signature") and
        std.mem.containsAtLeast(u8, lower, 1, "thinking") and
        std.mem.containsAtLeast(u8, lower, 1, "block"))
    {
        return true;
    }

    // Scenario 2: assistant message must start with a thinking block
    if (std.mem.containsAtLeast(u8, lower, 1, "must start with a thinking block")) {
        return true;
    }

    // Scenario 3: Expected thinking or redacted_thinking, found tool_use
    if (std.mem.containsAtLeast(u8, lower, 1, "expected") and
        (std.mem.containsAtLeast(u8, lower, 1, "thinking") or
            std.mem.containsAtLeast(u8, lower, 1, "redacted_thinking")) and
        std.mem.containsAtLeast(u8, lower, 1, "found") and
        std.mem.containsAtLeast(u8, lower, 1, "tool_use"))
    {
        return true;
    }

    // Scenario 4: signature field required but missing
    if (std.mem.containsAtLeast(u8, lower, 1, "signature") and
        std.mem.containsAtLeast(u8, lower, 1, "field required"))
    {
        return true;
    }

    // Scenario 5: signature field not accepted (third-party channels)
    if (std.mem.containsAtLeast(u8, lower, 1, "signature") and
        std.mem.containsAtLeast(u8, lower, 1, "extra inputs are not permitted"))
    {
        return true;
    }

    // Scenario 6: thinking/redacted_thinking blocks cannot be modified
    if ((std.mem.containsAtLeast(u8, lower, 1, "thinking") or
        std.mem.containsAtLeast(u8, lower, 1, "redacted_thinking")) and
        std.mem.containsAtLeast(u8, lower, 1, "cannot be modified"))
    {
        return true;
    }

    // Scenario 7: Illegal/invalid request (unified fallback)
    if (std.mem.containsAtLeast(u8, lower, 1, "非法请求") or
        std.mem.containsAtLeast(u8, lower, 1, "illegal request") or
        std.mem.containsAtLeast(u8, lower, 1, "invalid request"))
    {
        return true;
    }

    return false;
}

/// Rectify Anthropic request body with minimal intrusion
///
/// Actions:
/// - Remove thinking/redacted_thinking blocks from messages[*].content
/// - Remove signature fields from non-thinking blocks
/// - Remove top-level thinking field under specific conditions
pub fn rectifyAnthropicRequest(body: *json.Value) RectifyResult {
    var result = RectifyResult{
        .applied = false,
        .removed_thinking_blocks = 0,
        .removed_redacted_thinking_blocks = 0,
        .removed_signature_fields = 0,
    };

    const messages = body.object.getPtr("messages") orelse return result;
    if (messages.* != .array) return result;

    // Iterate all messages
    for (messages.array.items) |*msg| {
        const content = msg.object.getPtr("content") orelse continue;
        if (content.* != .array) continue;

        var new_content = std.json.Array.init(std.heap.page_allocator);
        var content_modified = false;

        for (content.array.items) |*block| {
            const block_type = block.object.get("type") orelse continue;

            if (block_type == .string) {
                if (std.mem.eql(u8, block_type.string, "thinking")) {
                    result.removed_thinking_blocks += 1;
                    content_modified = true;
                    continue;
                }
                if (std.mem.eql(u8, block_type.string, "redacted_thinking")) {
                    result.removed_redacted_thinking_blocks += 1;
                    content_modified = true;
                    continue;
                }
            }

            // Remove signature field from non-thinking blocks
            if (block.object.get("signature")) |_| {
                // Clone block without signature
                var new_block = std.json.ObjectMap.init(std.heap.page_allocator);
                for (block.object.keys()) |key| {
                    if (std.mem.eql(u8, key, "signature")) continue;
                    if (block.object.get(key)) |val| {
                        new_block.put(key, val) catch continue;
                    }
                }
                result.removed_signature_fields += 1;
                content_modified = true;
                new_content.append(json.Value{ .object = new_block }) catch continue;
            } else {
                new_content.append(block.*) catch continue;
            }
        }

        if (content_modified) {
            result.applied = true;
            content.* = json.Value{ .array = new_content };
        }
    }

    // Snapshot messages for should_remove_top_level_thinking check
    var messages_snapshot = std.json.Array.init(std.heap.page_allocator);
    if (body.object.get("messages")) |msgs| {
        if (msgs == .array) {
            for (msgs.array.items) |*msg| {
                messages_snapshot.append(msg.*) catch break;
            }
        }
    }

    // Fallback: Remove top-level thinking if enabled thinking + tool_use without thinking prefix
    if (shouldRemoveTopLevelThinking(body, &messages_snapshot)) {
        _ = body.object.remove("thinking");
        result.applied = true;
    }

    return result;
}

/// Check if top-level thinking should be removed
fn shouldRemoveTopLevelThinking(body: *const json.Value, messages: *const json.Array) bool {
    // Check if thinking is enabled (type = "enabled" only)
    const thinking_type = if (body.object.get("thinking")) |thinking|
        if (thinking.object.get("type")) |t|
            if (t == .string) t.string else null
        else
            null
    else
        null;

    // Only type=enabled triggers removal
    if (thinking_type == null or !std.mem.eql(u8, thinking_type.?, "enabled")) {
        return false;
    }

    // Find last assistant message
    var last_assistant: ?*const json.Value = null;
    for (messages.items) |*msg| {
        if (msg.object.get("role")) |role| {
            if (role == .string and std.mem.eql(u8, role.string, "assistant")) {
                last_assistant = msg;
            }
        }
    }

    const last_assistant_content = last_assistant orelse return false;
    const content = last_assistant_content.object.get("content") orelse return false;
    if (content != .array or content.array.items.len == 0) return false;

    // Check if first block is thinking/redacted_thinking
    const first_block = content.array.items[0].object.get("type") orelse return false;
    if (first_block != .string) return false;

    const missing_thinking_prefix = !std.mem.eql(u8, first_block.string, "thinking") and
        !std.mem.eql(u8, first_block.string, "redacted_thinking");

    if (!missing_thinking_prefix) return false;

    // Check if tool_use exists
    for (content.array.items) |*block| {
        const block_type = block.object.get("type") orelse continue;
        if (block_type == .string and std.mem.eql(u8, block_type.string, "tool_use")) {
            return true;
        }
    }

    return false;
}

/// Normalize thinking type - no-op in Zig (matches Rust behavior)
///
/// Note: In Rust cc-switch, this was a no-op function for CCH alignment.
/// In llmlite, we implement the same behavior.
pub fn normalizeThinkingType(body: json.Value) json.Value {
    return body;
}

// ============================================================================
// TESTS
// ============================================================================

test "shouldRectifyThinkingSignature - detects invalid signature" {
    const config = RectifierConfig{
        .enabled = true,
        .request_thinking_signature = true,
        .request_thinking_budget = true,
    };

    try std.testing.expect(shouldRectifyThinkingSignature(
        "messages.1.content.0: Invalid `signature` in `thinking` block",
        &config,
    ));
}

test "shouldRectifyThinkingSignature - detects invalid signature no backticks" {
    const config = RectifierConfig{
        .enabled = true,
        .request_thinking_signature = true,
        .request_thinking_budget = true,
    };

    try std.testing.expect(shouldRectifyThinkingSignature(
        "Messages.1.Content.0: invalid signature in thinking block",
        &config,
    ));
}

test "shouldRectifyThinkingSignature - detects thinking expected with tool_use" {
    const config = RectifierConfig{
        .enabled = true,
        .request_thinking_signature = true,
        .request_thinking_budget = true,
    };

    try std.testing.expect(shouldRectifyThinkingSignature(
        "messages.69.content.0.type: Expected `thinking` or `redacted_thinking`, but found `tool_use`.",
        &config,
    ));
}

test "shouldRectifyThinkingSignature - no detect without tool_use" {
    const config = RectifierConfig{
        .enabled = true,
        .request_thinking_signature = true,
        .request_thinking_budget = true,
    };

    try std.testing.expect(!shouldRectifyThinkingSignature(
        "messages.69.content.0.type: Expected `thinking` or `redacted_thinking`, but found `text`.",
        &config,
    ));
}

test "shouldRectifyThinkingSignature - detects must start with thinking" {
    const config = RectifierConfig{
        .enabled = true,
        .request_thinking_signature = true,
        .request_thinking_budget = true,
    };

    try std.testing.expect(shouldRectifyThinkingSignature(
        "a final `assistant` message must start with a thinking block",
        &config,
    ));
}

test "shouldRectifyThinkingSignature - no trigger for unrelated" {
    const config = RectifierConfig{
        .enabled = true,
        .request_thinking_signature = true,
        .request_thinking_budget = true,
    };

    try std.testing.expect(!shouldRectifyThinkingSignature("Request timeout", &config));
    try std.testing.expect(!shouldRectifyThinkingSignature("Connection refused", &config));
    try std.testing.expect(!shouldRectifyThinkingSignature(null, &config));
}

test "shouldRectifyThinkingSignature - detects signature field required" {
    const config = RectifierConfig{
        .enabled = true,
        .request_thinking_signature = true,
        .request_thinking_budget = true,
    };

    try std.testing.expect(shouldRectifyThinkingSignature(
        "***.***.***.***.***.signature: Field required",
        &config,
    ));
}

test "shouldRectifyThinkingSignature - detects signature extra inputs" {
    const config = RectifierConfig{
        .enabled = true,
        .request_thinking_signature = true,
        .request_thinking_budget = true,
    };

    try std.testing.expect(shouldRectifyThinkingSignature(
        "xxx.signature: Extra inputs are not permitted",
        &config,
    ));
}

test "shouldRectifyThinkingSignature - detects thinking cannot be modified" {
    const config = RectifierConfig{
        .enabled = true,
        .request_thinking_signature = true,
        .request_thinking_budget = true,
    };

    try std.testing.expect(shouldRectifyThinkingSignature(
        "thinking or redacted_thinking blocks in the response cannot be modified",
        &config,
    ));
}

test "shouldRectifyThinkingSignature - detects invalid request" {
    const config = RectifierConfig{
        .enabled = true,
        .request_thinking_signature = true,
        .request_thinking_budget = true,
    };

    try std.testing.expect(shouldRectifyThinkingSignature(
        "非法请求：thinking signature 不合法",
        &config,
    ));
    try std.testing.expect(shouldRectifyThinkingSignature(
        "illegal request: tool_use block mismatch",
        &config,
    ));
    try std.testing.expect(shouldRectifyThinkingSignature(
        "invalid request: malformed JSON",
        &config,
    ));
}

test "shouldRectifyThinkingSignature - does not detect adaptive tag mismatch" {
    const config = RectifierConfig{
        .enabled = true,
        .request_thinking_signature = true,
        .request_thinking_budget = true,
    };

    try std.testing.expect(!shouldRectifyThinkingSignature(
        "Input tag 'adaptive' found using 'type' does not match expected tags",
        &config,
    ));
}

test "shouldRectifyThinkingSignature - disabled config" {
    const config = RectifierConfig{
        .enabled = true,
        .request_thinking_signature = false,
        .request_thinking_budget = true,
    };

    try std.testing.expect(!shouldRectifyThinkingSignature(
        "Invalid `signature` in `thinking` block",
        &config,
    ));
}

test "shouldRectifyThinkingSignature - master disabled" {
    const config = RectifierConfig{
        .enabled = false,
        .request_thinking_signature = true,
        .request_thinking_budget = true,
    };

    try std.testing.expect(!shouldRectifyThinkingSignature(
        "Invalid `signature` in `thinking` block",
        &config,
    ));
}

test "rectifyAnthropicRequest - removes thinking blocks" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "claude-test" });

    var msgs_arr = std.json.Array.init(allocator);
    var assistant_msg = std.json.ObjectMap.init(allocator);
    try assistant_msg.put("role", json.Value{ .string = "assistant" });

    var content_arr = std.json.Array.init(allocator);

    // thinking block with signature
    var thinking_block = std.json.ObjectMap.init(allocator);
    try thinking_block.put("type", json.Value{ .string = "thinking" });
    try thinking_block.put("thinking", json.Value{ .string = "t" });
    try thinking_block.put("signature", json.Value{ .string = "sig" });
    try content_arr.append(json.Value{ .object = thinking_block });

    // text block with signature
    var text_block = std.json.ObjectMap.init(allocator);
    try text_block.put("type", json.Value{ .string = "text" });
    try text_block.put("text", json.Value{ .string = "hello" });
    try text_block.put("signature", json.Value{ .string = "sig_text" });
    try content_arr.append(json.Value{ .object = text_block });

    // tool_use block with signature
    var tool_block = std.json.ObjectMap.init(allocator);
    try tool_block.put("type", json.Value{ .string = "tool_use" });
    try tool_block.put("id", json.Value{ .string = "toolu_1" });
    try tool_block.put("name", json.Value{ .string = "WebSearch" });
    try tool_block.put("input", json.Value{ .object = std.json.ObjectMap.init(allocator) });
    try tool_block.put("signature", json.Value{ .string = "sig_tool" });
    try content_arr.append(json.Value{ .object = tool_block });

    // redacted_thinking block with signature
    var redacted_block = std.json.ObjectMap.init(allocator);
    try redacted_block.put("type", json.Value{ .string = "redacted_thinking" });
    try redacted_block.put("data", json.Value{ .string = "r" });
    try redacted_block.put("signature", json.Value{ .string = "sig_redacted" });
    try content_arr.append(json.Value{ .object = redacted_block });

    try assistant_msg.put("content", json.Value{ .array = content_arr });
    try msgs_arr.append(json.Value{ .object = assistant_msg });
    try body.object.put("messages", json.Value{ .array = msgs_arr });

    const result = rectifyAnthropicRequest(&body);

    try std.testing.expect(result.applied);
    try std.testing.expectEqual(@as(usize, 1), result.removed_thinking_blocks);
    try std.testing.expectEqual(@as(usize, 1), result.removed_redacted_thinking_blocks);
    try std.testing.expectEqual(@as(usize, 2), result.removed_signature_fields);

    const msgs = body.object.get("messages").?;
    const content = msgs.array.items[0].object.get("content").?;
    try std.testing.expectEqual(@as(usize, 2), content.array.items.len);
    try std.testing.expectEqual(json.Value{ .string = "text" }, content.array.items[0].object.get("type").?.*);
    try std.testing.expect(content.array.items[0].object.get("signature") == null);
    try std.testing.expectEqual(json.Value{ .string = "tool_use" }, content.array.items[1].object.get("type").?.*);
    try std.testing.expect(content.array.items[1].object.get("signature") == null);
}

test "rectifyAnthropicRequest - removes top level thinking" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "claude-test" });

    var thinking_map = std.json.ObjectMap.init(allocator);
    try thinking_map.put("type", json.Value{ .string = "enabled" });
    try thinking_map.put("budget_tokens", json.Value{ .number = 1024 });
    try body.object.put("thinking", json.Value{ .object = thinking_map });

    var msgs_arr = std.json.Array.init(allocator);

    // assistant message with tool_use
    var assistant_msg = std.json.ObjectMap.init(allocator);
    try assistant_msg.put("role", json.Value{ .string = "assistant" });
    var assistant_content = std.json.Array.init(allocator);
    var tool_block = std.json.ObjectMap.init(allocator);
    try tool_block.put("type", json.Value{ .string = "tool_use" });
    try tool_block.put("id", json.Value{ .string = "toolu_1" });
    try tool_block.put("name", json.Value{ .string = "WebSearch" });
    try tool_block.put("input", json.Value{ .object = std.json.ObjectMap.init(allocator) });
    try assistant_content.append(json.Value{ .object = tool_block });
    try assistant_msg.put("content", json.Value{ .array = assistant_content });
    try msgs_arr.append(json.Value{ .object = assistant_msg });

    // user message with tool_result
    var user_msg = std.json.ObjectMap.init(allocator);
    try user_msg.put("role", json.Value{ .string = "user" });
    var user_content = std.json.Array.init(allocator);
    var result_block = std.json.ObjectMap.init(allocator);
    try result_block.put("type", json.Value{ .string = "tool_result" });
    try result_block.put("tool_use_id", json.Value{ .string = "toolu_1" });
    try result_block.put("content", json.Value{ .string = "ok" });
    try user_content.append(json.Value{ .object = result_block });
    try user_msg.put("content", json.Value{ .array = user_content });
    try msgs_arr.append(json.Value{ .object = user_msg });

    try body.object.put("messages", json.Value{ .array = msgs_arr });

    const result = rectifyAnthropicRequest(&body);

    try std.testing.expect(result.applied);
    try std.testing.expect(body.object.get("thinking") == null);
}

test "rectifyAnthropicRequest - no change when no issues" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "claude-test" });

    var msgs_arr = std.json.Array.init(allocator);
    var user_msg = std.json.ObjectMap.init(allocator);
    try user_msg.put("role", json.Value{ .string = "user" });
    var content_arr = std.json.Array.init(allocator);
    var text_block = std.json.ObjectMap.init(allocator);
    try text_block.put("type", json.Value{ .string = "text" });
    try text_block.put("text", json.Value{ .string = "hello" });
    try content_arr.append(json.Value{ .object = text_block });
    try user_msg.put("content", json.Value{ .array = content_arr });
    try msgs_arr.append(json.Value{ .object = user_msg });
    try body.object.put("messages", json.Value{ .array = msgs_arr });

    const result = rectifyAnthropicRequest(&body);

    try std.testing.expect(!result.applied);
    try std.testing.expectEqual(@as(usize, 0), result.removed_thinking_blocks);
}

test "rectifyAnthropicRequest - no messages" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "claude-test" });

    const result = rectifyAnthropicRequest(&body);

    try std.testing.expect(!result.applied);
}

test "rectifyAnthropicRequest - keeps adaptive when no legacy blocks" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "claude-test" });

    var thinking_map = std.json.ObjectMap.init(allocator);
    try thinking_map.put("type", json.Value{ .string = "adaptive" });
    try body.object.put("thinking", json.Value{ .object = thinking_map });

    var msgs_arr = std.json.Array.init(allocator);
    var user_msg = std.json.ObjectMap.init(allocator);
    try user_msg.put("role", json.Value{ .string = "user" });
    var content_arr = std.json.Array.init(allocator);
    var text_block = std.json.ObjectMap.init(allocator);
    try text_block.put("type", json.Value{ .string = "text" });
    try text_block.put("text", json.Value{ .string = "hello" });
    try content_arr.append(json.Value{ .object = text_block });
    try user_msg.put("content", json.Value{ .array = content_arr });
    try msgs_arr.append(json.Value{ .object = user_msg });
    try body.object.put("messages", json.Value{ .array = msgs_arr });

    const result = rectifyAnthropicRequest(&body);

    try std.testing.expect(!result.applied);
    try std.testing.expectEqual(json.Value{ .string = "adaptive" }, body.object.get("thinking").?.object.get("type").?.*);
    try std.testing.expect(body.object.get("thinking").?.object.get("budget_tokens") == null);
}

test "rectifyAnthropicRequest - preserves existing budget_tokens with adaptive" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "claude-test" });

    var thinking_map = std.json.ObjectMap.init(allocator);
    try thinking_map.put("type", json.Value{ .string = "adaptive" });
    try thinking_map.put("budget_tokens", json.Value{ .number = 5000 });
    try body.object.put("thinking", json.Value{ .object = thinking_map });

    var msgs_arr = std.json.Array.init(allocator);
    var user_msg = std.json.ObjectMap.init(allocator);
    try user_msg.put("role", json.Value{ .string = "user" });
    var content_arr = std.json.Array.init(allocator);
    var text_block = std.json.ObjectMap.init(allocator);
    try text_block.put("type", json.Value{ .string = "text" });
    try text_block.put("text", json.Value{ .string = "hello" });
    try content_arr.append(json.Value{ .object = text_block });
    try user_msg.put("content", json.Value{ .array = content_arr });
    try msgs_arr.append(json.Value{ .object = user_msg });
    try body.object.put("messages", json.Value{ .array = msgs_arr });

    const result = rectifyAnthropicRequest(&body);

    try std.testing.expect(!result.applied);
    try std.testing.expectEqual(json.Value{ .string = "adaptive" }, body.object.get("thinking").?.object.get("type").?.*);
    try std.testing.expectEqual(json.Value{ .number = 5000 }, body.object.get("thinking").?.object.get("budget_tokens").?.*);
}

test "rectifyAnthropicRequest - does not change enabled type" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "claude-test" });

    var thinking_map = std.json.ObjectMap.init(allocator);
    try thinking_map.put("type", json.Value{ .string = "enabled" });
    try thinking_map.put("budget_tokens", json.Value{ .number = 1024 });
    try body.object.put("thinking", json.Value{ .object = thinking_map });

    var msgs_arr = std.json.Array.init(allocator);
    var user_msg = std.json.ObjectMap.init(allocator);
    try user_msg.put("role", json.Value{ .string = "user" });
    var content_arr = std.json.Array.init(allocator);
    var text_block = std.json.ObjectMap.init(allocator);
    try text_block.put("type", json.Value{ .string = "text" });
    try text_block.put("text", json.Value{ .string = "hello" });
    try content_arr.append(json.Value{ .object = text_block });
    try user_msg.put("content", json.Value{ .array = content_arr });
    try msgs_arr.append(json.Value{ .object = user_msg });
    try body.object.put("messages", json.Value{ .array = msgs_arr });

    const result = rectifyAnthropicRequest(&body);

    try std.testing.expect(!result.applied);
    try std.testing.expectEqual(json.Value{ .string = "enabled" }, body.object.get("thinking").?.object.get("type").?.*);
}

test "rectifyAnthropicRequest - adaptive still cleans signature blocks" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "claude-test" });

    var thinking_map = std.json.ObjectMap.init(allocator);
    try thinking_map.put("type", json.Value{ .string = "adaptive" });
    try body.object.put("thinking", json.Value{ .object = thinking_map });

    var msgs_arr = std.json.Array.init(allocator);
    var assistant_msg = std.json.ObjectMap.init(allocator);
    try assistant_msg.put("role", json.Value{ .string = "assistant" });
    var content_arr = std.json.Array.init(allocator);

    // thinking block with signature
    var thinking_block = std.json.ObjectMap.init(allocator);
    try thinking_block.put("type", json.Value{ .string = "thinking" });
    try thinking_block.put("thinking", json.Value{ .string = "t" });
    try thinking_block.put("signature", json.Value{ .string = "sig_thinking" });
    try content_arr.append(json.Value{ .object = thinking_block });

    // text block with signature
    var text_block = std.json.ObjectMap.init(allocator);
    try text_block.put("type", json.Value{ .string = "text" });
    try text_block.put("text", json.Value{ .string = "hello" });
    try text_block.put("signature", json.Value{ .string = "sig_text" });
    try content_arr.append(json.Value{ .object = text_block });

    try assistant_msg.put("content", json.Value{ .array = content_arr });
    try msgs_arr.append(json.Value{ .object = assistant_msg });
    try body.object.put("messages", json.Value{ .array = msgs_arr });

    const result = rectifyAnthropicRequest(&body);

    try std.testing.expect(result.applied);
    try std.testing.expectEqual(@as(usize, 1), result.removed_thinking_blocks);
    const msgs = body.object.get("messages").?;
    const content = msgs.array.items[0].object.get("content").?;
    try std.testing.expectEqual(@as(usize, 1), content.array.items.len);
    try std.testing.expectEqual(json.Value{ .string = "text" }, content.array.items[0].object.get("type").?.*);
    try std.testing.expect(content.array.items[0].object.get("signature") == null);
    try std.testing.expectEqual(json.Value{ .string = "adaptive" }, body.object.get("thinking").?.object.get("type").?.*);
}

test "normalizeThinkingType - adaptive unchanged" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "claude-test" });
    var thinking_map = std.json.ObjectMap.init(allocator);
    try thinking_map.put("type", json.Value{ .string = "adaptive" });
    try body.object.put("thinking", json.Value{ .object = thinking_map });

    const result = normalizeThinkingType(body);

    try std.testing.expectEqual(json.Value{ .string = "adaptive" }, result.object.get("thinking").?.object.get("type").?.*);
    try std.testing.expect(result.object.get("thinking").?.object.get("budget_tokens") == null);
}

test "normalizeThinkingType - enabled unchanged" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "claude-test" });
    var thinking_map = std.json.ObjectMap.init(allocator);
    try thinking_map.put("type", json.Value{ .string = "enabled" });
    try thinking_map.put("budget_tokens", json.Value{ .number = 2048 });
    try body.object.put("thinking", json.Value{ .object = thinking_map });

    const result = normalizeThinkingType(body);

    try std.testing.expectEqual(json.Value{ .string = "enabled" }, result.object.get("thinking").?.object.get("type").?.*);
    try std.testing.expectEqual(json.Value{ .number = 2048 }, result.object.get("thinking").?.object.get("budget_tokens").?.*);
}

test "normalizeThinkingType - no thinking unchanged" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "claude-test" });

    const result = normalizeThinkingType(body);

    try std.testing.expect(result.object.get("thinking") == null);
}
