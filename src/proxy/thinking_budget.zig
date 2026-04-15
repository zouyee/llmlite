//! Thinking Budget Rectifier for llmlite Proxy
//!
//! Automatically fixes requests that fail due to thinking budget constraints.
//! When upstream API returns budget_tokens + thinking related errors,
//! the system automatically adjusts budget parameters and retries.

const std = @import("std");
const json = std.json;

pub const ThinkingBudgetConfig = struct {
    enabled: bool = true,
    request_thinking_budget: bool = true,
    default_budget_tokens: u64 = 32000,
    max_tokens_value: u64 = 64000,
    min_max_tokens_for_budget: u64 = 32001,
};

/// Budget snapshot before rectification
pub const BudgetSnapshot = struct {
    max_tokens: ?u64,
    thinking_type: ?[]const u8,
    thinking_budget_tokens: ?u64,
};

/// Budget rectification result
pub const BudgetRectifyResult = struct {
    applied: bool,
    before: BudgetSnapshot,
    after: BudgetSnapshot,
};

/// Check if thinking budget rectification should be triggered
///
/// Conditions: error message contains `budget_tokens` + `thinking` + `1024` constraint
pub fn shouldRectifyThinkingBudget(error_message: ?[]const u8, config: *const ThinkingBudgetConfig) bool {
    // Check global switch
    if (!config.enabled) return false;
    // Check sub switch
    if (!config.request_thinking_budget) return false;

    const msg = error_message orelse return false;

    const lower = std.ascii.lowerString(msg);

    // Check for budget_tokens reference
    const has_budget_tokens = std.mem.containsAtLeast(u8, lower, 1, "budget_tokens") or
        std.mem.containsAtLeast(u8, lower, 1, "budget tokens");
    // Check for thinking reference
    const has_thinking = std.mem.containsAtLeast(u8, lower, 1, "thinking");
    // Check for 1024 constraint
    const has_1024_constraint = (std.mem.containsAtLeast(u8, lower, 1, "greater than or equal to 1024") or
        std.mem.containsAtLeast(u8, lower, 1, ">= 1024") or
        (std.mem.containsAtLeast(u8, lower, 1, "1024") and std.mem.containsAtLeast(u8, lower, 1, "input should be")));

    return has_budget_tokens and has_thinking and has_1024_constraint;
}

fn snapshotBudget(body: *const json.Value) BudgetSnapshot {
    var snapshot = BudgetSnapshot{
        .max_tokens = null,
        .thinking_type = null,
        .thinking_budget_tokens = null,
    };

    // Get max_tokens
    if (body.object.get("max_tokens")) |max_tokens| {
        if (max_tokens.isNumber()) {
            snapshot.max_tokens = @as(u64, @intFromFloat(max_tokens.number));
        }
    }

    // Get thinking block
    if (body.object.get("thinking")) |thinking| {
        if (thinking.object.get("type")) |t| {
            if (t.isString()) {
                snapshot.thinking_type = t.string;
            }
        }
        if (thinking.object.get("budget_tokens")) |bt| {
            if (bt.isNumber()) {
                snapshot.thinking_budget_tokens = @as(u64, @intFromFloat(bt.number));
            }
        }
    }

    return snapshot;
}

