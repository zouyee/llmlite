//! Cache Injector for llmlite Proxy
//!
//! Automatically injects cache_control breakpoints to enable Bedrock Prompt Caching.
//!
//! Injects at three key locations (budget of 4):
//! (a) Last tool in tools array
//! (b) Last block in system array
//! (c) Last non-thinking block in last assistant message

const std = @import("std");
const json = std.json;

pub const OptimizerConfig = struct {
    enabled: bool = false,
    thinking_optimizer: bool = true,
    cache_injection: bool = true,
    cache_ttl: []const u8 = "1h",
};

/// Inject cache_control breakpoints into request body for Bedrock Prompt Caching
pub fn inject(body: *json.Value, config: *const OptimizerConfig) void {
    if (!config.enabled or !config.cache_injection) return;

    const existing = countExisting(body);

    // Upgrade existing TTLs
    upgradeExistingTtl(body, config.cache_ttl);

    var budget: usize = 4;
    if (budget <= existing) {
        return; // No room for new injections
    }
    budget = budget -| existing;

    // (a) tools last element
    if (budget > 0) {
        if (injectToToolsLast(body, config.cache_ttl)) {
            budget -= 1;
        }
    }

    // (b) system last element
    if (budget > 0) {
        if (injectToSystemLast(body, config.cache_ttl)) {
            budget -= 1;
        }
    }

    // (c) last assistant message last non-thinking block
    if (budget > 0) {
        if (injectToAssistantLast(body, config.cache_ttl)) {
            _ = budget -| 1;
        }
    }
}

fn makeCacheControl(allocator: std.mem.Allocator, ttl: []const u8) !json.Value {
    var obj = std.json.ObjectMap.init(allocator);
    try obj.put("type", json.Value{ .string = "ephemeral" });
    if (!std.mem.eql(u8, ttl, "5m")) {
        try obj.put("ttl", json.Value{ .string = ttl });
    }
    return json.Value{ .object = obj };
}

fn countExisting(body: *const json.Value) usize {
    var count: usize = 0;

    // Count in tools
    if (body.object.get("tools")) |tools| {
        if (tools == .array) {
            for (tools.array.items) |tool| {
                if (tool.object.get("cache_control")) |_| {
                    count += 1;
                }
            }
        }
    }

    // Count in system
    if (body.object.get("system")) |system| {
        if (system == .array) {
            for (system.array.items) |block| {
                if (block.object.get("cache_control")) |_| {
                    count += 1;
                }
            }
        }
    }

    // Count in messages
    if (body.object.get("messages")) |messages| {
        if (messages == .array) {
            for (messages.array.items) |msg| {
                if (msg.object.get("content")) |content| {
                    if (content == .array) {
                        for (content.array.items) |block| {
                            if (block.object.get("cache_control")) |_| {
                                count += 1;
                            }
                        }
                    }
                }
            }
        }
    }

    return count;
}

fn upgradeExistingTtl(body: *json.Value, ttl: []const u8) void {
    if (!std.mem.eql(u8, ttl, "5m")) {
        // Upgrade TTL on all existing cache_control fields
        upgradeTtlInTools(body, ttl);
        upgradeTtlInSystem(body, ttl);
        upgradeTtlInMessages(body, ttl);
    } else {
        // For 5m, remove ttl field
        removeTtlInTools(body);
        removeTtlInSystem(body);
        removeTtlInMessages(body);
    }
}

fn upgradeTtlInTools(body: *json.Value, ttl: []const u8) void {
    if (body.object.getPtr("tools")) |tools| {
        if (tools.* == .array) {
            for (tools.array.items) |*tool| {
                upgradeTtlInObject(tool, ttl);
            }
        }
    }
}

fn upgradeTtlInSystem(body: *json.Value, ttl: []const u8) void {
    if (body.object.getPtr("system")) |system| {
        if (system.* == .array) {
            for (system.array.items) |*block| {
                upgradeTtlInObject(block, ttl);
            }
        }
    }
}

fn upgradeTtlInMessages(body: *json.Value, ttl: []const u8) void {
    if (body.object.getPtr("messages")) |messages| {
        if (messages.* == .array) {
            for (messages.array.items) |*msg| {
                if (msg.object.getPtr("content")) |content| {
                    if (content.* == .array) {
                        for (content.array.items) |*block| {
                            upgradeTtlInObject(block, ttl);
                        }
                    }
                }
            }
        }
    }
}

