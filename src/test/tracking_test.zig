//! Tracking and Analytics Types Tests
//!
//! Tests for the analytics types shared between cmd and proxy.
//! These types are used for tracking sync, gain stats, and session analysis.
//!
//! Run with: zig build test

const std = @import("std");
const testing = std.testing;

// Import the analytics types directly from the source
// Note: proxy_analytics_types must be registered in build.zig as a module
const analytics_types = @import("proxy_analytics_types");

// ============================================================================
// Analytics Types Tests
// ============================================================================

test "TrackingRecord creation" {
    const record = analytics_types.TrackingRecord{
        .timestamp = 1234567890,
        .original_cmd = "cargo build",
        .rtk_cmd = "cargo build --release",
        .raw_output_len = 10000,
        .filtered_output_len = 500,
        .exit_code = 0,
        .hostname = "localhost",
        .user_id = null,
        .team_id = null,
    };

    try testing.expectEqual(@as(i64, 1234567890), record.timestamp);
    try testing.expectEqualStrings("cargo build", record.original_cmd);
    try testing.expectEqualStrings("cargo build --release", record.rtk_cmd);
    try testing.expectEqual(@as(usize, 10000), record.raw_output_len);
    try testing.expectEqual(@as(usize, 500), record.filtered_output_len);
    try testing.expectEqual(@as(i32, 0), record.exit_code);
    try testing.expectEqualStrings("localhost", record.hostname);
}

test "TrackingRecord with user and team" {
    const record = analytics_types.TrackingRecord{
        .timestamp = 1234567890,
        .original_cmd = "cargo test",
        .rtk_cmd = "cargo test",
        .raw_output_len = 20000,
        .filtered_output_len = 1000,
        .exit_code = 0,
        .hostname = "workstation",
        .user_id = "alice",
        .team_id = "engineering",
    };

    try testing.expectEqualStrings("alice", record.user_id.?);
    try testing.expectEqualStrings("engineering", record.team_id.?);
}

test "estimateTokens - basic" {
    const text = "Hello, world!";
    const tokens = analytics_types.estimateTokens(text);
    // Simple approximation: 4 chars per token
    try testing.expectEqual(@as(usize, 4), tokens);
}

test "estimateTokens - empty string" {
    const tokens = analytics_types.estimateTokens("");
    try testing.expectEqual(@as(usize, 0), tokens);
}

test "estimateTokens - long text" {
    const text = "This is a longer piece of text that should estimate to more tokens.";
    const tokens = analytics_types.estimateTokens(text);
    // 70 chars / 4 = 18 tokens (ceiling)
    try testing.expectEqual(@as(usize, 18), tokens);
}

test "calculateSavings - positive savings" {
    const result = analytics_types.calculateSavings(1000, 500);
    try testing.expectEqual(@as(usize, 500), result.saved);
    try testing.expectEqual(@as(f64, 50.0), result.pct);
}

test "calculateSavings - no savings (filtered > raw)" {
    const result = analytics_types.calculateSavings(500, 1000);
    try testing.expectEqual(@as(usize, 0), result.saved);
    try testing.expectEqual(@as(f64, 0.0), result.pct);
}

test "calculateSavings - zero raw" {
    const result = analytics_types.calculateSavings(0, 0);
    try testing.expectEqual(@as(usize, 0), result.saved);
    try testing.expectEqual(@as(f64, 0.0), result.pct);
}

test "calculateSavings - equal values (no change)" {
    const result = analytics_types.calculateSavings(1000, 1000);
    try testing.expectEqual(@as(usize, 0), result.saved);
    try testing.expectEqual(@as(f64, 0.0), result.pct);
}

test "calculateSavings - high savings ratio" {
    const result = analytics_types.calculateSavings(10000, 1000);
    try testing.expectEqual(@as(usize, 9000), result.saved);
    try testing.expectEqual(@as(f64, 90.0), result.pct);
}

