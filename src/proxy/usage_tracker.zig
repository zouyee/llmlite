//! Usage Tracker for llmlite Proxy
//!
//! Parses token usage from multiple provider response formats (Anthropic, OpenAI, Gemini)
//! and calculates request cost.

const std = @import("std");
const json = std.json;

pub const UsageInfo = struct {
    input_tokens: u32 = 0,
    output_tokens: u32 = 0,
    cache_creation_input_tokens: u32 = 0,
    cache_read_input_tokens: u32 = 0,
    total_tokens: u32 = 0,
    model: ?[]const u8 = null,
    provider: ?[]const u8 = null,
    latency_ms: u64 = 0,
    cost: f64 = 0,
};

pub const RequestLog = struct {
    timestamp: i64,
    method: []const u8,
    path: []const u8,
    status: u16,
    latency_ms: u64,
    provider: []const u8,
    model: []const u8,
    input_tokens: u32 = 0,
    output_tokens: u32 = 0,
    total_tokens: u32 = 0,
    cost: f64 = 0,
    error_msg: ?[]const u8 = null,
};

pub const UsageTracker = struct {
    allocator: std.mem.Allocator,
    logs: std.ArrayListUnmanaged(RequestLog),

    pub fn init(allocator: std.mem.Allocator) UsageTracker {
        return .{
            .allocator = allocator,
            .logs = .empty,
        };
    }

    pub fn deinit(self: *UsageTracker) void {
        self.logs.deinit(self.allocator);
    }

    /// Parse usage from Anthropic response JSON.
    /// Expects: { "usage": { "input_tokens": N, "output_tokens": N, ... }, "model": "..." }
    pub fn parseAnthropicUsage(_: *UsageTracker, body_json: []const u8) UsageInfo {
        var info = UsageInfo{};

        const parsed = json.parseFromSlice(json.Value, std.heap.page_allocator, body_json, .{
            .ignore_unknown_fields = true,
        }) catch return info;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return info;

        // Extract model
        if (root.object.get("model")) |model_val| {
            if (model_val == .string) {
                info.model = model_val.string;
            }
        }

        // Extract usage object
        const usage_val = root.object.get("usage") orelse return info;
        if (usage_val != .object) return info;
        const usage = usage_val.object;

        info.input_tokens = jsonToU32(usage.get("input_tokens"));
        info.output_tokens = jsonToU32(usage.get("output_tokens"));
        info.cache_creation_input_tokens = jsonToU32(usage.get("cache_creation_input_tokens"));
        info.cache_read_input_tokens = jsonToU32(usage.get("cache_read_input_tokens"));
        info.total_tokens = info.input_tokens + info.output_tokens;

        return info;
    }

    /// Parse usage from OpenAI response JSON.
    /// Expects: { "usage": { "prompt_tokens": N, "completion_tokens": N, "total_tokens": N }, "model": "..." }
    pub fn parseOpenAIUsage(_: *UsageTracker, body_json: []const u8) UsageInfo {
        var info = UsageInfo{};

        const parsed = json.parseFromSlice(json.Value, std.heap.page_allocator, body_json, .{
            .ignore_unknown_fields = true,
        }) catch return info;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return info;

        // Extract model
        if (root.object.get("model")) |model_val| {
            if (model_val == .string) {
                info.model = model_val.string;
            }
        }

        // Extract usage object
        const usage_val = root.object.get("usage") orelse return info;
        if (usage_val != .object) return info;
        const usage = usage_val.object;

        info.input_tokens = jsonToU32(usage.get("prompt_tokens"));
        info.output_tokens = jsonToU32(usage.get("completion_tokens"));
        info.total_tokens = jsonToU32(usage.get("total_tokens"));

        return info;
    }

    /// Parse usage from Gemini response JSON.
    /// Expects: { "usageMetadata": { "promptTokenCount": N, "candidatesTokenCount": N, "totalTokenCount": N } }
    pub fn parseGeminiUsage(_: *UsageTracker, body_json: []const u8) UsageInfo {
        var info = UsageInfo{};

        const parsed = json.parseFromSlice(json.Value, std.heap.page_allocator, body_json, .{
            .ignore_unknown_fields = true,
        }) catch return info;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return info;

        // Extract usageMetadata object
        const meta_val = root.object.get("usageMetadata") orelse return info;
        if (meta_val != .object) return info;
        const meta = meta_val.object;

        info.input_tokens = jsonToU32(meta.get("promptTokenCount"));
        info.output_tokens = jsonToU32(meta.get("candidatesTokenCount"));
        info.total_tokens = jsonToU32(meta.get("totalTokenCount"));

        return info;
    }

    /// Accumulate usage from an SSE event data string into an existing UsageInfo.
    /// Parses the event data as JSON and extracts incremental usage fields.
    /// Supports both Anthropic (message_delta.usage) and OpenAI (usage) formats.
    pub fn accumulateSseUsage(_: *UsageTracker, accumulated: *UsageInfo, event_data: []const u8) void {
        const parsed = json.parseFromSlice(json.Value, std.heap.page_allocator, event_data, .{
            .ignore_unknown_fields = true,
        }) catch return;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return;

        // Check for Anthropic message_delta format: {"type":"message_delta","delta":{"usage":{...}}}
        if (root.object.get("type")) |type_val| {
            if (type_val == .string and std.mem.eql(u8, type_val.string, "message_delta")) {
                if (root.object.get("delta")) |delta_val| {
                    if (delta_val == .object) {
                        if (delta_val.object.get("usage")) |usage_val| {
                            if (usage_val == .object) {
                                accumulated.output_tokens += jsonToU32(usage_val.object.get("output_tokens"));
                                accumulated.input_tokens += jsonToU32(usage_val.object.get("input_tokens"));
                                accumulated.total_tokens = accumulated.input_tokens + accumulated.output_tokens;
                                return;
                            }
                        }
                    }
                }
                // Also check top-level usage in message_delta events
                if (root.object.get("usage")) |usage_val| {
                    if (usage_val == .object) {
                        accumulated.output_tokens += jsonToU32(usage_val.object.get("output_tokens"));
                        accumulated.input_tokens += jsonToU32(usage_val.object.get("input_tokens"));
                        accumulated.total_tokens = accumulated.input_tokens + accumulated.output_tokens;
                        return;
                    }
                }
                return;
            }
        }

        // Check for OpenAI format: {"usage":{"prompt_tokens":N,"completion_tokens":N}}
        // or generic format: {"usage":{"input_tokens":N,"output_tokens":N}}
        if (root.object.get("usage")) |usage_val| {
            if (usage_val == .object) {
                const usage = usage_val.object;
                // OpenAI naming
                accumulated.input_tokens += jsonToU32(usage.get("prompt_tokens"));
                accumulated.output_tokens += jsonToU32(usage.get("completion_tokens"));
                // Anthropic naming (for non-message_delta events with top-level usage)
                accumulated.input_tokens += jsonToU32(usage.get("input_tokens"));
                accumulated.output_tokens += jsonToU32(usage.get("output_tokens"));
                accumulated.total_tokens = accumulated.input_tokens + accumulated.output_tokens;
            }
        }
    }

    /// Append a request log entry.
    pub fn recordLog(self: *UsageTracker, log: RequestLog) !void {
        try self.logs.append(self.allocator, log);
    }

    /// Return the last N log entries (or all if fewer than N exist).
    pub fn getRecentLogs(self: *UsageTracker, limit: usize) []const RequestLog {
        const items = self.logs.items;
        if (items.len <= limit) return items;
        return items[items.len - limit ..];
    }

    /// Calculate cost: (input_tokens * input_price_per_mtok + output_tokens * output_price_per_mtok) / 1_000_000
    pub fn calculateCost(_: *UsageTracker, usage: *UsageInfo, input_price_per_mtok: f64, output_price_per_mtok: f64) f64 {
        const input_cost = @as(f64, @floatFromInt(usage.input_tokens)) * input_price_per_mtok / 1_000_000.0;
        const output_cost = @as(f64, @floatFromInt(usage.output_tokens)) * output_price_per_mtok / 1_000_000.0;
        const total = input_cost + output_cost;
        usage.cost = total;
        return total;
    }
};