/// Rectify thinking budget in request body
///
/// Actions:
/// - `thinking.type = "enabled"`
/// - `thinking.budget_tokens = 32000`
/// - If `max_tokens < 32001`, set to `64000`
pub fn rectifyThinkingBudget(allocator: std.mem.Allocator, body: *json.Value, config: *const ThinkingBudgetConfig) BudgetRectifyResult {
    const before = snapshotBudget(body);

    // Adaptive requests should not be modified
    if (before.thinking_type) |t| {
        if (std.mem.eql(u8, t, "adaptive")) {
            return .{
                .applied = false,
                .before = before,
                .after = before,
            };
        }
    }

    // If thinking block doesn't exist, create it
    if (!body.object.contains("thinking")) {
        const thinking_map = std.json.ObjectMap.init(allocator);
        body.object.put("thinking", json.Value{ .object = thinking_map }) catch return .{
            .applied = false,
            .before = before,
            .after = before,
        };
    }

    const thinking = body.object.getPtr("thinking") orelse {
        return .{
            .applied = false,
            .before = before,
            .after = before,
        };
    };

    thinking.object.put("type", json.Value{ .string = "enabled" }) catch return .{
        .applied = false,
        .before = before,
        .after = before,
    };

    // Set budget_tokens
    thinking.object.put("budget_tokens", json.Value{ .number = @floatFromInt(config.default_budget_tokens) }) catch return .{
        .applied = false,
        .before = before,
        .after = before,
    };

    // If max_tokens is too small, increase it
    if (body.object.get("max_tokens")) |max_tokens| {
        if (max_tokens.isNumber()) {
            const current_max: u64 = @intFromFloat(max_tokens.number);
            if (current_max < config.min_max_tokens_for_budget) {
                body.object.put("max_tokens", json.Value{ .number = @floatFromInt(config.max_tokens_value) }) catch return .{
                    .applied = false,
                    .before = before,
                    .after = before,
                };
            }
        }
    } else {
        // If max_tokens not set, add it
        body.object.put("max_tokens", json.Value{ .number = @floatFromInt(config.max_tokens_value) }) catch return .{
            .applied = false,
            .before = before,
            .after = before,
        };
    }

    const after = snapshotBudget(body);

    return .{
        .applied = true,
        .before = before,
        .after = after,
    };
}

/// Detect if thinking mode is enabled in request
pub fn hasThinkingEnabled(body: *const json.Value) bool {
    if (body.object.get("thinking")) |thinking| {
        if (thinking.object.get("type")) |t| {
            if (t.isString()) {
                return std.mem.eql(u8, t.string, "enabled") or std.mem.eql(u8, t.string, "block");
            }
        }
    }
    return false;
}

/// Get thinking budget from request body
pub fn getThinkingBudget(body: *const json.Value) ?u64 {
    if (body.object.get("thinking")) |thinking| {
        if (thinking.object.get("budget_tokens")) |bt| {
            if (bt.isNumber()) {
                return @as(u64, @intFromFloat(bt.number));
            }
        }
    }
    return null;
}

/// Set thinking budget in request body
pub fn setThinkingBudget(allocator: std.mem.Allocator, body: *json.Value, budget_tokens: u64) !void {
    // Ensure thinking block exists
    if (!body.object.contains("thinking")) {
        const thinking_map = std.json.ObjectMap.init(allocator);
        try body.object.put("thinking", json.Value{ .object = thinking_map });
    }

    const thinking = body.object.getPtr("thinking") orelse return;

    // Set type to enabled
    try thinking.object.put("type", json.Value{ .string = "enabled" });

    // Set budget_tokens
    try thinking.object.put("budget_tokens", json.Value{ .number = @floatFromInt(budget_tokens) });
}

/// Remove thinking block from request body
pub fn removeThinking(body: *json.Value) void {
    _ = body.object.remove("thinking");
}

// ============================================================================
// TESTS
// ============================================================================

test "shouldRectifyThinkingBudget - detects budget_tokens error" {
    const config = ThinkingBudgetConfig{
        .enabled = true,
        .request_thinking_budget = true,
        .default_budget_tokens = 32000,
        .max_tokens_value = 64000,
        .min_max_tokens_for_budget = 32001,
    };

    // Valid error message with all conditions
    const error_msg = "budget_tokens must be greater than or equal to 1024";
    try std.testing.expect(shouldRectifyThinkingBudget(error_msg, &config));

    // Another valid format
    const error_msg2 = "thinking budget_tokens constraint >= 1024";
    try std.testing.expect(shouldRectifyThinkingBudget(error_msg2, &config));

    // Missing budget_tokens - should not trigger
    const error_msg3 = "thinking constraint >= 1024";
    try std.testing.expect(!shouldRectifyThinkingBudget(error_msg3, &config));

    // Missing thinking - should not trigger
    const error_msg4 = "budget_tokens must be >= 1024";
    try std.testing.expect(!shouldRectifyThinkingBudget(error_msg4, &config));
}

