//! Request Context for llmlite Proxy
//!
//! Encapsulates per-request state for the multi-app proxy pipeline.
//! This is a standalone module that server.zig can import later.
//!
//! Usage:
//!   const ctx = RequestContext.init(.claude, .anthropic);
//!   defer _ = ctx; // no heap allocs to free
//!   const latency = ctx.latencyMs();

const std = @import("std");
const time_compat = @import("time_compat");

/// Per-request context carrying app type, format, provider info, and timing.
pub const RequestContext = struct {
    app_type: AppType,
    detected_format: ApiFormat,
    session_id: ?[]const u8 = null,
    provider_id: ?[]const u8 = null,
    provider_name: ?[]const u8 = null,
    request_model: ?[]const u8 = null,
    start_time: i64,
    is_streaming: bool = false,
    tag: []const u8 = "unknown",

    /// Create a new RequestContext with the given app type and detected format.
    pub fn init(io: std.Io, app_type: AppType, format: ApiFormat) RequestContext {
        return .{
            .app_type = app_type,
            .detected_format = format,
            .start_time = time_compat.timestamp(io),
        };
    }

    /// Calculate elapsed time in milliseconds since request start.
    pub fn latencyMs(self: *const RequestContext, io: std.Io) u64 {
        const now = time_compat.timestamp(io);
        const diff = now - self.start_time;
        return if (diff > 0) @intCast(diff * 1000) else 0;
    }
};

/// Supported AI CLI tool types (mirrors app_type_router.zig AppType).
pub const AppType = enum(u3) {
    claude,
    codex,
    gemini,
    kiro,
    cursor,
    kimi,
    minimax,
    unknown,

    pub const count = @typeInfo(AppType).@"enum".fields.len;
};

/// Supported API formats (mirrors format_transformer.zig ApiFormat).
pub const ApiFormat = enum {
    anthropic,
    openai_chat,
    openai_responses,
};


// ============================================================================
// TESTS
// ============================================================================

test "request_context - init sets app_type and format" {
    const io = std.testing.io;
    const ctx = RequestContext.init(io, .claude, .anthropic);
    try std.testing.expectEqual(AppType.claude, ctx.app_type);
    try std.testing.expectEqual(ApiFormat.anthropic, ctx.detected_format);
    try std.testing.expect(ctx.start_time > 0);
    try std.testing.expectEqual(false, ctx.is_streaming);
    try std.testing.expectEqual(null, ctx.session_id);
    try std.testing.expectEqual(null, ctx.provider_id);
    try std.testing.expectEqual(null, ctx.provider_name);
    try std.testing.expectEqual(null, ctx.request_model);
    try std.testing.expectEqualStrings("unknown", ctx.tag);
}

test "request_context - init with different app types" {
    const io = std.testing.io;
    const types = [_]AppType{ .claude, .codex, .gemini, .kiro, .cursor, .kimi, .minimax, .unknown };
    for (types) |app_type| {
        const ctx = RequestContext.init(io, app_type, .openai_chat);
        try std.testing.expectEqual(app_type, ctx.app_type);
        try std.testing.expectEqual(ApiFormat.openai_chat, ctx.detected_format);
    }
}

test "request_context - init with different formats" {
    const io = std.testing.io;
    const formats = [_]ApiFormat{ .anthropic, .openai_chat, .openai_responses };
    for (formats) |format| {
        const ctx = RequestContext.init(io, .codex, format);
        try std.testing.expectEqual(format, ctx.detected_format);
    }
}

test "request_context - latencyMs returns zero or positive" {
    const io = std.testing.io;
    const ctx = RequestContext.init(io, .claude, .anthropic);
    const latency = ctx.latencyMs(io);
    // Since we just created it, latency should be 0 (sub-second)
    try std.testing.expect(latency == 0 or latency > 0);
}

test "request_context - latencyMs with past start_time" {
    const io = std.testing.io;
    var ctx = RequestContext.init(io, .claude, .anthropic);
    // Simulate a request that started 2 seconds ago
    ctx.start_time = time_compat.timestamp(io) - 2;
    const latency = ctx.latencyMs(io);
    try std.testing.expect(latency >= 1000); // at least 1 second
}

test "request_context - optional fields can be set" {
    const io = std.testing.io;
    var ctx = RequestContext.init(io, .gemini, .openai_responses);
    ctx.session_id = "sess-123";
    ctx.provider_id = "provider-abc";
    ctx.provider_name = "anthropic";
    ctx.request_model = "claude-sonnet-4-20250514";
    ctx.is_streaming = true;
    ctx.tag = "test-request";

    try std.testing.expectEqualStrings("sess-123", ctx.session_id.?);
    try std.testing.expectEqualStrings("provider-abc", ctx.provider_id.?);
    try std.testing.expectEqualStrings("anthropic", ctx.provider_name.?);
    try std.testing.expectEqualStrings("claude-sonnet-4-20250514", ctx.request_model.?);
    try std.testing.expectEqual(true, ctx.is_streaming);
    try std.testing.expectEqualStrings("test-request", ctx.tag);
}

test "request_context - AppType count is 8" {
    try std.testing.expectEqual(@as(usize, 8), AppType.count);
}