/// Helper: extract u32 from a JSON integer value, returning 0 on null/type mismatch.
fn jsonToU32(val: ?json.Value) u32 {
    const v = val orelse return 0;
    return switch (v) {
        .integer => |i| if (i >= 0) @intCast(@min(i, std.math.maxInt(u32))) else 0,
        .float => |f| blk: {
            if (f >= 0 and f <= @as(f64, @floatFromInt(std.math.maxInt(u32)))) {
                break :blk @intFromFloat(f);
            }
            break :blk 0;
        },
        else => 0,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "parseAnthropicUsage - sample response" {
    var tracker = UsageTracker.init(std.testing.allocator);
    defer tracker.deinit();

    const body =
        \\{
        \\  "id": "msg_123",
        \\  "type": "message",
        \\  "model": "claude-3-5-sonnet-20241022",
        \\  "usage": {
        \\    "input_tokens": 100,
        \\    "output_tokens": 250,
        \\    "cache_creation_input_tokens": 50,
        \\    "cache_read_input_tokens": 30
        \\  }
        \\}
    ;

    const info = tracker.parseAnthropicUsage(body);
    try std.testing.expectEqual(@as(u32, 100), info.input_tokens);
    try std.testing.expectEqual(@as(u32, 250), info.output_tokens);
    try std.testing.expectEqual(@as(u32, 50), info.cache_creation_input_tokens);
    try std.testing.expectEqual(@as(u32, 30), info.cache_read_input_tokens);
    try std.testing.expectEqual(@as(u32, 350), info.total_tokens);
    try std.testing.expect(info.model != null);
}

test "parseOpenAIUsage - sample response" {
    var tracker = UsageTracker.init(std.testing.allocator);
    defer tracker.deinit();

    const body =
        \\{
        \\  "id": "chatcmpl-abc",
        \\  "object": "chat.completion",
        \\  "model": "gpt-4o",
        \\  "usage": {
        \\    "prompt_tokens": 200,
        \\    "completion_tokens": 150,
        \\    "total_tokens": 350
        \\  }
        \\}
    ;

    const info = tracker.parseOpenAIUsage(body);
    try std.testing.expectEqual(@as(u32, 200), info.input_tokens);
    try std.testing.expectEqual(@as(u32, 150), info.output_tokens);
    try std.testing.expectEqual(@as(u32, 350), info.total_tokens);
    try std.testing.expect(info.model != null);
}

test "parseGeminiUsage - sample response" {
    var tracker = UsageTracker.init(std.testing.allocator);
    defer tracker.deinit();

    const body =
        \\{
        \\  "candidates": [{"content": {"parts": [{"text": "hello"}]}}],
        \\  "usageMetadata": {
        \\    "promptTokenCount": 80,
        \\    "candidatesTokenCount": 120,
        \\    "totalTokenCount": 200
        \\  }
        \\}
    ;

    const info = tracker.parseGeminiUsage(body);
    try std.testing.expectEqual(@as(u32, 80), info.input_tokens);
    try std.testing.expectEqual(@as(u32, 120), info.output_tokens);
    try std.testing.expectEqual(@as(u32, 200), info.total_tokens);
}

test "calculateCost - correctness" {
    var tracker = UsageTracker.init(std.testing.allocator);
    defer tracker.deinit();

    var usage = UsageInfo{
        .input_tokens = 1_000_000,
        .output_tokens = 500_000,
    };

    // $3/M input, $15/M output
    const cost = tracker.calculateCost(&usage, 3.0, 15.0);
    // Expected: (1_000_000 * 3.0 + 500_000 * 15.0) / 1_000_000 = 3.0 + 7.5 = 10.5
    try std.testing.expectApproxEqAbs(@as(f64, 10.5), cost, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 10.5), usage.cost, 0.0001);
}

test "calculateCost - zero tokens" {
    var tracker = UsageTracker.init(std.testing.allocator);
    defer tracker.deinit();

    var usage = UsageInfo{};
    const cost = tracker.calculateCost(&usage, 5.0, 15.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), cost, 0.0001);
}