test "shouldRectifyThinkingBudget - disabled config returns false" {
    const config = ThinkingBudgetConfig{
        .enabled = false,
        .request_thinking_budget = true,
        .default_budget_tokens = 32000,
        .max_tokens_value = 64000,
        .min_max_tokens_for_budget = 32001,
    };

    const error_msg = "budget_tokens thinking >= 1024";
    try std.testing.expect(!shouldRectifyThinkingBudget(error_msg, &config));
}

test "shouldRectifyThinkingBudget - null error message returns false" {
    const config = ThinkingBudgetConfig{
        .enabled = true,
        .request_thinking_budget = true,
        .default_budget_tokens = 32000,
        .max_tokens_value = 64000,
        .min_max_tokens_for_budget = 32001,
    };

    try std.testing.expect(!shouldRectifyThinkingBudget(null, &config));
}

test "hasThinkingEnabled - detects enabled thinking" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer body.object.deinit();

    // No thinking block
    try std.testing.expect(!hasThinkingEnabled(&body));

    // Add thinking block with enabled
    try body.object.put("thinking", json.Value{ .object = std.json.ObjectMap.init(allocator) });
    const thinking = body.object.getPtr("thinking").?;
    try thinking.object.put("type", json.Value{ .string = "enabled" });

    try std.testing.expect(hasThinkingEnabled(&body));
}

test "hasThinkingEnabled - detects block thinking" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer body.object.deinit();

    try body.object.put("thinking", json.Value{ .object = std.json.ObjectMap.init(allocator) });
    const thinking = body.object.getPtr("thinking").?;
    try thinking.object.put("type", json.Value{ .string = "block" });

    try std.testing.expect(hasThinkingEnabled(&body));
}

test "hasThinkingEnabled - returns false for adaptive" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer body.object.deinit();

    try body.object.put("thinking", json.Value{ .object = std.json.ObjectMap.init(allocator) });
    const thinking = body.object.getPtr("thinking").?;
    try thinking.object.put("type", json.Value{ .string = "adaptive" });

    try std.testing.expect(!hasThinkingEnabled(&body));
}

test "getThinkingBudget - extracts budget from body" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer body.object.deinit();

    // No thinking block
    try std.testing.expect(getThinkingBudget(&body) == null);

    // Add thinking block with budget
    try body.object.put("thinking", json.Value{ .object = std.json.ObjectMap.init(allocator) });
    const thinking = body.object.getPtr("thinking").?;
    try thinking.object.put("budget_tokens", json.Value{ .number = 16000 });

    const budget = getThinkingBudget(&body);
    try std.testing.expect(budget != null);
    try std.testing.expectEqual(@as(u64, 16000), budget.?);
}

test "setThinkingBudget - sets budget in body" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer body.object.deinit();

    try setThinkingBudget(allocator, &body, 20000);

    const budget = getThinkingBudget(&body);
    try std.testing.expect(budget != null);
    try std.testing.expectEqual(@as(u64, 20000), budget.?);

    // Should also have type = enabled
    try std.testing.expect(hasThinkingEnabled(&body));
}

test "removeThinking - removes thinking block" {
    const allocator = std.heap.page_allocator;
    var body = json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer body.object.deinit();

    // Add thinking block
    try body.object.put("thinking", json.Value{ .object = std.json.ObjectMap.init(allocator) });
    const thinking = body.object.getPtr("thinking").?;
    try thinking.object.put("type", json.Value{ .string = "enabled" });

    try std.testing.expect(hasThinkingEnabled(&body));

    removeThinking(&body);

    try std.testing.expect(!hasThinkingEnabled(&body));
}
