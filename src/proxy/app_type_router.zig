//! App Type Router - Multi-application request dispatcher
//!
//! Detects the AI CLI tool type from request path and User-Agent,
//! and manages per-app configuration for proxy routing.
//!
//! Usage:
//!   var router = AppTypeRouter.init(allocator);
//!   defer router.deinit();
//!   const app_type = AppTypeRouter.detectAppType("/v1/messages", null);
//!   const config = router.getConfig(app_type);

const std = @import("std");

/// Supported AI CLI tool types
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

/// Per-app proxy configuration
pub const AppConfig = struct {
    enabled: bool = true,
    failover_enabled: bool = true,
    stream_first_byte_timeout_ms: u32 = 30000,
    stream_idle_timeout_ms: u32 = 60000,
    non_stream_timeout_ms: u32 = 120000,
};

pub const AppTypeRouter = struct {
    allocator: std.mem.Allocator,
    configs: [AppType.count]AppConfig,

    pub fn init(allocator: std.mem.Allocator) AppTypeRouter {
        var configs: [AppType.count]AppConfig = undefined;
        for (&configs) |*c| {
            c.* = AppConfig{};
        }
        return .{
            .allocator = allocator,
            .configs = configs,
        };
    }

    pub fn deinit(self: *AppTypeRouter) void {
        _ = self;
    }

    /// Detect AppType from request path and optional User-Agent header.
    ///
    /// Detection rules:
    /// - /v1/messages → claude
    /// - /v1/chat/completions → codex (default OpenAI format)
    /// - paths containing "gemini" or "generateContent" → gemini
    /// - User-Agent containing "kiro" → kiro
    /// - User-Agent containing "cursor" → cursor
    /// - User-Agent containing "kimi" → kimi
    /// - User-Agent containing "minimax" → minimax
    /// - Otherwise → unknown
    pub fn detectAppType(path: []const u8, user_agent: ?[]const u8) AppType {
        // Path-based detection (highest priority)
        if (asciiContains(path, "/v1/messages")) {
            return .claude;
        }
        if (asciiContains(path, "/v1/chat/completions")) {
            return .codex;
        }
        if (asciiContains(path, "gemini") or asciiContains(path, "generateContent")) {
            return .gemini;
        }

        // User-Agent based detection
        if (user_agent) |ua| {
            const lower_buf = lowerBuf(ua);
            const lower = lower_buf[0..ua.len];

            if (std.mem.indexOf(u8, lower, "kiro") != null) return .kiro;
            if (std.mem.indexOf(u8, lower, "cursor") != null) return .cursor;
            if (std.mem.indexOf(u8, lower, "kimi") != null) return .kimi;
            if (std.mem.indexOf(u8, lower, "minimax") != null) return .minimax;
        }

        return .unknown;
    }

    /// Get the config for a given AppType.
    pub fn getConfig(self: *const AppTypeRouter, app_type: AppType) *const AppConfig {
        return &self.configs[@intFromEnum(app_type)];
    }

    /// Update the config for a given AppType.
    pub fn updateConfig(self: *AppTypeRouter, app_type: AppType, config: AppConfig) void {
        self.configs[@intFromEnum(app_type)] = config;
    }

    /// Check if a given AppType is enabled.
    pub fn isEnabled(self: *const AppTypeRouter, app_type: AppType) bool {
        return self.configs[@intFromEnum(app_type)].enabled;
    }
};

