//! Provider Adapter - Multi-provider authentication and request adaptation
//!
//! Provides per-provider authentication strategies and auto-detection of
//! provider types based on base_url, auth_mode, and api_key patterns.
//!
//! Usage:
//!   const adapter_type = ProviderAdapter.autoDetect("https://api.anthropic.com", null, "sk-ant-...");
//!   var adapter = ProviderAdapter.init(allocator, .{
//!       .adapter_type = .claude,
//!       .base_url = "https://api.anthropic.com",
//!       .auth_strategy = .api_key,
//!       .api_key = "sk-ant-...",
//!   });
//!   defer adapter.deinit();

const std = @import("std");

/// Supported upstream LLM provider types
pub const ProviderAdapterType = enum(u4) {
    claude,
    claude_auth,
    codex,
    gemini,
    gemini_cli,
    open_router,
    github_copilot,
    codex_oauth,
};

/// Authentication strategy for a provider
pub const AuthStrategy = enum(u3) {
    api_key,
    bearer_token,
    oauth_codex,
    oauth_copilot,
    oauth_gemini_cli,
};

/// Configuration for a provider adapter instance
pub const ProviderAdapterConfig = struct {
    adapter_type: ProviderAdapterType,
    base_url: []const u8,
    auth_strategy: AuthStrategy,
    api_key: ?[]const u8 = null,
    oauth_token: ?[]const u8 = null,
    oauth_refresh_token: ?[]const u8 = null,
    oauth_expiry: ?i64 = null,
};

