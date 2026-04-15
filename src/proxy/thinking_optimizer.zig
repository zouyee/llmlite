//! Thinking Optimizer for llmlite Proxy
//!
//! Automatically optimizes thinking config based on model type.
//!
//! Three-path routing:
//! - skip: haiku models skip thinking entirely
//! - adaptive: opus-4-6 / sonnet-4-6 use adaptive thinking with effort=max
//! - legacy: other models use enabled thinking with budget_tokens = max_tokens - 1

const std = @import("std");
const json = std.json;

pub const OptimizerConfig = struct {
    enabled: bool = false,
    thinking_optimizer: bool = true,
};

/// Optimize thinking configuration based on model type
///
/// Three-path routing:
/// - haiku -> skip (no modification)
/// - opus-4-6 / sonnet-4-6 -> adaptive thinking + output_config.effort=max
/// - legacy -> enabled thinking + budget_tokens = max_tokens - 1
pub fn optimize(body: *json.Value, config: *const OptimizerConfig) void {
    if (!config.enabled or !config.thinking_optimizer) return;

    const model = body.object.get("model") orelse return;
    const model_str = model.string orelse return;

    const lower_model = std.ascii.lowerString(model_str);

    // Skip: haiku models
    if (std.mem.containsAtLeast(u8, lower_model, 1, "haiku")) {
        return;
    }

    // Adaptive: opus-4-6 / sonnet-4-6
    if (std.mem.containsAtLeast(u8, lower_model, 1, "opus-4-6") or
        std.mem.containsAtLeast(u8, lower_model, 1, "sonnet-4-6"))
    {
        // Set thinking.type = "adaptive"
        if (body.object.getPtr("thinking")) |thinking| {
            thinking.object.put("type", json.Value{ .string = "adaptive" }) catch return;
            // Remove budget_tokens for adaptive
            _ = thinking.object.remove("budget_tokens");
        } else {
            const thinking_map = std.json.ObjectMap.init(std.heap.page_allocator);
            body.object.put("thinking", json.Value{ .object = thinking_map }) catch return;
            const t = body.object.getPtr("thinking") orelse return;
            t.object.put("type", json.Value{ .string = "adaptive" }) catch return;
        }

        // Set output_config.effort = "max"
        if (body.object.getPtr("output_config")) |output_config| {
            output_config.object.put("effort", json.Value{ .string = "max" }) catch return;
        } else {
            const output_map = std.json.ObjectMap.init(std.heap.page_allocator);
            body.object.put("output_config", json.Value{ .object = output_map }) catch return;
            const o = body.object.getPtr("output_config") orelse return;
            o.object.put("effort", json.Value{ .string = "max" }) catch return;
        }

        // Append beta header (deduplicated)
        appendBeta(body, "context-1m-2025-08-07");
        return;
    }

    // Legacy path: other models
    const max_tokens = body.object.get("max_tokens") orelse blk: {
        // Default max_tokens if not specified
        break :blk @as(u64, 16384);
    };
    const max_tokens_u64 = if (max_tokens.isNumber()) @as(u64, @intFromFloat(max_tokens.number)) else @as(u64, 16384);
    const budget_target = max_tokens_u64 -| 1; // saturating subtract

    const thinking_type = if (body.object.get("thinking")) |thinking|
        if (thinking.object.get("type")) |t|
            if (t.isString()) t.string else null
        else
            null
    else
        null;

    switch (thinking_type orelse .none) {
        .none, .null => {
            // No thinking block or null type -> inject enabled
            if (body.object.getPtr("thinking")) |thinking| {
                thinking.object.put("type", json.Value{ .string = "enabled" }) catch return;
                thinking.object.put("budget_tokens", json.Value{ .number = @floatFromInt(budget_target) }) catch return;
            } else {
                const thinking_map = std.json.ObjectMap.init(std.heap.page_allocator);
                body.object.put("thinking", json.Value{ .object = thinking_map }) catch return;
                const t = body.object.getPtr("thinking") orelse return;
                t.object.put("type", json.Value{ .string = "enabled" }) catch return;
                t.object.put("budget_tokens", json.Value{ .number = @floatFromInt(budget_target) }) catch return;
            }
        },
        .string => |t_str| {
            if (std.mem.eql(u8, t_str, "disabled")) {
                // disabled -> inject enabled
                if (body.object.getPtr("thinking")) |thinking| {
                    thinking.object.put("type", json.Value{ .string = "enabled" }) catch return;
                    thinking.object.put("budget_tokens", json.Value{ .number = @floatFromInt(budget_target) }) catch return;
                }
            } else if (std.mem.eql(u8, t_str, "enabled")) {
                // enabled -> check if budget too small
                if (body.object.getPtr("thinking")) |thinking| {
                    if (thinking.object.get("budget_tokens")) |bt| {
                        if (bt.isNumber()) {
                            const current_budget = @as(u64, @intFromFloat(bt.number));
                            if (current_budget < budget_target) {
                                thinking.object.put("budget_tokens", json.Value{ .number = @floatFromInt(budget_target) }) catch return;
                            }
                        }
                    }
                }
            }
        },
        else => {},
    }

    // Append beta header (deduplicated)
    appendBeta(body, "interleaved-thinking-2025-05-14");
}