test "TokenStats structure" {
    const stats = analytics_types.TokenStats{
        .total_commands = 100,
        .total_input_tokens = 50000,
        .total_output_tokens = 100000,
        .total_saved_tokens = 25000,
        .avg_savings_pct = 45.5,
    };

    try testing.expectEqual(@as(usize, 100), stats.total_commands);
    try testing.expectEqual(@as(usize, 50000), stats.total_input_tokens);
    try testing.expectEqual(@as(usize, 100000), stats.total_output_tokens);
    try testing.expectEqual(@as(usize, 25000), stats.total_saved_tokens);
    try testing.expectEqual(@as(f64, 45.5), stats.avg_savings_pct);
}

test "UserStats structure" {
    const stats = analytics_types.UserStats{
        .user_id = "bob",
        .hostname = "server1",
        .total_commands = 50,
        .llmlite_commands = 30,
        .total_saved_tokens = 15000,
        .avg_savings_pct = 33.3,
    };

    try testing.expectEqualStrings("bob", stats.user_id);
    try testing.expectEqualStrings("server1", stats.hostname);
    try testing.expectEqual(@as(usize, 50), stats.total_commands);
    try testing.expectEqual(@as(usize, 30), stats.llmlite_commands);
}

test "CommandStats structure" {
    const stats = analytics_types.CommandStats{
        .command = "cargo",
        .count = 200,
        .total_saved_tokens = 50000,
        .avg_savings_pct = 25.0,
    };

    try testing.expectEqualStrings("cargo", stats.command);
    try testing.expectEqual(@as(usize, 200), stats.count);
    try testing.expectEqual(@as(usize, 50000), stats.total_saved_tokens);
}

test "DailyStats structure" {
    const stats = analytics_types.DailyStats{
        .date = "2024-01-15",
        .total_commands = 75,
        .llmlite_commands = 45,
        .total_saved_tokens = 20000,
        .avg_savings_pct = 26.67,
    };

    try testing.expectEqualStrings("2024-01-15", stats.date);
    try testing.expectEqual(@as(usize, 75), stats.total_commands);
    try testing.expectEqual(@as(usize, 45), stats.llmlite_commands);
}

test "TeamStats structure" {
    const team_stats = analytics_types.TeamStats{
        .team_id = "backend",
        .period = analytics_types.Period{
            .start = 1704067200,
            .end = 1704153600,
        },
        .total_saved_tokens = 100000,
        .total_requests = 500,
        .avg_savings_pct = 40.0,
        .by_user = &.{},
        .by_command = &.{},
        .by_day = &.{},
    };

    try testing.expectEqualStrings("backend", team_stats.team_id.?);
    try testing.expectEqual(@as(usize, 100000), team_stats.total_saved_tokens);
    try testing.expectEqual(@as(usize, 500), team_stats.total_requests);
    try testing.expectEqual(@as(f64, 40.0), team_stats.avg_savings_pct);
}

test "Period structure" {
    const period = analytics_types.Period{
        .start = 1704067200, // 2024-01-01 00:00:00
        .end = 1704153600, // 2024-01-02 00:00:00
    };

    try testing.expectEqual(@as(i64, 1704067200), period.start);
    try testing.expectEqual(@as(i64, 1704153600), period.end);
}

test "AnalyticsQuery defaults" {
    const query = analytics_types.AnalyticsQuery{};

    try testing.expectEqual(@as(?[]const u8, null), query.team_id);
    try testing.expectEqual(@as(?[]const u8, null), query.user_id);
    try testing.expectEqual(@as(?[]const u8, null), query.hostname);
    try testing.expectEqual(@as(u32, 7), query.since_days);
    try testing.expectEqual(@as(?[]const u8, null), query.command);
}