pub const ProviderAdapter = struct {
    allocator: std.mem.Allocator,
    config: ProviderAdapterConfig,

    pub fn init(allocator: std.mem.Allocator, config: ProviderAdapterConfig) ProviderAdapter {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *ProviderAdapter) void {
        _ = self;
    }

    /// Auto-detect provider type from base_url, auth_mode, and api_key patterns.
    ///
    /// Detection rules (in priority order):
    /// 1. base_url contains "anthropic.com" → claude
    /// 2. base_url contains "openrouter.ai" → open_router
    /// 3. base_url contains "githubcopilot.com" → github_copilot
    /// 4. base_url contains "generativelanguage.googleapis.com" → gemini
    /// 5. auth_mode == "bearer_only" → claude_auth
    /// 6. api_key starts with "ya29." → gemini_cli
    /// 7. api_key starts with "{" (JSON) → gemini_cli
    /// 8. Default → codex
    pub fn autoDetect(base_url: []const u8, auth_mode: ?[]const u8, api_key: ?[]const u8) ProviderAdapterType {
        // URL-based detection (highest priority)
        if (asciiContains(base_url, "anthropic.com")) return .claude;
        if (asciiContains(base_url, "openrouter.ai")) return .open_router;
        if (asciiContains(base_url, "githubcopilot.com")) return .github_copilot;
        if (asciiContains(base_url, "generativelanguage.googleapis.com")) return .gemini;

        // Auth mode detection
        if (auth_mode) |mode| {
            if (std.mem.eql(u8, mode, "bearer_only")) return .claude_auth;
        }

        // API key pattern detection
        if (api_key) |key| {
            if (key.len >= 5 and std.mem.eql(u8, key[0..5], "ya29.")) return .gemini_cli;
            if (key.len > 0 and key[0] == '{') return .gemini_cli;
        }

        return .codex;
    }

    /// Build the auth header value into the provided buffer.
    /// Returns the slice of `buf` that was written.
    ///
    /// For api_key strategy:
    ///   - claude/claude_auth types: "x-api-key: {key}"
    ///   - other types: "Authorization: Bearer {key}"
    /// For bearer_token: "Authorization: Bearer {token}"
    /// For oauth_*: "Authorization: Bearer {oauth_token}"
    pub fn buildAuthHeaders(self: *const ProviderAdapter, buf: []u8) []const u8 {
        switch (self.config.auth_strategy) {
            .api_key => {
                const key = self.config.api_key orelse return buf[0..0];
                switch (self.config.adapter_type) {
                    .claude, .claude_auth => {
                        return writeHeader(buf, "x-api-key: ", key);
                    },
                    else => {
                        return writeHeader(buf, "Authorization: Bearer ", key);
                    },
                }
            },
            .bearer_token => {
                const key = self.config.api_key orelse return buf[0..0];
                return writeHeader(buf, "Authorization: Bearer ", key);
            },
            .oauth_codex, .oauth_copilot, .oauth_gemini_cli => {
                const token = self.config.oauth_token orelse return buf[0..0];
                return writeHeader(buf, "Authorization: Bearer ", token);
            },
        }
    }

    /// Check if the OAuth token has expired.
    /// Returns true if oauth_expiry is set and is less than the current time.
    pub fn isTokenExpired(self: *const ProviderAdapter) bool {
        const expiry = self.config.oauth_expiry orelse return false;
        const now = std.time.timestamp();
        return expiry < now;
    }

    /// Return the base URL for this provider.
    pub fn getEndpoint(self: *const ProviderAdapter) []const u8 {
        return self.config.base_url;
    }

    // ========================================================================
    // Claude adapter helpers (Task 24.1)
    // ========================================================================

    /// Extract ANTHROPIC_BASE_URL from settings JSON env object.
    /// Returns null if not found or parse error.
    pub fn extractClaudeBaseUrl(settings_json: []const u8) ?[]const u8 {
        return extractEnvValue(settings_json, "ANTHROPIC_BASE_URL");
    }

    /// Extract ANTHROPIC_AUTH_TOKEN from settings JSON env object.
    /// Returns null if not found or parse error.
    pub fn extractClaudeApiKey(settings_json: []const u8) ?[]const u8 {
        return extractEnvValue(settings_json, "ANTHROPIC_AUTH_TOKEN");
    }

    /// Detect the API format based on the base_url.
    /// - base_url contains "openrouter.ai" → "openai"
    /// - base_url contains "githubcopilot.com" → "openai"
    /// - default → "native"
    pub fn detectClaudeApiFormat(base_url: []const u8) []const u8 {
        if (asciiContains(base_url, "openrouter.ai")) return "openai";
        if (asciiContains(base_url, "githubcopilot.com")) return "openai";
        return "native";
    }

    // ========================================================================
    // Codex adapter helpers (Task 24.2)
    // ========================================================================

    /// Extract OPENAI_BASE_URL from settings JSON env object.
    /// Returns null if not found or parse error.
    pub fn extractCodexBaseUrl(settings_json: []const u8) ?[]const u8 {
        return extractEnvValue(settings_json, "OPENAI_BASE_URL");
    }

    /// Extract OPENAI_API_KEY from settings JSON env object.
    /// Returns null if not found or parse error.
    pub fn extractCodexApiKey(settings_json: []const u8) ?[]const u8 {
        return extractEnvValue(settings_json, "OPENAI_API_KEY");
    }

    // ========================================================================
    // Gemini adapter helpers (Task 24.3)
    // ========================================================================

    /// Extract GEMINI_API_BASE from settings JSON env object.
    /// Returns null if not found or parse error.
    pub fn extractGeminiBaseUrl(settings_json: []const u8) ?[]const u8 {
        return extractEnvValue(settings_json, "GEMINI_API_BASE");
    }

    /// Extract GEMINI_API_KEY from settings JSON env object.
    /// Returns null if not found or parse error.
    pub fn extractGeminiApiKey(settings_json: []const u8) ?[]const u8 {
        return extractEnvValue(settings_json, "GEMINI_API_KEY");
    }

    /// Check if the API key looks like a Google OAuth token.
    /// Returns true if key starts with "ya29." or "{".
    pub fn isGeminiOAuth(api_key: []const u8) bool {
        if (api_key.len >= 5 and std.mem.eql(u8, api_key[0..5], "ya29.")) return true;
        if (api_key.len > 0 and api_key[0] == '{') return true;
        return false;
    }

    // ========================================================================
    // OAuth token refresh framework (Task 24.4)
    // ========================================================================

    /// Returns true if auth_strategy is an OAuth type and the token is expired.
    pub fn needsTokenRefresh(self: *const ProviderAdapter) bool {
        return switch (self.config.auth_strategy) {
            .oauth_codex, .oauth_copilot, .oauth_gemini_cli => self.isTokenExpired(),
            else => false,
        };
    }

    /// Update the OAuth token and expiry timestamp.
    pub fn setOAuthToken(self: *ProviderAdapter, token: []const u8, expiry: i64) void {
        self.config.oauth_token = token;
        self.config.oauth_expiry = expiry;
    }
};