fn upgradeTtlInObject(obj: *json.Value, ttl: []const u8) void {
    if (obj.object.getPtr("cache_control")) |cc| {
        if (cc.* == .object) {
            cc.object.put("ttl", json.Value{ .string = ttl }) catch return;
        }
    }
}

fn removeTtlInTools(body: *json.Value) void {
    if (body.object.getPtr("tools")) |tools| {
        if (tools.* == .array) {
            for (tools.array.items) |*tool| {
                removeTtlInObject(tool);
            }
        }
    }
}

fn removeTtlInSystem(body: *json.Value) void {
    if (body.object.getPtr("system")) |system| {
        if (system.* == .array) {
            for (system.array.items) |*block| {
                removeTtlInObject(block);
            }
        }
    }
}

fn removeTtlInMessages(body: *json.Value) void {
    if (body.object.getPtr("messages")) |messages| {
        if (messages.* == .array) {
            for (messages.array.items) |*msg| {
                if (msg.object.getPtr("content")) |content| {
                    if (content.* == .array) {
                        for (content.array.items) |*block| {
                            removeTtlInObject(block);
                        }
                    }
                }
            }
        }
    }
}

fn removeTtlInObject(obj: *json.Value) void {
    if (obj.object.getPtr("cache_control")) |cc| {
        if (cc.* == .object) {
            _ = cc.object.remove("ttl");
        }
    }
}

fn injectToToolsLast(body: *json.Value, ttl: []const u8) bool {
    const tools = body.object.getPtr("tools") orelse return false;
    if (tools.* != .array) return false;
    if (tools.array.items.len == 0) return false;

    const last = &tools.array.items[tools.array.items.len - 1];
    if (last.object.get("cache_control")) |_| {
        return false; // Already has cache_control
    }

    const allocator = std.heap.page_allocator;
    const cc = makeCacheControl(allocator, ttl) catch return false;
    last.object.put("cache_control", cc) catch return false;
    return true;
}

fn injectToSystemLast(body: *json.Value, ttl: []const u8) bool {
    const system = body.object.getPtr("system") orelse return false;

    // If system is a string, convert to array
    if (system.* == .string) {
        const text = system.string;
        const allocator = std.heap.page_allocator;
        var arr = std.json.Array.init(allocator);
        var block_map = std.json.ObjectMap.init(allocator);
        block_map.put("type", json.Value{ .string = "text" }) catch return false;
        block_map.put("text", json.Value{ .string = text }) catch return false;
        arr.append(json.Value{ .object = block_map }) catch return false;

        const cc = makeCacheControl(allocator, ttl) catch return false;
        arr.items[0].object.put("cache_control", cc) catch return false;

        body.object.put("system", json.Value{ .array = arr }) catch return false;
        return true;
    }

    if (system.* != .array) return false;
    if (system.array.items.len == 0) return false;

    const last = &system.array.items[system.array.items.len - 1];
    if (last.object.get("cache_control")) |_| {
        return false;
    }

    const allocator = std.heap.page_allocator;
    const cc = makeCacheControl(allocator, ttl) catch return false;
    last.object.put("cache_control", cc) catch return false;
    return true;
}

fn injectToAssistantLast(body: *json.Value, ttl: []const u8) bool {
    const messages = body.object.getPtr("messages") orelse return false;
    if (messages.* != .array) return false;
    if (messages.array.items.len == 0) return false;

    // Find last assistant message (iterate in reverse)
    var assistant_msg: *json.Value = null;
    for (messages.array.items[0..messages.array.items.len]) |*msg| {
        if (msg.object.get("role")) |role| {
            if (role == .string and std.mem.eql(u8, role.string, "assistant")) {
                assistant_msg = msg;
            }
        }
    }
    if (assistant_msg == null) return false;

    const content = assistant_msg.object.getPtr("content") orelse return false;
    if (content.* != .array) return false;
    if (content.array.items.len == 0) return false;

    // Find last non-thinking block (iterate in reverse)
    var target_block: ?*json.Value = null;
    for (content.array.items[0..content.array.items.len]) |*block| {
        const block_type = block.object.get("type") orelse continue;
        if (block_type != .string) continue;
        if (std.mem.eql(u8, block_type.string, "thinking")) continue;
        if (std.mem.eql(u8, block_type.string, "redacted_thinking")) continue;
        target_block = block;
    }

    const target = target_block orelse return false;
    if (target.object.get("cache_control")) |_| {
        return false;
    }

    const allocator = std.heap.page_allocator;
    const cc = makeCacheControl(allocator, ttl) catch return false;
    target.object.put("cache_control", cc) catch return false;
    return true;
}