/// Append beta identifier to anthropic_beta array (deduplicated)
fn appendBeta(body: *json.Value, beta: []const u8) void {
    const anthropic_beta = body.object.getPtr("anthropic_beta") orelse {
        // No anthropic_beta field -> create array with beta
        const arr = std.json.Array.init(std.heap.page_allocator);
        body.object.put("anthropic_beta", json.Value{ .array = arr }) catch return;
        const ab = body.object.getPtr("anthropic_beta") orelse return;
        ab.array.append(json.Value{ .string = beta }) catch return;
        return;
    };

    // If null, replace with array
    if (anthropic_beta.* == .null) {
        const arr = std.json.Array.init(std.heap.page_allocator);
        anthropic_beta.* = json.Value{ .array = arr };
        anthropic_beta.array.append(json.Value{ .string = beta }) catch return;
        return;
    }

    // If array, check for duplicates and append
    if (anthropic_beta.* == .array) {
        for (anthropic_beta.array.items) |item| {
            if (item == .string and std.mem.eql(u8, item.string, beta)) {
                return; // Already present, skip
            }
        }
        anthropic_beta.array.append(json.Value{ .string = beta }) catch return;
        return;
    }

    // Other cases (number, bool, etc.) -> replace with array
    const arr = std.json.Array.init(std.heap.page_allocator);
    anthropic_beta.* = json.Value{ .array = arr };
    anthropic_beta.array.append(json.Value{ .string = beta }) catch return;
}

// ============================================================================
// TESTS
// ============================================================================

test "optimize - skip haiku" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "anthropic.claude-haiku-4-5-20250514-v1:0" });
    try body.object.put("max_tokens", json.Value{ .number = 8192 });
    try body.object.put("messages", json.Value{ .array = std.json.Array.init(allocator) });

    const original_model = body.object.get("model").?;
    const original_max = body.object.get("max_tokens").?;

    const config = OptimizerConfig{ .enabled = true, .thinking_optimizer = true };
    optimize(&body, &config);

    // Should be unchanged
    try std.testing.expectEqual(original_model.string, body.object.get("model").?.string);
    try std.testing.expectEqual(original_max.number, body.object.get("max_tokens").?.number);
}

test "optimize - adaptive opus-4-6" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "anthropic.claude-opus-4-6-20250514-v1:0" });
    try body.object.put("max_tokens", json.Value{ .number = 16384 });
    try body.object.put("messages", json.Value{ .array = std.json.Array.init(allocator) });

    const config = OptimizerConfig{ .enabled = true, .thinking_optimizer = true };
    optimize(&body, &config);

    // Should have thinking.type = "adaptive"
    const thinking = body.object.get("thinking").?;
    try std.testing.expectEqual(json.Value{ .string = "adaptive" }, thinking.object.get("type").?.*);

    // Should have output_config.effort = "max"
    const output_config = body.object.get("output_config").?;
    try std.testing.expectEqual(json.Value{ .string = "max" }, output_config.object.get("effort").?.*);

    // Should have beta header
    const beta = body.object.get("anthropic_beta").?;
    try std.testing.expect(beta.array.items.len > 0);
}

test "optimize - adaptive sonnet-4-6" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "anthropic.claude-sonnet-4-6-20250514-v1:0" });
    try body.object.put("max_tokens", json.Value{ .number = 16384 });
    try body.object.put("messages", json.Value{ .array = std.json.Array.init(allocator) });

    const config = OptimizerConfig{ .enabled = true, .thinking_optimizer = true };
    optimize(&body, &config);

    // Should have thinking.type = "adaptive"
    const thinking = body.object.get("thinking").?;
    try std.testing.expectEqual(json.Value{ .string = "adaptive" }, thinking.object.get("type").?.*);
}