// ============================================================================
// Internal helpers
// ============================================================================

/// Write "{prefix}{value}" into buf, return the written slice.
fn writeHeader(buf: []u8, prefix: []const u8, value: []const u8) []const u8 {
    const total = prefix.len + value.len;
    if (total > buf.len) return buf[0..0];
    @memcpy(buf[0..prefix.len], prefix);
    @memcpy(buf[prefix.len..total], value);
    return buf[0..total];
}

/// Extract a value from the "env" object in a settings JSON string.
/// Uses std.json to parse, looks for root.env[key]. Returns null on any error.
fn extractEnvValue(settings_json: []const u8, key: []const u8) ?[]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, settings_json, .{}) catch return null;
    defer parsed.deinit();
    const root = parsed.value;
    const env_val = switch (root) {
        .object => |obj| obj.get("env") orelse return null,
        else => return null,
    };
    const env_obj = switch (env_val) {
        .object => |obj| obj,
        else => return null,
    };
    const val = env_obj.get(key) orelse return null;
    return switch (val) {
        .string => |s| s,
        else => null,
    };
}

/// Case-insensitive ASCII substring search.
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

// ============================================================================
// TESTS
// ============================================================================


// --- extractClaudeBaseUrl tests (Task 24.1) ---

test "provider_adapter - extractClaudeBaseUrl returns url from env" {
    const json_str =
        \\{"env":{"ANTHROPIC_BASE_URL":"https://api.anthropic.com"}}
    ;
    const result = ProviderAdapter.extractClaudeBaseUrl(json_str);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("https://api.anthropic.com", result.?);
}

test "provider_adapter - extractClaudeBaseUrl returns null when missing" {
    const json_str =
        \\{"env":{"OTHER_KEY":"value"}}
    ;
    try std.testing.expect(ProviderAdapter.extractClaudeBaseUrl(json_str) == null);
}

test "provider_adapter - extractClaudeBaseUrl returns null on invalid json" {
    try std.testing.expect(ProviderAdapter.extractClaudeBaseUrl("not json") == null);
}

test "provider_adapter - extractClaudeBaseUrl returns null when no env object" {
    const json_str =
        \\{"other":{"ANTHROPIC_BASE_URL":"https://api.anthropic.com"}}
    ;
    try std.testing.expect(ProviderAdapter.extractClaudeBaseUrl(json_str) == null);
}

// --- extractClaudeApiKey tests (Task 24.1) ---

test "provider_adapter - extractClaudeApiKey returns token from env" {
    const json_str =
        \\{"env":{"ANTHROPIC_AUTH_TOKEN":"sk-ant-abc123"}}
    ;
    const result = ProviderAdapter.extractClaudeApiKey(json_str);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("sk-ant-abc123", result.?);
}

test "provider_adapter - extractClaudeApiKey returns null when missing" {
    const json_str =
        \\{"env":{}}
    ;
    try std.testing.expect(ProviderAdapter.extractClaudeApiKey(json_str) == null);
}

// --- detectClaudeApiFormat tests (Task 24.1) ---

test "provider_adapter - detectClaudeApiFormat openrouter returns openai" {
    try std.testing.expectEqualStrings("openai", ProviderAdapter.detectClaudeApiFormat("https://openrouter.ai/api/v1"));
}

test "provider_adapter - detectClaudeApiFormat githubcopilot returns openai" {
    try std.testing.expectEqualStrings("openai", ProviderAdapter.detectClaudeApiFormat("https://api.githubcopilot.com"));
}