test "missing usage fields return zeros" {
    var tracker = UsageTracker.init(std.testing.allocator);
    defer tracker.deinit();

    // No usage field at all
    const no_usage = tracker.parseAnthropicUsage(
        \\{"id": "msg_123", "model": "claude-3"}
    );
    try std.testing.expectEqual(@as(u32, 0), no_usage.input_tokens);
    try std.testing.expectEqual(@as(u32, 0), no_usage.output_tokens);

    // Empty usage object
    const empty_usage = tracker.parseOpenAIUsage(
        \\{"model": "gpt-4o", "usage": {}}
    );
    try std.testing.expectEqual(@as(u32, 0), empty_usage.input_tokens);
    try std.testing.expectEqual(@as(u32, 0), empty_usage.output_tokens);
    try std.testing.expectEqual(@as(u32, 0), empty_usage.total_tokens);

    // Malformed JSON returns zeros
    const malformed = tracker.parseGeminiUsage("not json at all");
    try std.testing.expectEqual(@as(u32, 0), malformed.input_tokens);
    try std.testing.expectEqual(@as(u32, 0), malformed.output_tokens);

    // Empty object
    const empty_obj = tracker.parseAnthropicUsage("{}");
    try std.testing.expectEqual(@as(u32, 0), empty_obj.input_tokens);
    try std.testing.expect(empty_obj.model == null);
}

test "accumulateSseUsage - OpenAI format" {
    var tracker = UsageTracker.init(std.testing.allocator);
    defer tracker.deinit();

    var accumulated = UsageInfo{};
    const event_data =
        \\{"usage":{"prompt_tokens":50,"completion_tokens":30}}
    ;
    tracker.accumulateSseUsage(&accumulated, event_data);
    try std.testing.expectEqual(@as(u32, 50), accumulated.input_tokens);
    try std.testing.expectEqual(@as(u32, 30), accumulated.output_tokens);
    try std.testing.expectEqual(@as(u32, 80), accumulated.total_tokens);
}