// ============================================================================
// TESTS
// ============================================================================

test "inject - empty body no injection" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "test" });
    try body.object.put("messages", json.Value{
        .array = blk: {
            var arr = std.json.Array.init(allocator);
            var msg_map = std.json.ObjectMap.init(allocator);
            try msg_map.put("role", json.Value{ .string = "user" });
            var content_arr = std.json.Array.init(allocator);
            var content_map = std.json.ObjectMap.init(allocator);
            try content_map.put("type", json.Value{ .string = "text" });
            try content_map.put("text", json.Value{ .string = "hi" });
            try content_arr.append(json.Value{ .object = content_map });
            try msg_map.put("content", json.Value{ .array = content_arr });
            try arr.append(json.Value{ .object = msg_map });
            break :blk arr;
        },
    });

    const config = OptimizerConfig{ .enabled = true, .cache_injection = true, .cache_ttl = "1h" };
    const original_count = countExisting(&body);
    inject(&body, &config);

    // No tools, no system, no assistant → no injection
    try std.testing.expectEqual(original_count, countExisting(&body));
}

test "inject - three breakpoints" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    // tools
    var tools_arr = std.json.Array.init(allocator);
    var tool1 = std.json.ObjectMap.init(allocator);
    try tool1.put("name", json.Value{ .string = "tool1" });
    var tool2 = std.json.ObjectMap.init(allocator);
    try tool2.put("name", json.Value{ .string = "tool2" });
    try tools_arr.append(json.Value{ .object = tool1 });
    try tools_arr.append(json.Value{ .object = tool2 });
    try body.object.put("tools", json.Value{ .array = tools_arr });

    // system
    var sys_arr = std.json.Array.init(allocator);
    var sys_block = std.json.ObjectMap.init(allocator);
    try sys_block.put("type", json.Value{ .string = "text" });
    try sys_block.put("text", json.Value{ .string = "sys prompt" });
    try sys_arr.append(json.Value{ .object = sys_block });
    try body.object.put("system", json.Value{ .array = sys_arr });

    // messages
    var msgs_arr = std.json.Array.init(allocator);
    var user_msg = std.json.ObjectMap.init(allocator);
    try user_msg.put("role", json.Value{ .string = "user" });
    var user_content = std.json.Array.init(allocator);
    var user_text = std.json.ObjectMap.init(allocator);
    try user_text.put("type", json.Value{ .string = "text" });
    try user_text.put("text", json.Value{ .string = "hi" });
    try user_content.append(json.Value{ .object = user_text });
    try user_msg.put("content", json.Value{ .array = user_content });
    try msgs_arr.append(json.Value{ .object = user_msg });

    var assistant_msg = std.json.ObjectMap.init(allocator);
    try assistant_msg.put("role", json.Value{ .string = "assistant" });
    var assistant_content = std.json.Array.init(allocator);
    var assistant_text = std.json.ObjectMap.init(allocator);
    try assistant_text.put("type", json.Value{ .string = "text" });
    try assistant_text.put("text", json.Value{ .string = "hello" });
    try assistant_content.append(json.Value{ .object = assistant_text });
    try assistant_msg.put("content", json.Value{ .array = assistant_content });
    try msgs_arr.append(json.Value{ .object = assistant_msg });

    try body.object.put("messages", json.Value{ .array = msgs_arr });

    const config = OptimizerConfig{ .enabled = true, .cache_injection = true, .cache_ttl = "1h" };
    inject(&body, &config);

    // tools last element
    const tools = body.object.get("tools").?;
    try std.testing.expect(tools.array.items[1].object.get("cache_control") != null);
    const tool_cc = tools.array.items[1].object.get("cache_control").?;
    try std.testing.expectEqual(json.Value{ .string = "1h" }, tool_cc.object.get("ttl").?.*);

    // system last element
    const system = body.object.get("system").?;
    try std.testing.expect(system.array.items[0].object.get("cache_control") != null);

    // assistant last non-thinking block
    const msgs = body.object.get("messages").?;
    const assistant = msgs.array.items[1].object.get("content").?;
    try std.testing.expect(assistant.array.items[0].object.get("cache_control") != null);
}