test "provider_adapter - detectClaudeApiFormat anthropic returns native" {
    try std.testing.expectEqualStrings("native", ProviderAdapter.detectClaudeApiFormat("https://api.anthropic.com"));
}

test "provider_adapter - detectClaudeApiFormat unknown returns native" {
    try std.testing.expectEqualStrings("native", ProviderAdapter.detectClaudeApiFormat("https://custom-proxy.example.com"));
}

// --- extractCodexBaseUrl tests (Task 24.2) ---

test "provider_adapter - extractCodexBaseUrl returns url from env" {
    const json_str =
        \\{"env":{"OPENAI_BASE_URL":"https://api.openai.com/v1"}}
    ;
    const result = ProviderAdapter.extractCodexBaseUrl(json_str);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("https://api.openai.com/v1", result.?);
}

test "provider_adapter - extractCodexBaseUrl returns null when missing" {
    const json_str =
        \\{"env":{}}
    ;
    try std.testing.expect(ProviderAdapter.extractCodexBaseUrl(json_str) == null);
}

// --- extractCodexApiKey tests (Task 24.2) ---

test "provider_adapter - extractCodexApiKey returns key from env" {
    const json_str =
        \\{"env":{"OPENAI_API_KEY":"sk-openai-test"}}
    ;
    const result = ProviderAdapter.extractCodexApiKey(json_str);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("sk-openai-test", result.?);
}

test "provider_adapter - extractCodexApiKey returns null when missing" {
    const json_str =
        \\{"env":{"OTHER":"val"}}
    ;
    try std.testing.expect(ProviderAdapter.extractCodexApiKey(json_str) == null);
}

// --- extractGeminiBaseUrl tests (Task 24.3) ---

test "provider_adapter - extractGeminiBaseUrl returns url from env" {
    const json_str =
        \\{"env":{"GEMINI_API_BASE":"https://generativelanguage.googleapis.com"}}
    ;
    const result = ProviderAdapter.extractGeminiBaseUrl(json_str);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("https://generativelanguage.googleapis.com", result.?);
}

test "provider_adapter - extractGeminiBaseUrl returns null when missing" {
    const json_str =
        \\{"env":{}}
    ;
    try std.testing.expect(ProviderAdapter.extractGeminiBaseUrl(json_str) == null);
}

// --- extractGeminiApiKey tests (Task 24.3) ---

test "provider_adapter - extractGeminiApiKey returns key from env" {
    const json_str =
        \\{"env":{"GEMINI_API_KEY":"AIza-gemini-key"}}
    ;
    const result = ProviderAdapter.extractGeminiApiKey(json_str);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("AIza-gemini-key", result.?);
}

test "provider_adapter - extractGeminiApiKey returns null when missing" {
    const json_str =
        \\{"env":{}}
    ;
    try std.testing.expect(ProviderAdapter.extractGeminiApiKey(json_str) == null);
}

// --- isGeminiOAuth tests (Task 24.3) ---

test "provider_adapter - isGeminiOAuth ya29 prefix returns true" {
    try std.testing.expect(ProviderAdapter.isGeminiOAuth("ya29.abc123xyz"));
}

test "provider_adapter - isGeminiOAuth json prefix returns true" {
    try std.testing.expect(ProviderAdapter.isGeminiOAuth("{\"token\":\"abc\"}"));
}

test "provider_adapter - isGeminiOAuth regular key returns false" {
    try std.testing.expect(!ProviderAdapter.isGeminiOAuth("AIza-regular-key"));
}

test "provider_adapter - isGeminiOAuth empty string returns false" {
    try std.testing.expect(!ProviderAdapter.isGeminiOAuth(""));
}

// --- needsTokenRefresh tests (Task 24.4) ---

test "provider_adapter - needsTokenRefresh returns true for expired oauth_codex" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .codex_oauth,
        .base_url = "https://api.openai.com",
        .auth_strategy = .oauth_codex,
        .oauth_token = "old-token",
        .oauth_expiry = 1000, // far in the past
    });
    defer adapter.deinit();
    try std.testing.expect(adapter.needsTokenRefresh());
}