test "optimize - legacy sonnet-4-5 injects thinking" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "anthropic.claude-sonnet-4-5-20250514-v1:0" });
    try body.object.put("max_tokens", json.Value{ .number = 16384 });
    try body.object.put("messages", json.Value{ .array = std.json.Array.init(allocator) });

    const config = OptimizerConfig{ .enabled = true, .thinking_optimizer = true };
    optimize(&body, &config);

    // Should have thinking.type = "enabled"
    const thinking = body.object.get("thinking").?;
    try std.testing.expectEqual(json.Value{ .string = "enabled" }, thinking.object.get("type").?.*);

    // Should have budget_tokens = max_tokens - 1
    const budget = thinking.object.get("budget_tokens").?;
    try std.testing.expectEqual(json.Value{ .number = 16383 }, budget.*);

    // Should have beta header
    const beta = body.object.get("anthropic_beta").?;
    try std.testing.expect(beta.array.items.len > 0);
}

test "optimize - legacy budget upgrade" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "anthropic.claude-sonnet-4-5-20250514-v1:0" });
    try body.object.put("max_tokens", json.Value{ .number = 16384 });

    const thinking_map = std.json.ObjectMap.init(allocator);
    try thinking_map.put("type", json.Value{ .string = "enabled" });
    try thinking_map.put("budget_tokens", json.Value{ .number = 1024 });
    try body.object.put("thinking", json.Value{ .object = thinking_map });

    const config = OptimizerConfig{ .enabled = true, .thinking_optimizer = true };
    optimize(&body, &config);

    // Should upgrade budget_tokens
    const thinking = body.object.get("thinking").?;
    const budget = thinking.object.get("budget_tokens").?;
    try std.testing.expectEqual(json.Value{ .number = 16383 }, budget.*);
}

test "optimize - disabled config returns unchanged" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "anthropic.claude-opus-4-6-20250514-v1:0" });
    try body.object.put("max_tokens", json.Value{ .number = 16384 });

    // Clone for comparison
    const original = try json.stringifyAlloc(allocator, body);
    defer allocator.free(original);

    const config = OptimizerConfig{ .enabled = true, .thinking_optimizer = false };
    optimize(&body, &config);

    const after = try json.stringifyAlloc(allocator, body);
    defer allocator.free(after);

    try std.testing.expectEqualSlices(u8, original, after);
}

test "optimize - beta deduplication" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "anthropic.claude-opus-4-6-20250514-v1:0" });
    try body.object.put("max_tokens", json.Value{ .number = 16384 });

    const beta_arr = std.json.Array.init(allocator);
    try beta_arr.append(json.Value{ .string = "context-1m-2025-08-07" });
    try body.object.put("anthropic_beta", json.Value{ .array = beta_arr });

    const config = OptimizerConfig{ .enabled = true, .thinking_optimizer = true };
    optimize(&body, &config);

    // Should still have only one instance of the beta header
    var count: u32 = 0;
    for (body.object.get("anthropic_beta").?.array.items) |item| {
        if (item == .string and std.mem.eql(u8, item.string, "context-1m-2025-08-07")) {
            count += 1;
        }
    }
    try std.testing.expectEqual(@as(u32, 1), count);
}

test "optimize - legacy disabled thinking injected" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "anthropic.claude-sonnet-4-5-20250514-v1:0" });
    try body.object.put("max_tokens", json.Value{ .number = 8192 });

    const thinking_map = std.json.ObjectMap.init(allocator);
    try thinking_map.put("type", json.Value{ .string = "disabled" });
    try body.object.put("thinking", json.Value{ .object = thinking_map });

    const config = OptimizerConfig{ .enabled = true, .thinking_optimizer = true };
    optimize(&body, &config);

    // Should change to enabled with correct budget
    const thinking = body.object.get("thinking").?;
    try std.testing.expectEqual(json.Value{ .string = "enabled" }, thinking.object.get("type").?.*);
    try std.testing.expectEqual(json.Value{ .number = 8191 }, thinking.object.get("budget_tokens").?.*);
}

test "optimize - legacy default max_tokens" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "anthropic.claude-sonnet-4-5-20250514-v1:0" });
    // No max_tokens specified

    const config = OptimizerConfig{ .enabled = true, .thinking_optimizer = true };
    optimize(&body, &config);

    // Should use default 16384 - 1 = 16383
    const thinking = body.object.get("thinking").?;
    try std.testing.expectEqual(json.Value{ .string = "enabled" }, thinking.object.get("type").?.*);
    try std.testing.expectEqual(json.Value{ .number = 16383 }, thinking.object.get("budget_tokens").?.*);
}

test "appendBeta - null field" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer body.object.deinit();

    try body.object.put("model", json.Value{ .string = "anthropic.claude-opus-4-6-20250514-v1:0" });
    try body.object.put("anthropic_beta", json.Value{ .null = {} });

    const config = OptimizerConfig{ .enabled = true, .thinking_optimizer = true };
    optimize(&body, &config);

    // Should have beta header
    const beta = body.object.get("anthropic_beta").?;
    try std.testing.expect(beta.array.items.len > 0);
}
