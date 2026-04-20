//! Shared Analytics Types for llmlite-proxy and llmlite-cmd
//!
//! This module defines common data structures used by both proxy and cmd
//! components for token metrics, cost tracking, and savings reporting.

const std = @import("std");

// ============================================================================
// Core Metrics Types
// ============================================================================

/// Unified token metrics — replaces inline token field definitions in UsageInfo and GainStats
pub const TokenMetrics = struct {
    input_tokens: u64 = 0,
    output_tokens: u64 = 0,
    total_tokens: u64 = 0,
    cache_creation_tokens: u64 = 0,
    cache_read_tokens: u64 = 0,
};

/// Cost metrics
pub const CostMetrics = struct {
    cost_usd: f64 = 0.0,
    cost_per_token: f64 = 0.0,
    model: ?[]const u8 = null,
    provider: ?[]const u8 = null,
};

/// Savings metrics
pub const SavingsMetrics = struct {
    raw_tokens: u64 = 0,
    filtered_tokens: u64 = 0,
    saved_tokens: u64 = 0,
    savings_pct: f64 = 0.0,
};

// ============================================================================
// Report / Response Types
// ============================================================================

/// Cmd → Proxy savings report
pub const SavingsReport = struct {
    timestamp: i64,
    original_cmd: []const u8,
    raw_output_tokens: u64,
    filtered_output_tokens: u64,
    saved_tokens: u64,
    savings_pct: f64,
    exit_code: i32,
    hostname: []const u8,
};

/// Breakdown structs for UnifiedResponse
pub const ProviderBreakdown = struct {
    provider: []const u8,
    requests: u64,
    cost_usd: f64,
};

pub const ModelBreakdown = struct {
    model: []const u8,
    requests: u64,
    cost_usd: f64,
};

pub const CommandBreakdown = struct {
    command: []const u8,
    count: u64,
    saved_tokens: u64,
};

/// API cost summary for UnifiedResponse
pub const ApiCostSummary = struct {
    total_requests: u64 = 0,
    total_input_tokens: u64 = 0,
    total_output_tokens: u64 = 0,
    total_cost_usd: f64 = 0.0,
    by_provider: []const ProviderBreakdown = &.{},
    by_model: []const ModelBreakdown = &.{},
};

/// Cmd savings summary for UnifiedResponse
pub const CmdSavingsSummary = struct {
    total_commands: u64 = 0,
    total_saved_tokens: u64 = 0,
    avg_savings_pct: f64 = 0.0,
    by_command: []const CommandBreakdown = &.{},
};

/// GET /analytics/unified response
pub const UnifiedResponse = struct {
    api_cost: ApiCostSummary,
    cmd_savings: CmdSavingsSummary,
    net_cost: f64,
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Unified token estimation logic: ~4 chars per token
pub fn estimateTokens(text_len: usize) u64 {
    if (text_len == 0) return 0;
    return @intFromFloat(@ceil(@as(f64, @floatFromInt(text_len)) / 4.0));
}

// ============================================================================
// Serialization
// ============================================================================

/// Serialize SavingsReport to JSON string
/// Caller owns returned memory
pub fn serializeSavingsReport(allocator: std.mem.Allocator, report: SavingsReport) ![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, report, .{});
}

/// Parse JSON string to SavingsReport
/// Caller owns returned memory (string fields are deep-copied)
pub fn parseSavingsReport(allocator: std.mem.Allocator, json_bytes: []const u8) !SavingsReport {
    const parsed = try std.json.parseFromSlice(SavingsReport, allocator, json_bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    // Deep-copy string fields so they outlive the parsed object
    return SavingsReport{
        .timestamp = parsed.value.timestamp,
        .original_cmd = try allocator.dupe(u8, parsed.value.original_cmd),
        .raw_output_tokens = parsed.value.raw_output_tokens,
        .filtered_output_tokens = parsed.value.filtered_output_tokens,
        .saved_tokens = parsed.value.saved_tokens,
        .savings_pct = parsed.value.savings_pct,
        .exit_code = parsed.value.exit_code,
        .hostname = try allocator.dupe(u8, parsed.value.hostname),
    };
}

/// Serialize UnifiedResponse to JSON string
/// Caller owns returned memory
pub fn serializeUnifiedResponse(allocator: std.mem.Allocator, response: UnifiedResponse) ![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, response, .{});
}