test "provider_adapter - needsTokenRefresh returns false for non-expired oauth" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .codex_oauth,
        .base_url = "https://api.openai.com",
        .auth_strategy = .oauth_codex,
        .oauth_token = "valid-token",
        .oauth_expiry = 4102444800, // 2100-01-01
    });
    defer adapter.deinit();
    try std.testing.expect(!adapter.needsTokenRefresh());
}

test "provider_adapter - needsTokenRefresh returns false for api_key strategy" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .claude,
        .base_url = "https://api.anthropic.com",
        .auth_strategy = .api_key,
        .api_key = "sk-ant-key",
        .oauth_expiry = 1000, // expired but not oauth
    });
    defer adapter.deinit();
    try std.testing.expect(!adapter.needsTokenRefresh());
}

test "provider_adapter - needsTokenRefresh returns false for bearer_token strategy" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .claude_auth,
        .base_url = "https://proxy.example.com",
        .auth_strategy = .bearer_token,
        .api_key = "bearer-key",
    });
    defer adapter.deinit();
    try std.testing.expect(!adapter.needsTokenRefresh());
}

test "provider_adapter - needsTokenRefresh oauth_copilot expired" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .github_copilot,
        .base_url = "https://api.githubcopilot.com",
        .auth_strategy = .oauth_copilot,
        .oauth_token = "ghu_old",
        .oauth_expiry = 1000,
    });
    defer adapter.deinit();
    try std.testing.expect(adapter.needsTokenRefresh());
}

test "provider_adapter - needsTokenRefresh oauth_gemini_cli expired" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .gemini_cli,
        .base_url = "https://generativelanguage.googleapis.com",
        .auth_strategy = .oauth_gemini_cli,
        .oauth_token = "ya29.old",
        .oauth_expiry = 1000,
    });
    defer adapter.deinit();
    try std.testing.expect(adapter.needsTokenRefresh());
}

// --- setOAuthToken tests (Task 24.4) ---

test "provider_adapter - setOAuthToken updates token and expiry" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .codex_oauth,
        .base_url = "https://api.openai.com",
        .auth_strategy = .oauth_codex,
        .oauth_token = "old-token",
        .oauth_expiry = 1000,
    });
    defer adapter.deinit();

    adapter.setOAuthToken("new-token-abc", 9999999999);
    try std.testing.expectEqualStrings("new-token-abc", adapter.config.oauth_token.?);
    try std.testing.expectEqual(@as(i64, 9999999999), adapter.config.oauth_expiry.?);
}

test "provider_adapter - setOAuthToken sets token when previously null" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .codex_oauth,
        .base_url = "https://api.openai.com",
        .auth_strategy = .oauth_codex,
    });
    defer adapter.deinit();

    try std.testing.expect(adapter.config.oauth_token == null);
    adapter.setOAuthToken("fresh-token", 5000000000);
    try std.testing.expectEqualStrings("fresh-token", adapter.config.oauth_token.?);
    try std.testing.expectEqual(@as(i64, 5000000000), adapter.config.oauth_expiry.?);
}

test "provider_adapter - setOAuthToken then needsTokenRefresh reflects new expiry" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .codex_oauth,
        .base_url = "https://api.openai.com",
        .auth_strategy = .oauth_codex,
        .oauth_token = "old",
        .oauth_expiry = 1000, // expired
    });
    defer adapter.deinit();

    try std.testing.expect(adapter.needsTokenRefresh());
    adapter.setOAuthToken("refreshed", 4102444800); // 2100-01-01
    try std.testing.expect(!adapter.needsTokenRefresh());
}

// --- autoDetect tests ---

test "provider_adapter - autoDetect anthropic.com returns claude" {
    const t = ProviderAdapter.autoDetect("https://api.anthropic.com/v1", null, null);
    try std.testing.expectEqual(ProviderAdapterType.claude, t);
}