/// Case-insensitive substring search for ASCII strings.
fn asciiContains(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    if (needle.len == 0) return true;
    const end = haystack.len - needle.len + 1;
    for (0..end) |i| {
        var match = true;
        for (0..needle.len) |j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(needle[j])) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

/// Lowercase a slice into a stack buffer (max 1024 bytes).
fn lowerBuf(s: []const u8) [1024]u8 {
    var buf: [1024]u8 = undefined;
    const len = @min(s.len, 1024);
    for (0..len) |i| {
        buf[i] = std.ascii.toLower(s[i]);
    }
    return buf;
}

// ============================================================================
// TESTS
// ============================================================================

test "app_type_router - detectAppType with /v1/messages returns claude" {
    const app_type = AppTypeRouter.detectAppType("/v1/messages", null);
    try std.testing.expectEqual(AppType.claude, app_type);
}

test "app_type_router - detectAppType with /v1/chat/completions returns codex" {
    const app_type = AppTypeRouter.detectAppType("/v1/chat/completions", null);
    try std.testing.expectEqual(AppType.codex, app_type);
}

test "app_type_router - detectAppType with gemini path returns gemini" {
    const t1 = AppTypeRouter.detectAppType("/v1beta/models/gemini-pro:generateContent", null);
    try std.testing.expectEqual(AppType.gemini, t1);

    const t2 = AppTypeRouter.detectAppType("/v1/gemini/chat", null);
    try std.testing.expectEqual(AppType.gemini, t2);
}

test "app_type_router - detectAppType with generateContent path returns gemini" {
    const app_type = AppTypeRouter.detectAppType("/v1beta/models/some-model:generateContent", null);
    try std.testing.expectEqual(AppType.gemini, app_type);
}

test "app_type_router - detectAppType with User-Agent kiro" {
    const app_type = AppTypeRouter.detectAppType("/some/path", "Kiro/1.0");
    try std.testing.expectEqual(AppType.kiro, app_type);
}

test "app_type_router - detectAppType with User-Agent cursor" {
    const app_type = AppTypeRouter.detectAppType("/some/path", "Cursor-Agent/2.0");
    try std.testing.expectEqual(AppType.cursor, app_type);
}

test "app_type_router - detectAppType with User-Agent kimi" {
    const app_type = AppTypeRouter.detectAppType("/some/path", "kimi-cli/0.1");
    try std.testing.expectEqual(AppType.kimi, app_type);
}

test "app_type_router - detectAppType with User-Agent minimax" {
    const app_type = AppTypeRouter.detectAppType("/some/path", "MiniMax-SDK/1.0");
    try std.testing.expectEqual(AppType.minimax, app_type);
}

test "app_type_router - detectAppType unknown path and no user-agent" {
    const app_type = AppTypeRouter.detectAppType("/unknown/path", null);
    try std.testing.expectEqual(AppType.unknown, app_type);
}

test "app_type_router - detectAppType path takes priority over user-agent" {
    // Even with a kiro user-agent, /v1/messages should detect as claude
    const app_type = AppTypeRouter.detectAppType("/v1/messages", "Kiro/1.0");
    try std.testing.expectEqual(AppType.claude, app_type);
}

test "app_type_router - config isolation between app types" {
    var router = AppTypeRouter.init(std.testing.allocator);
    defer router.deinit();

    // Update claude config
    router.updateConfig(.claude, .{
        .enabled = false,
        .failover_enabled = false,
        .stream_first_byte_timeout_ms = 5000,
        .stream_idle_timeout_ms = 10000,
        .non_stream_timeout_ms = 20000,
    });

    // Claude should have updated values
    const claude_cfg = router.getConfig(.claude);
    try std.testing.expectEqual(false, claude_cfg.enabled);
    try std.testing.expectEqual(@as(u32, 5000), claude_cfg.stream_first_byte_timeout_ms);

    // Codex should still have defaults
    const codex_cfg = router.getConfig(.codex);
    try std.testing.expectEqual(true, codex_cfg.enabled);
    try std.testing.expectEqual(@as(u32, 30000), codex_cfg.stream_first_byte_timeout_ms);

    // Unknown should still have defaults
    const unknown_cfg = router.getConfig(.unknown);
    try std.testing.expectEqual(true, unknown_cfg.enabled);
    try std.testing.expectEqual(@as(u32, 120000), unknown_cfg.non_stream_timeout_ms);
}

test "app_type_router - isEnabled check" {
    var router = AppTypeRouter.init(std.testing.allocator);
    defer router.deinit();

    // All enabled by default
    try std.testing.expect(router.isEnabled(.claude));
    try std.testing.expect(router.isEnabled(.codex));
    try std.testing.expect(router.isEnabled(.unknown));

    // Disable gemini
    router.updateConfig(.gemini, .{
        .enabled = false,
    });
    try std.testing.expect(!router.isEnabled(.gemini));

    // Others still enabled
    try std.testing.expect(router.isEnabled(.claude));
    try std.testing.expect(router.isEnabled(.codex));
}

test "app_type_router - init sets all configs to defaults" {
    var router = AppTypeRouter.init(std.testing.allocator);
    defer router.deinit();

    // Check every app type has default config
    inline for (0..AppType.count) |i| {
        const app_type: AppType = @enumFromInt(i);
        const cfg = router.getConfig(app_type);
        try std.testing.expectEqual(true, cfg.enabled);
        try std.testing.expectEqual(true, cfg.failover_enabled);
        try std.testing.expectEqual(@as(u32, 30000), cfg.stream_first_byte_timeout_ms);
        try std.testing.expectEqual(@as(u32, 60000), cfg.stream_idle_timeout_ms);
        try std.testing.expectEqual(@as(u32, 120000), cfg.non_stream_timeout_ms);
    }
}