/// Parse JSON string to UnifiedResponse
/// Caller owns returned memory (slice elements are deep-copied)
pub fn parseUnifiedResponse(allocator: std.mem.Allocator, json_bytes: []const u8) !UnifiedResponse {
    const parsed = try std.json.parseFromSlice(UnifiedResponse, allocator, json_bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    return try deepCopyUnifiedResponse(allocator, parsed.value);
}

fn deepCopyUnifiedResponse(allocator: std.mem.Allocator, value: UnifiedResponse) !UnifiedResponse {
    // Deep-copy by_provider slices
    const by_provider = try allocator.alloc(ProviderBreakdown, value.api_cost.by_provider.len);
    for (value.api_cost.by_provider, 0..) |pb, i| {
        by_provider[i] = .{
            .provider = try allocator.dupe(u8, pb.provider),
            .requests = pb.requests,
            .cost_usd = pb.cost_usd,
        };
    }

    // Deep-copy by_model slices
    const by_model = try allocator.alloc(ModelBreakdown, value.api_cost.by_model.len);
    for (value.api_cost.by_model, 0..) |mb, i| {
        by_model[i] = .{
            .model = try allocator.dupe(u8, mb.model),
            .requests = mb.requests,
            .cost_usd = mb.cost_usd,
        };
    }

    // Deep-copy by_command slices
    const by_command = try allocator.alloc(CommandBreakdown, value.cmd_savings.by_command.len);
    for (value.cmd_savings.by_command, 0..) |cb, i| {
        by_command[i] = .{
            .command = try allocator.dupe(u8, cb.command),
            .count = cb.count,
            .saved_tokens = cb.saved_tokens,
        };
    }

    return UnifiedResponse{
        .api_cost = .{
            .total_requests = value.api_cost.total_requests,
            .total_input_tokens = value.api_cost.total_input_tokens,
            .total_output_tokens = value.api_cost.total_output_tokens,
            .total_cost_usd = value.api_cost.total_cost_usd,
            .by_provider = by_provider,
            .by_model = by_model,
        },
        .cmd_savings = .{
            .total_commands = value.cmd_savings.total_commands,
            .total_saved_tokens = value.cmd_savings.total_saved_tokens,
            .avg_savings_pct = value.cmd_savings.avg_savings_pct,
            .by_command = by_command,
        },
        .net_cost = value.net_cost,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "estimateTokens basic" {
    try std.testing.expectEqual(@as(u64, 0), estimateTokens(0));
    try std.testing.expectEqual(@as(u64, 1), estimateTokens(1));
    try std.testing.expectEqual(@as(u64, 1), estimateTokens(4));
    try std.testing.expectEqual(@as(u64, 2), estimateTokens(5));
    try std.testing.expectEqual(@as(u64, 3), estimateTokens(12));
}

test "SavingsReport round-trip" {
    const allocator = std.testing.allocator;

    const original = SavingsReport{
        .timestamp = 1700000000,
        .original_cmd = "git status",
        .raw_output_tokens = 1000,
        .filtered_output_tokens = 400,
        .saved_tokens = 600,
        .savings_pct = 60.0,
        .exit_code = 0,
        .hostname = "localhost",
    };

    const json = try serializeSavingsReport(allocator, original);
    defer allocator.free(json);

    const parsed = try parseSavingsReport(allocator, json);
    defer {
        allocator.free(parsed.original_cmd);
        allocator.free(parsed.hostname);
    }

    try std.testing.expectEqual(original.timestamp, parsed.timestamp);
    try std.testing.expectEqualStrings(original.original_cmd, parsed.original_cmd);
    try std.testing.expectEqual(original.raw_output_tokens, parsed.raw_output_tokens);
    try std.testing.expectEqual(original.filtered_output_tokens, parsed.filtered_output_tokens);
    try std.testing.expectEqual(original.saved_tokens, parsed.saved_tokens);
    try std.testing.expectEqual(original.savings_pct, parsed.savings_pct);
    try std.testing.expectEqual(original.exit_code, parsed.exit_code);
    try std.testing.expectEqualStrings(original.hostname, parsed.hostname);
}

test "UnifiedResponse round-trip" {
    const allocator = std.testing.allocator;

    const original = UnifiedResponse{
        .api_cost = .{
            .total_requests = 100,
            .total_input_tokens = 5000,
            .total_output_tokens = 2000,
            .total_cost_usd = 0.5,
            .by_provider = &[_]ProviderBreakdown{
                .{ .provider = "openai", .requests = 80, .cost_usd = 0.4 },
            },
            .by_model = &[_]ModelBreakdown{
                .{ .model = "gpt-4", .requests = 50, .cost_usd = 0.3 },
            },
        },
        .cmd_savings = .{
            .total_commands = 20,
            .total_saved_tokens = 10000,
            .avg_savings_pct = 45.5,
            .by_command = &[_]CommandBreakdown{
                .{ .command = "git status", .count = 10, .saved_tokens = 5000 },
            },
        },
        .net_cost = 0.25,
    };

    const json = try serializeUnifiedResponse(allocator, original);
    defer allocator.free(json);

    const parsed = try parseUnifiedResponse(allocator, json);
    defer {
        allocator.free(parsed.api_cost.by_provider[0].provider);
        allocator.free(parsed.api_cost.by_model[0].model);
        allocator.free(parsed.cmd_savings.by_command[0].command);
        allocator.free(parsed.api_cost.by_provider);
        allocator.free(parsed.api_cost.by_model);
        allocator.free(parsed.cmd_savings.by_command);
    }

    try std.testing.expectEqual(original.api_cost.total_requests, parsed.api_cost.total_requests);
    try std.testing.expectEqual(original.cmd_savings.total_commands, parsed.cmd_savings.total_commands);
    try std.testing.expectEqualStrings(original.api_cost.by_provider[0].provider, parsed.api_cost.by_provider[0].provider);
    try std.testing.expectEqualStrings(original.cmd_savings.by_command[0].command, parsed.cmd_savings.by_command[0].command);
    try std.testing.expectEqual(original.net_cost, parsed.net_cost);
}

test "parseSavingsReport rejects invalid JSON" {
    const allocator = std.testing.allocator;
    const bad_json = "not json at all";
    try std.testing.expectError(error.SyntaxError, parseSavingsReport(allocator, bad_json));
}

test "parseSavingsReport rejects missing fields" {
    const allocator = std.testing.allocator;
    const incomplete = "{\"timestamp\":123}";
    try std.testing.expectError(error.MissingField, parseSavingsReport(allocator, incomplete));
}