test "provider_adapter - autoDetect openrouter.ai returns open_router" {
    const t = ProviderAdapter.autoDetect("https://openrouter.ai/api/v1", null, null);
    try std.testing.expectEqual(ProviderAdapterType.open_router, t);
}

test "provider_adapter - autoDetect githubcopilot.com returns github_copilot" {
    const t = ProviderAdapter.autoDetect("https://api.githubcopilot.com", null, null);
    try std.testing.expectEqual(ProviderAdapterType.github_copilot, t);
}

test "provider_adapter - autoDetect googleapis.com returns gemini" {
    const t = ProviderAdapter.autoDetect("https://generativelanguage.googleapis.com/v1", null, null);
    try std.testing.expectEqual(ProviderAdapterType.gemini, t);
}

test "provider_adapter - autoDetect bearer_only auth_mode returns claude_auth" {
    const t = ProviderAdapter.autoDetect("https://custom-proxy.example.com", "bearer_only", null);
    try std.testing.expectEqual(ProviderAdapterType.claude_auth, t);
}

test "provider_adapter - autoDetect ya29. api_key returns gemini_cli" {
    const t = ProviderAdapter.autoDetect("https://custom.example.com", null, "ya29.abc123");
    try std.testing.expectEqual(ProviderAdapterType.gemini_cli, t);
}

test "provider_adapter - autoDetect JSON api_key returns gemini_cli" {
    const t = ProviderAdapter.autoDetect("https://custom.example.com", null, "{\"token\":\"abc\"}");
    try std.testing.expectEqual(ProviderAdapterType.gemini_cli, t);
}

test "provider_adapter - autoDetect default returns codex" {
    const t = ProviderAdapter.autoDetect("https://api.openai.com/v1", null, "sk-abc123");
    try std.testing.expectEqual(ProviderAdapterType.codex, t);
}

test "provider_adapter - autoDetect case insensitive url matching" {
    const t = ProviderAdapter.autoDetect("https://API.ANTHROPIC.COM/v1", null, null);
    try std.testing.expectEqual(ProviderAdapterType.claude, t);
}

test "provider_adapter - autoDetect url priority over auth_mode" {
    // anthropic.com URL should win over bearer_only auth_mode
    const t = ProviderAdapter.autoDetect("https://api.anthropic.com", "bearer_only", null);
    try std.testing.expectEqual(ProviderAdapterType.claude, t);
}

// --- buildAuthHeaders tests ---

test "provider_adapter - buildAuthHeaders api_key for claude uses x-api-key" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .claude,
        .base_url = "https://api.anthropic.com",
        .auth_strategy = .api_key,
        .api_key = "sk-ant-test123",
    });
    defer adapter.deinit();

    var buf: [256]u8 = undefined;
    const header = adapter.buildAuthHeaders(&buf);
    try std.testing.expectEqualStrings("x-api-key: sk-ant-test123", header);
}

test "provider_adapter - buildAuthHeaders api_key for codex uses Bearer" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .codex,
        .base_url = "https://api.openai.com",
        .auth_strategy = .api_key,
        .api_key = "sk-openai-key",
    });
    defer adapter.deinit();

    var buf: [256]u8 = undefined;
    const header = adapter.buildAuthHeaders(&buf);
    try std.testing.expectEqualStrings("Authorization: Bearer sk-openai-key", header);
}

test "provider_adapter - buildAuthHeaders bearer_token strategy" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .claude_auth,
        .base_url = "https://proxy.example.com",
        .auth_strategy = .bearer_token,
        .api_key = "my-bearer-token",
    });
    defer adapter.deinit();

    var buf: [256]u8 = undefined;
    const header = adapter.buildAuthHeaders(&buf);
    try std.testing.expectEqualStrings("Authorization: Bearer my-bearer-token", header);
}

test "provider_adapter - buildAuthHeaders oauth uses oauth_token" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .codex_oauth,
        .base_url = "https://api.openai.com",
        .auth_strategy = .oauth_codex,
        .oauth_token = "oauth-access-token-123",
    });
    defer adapter.deinit();

    var buf: [256]u8 = undefined;
    const header = adapter.buildAuthHeaders(&buf);
    try std.testing.expectEqualStrings("Authorization: Bearer oauth-access-token-123", header);
}