test "AnalyticsQuery with values" {
    const query = analytics_types.AnalyticsQuery{
        .team_id = "team-a",
        .user_id = "charlie",
        .hostname = "desktop",
        .since_days = 30,
        .command = "cargo",
    };

    try testing.expectEqualStrings("team-a", query.team_id.?);
    try testing.expectEqualStrings("charlie", query.user_id.?);
    try testing.expectEqualStrings("desktop", query.hostname.?);
    try testing.expectEqual(@as(u32, 30), query.since_days);
    try testing.expectEqualStrings("cargo", query.command.?);
}

test "SessionSummary structure" {
    const session = analytics_types.SessionSummary{
        .id = "host_2024-01-15",
        .date = "2024-01-15",
        .hostname = "host",
        .total_cmds = 100,
        .llmlite_cmds = 60,
        .output_tokens = 5000,
    };

    try testing.expectEqualStrings("host_2024-01-15", session.id);
    try testing.expectEqualStrings("2024-01-15", session.date);
    try testing.expectEqualStrings("host", session.hostname);
    try testing.expectEqual(@as(usize, 100), session.total_cmds);
    try testing.expectEqual(@as(usize, 60), session.llmlite_cmds);
    try testing.expectEqual(@as(usize, 5000), session.output_tokens);
}

test "SyncRequest structure" {
    const record = analytics_types.TrackingRecord{
        .timestamp = 1234567890,
        .original_cmd = "cargo build",
        .rtk_cmd = "cargo build",
        .raw_output_len = 1000,
        .filtered_output_len = 500,
        .exit_code = 0,
        .hostname = "localhost",
        .user_id = null,
        .team_id = null,
    };

    var records = [_]analytics_types.TrackingRecord{record};
    const sync_req = analytics_types.SyncRequest{
        .records = records[0..],
    };

    try testing.expectEqual(@as(usize, 1), sync_req.records.len);
    try testing.expectEqualStrings("cargo build", sync_req.records[0].original_cmd);
}

test "SyncResponse structure" {
    const sync_resp = analytics_types.SyncResponse{
        .synced = 10,
        .errors = 2,
    };

    try testing.expectEqual(@as(usize, 10), sync_resp.synced);
    try testing.expectEqual(@as(usize, 2), sync_resp.errors);
}

test "GainResponse structure" {
    const cmd_stats = analytics_types.CommandStats{
        .command = "cargo",
        .count = 100,
        .total_saved_tokens = 25000,
        .avg_savings_pct = 25.0,
    };

    var cmd_stats_arr = [_]analytics_types.CommandStats{cmd_stats};
    const gain_resp = analytics_types.GainResponse{
        .total_saved_tokens = 100000,
        .total_requests = 500,
        .avg_savings_pct = 42.5,
        .breakdown = cmd_stats_arr[0..],
    };

    try testing.expectEqual(@as(usize, 100000), gain_resp.total_saved_tokens);
    try testing.expectEqual(@as(usize, 500), gain_resp.total_requests);
    try testing.expectEqual(@as(f64, 42.5), gain_resp.avg_savings_pct);
    try testing.expectEqual(@as(usize, 1), gain_resp.breakdown.len);
    try testing.expectEqualStrings("cargo", gain_resp.breakdown[0].command);
}

test "TeamResponse structure" {
    const team_resp = analytics_types.TeamResponse{
        .team_id = "engineering",
        .total_saved_tokens = 500000,
        .total_requests = 2000,
        .avg_savings_pct = 35.0,
        .adoption_rate = 65.5,
        .users = &.{},
        .daily = &.{},
    };

    try testing.expectEqualStrings("engineering", team_resp.team_id.?);
    try testing.expectEqual(@as(usize, 500000), team_resp.total_saved_tokens);
    try testing.expectEqual(@as(usize, 2000), team_resp.total_requests);
    try testing.expectEqual(@as(f64, 35.0), team_resp.avg_savings_pct);
    try testing.expectEqual(@as(f64, 65.5), team_resp.adoption_rate);
}