test "inject - existing four breakpoints only upgrades ttl" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    // tools with cache_control
    var tools_arr = std.json.Array.init(allocator);
    var tool1 = std.json.ObjectMap.init(allocator);
    try tool1.put("name", json.Value{ .string = "t1" });
    var cc1 = std.json.ObjectMap.init(allocator);
    try cc1.put("type", json.Value{ .string = "ephemeral" });
    try cc1.put("ttl", json.Value{ .string = "5m" });
    try tool1.put("cache_control", json.Value{ .object = cc1 });

    var tool2 = std.json.ObjectMap.init(allocator);
    try tool2.put("name", json.Value{ .string = "t2" });
    var cc2 = std.json.ObjectMap.init(allocator);
    try cc2.put("type", json.Value{ .string = "ephemeral" });
    try cc2.put("ttl", json.Value{ .string = "5m" });
    try tool2.put("cache_control", json.Value{ .object = cc2 });

    try tools_arr.append(json.Value{ .object = tool1 });
    try tools_arr.append(json.Value{ .object = tool2 });
    try body.object.put("tools", json.Value{ .array = tools_arr });

    // system with cache_control
    var sys_arr = std.json.Array.init(allocator);
    var sys_block = std.json.ObjectMap.init(allocator);
    try sys_block.put("type", json.Value{ .string = "text" });
    try sys_block.put("text", json.Value{ .string = "sys" });
    var sys_cc = std.json.ObjectMap.init(allocator);
    try sys_cc.put("type", json.Value{ .string = "ephemeral" });
    try sys_cc.put("ttl", json.Value{ .string = "5m" });
    try sys_block.put("cache_control", json.Value{ .object = sys_cc });
    try sys_arr.append(json.Value{ .object = sys_block });
    try body.object.put("system", json.Value{ .array = sys_arr });

    // messages with cache_control
    var msgs_arr = std.json.Array.init(allocator);
    var assistant_msg = std.json.ObjectMap.init(allocator);
    try assistant_msg.put("role", json.Value{ .string = "assistant" });
    var assistant_content = std.json.Array.init(allocator);
    var msg_block = std.json.ObjectMap.init(allocator);
    try msg_block.put("type", json.Value{ .string = "text" });
    try msg_block.put("text", json.Value{ .string = "ok" });
    var msg_cc = std.json.ObjectMap.init(allocator);
    try msg_cc.put("type", json.Value{ .string = "ephemeral" });
    try msg_cc.put("ttl", json.Value{ .string = "5m" });
    try msg_block.put("cache_control", json.Value{ .object = msg_cc });
    try assistant_content.append(json.Value{ .object = msg_block });
    try assistant_msg.put("content", json.Value{ .array = assistant_content });
    try msgs_arr.append(json.Value{ .object = assistant_msg });
    try body.object.put("messages", json.Value{ .array = msgs_arr });

    const config = OptimizerConfig{ .enabled = true, .cache_injection = true, .cache_ttl = "1h" };
    inject(&body, &config);

    // All TTLs upgraded to 1h, no new breakpoints
    const tools = body.object.get("tools").?;
    try std.testing.expectEqual(json.Value{ .string = "1h" }, tools.array.items[0].object.get("cache_control").?.object.get("ttl").?.*);
    try std.testing.expectEqual(json.Value{ .string = "1h" }, tools.array.items[1].object.get("cache_control").?.object.get("ttl").?.*);

    const system = body.object.get("system").?;
    try std.testing.expectEqual(json.Value{ .string = "1h" }, system.array.items[0].object.get("cache_control").?.object.get("ttl").?.*);

    const msgs = body.object.get("messages").?;
    const content = msgs.array.items[0].object.get("content").?;
    try std.testing.expectEqual(json.Value{ .string = "1h" }, content.array.items[0].object.get("cache_control").?.object.get("ttl").?.*);
}

test "inject - system string converted to array" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "test" });
    try body.object.put("system", json.Value{ .string = "You are a helpful assistant" });

    var msgs_arr = std.json.Array.init(allocator);
    var user_msg = std.json.ObjectMap.init(allocator);
    try user_msg.put("role", json.Value{ .string = "user" });
    var content_arr = std.json.Array.init(allocator);
    var text_block = std.json.ObjectMap.init(allocator);
    try text_block.put("type", json.Value{ .string = "text" });
    try text_block.put("text", json.Value{ .string = "hi" });
    try content_arr.append(json.Value{ .object = text_block });
    try user_msg.put("content", json.Value{ .array = content_arr });
    try msgs_arr.append(json.Value{ .object = user_msg });
    try body.object.put("messages", json.Value{ .array = msgs_arr });

    const config = OptimizerConfig{ .enabled = true, .cache_injection = true, .cache_ttl = "1h" };
    inject(&body, &config);

    // System should be converted to array
    const system = body.object.get("system").?;
    try std.testing.expect(system == .array);
    try std.testing.expectEqual(@as(usize, 1), system.array.items.len);
    try std.testing.expectEqual(json.Value{ .string = "text" }, system.array.items[0].object.get("type").?.*);
    try std.testing.expectEqual(json.Value{ .string = "You are a helpful assistant" }, system.array.items[0].object.get("text").?.*);
    try std.testing.expect(system.array.items[0].object.get("cache_control") != null);
}

