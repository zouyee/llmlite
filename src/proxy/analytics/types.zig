//! Analytics Types for llmlite Proxy
//!
//! Unified data types for tracking, gain statistics, and session analysis.
//! Shared between proxy (server-side) and cmd (client-side).

const std = @import("std");

// ============================================================================
// Tracking Record Types
// ============================================================================

/// A tracking record from llmlite-cmd command execution
pub const TrackingRecord = struct {
    timestamp: i64,
    original_cmd: []const u8,
    rtk_cmd: []const u8,
    raw_output_len: usize,
    filtered_output_len: usize,
    exit_code: i32,
    hostname: []const u8,
    user_id: ?[]const u8 = null,
    team_id: ?[]const u8 = null,
};

/// Request body for POST /tracking/sync
pub const SyncRequest = struct {
    records: []TrackingRecord,
};

/// Response for POST /tracking/sync
pub const SyncResponse = struct {
    synced: usize,
    errors: usize,
};

// ============================================================================
// Token Statistics Types
// ============================================================================

/// Token statistics for a single record
pub const TokenStats = struct {
    total_commands: usize,
    total_input_tokens: usize,
    total_output_tokens: usize,
    total_saved_tokens: usize,
    avg_savings_pct: f64,
};

/// User-level statistics
pub const UserStats = struct {
    user_id: []const u8,
    hostname: []const u8,
    total_commands: usize,
    llmlite_commands: usize,
    total_saved_tokens: usize,
    avg_savings_pct: f64,
};

/// Command-level statistics
pub const CommandStats = struct {
    command: []const u8,
    count: usize,
    total_saved_tokens: usize,
    avg_savings_pct: f64,
};

/// Daily statistics breakdown
pub const DailyStats = struct {
    date: []const u8,
    total_commands: usize,
    llmlite_commands: usize,
    total_saved_tokens: usize,
    avg_savings_pct: f64,
};

/// Team-level aggregated statistics
pub const TeamStats = struct {
    team_id: ?[]const u8,
    period: Period,
    total_saved_tokens: usize,
    total_requests: usize,
    avg_savings_pct: f64,
    by_user: []UserStats,
    by_command: []CommandStats,
    by_day: []DailyStats,
};

/// Time period for queries
pub const Period = struct {
    start: i64,
    end: i64,
};

/// Query parameters for analytics endpoints
pub const AnalyticsQuery = struct {
    team_id: ?[]const u8 = null,
    user_id: ?[]const u8 = null,
    hostname: ?[]const u8 = null,
    since_days: u32 = 7,
    command: ?[]const u8 = null,
};

/// Response for GET /analytics/gain
pub const GainResponse = struct {
    total_saved_tokens: usize,
    total_requests: usize,
    avg_savings_pct: f64,
    breakdown: []CommandStats,
};

/// Response for GET /analytics/team
pub const TeamResponse = struct {
    team_id: ?[]const u8,
    total_saved_tokens: usize,
    total_requests: usize,
    avg_savings_pct: f64,
    adoption_rate: f64,
    users: []UserStats,
    daily: []DailyStats,
};

// ============================================================================
// Session Analysis Types
// ============================================================================

/// A summarized session for display
pub const SessionSummary = struct {
    id: []const u8,
    date: []const u8,
    hostname: []const u8,
    total_cmds: usize,
    llmlite_cmds: usize,
    output_tokens: usize,
};

/// Response for GET /analytics/sessions
pub const SessionsResponse = struct {
    sessions_scanned: usize,
    total_commands: usize,
    llmlite_commands: usize,
    adoption_rate: f64,
    sessions: []SessionSummary,
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Estimate token count from text length (simple approximation)
pub fn estimateTokens(text: []const u8) usize {
    if (text.len == 0) return 0;
    return @intFromFloat(@ceil(@as(f64, @floatFromInt(text.len)) / 4.0));
}

/// Calculate token savings from raw and filtered output lengths
pub fn calculateSavings(raw_len: usize, filtered_len: usize) struct { saved: usize, pct: f64 } {
    if (raw_len == 0) return .{ .saved = 0, .pct = 0.0 };
    const saved = if (raw_len > filtered_len) raw_len - filtered_len else 0;
    const pct = @as(f64, @floatFromInt(saved)) / @as(f64, @floatFromInt(raw_len)) * 100.0;
    return .{ .saved = saved, .pct = pct };
}