test "provider_adapter - buildAuthHeaders oauth_copilot" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .github_copilot,
        .base_url = "https://api.githubcopilot.com",
        .auth_strategy = .oauth_copilot,
        .oauth_token = "ghu_copilot_token",
    });
    defer adapter.deinit();

    var buf: [256]u8 = undefined;
    const header = adapter.buildAuthHeaders(&buf);
    try std.testing.expectEqualStrings("Authorization: Bearer ghu_copilot_token", header);
}

test "provider_adapter - buildAuthHeaders oauth_gemini_cli" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .gemini_cli,
        .base_url = "https://generativelanguage.googleapis.com",
        .auth_strategy = .oauth_gemini_cli,
        .oauth_token = "ya29.gemini-oauth",
    });
    defer adapter.deinit();

    var buf: [256]u8 = undefined;
    const header = adapter.buildAuthHeaders(&buf);
    try std.testing.expectEqualStrings("Authorization: Bearer ya29.gemini-oauth", header);
}

test "provider_adapter - buildAuthHeaders returns empty when no key" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .codex,
        .base_url = "https://api.openai.com",
        .auth_strategy = .api_key,
        // no api_key set
    });
    defer adapter.deinit();

    var buf: [256]u8 = undefined;
    const header = adapter.buildAuthHeaders(&buf);
    try std.testing.expectEqual(@as(usize, 0), header.len);
}

test "provider_adapter - buildAuthHeaders oauth returns empty when no oauth_token" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .codex_oauth,
        .base_url = "https://api.openai.com",
        .auth_strategy = .oauth_codex,
        // no oauth_token set
    });
    defer adapter.deinit();

    var buf: [256]u8 = undefined;
    const header = adapter.buildAuthHeaders(&buf);
    try std.testing.expectEqual(@as(usize, 0), header.len);
}

// --- isTokenExpired tests ---

test "provider_adapter - isTokenExpired returns false when no expiry" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .codex_oauth,
        .base_url = "https://api.openai.com",
        .auth_strategy = .oauth_codex,
    });
    defer adapter.deinit();

    try std.testing.expect(!adapter.isTokenExpired());
}

test "provider_adapter - isTokenExpired returns true for past expiry" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .codex_oauth,
        .base_url = "https://api.openai.com",
        .auth_strategy = .oauth_codex,
        .oauth_expiry = 1000, // epoch + 1000s, definitely in the past
    });
    defer adapter.deinit();

    try std.testing.expect(adapter.isTokenExpired());
}

test "provider_adapter - isTokenExpired returns false for far future expiry" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .codex_oauth,
        .base_url = "https://api.openai.com",
        .auth_strategy = .oauth_codex,
        .oauth_expiry = 4102444800, // 2100-01-01
    });
    defer adapter.deinit();

    try std.testing.expect(!adapter.isTokenExpired());
}

// --- getEndpoint tests ---

test "provider_adapter - getEndpoint returns base_url" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .claude,
        .base_url = "https://api.anthropic.com",
        .auth_strategy = .api_key,
    });
    defer adapter.deinit();

    try std.testing.expectEqualStrings("https://api.anthropic.com", adapter.getEndpoint());
}

// --- init/deinit tests ---

test "provider_adapter - init and deinit" {
    var adapter = ProviderAdapter.init(std.testing.allocator, .{
        .adapter_type = .gemini,
        .base_url = "https://generativelanguage.googleapis.com",
        .auth_strategy = .api_key,
        .api_key = "AIza-test",
    });
    defer adapter.deinit();

    try std.testing.expectEqual(ProviderAdapterType.gemini, adapter.config.adapter_type);
    try std.testing.expectEqual(AuthStrategy.api_key, adapter.config.auth_strategy);
    try std.testing.expectEqualStrings("AIza-test", adapter.config.api_key.?);
}