test "inject - skip thinking blocks in assistant" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    var msgs_arr = std.json.Array.init(allocator);
    var assistant_msg = std.json.ObjectMap.init(allocator);
    try assistant_msg.put("role", json.Value{ .string = "assistant" });

    var assistant_content = std.json.Array.init(allocator);

    // thinking block
    var thinking_block = std.json.ObjectMap.init(allocator);
    try thinking_block.put("type", json.Value{ .string = "thinking" });
    try thinking_block.put("thinking", json.Value{ .string = "hmm" });
    try assistant_content.append(json.Value{ .object = thinking_block });

    // text block (should get cache_control)
    var text_block = std.json.ObjectMap.init(allocator);
    try text_block.put("type", json.Value{ .string = "text" });
    try text_block.put("text", json.Value{ .string = "result" });
    try assistant_content.append(json.Value{ .object = text_block });

    // redacted_thinking block
    var redacted_block = std.json.ObjectMap.init(allocator);
    try redacted_block.put("type", json.Value{ .string = "redacted_thinking" });
    try redacted_block.put("data", json.Value{ .string = "xxx" });
    try assistant_content.append(json.Value{ .object = redacted_block });

    try assistant_msg.put("content", json.Value{ .array = assistant_content });
    try msgs_arr.append(json.Value{ .object = assistant_msg });
    try body.object.put("messages", json.Value{ .array = msgs_arr });

    const config = OptimizerConfig{ .enabled = true, .cache_injection = true, .cache_ttl = "1h" };
    inject(&body, &config);

    // Should inject on text block, not thinking/redacted_thinking
    const msgs = body.object.get("messages").?;
    const content = msgs.array.items[0].object.get("content").?;

    // text block (index 1) should have cache_control
    try std.testing.expect(content.array.items[1].object.get("cache_control") != null);

    // thinking block (index 0) should NOT
    try std.testing.expect(content.array.items[0].object.get("cache_control") == null);

    // redacted_thinking block (index 2) should NOT
    try std.testing.expect(content.array.items[2].object.get("cache_control") == null);
}

test "inject - disabled no change" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    // tools
    var tools_arr = std.json.Array.init(allocator);
    var tool1 = std.json.ObjectMap.init(allocator);
    try tool1.put("name", json.Value{ .string = "tool1" });
    try tools_arr.append(json.Value{ .object = tool1 });
    try body.object.put("tools", json.Value{ .array = tools_arr });

    // system
    var sys_arr = std.json.Array.init(allocator);
    var sys_block = std.json.ObjectMap.init(allocator);
    try sys_block.put("type", json.Value{ .string = "text" });
    try sys_block.put("text", json.Value{ .string = "sys" });
    try sys_arr.append(json.Value{ .object = sys_block });
    try body.object.put("system", json.Value{ .array = sys_arr });

    // messages
    var msgs_arr = std.json.Array.init(allocator);
    var assistant_msg = std.json.ObjectMap.init(allocator);
    try assistant_msg.put("role", json.Value{ .string = "assistant" });
    var assistant_content = std.json.Array.init(allocator);
    var msg_text = std.json.ObjectMap.init(allocator);
    try msg_text.put("type", json.Value{ .string = "text" });
    try msg_text.put("text", json.Value{ .string = "ok" });
    try assistant_content.append(json.Value{ .object = msg_text });
    try assistant_msg.put("content", json.Value{ .array = assistant_content });
    try msgs_arr.append(json.Value{ .object = assistant_msg });
    try body.object.put("messages", json.Value{ .array = msgs_arr });

    // Store original JSON for comparison
    const original = try json.stringifyAlloc(allocator, body);
    defer allocator.free(original);

    const config = OptimizerConfig{ .enabled = true, .cache_injection = false, .cache_ttl = "1h" };
    inject(&body, &config);

    const after = try json.stringifyAlloc(allocator, body);
    defer allocator.free(after);

    try std.testing.expectEqualSlices(u8, original, after);
}