test "accumulateSseUsage - Anthropic message_delta format" {
    var tracker = UsageTracker.init(std.testing.allocator);
    defer tracker.deinit();

    var accumulated = UsageInfo{};
    const event_data =
        \\{"type":"message_delta","delta":{"usage":{"output_tokens":42}}}
    ;
    tracker.accumulateSseUsage(&accumulated, event_data);
    try std.testing.expectEqual(@as(u32, 0), accumulated.input_tokens);
    try std.testing.expectEqual(@as(u32, 42), accumulated.output_tokens);
    try std.testing.expectEqual(@as(u32, 42), accumulated.total_tokens);
}

test "accumulateSseUsage - multiple events accumulate" {
    var tracker = UsageTracker.init(std.testing.allocator);
    defer tracker.deinit();

    var accumulated = UsageInfo{};

    // First OpenAI event
    tracker.accumulateSseUsage(&accumulated,
        \\{"usage":{"prompt_tokens":10,"completion_tokens":5}}
    );
    try std.testing.expectEqual(@as(u32, 10), accumulated.input_tokens);
    try std.testing.expectEqual(@as(u32, 5), accumulated.output_tokens);

    // Second OpenAI event
    tracker.accumulateSseUsage(&accumulated,
        \\{"usage":{"prompt_tokens":20,"completion_tokens":15}}
    );
    try std.testing.expectEqual(@as(u32, 30), accumulated.input_tokens);
    try std.testing.expectEqual(@as(u32, 20), accumulated.output_tokens);
    try std.testing.expectEqual(@as(u32, 50), accumulated.total_tokens);
}

test "accumulateSseUsage - malformed JSON does not crash" {
    var tracker = UsageTracker.init(std.testing.allocator);
    defer tracker.deinit();

    var accumulated = UsageInfo{ .input_tokens = 7, .output_tokens = 3 };
    tracker.accumulateSseUsage(&accumulated, "not valid json {{{");
    // Values unchanged
    try std.testing.expectEqual(@as(u32, 7), accumulated.input_tokens);
    try std.testing.expectEqual(@as(u32, 3), accumulated.output_tokens);

    // Empty string
    tracker.accumulateSseUsage(&accumulated, "");
    try std.testing.expectEqual(@as(u32, 7), accumulated.input_tokens);

    // Valid JSON but no usage
    tracker.accumulateSseUsage(&accumulated,
        \\{"type":"content_block_delta","delta":{"text":"hello"}}
    );
    try std.testing.expectEqual(@as(u32, 7), accumulated.input_tokens);
    try std.testing.expectEqual(@as(u32, 3), accumulated.output_tokens);
}

test "recordLog and getRecentLogs" {
    var tracker = UsageTracker.init(std.testing.allocator);
    defer tracker.deinit();

    try tracker.recordLog(.{
        .timestamp = 1000,
        .method = "POST",
        .path = "/v1/messages",
        .status = 200,
        .latency_ms = 150,
        .provider = "anthropic",
        .model = "claude-3-5-sonnet",
        .input_tokens = 100,
        .output_tokens = 50,
        .total_tokens = 150,
        .cost = 0.005,
    });
    try tracker.recordLog(.{
        .timestamp = 2000,
        .method = "POST",
        .path = "/v1/chat/completions",
        .status = 200,
        .latency_ms = 200,
        .provider = "openai",
        .model = "gpt-4o",
        .input_tokens = 200,
        .output_tokens = 100,
        .total_tokens = 300,
        .cost = 0.01,
    });
    try tracker.recordLog(.{
        .timestamp = 3000,
        .method = "POST",
        .path = "/v1/messages",
        .status = 500,
        .latency_ms = 50,
        .provider = "anthropic",
        .model = "claude-3-5-sonnet",
        .error_msg = "internal server error",
    });

    // getRecentLogs with limit larger than count returns all
    const all = tracker.getRecentLogs(10);
    try std.testing.expectEqual(@as(usize, 3), all.len);

    // getRecentLogs with exact count
    const exact = tracker.getRecentLogs(3);
    try std.testing.expectEqual(@as(usize, 3), exact.len);

    // getRecentLogs with limit smaller than count returns last N
    const last2 = tracker.getRecentLogs(2);
    try std.testing.expectEqual(@as(usize, 2), last2.len);
    try std.testing.expectEqual(@as(i64, 2000), last2[0].timestamp);
    try std.testing.expectEqual(@as(i64, 3000), last2[1].timestamp);
    try std.testing.expectEqual(@as(u16, 500), last2[1].status);
    try std.testing.expect(last2[1].error_msg != null);

    // getRecentLogs with 0 limit
    const none = tracker.getRecentLogs(0);
    try std.testing.expectEqual(@as(usize, 0), none.len);
}