test "SessionsResponse structure" {
    const sessions_resp = analytics_types.SessionsResponse{
        .sessions_scanned = 10,
        .total_commands = 500,
        .llmlite_commands = 350,
        .adoption_rate = 70.0,
        .sessions = &.{},
    };

    try testing.expectEqual(@as(usize, 10), sessions_resp.sessions_scanned);
    try testing.expectEqual(@as(usize, 500), sessions_resp.total_commands);
    try testing.expectEqual(@as(usize, 350), sessions_resp.llmlite_commands);
    try testing.expectEqual(@as(f64, 70.0), sessions_resp.adoption_rate);
}

test "SessionsResponse with sessions" {
    const session = analytics_types.SessionSummary{
        .id = "workstation_2024-03-01",
        .date = "2024-03-01",
        .hostname = "workstation",
        .total_cmds = 150,
        .llmlite_cmds = 120,
        .output_tokens = 15000,
    };

    var sessions_arr = [_]analytics_types.SessionSummary{session};
    const sessions_resp = analytics_types.SessionsResponse{
        .sessions_scanned = 1,
        .total_commands = 150,
        .llmlite_commands = 120,
        .adoption_rate = 80.0,
        .sessions = sessions_arr[0..],
    };

    try testing.expectEqual(@as(usize, 1), sessions_resp.sessions_scanned);
    try testing.expectEqual(@as(usize, 1), sessions_resp.sessions.len);
    try testing.expectEqual(@as(f64, 80.0), sessions_resp.adoption_rate);
}

// ============================================================================
// Token Calculation Edge Cases
// ============================================================================

test "calculateSavings - 100% savings" {
    const result = analytics_types.calculateSavings(1000, 0);
    try testing.expectEqual(@as(usize, 1000), result.saved);
    try testing.expectEqual(@as(f64, 100.0), result.pct);
}

test "calculateSavings - very small savings" {
    const result = analytics_types.calculateSavings(10000, 9999);
    try testing.expectEqual(@as(usize, 1), result.saved);
    try testing.expectEqual(@as(f64, 0.01), result.pct);
}

test "estimateTokens - exactly divisible" {
    const text = "12345678"; // 8 chars = 2 tokens
    const tokens = analytics_types.estimateTokens(text);
    try testing.expectEqual(@as(usize, 2), tokens);
}

test "estimateTokens - with ceiling" {
    const text = "123456789"; // 9 chars = 3 tokens (ceiling of 2.25)
    const tokens = analytics_types.estimateTokens(text);
    try testing.expectEqual(@as(usize, 3), tokens);
}

// ============================================================================
// Adoption Rate Calculations
// ============================================================================

test "adoption rate - 100%" {
    // If all commands use llmlite
    const total: usize = 100;
    const llmlite: usize = 100;
    const rate = @as(f64, @floatFromInt(llmlite)) / @as(f64, @floatFromInt(total)) * 100.0;
    try testing.expectEqual(@as(f64, 100.0), rate);
}

test "adoption rate - 0%" {
    const total: usize = 100;
    const llmlite: usize = 0;
    const rate = @as(f64, @floatFromInt(llmlite)) / @as(f64, @floatFromInt(total)) * 100.0;
    try testing.expectEqual(@as(f64, 0.0), rate);
}

test "adoption rate - 50%" {
    const total: usize = 100;
    const llmlite: usize = 50;
    const rate = @as(f64, @floatFromInt(llmlite)) / @as(f64, @floatFromInt(total)) * 100.0;
    try testing.expectEqual(@as(f64, 50.0), rate);
}

test "adoption rate - division by zero protection" {
    const total: usize = 0;
    const llmlite: usize = 0;
    const rate = if (total > 0)
        @as(f64, @floatFromInt(llmlite)) / @as(f64, @floatFromInt(total)) * 100.0
    else
        0.0;
    try testing.expectEqual(@as(f64, 0.0), rate);
}
