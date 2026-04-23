//! Time Compatibility Module for Zig 0.16.0 Migration
//!
//! Provides thin wrappers around the new std.Io clock API to replace
//! the removed std.time.timestamp() and std.time.milliTimestamp().
//!
//! Usage:
//!   const time_compat = @import("time_compat");
//!   const now_secs = time_compat.timestamp(io);
//!   const now_ms = time_compat.milliTimestamp(io);

const std = @import("std");

/// Returns the current wall-clock time as seconds since the Unix epoch.
/// Replaces `std.time.timestamp()` which was removed in Zig 0.16.0.
pub fn timestamp(io: std.Io) i64 {
    const ns: i96 = std.Io.Timestamp.now(io, .real).nanoseconds;
    return @intCast(@divTrunc(ns, std.time.ns_per_s));
}

/// Returns the current wall-clock time as milliseconds since the Unix epoch.
/// Replaces `std.time.milliTimestamp()` which was removed in Zig 0.16.0.
pub fn milliTimestamp(io: std.Io) i64 {
    const ns: i96 = std.Io.Timestamp.now(io, .real).nanoseconds;
    return @intCast(@divTrunc(ns, std.time.ns_per_ms));
}

// ============================================================================
// Tests
// ============================================================================

test "timestamp returns positive value" {
    const io = std.testing.io;
    const ts = timestamp(io);
    try std.testing.expect(ts > 0);
}

test "milliTimestamp returns positive value" {
    const io = std.testing.io;
    const ms = milliTimestamp(io);
    try std.testing.expect(ms > 0);
}

test "milliTimestamp >= timestamp * 1000" {
    const io = std.testing.io;
    const ts = timestamp(io);
    const ms = milliTimestamp(io);
    // milliTimestamp should be at least timestamp * 1000 (same instant or later)
    try std.testing.expect(ms >= ts * 1000);
}

test "timestamp is consistent with milliTimestamp" {
    const io = std.testing.io;
    const ts = timestamp(io);
    const ms = milliTimestamp(io);
    // The second-precision value should match the millisecond value divided by 1000
    const ms_to_s = @divTrunc(ms, 1000);
    // Allow 1 second tolerance for clock reads at different instants
    try std.testing.expect(ms_to_s >= ts);
    try std.testing.expect(ms_to_s <= ts + 1);
}

// ============================================================================
// Property-Based Tests
// ============================================================================

// **Feature: zig-016-upgrade, Property 5: 速率限制器窗口执行正确性**
// Verify timestamp function returns monotonically increasing values at second precision.
// For any sequence of consecutive calls, each returned value must be >= the previous one.
//
// **Validates: Requirements 3.2**
test "Property 5: timestamp returns monotonically non-decreasing values" {
    const io = std.testing.io;
    const iterations: usize = 200;

    var prev = timestamp(io);
    for (0..iterations) |_| {
        const curr = timestamp(io);
        // Each successive call must return a value >= the previous
        try std.testing.expect(curr >= prev);
        prev = curr;
    }
}

// **Feature: zig-016-upgrade, Property 5 (milli): milliTimestamp monotonicity**
// Same property at millisecond precision — consecutive calls never decrease.
//
// **Validates: Requirements 3.2**
test "Property 5: milliTimestamp returns monotonically non-decreasing values" {
    const io = std.testing.io;
    const iterations: usize = 200;

    var prev = milliTimestamp(io);
    for (0..iterations) |_| {
        const curr = milliTimestamp(io);
        try std.testing.expect(curr >= prev);
        prev = curr;
    }
}
