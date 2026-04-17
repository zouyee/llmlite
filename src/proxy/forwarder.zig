//! Request Forwarder for llmlite Proxy
//!
//! Coordinates request forwarding, rectification retry, and failover.
//! This module provides the core types (ForwarderConfig, ForwardResult, Forwarder)
//! and rectification error pattern detection logic.
//!
//! The actual forward() method that coordinates with CircuitBreaker/FailoverManager
//! will be added in the integration task.

const std = @import("std");

/// Configuration for the Forwarder
pub const ForwarderConfig = struct {
    /// Maximum number of rectification retries per error type (one-retry-only policy)
    max_rectify_retries: u32 = 1,
};

/// Result of a forwarded request
pub const ForwardResult = struct {
    status_code: u16,
    body: []u8,
    provider_id: []const u8,
    latency_ms: u64,
    was_rectified: bool = false,
    was_failover: bool = false,
};

/// Request Forwarder - coordinates forwarding, rectification, and failover
pub const Forwarder = struct {
    allocator: std.mem.Allocator,
    config: ForwarderConfig,

    pub fn init(allocator: std.mem.Allocator, config: ForwarderConfig) Forwarder {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Forwarder) void {
        _ = self;
    }

    /// Deep copy a JSON body string. Caller owns the returned memory.
    pub fn cloneJsonBody(self: *Forwarder, body_json: []const u8) ![]u8 {
        return self.allocator.dupe(u8, body_json);
    }

    /// Check if error body matches one of 7 known thinking signature error patterns.
    ///
    /// Patterns (case-insensitive):
    ///   1. "invalid" + "signature" + "thinking" + "block"
    ///   2. "must start with a thinking block"
    ///   3. "expected" + ("thinking" or "redacted_thinking") + "found" + "tool_use"
    ///   4. "signature" + "field required"
    ///   5. "signature" + "extra inputs are not permitted"
    ///   6. ("thinking" or "redacted_thinking") + "cannot be modified"
    ///   7. "invalid request" or "非法请求" or "illegal request"
    pub fn shouldRectifySignature(error_body: []const u8) bool {
        var buf: [4096]u8 = undefined;
        const len = @min(error_body.len, buf.len);
        const lower = std.ascii.lowerString(buf[0..len], error_body[0..len]);

        // Pattern 1: invalid + signature + thinking + block
        if (std.mem.containsAtLeast(u8, lower, 1, "invalid") and
            std.mem.containsAtLeast(u8, lower, 1, "signature") and
            std.mem.containsAtLeast(u8, lower, 1, "thinking") and
            std.mem.containsAtLeast(u8, lower, 1, "block"))
        {
            return true;
        }

        // Pattern 2: must start with a thinking block
        if (std.mem.containsAtLeast(u8, lower, 1, "must start with a thinking block")) {
            return true;
        }

        // Pattern 3: expected + (thinking or redacted_thinking) + found + tool_use
        if (std.mem.containsAtLeast(u8, lower, 1, "expected") and
            (std.mem.containsAtLeast(u8, lower, 1, "thinking") or
                std.mem.containsAtLeast(u8, lower, 1, "redacted_thinking")) and
            std.mem.containsAtLeast(u8, lower, 1, "found") and
            std.mem.containsAtLeast(u8, lower, 1, "tool_use"))
        {
            return true;
        }

        // Pattern 4: signature + field required
        if (std.mem.containsAtLeast(u8, lower, 1, "signature") and
            std.mem.containsAtLeast(u8, lower, 1, "field required"))
        {
            return true;
        }

        // Pattern 5: signature + extra inputs are not permitted
        if (std.mem.containsAtLeast(u8, lower, 1, "signature") and
            std.mem.containsAtLeast(u8, lower, 1, "extra inputs are not permitted"))
        {
            return true;
        }

        // Pattern 6: (thinking or redacted_thinking) + cannot be modified
        if ((std.mem.containsAtLeast(u8, lower, 1, "thinking") or
            std.mem.containsAtLeast(u8, lower, 1, "redacted_thinking")) and
            std.mem.containsAtLeast(u8, lower, 1, "cannot be modified"))
        {
            return true;
        }

        // Pattern 7: invalid request / 非法请求 / illegal request
        // Note: 非法请求 is checked against original (non-lowered) since it's not ASCII
        if (std.mem.containsAtLeast(u8, lower, 1, "invalid request") or
            std.mem.containsAtLeast(u8, error_body, 1, "非法请求") or
            std.mem.containsAtLeast(u8, lower, 1, "illegal request"))
        {
            return true;
        }

        return false;
    }

    /// Check if error body matches budget constraint error pattern.
    ///
    /// Pattern (case-insensitive):
    ///   "budget_tokens" + "thinking" + ("1024" or ">= 1024" or "greater than or equal to 1024")
    pub fn shouldRectifyBudget(error_body: []const u8) bool {
        var buf: [4096]u8 = undefined;
        const len = @min(error_body.len, buf.len);
        const lower = std.ascii.lowerString(buf[0..len], error_body[0..len]);

        const has_budget_tokens = std.mem.containsAtLeast(u8, lower, 1, "budget_tokens") or
            std.mem.containsAtLeast(u8, lower, 1, "budget tokens");
        const has_thinking = std.mem.containsAtLeast(u8, lower, 1, "thinking");
        const has_1024_constraint = std.mem.containsAtLeast(u8, lower, 1, "1024") and
            (std.mem.containsAtLeast(u8, lower, 1, ">= 1024") or
                std.mem.containsAtLeast(u8, lower, 1, "greater than or equal to 1024") or
                std.mem.containsAtLeast(u8, lower, 1, "1024"));

        return has_budget_tokens and has_thinking and has_1024_constraint;
    }
    // ========================================================================
    // Forward coordination methods (Task 25)
    // ========================================================================

    pub const ProviderInfo = struct {
        id: []const u8,
        name: []const u8,
        base_url: []const u8,
        is_bedrock: bool = false,
    };

    pub const ForwardContext = struct {
        app_type: []const u8,
        providers: []const ProviderInfo,
        body: []const u8,
        is_streaming: bool = false,
    };

    /// Coordinate request forwarding across multiple providers with failover.
    /// Tries each provider in order. On failure, checks for rectification opportunity,
    /// then moves to next provider. Returns ForwardResult on first success.
    pub fn forward(self: *Forwarder, ctx: ForwardContext) ForwardResult {
        var signature_retried = false;
        var budget_retried = false;

        for (ctx.providers, 0..) |provider, i| {
            const body_clone = self.prepareProviderBody(ctx.body, provider) catch {
                continue;
            };

            const result = self.executeWithRectify(
                provider,
                body_clone,
                &signature_retried,
                &budget_retried,
            );

            if (result.status_code >= 200 and result.status_code < 300) {
                // Success — return with failover flag if not first provider
                return ForwardResult{
                    .status_code = result.status_code,
                    .body = result.body,
                    .provider_id = provider.id,
                    .latency_ms = result.latency_ms,
                    .was_rectified = result.was_rectified,
                    .was_failover = i > 0,
                };
            }

            // Failure — free the cloned body and try next provider
            self.allocator.free(body_clone);
        }

        // All providers failed
        return ForwardResult{
            .status_code = 503,
            .body = &.{},
            .provider_id = if (ctx.providers.len > 0) ctx.providers[0].id else "",
            .latency_ms = 0,
            .was_rectified = false,
            .was_failover = ctx.providers.len > 1,
        };
    }

    /// Execute a single request attempt with optional rectification retry.
    /// Returns the result of the attempt (success or final failure).
    /// Currently simulated — always returns success with the body as response.
    /// Will be connected to actual HTTP when server.zig integration happens (Task 27).
    fn executeWithRectify(
        self: *Forwarder,
        provider: ProviderInfo,
        body: []u8,
        signature_retried: *bool,
        budget_retried: *bool,
    ) ForwardResult {
        // Suppress unused parameter warnings for rectification flags.
        // The rectification detection logic (shouldRectifySignature/shouldRectifyBudget)
        // is already implemented. When actual HTTP is wired in (Task 27), these flags
        // will gate one-retry-only rectification per error type.
        _ = signature_retried;
        _ = budget_retried;
        _ = self;

        // Simulated success — return the body as the response
        return ForwardResult{
            .status_code = 200,
            .body = body,
            .provider_id = provider.id,
            .latency_ms = 0,
            .was_rectified = false,
            .was_failover = false,
        };
    }

    /// Clone body and optionally apply Bedrock optimizations.
    /// For Bedrock providers: would apply thinking_optimizer + cache_injector (Task 27).
    /// For non-Bedrock: returns plain clone.
    pub fn prepareProviderBody(self: *Forwarder, body: []const u8, provider: ProviderInfo) ![]u8 {
        const cloned = try self.cloneJsonBody(body);

        if (provider.is_bedrock) {
            // Bedrock-specific optimizations (thinking_optimizer + cache_injector)
            // will be applied here when actual HTTP integration happens in Task 27.
            // For now, just return the clone.
        }

        return cloned;
    }
};


// ============================================================================
// TESTS
// ============================================================================

test "forwarder - ForwarderConfig defaults" {
    const config = ForwarderConfig{};
    try std.testing.expectEqual(@as(u32, 1), config.max_rectify_retries);
}

test "forwarder - cloneJsonBody produces independent copy" {
    const allocator = std.testing.allocator;
    var fwd = Forwarder.init(allocator, .{});
    defer fwd.deinit();

    const original = "{\"model\":\"claude-3\",\"messages\":[]}";
    const cloned = try fwd.cloneJsonBody(original);
    defer allocator.free(cloned);

    // Content should be equal
    try std.testing.expectEqualStrings(original, cloned);

    // Pointers should be different (independent copy)
    try std.testing.expect(original.ptr != cloned.ptr);

    // Modifying clone should not affect original
    cloned[0] = 'X';
    try std.testing.expectEqual(@as(u8, '{'), original[0]);
    try std.testing.expectEqual(@as(u8, 'X'), cloned[0]);
}

test "forwarder - shouldRectifySignature pattern 1: invalid signature thinking block" {
    try std.testing.expect(Forwarder.shouldRectifySignature(
        "messages.1.content.0: Invalid `signature` in `thinking` block",
    ));
    try std.testing.expect(Forwarder.shouldRectifySignature(
        "invalid signature in thinking block",
    ));
}

test "forwarder - shouldRectifySignature pattern 2: must start with thinking block" {
    try std.testing.expect(Forwarder.shouldRectifySignature(
        "a final `assistant` message must start with a thinking block",
    ));
}

test "forwarder - shouldRectifySignature pattern 3: expected thinking found tool_use" {
    try std.testing.expect(Forwarder.shouldRectifySignature(
        "messages.69.content.0.type: Expected `thinking` or `redacted_thinking`, but found `tool_use`.",
    ));
    try std.testing.expect(Forwarder.shouldRectifySignature(
        "Expected redacted_thinking but found tool_use",
    ));
}

test "forwarder - shouldRectifySignature pattern 4: signature field required" {
    try std.testing.expect(Forwarder.shouldRectifySignature(
        "***.***.***.***.***.signature: Field required",
    ));
}

test "forwarder - shouldRectifySignature pattern 5: signature extra inputs not permitted" {
    try std.testing.expect(Forwarder.shouldRectifySignature(
        "xxx.signature: Extra inputs are not permitted",
    ));
}

test "forwarder - shouldRectifySignature pattern 6: thinking cannot be modified" {
    try std.testing.expect(Forwarder.shouldRectifySignature(
        "thinking or redacted_thinking blocks in the response cannot be modified",
    ));
    try std.testing.expect(Forwarder.shouldRectifySignature(
        "redacted_thinking blocks cannot be modified",
    ));
}

test "forwarder - shouldRectifySignature pattern 7: invalid/illegal request" {
    try std.testing.expect(Forwarder.shouldRectifySignature("invalid request: malformed JSON"));
    try std.testing.expect(Forwarder.shouldRectifySignature("illegal request: tool_use block mismatch"));
    try std.testing.expect(Forwarder.shouldRectifySignature("非法请求：thinking signature 不合法"));
}

test "forwarder - shouldRectifySignature returns false for non-matching errors" {
    try std.testing.expect(!Forwarder.shouldRectifySignature("Request timeout"));
    try std.testing.expect(!Forwarder.shouldRectifySignature("Connection refused"));
    try std.testing.expect(!Forwarder.shouldRectifySignature("Rate limit exceeded"));
    try std.testing.expect(!Forwarder.shouldRectifySignature("Internal server error"));
    try std.testing.expect(!Forwarder.shouldRectifySignature(""));
}

test "forwarder - shouldRectifyBudget detects budget constraint errors" {
    try std.testing.expect(Forwarder.shouldRectifyBudget(
        "thinking.budget_tokens: Input should be greater than or equal to 1024",
    ));
    try std.testing.expect(Forwarder.shouldRectifyBudget(
        "thinking budget_tokens must be >= 1024",
    ));
    try std.testing.expect(Forwarder.shouldRectifyBudget(
        "budget_tokens for thinking must be at least 1024",
    ));
}

test "forwarder - shouldRectifyBudget returns false for non-matching errors" {
    try std.testing.expect(!Forwarder.shouldRectifyBudget("Request timeout"));
    try std.testing.expect(!Forwarder.shouldRectifyBudget("Connection refused"));
    try std.testing.expect(!Forwarder.shouldRectifyBudget("budget_tokens is too large"));
    try std.testing.expect(!Forwarder.shouldRectifyBudget("thinking error occurred"));
    try std.testing.expect(!Forwarder.shouldRectifyBudget(""));
}

test "forwarder - ForwardResult defaults" {
    const result = ForwardResult{
        .status_code = 200,
        .body = &.{},
        .provider_id = "claude",
        .latency_ms = 150,
    };
    try std.testing.expectEqual(false, result.was_rectified);
    try std.testing.expectEqual(false, result.was_failover);
    try std.testing.expectEqual(@as(u16, 200), result.status_code);
}

// ============================================================================
// Task 25 Tests: forward(), executeWithRectify(), prepareProviderBody()
// ============================================================================

test "forwarder - forward with single provider returns success" {
    const allocator = std.testing.allocator;
    var fwd = Forwarder.init(allocator, .{});
    defer fwd.deinit();

    const providers = [_]Forwarder.ProviderInfo{
        .{ .id = "anthropic-1", .name = "Anthropic", .base_url = "https://api.anthropic.com" },
    };

    const body = "{\"model\":\"claude-3\",\"messages\":[]}";
    const result = fwd.forward(.{
        .app_type = "claude",
        .providers = &providers,
        .body = body,
    });
    defer allocator.free(result.body);

    try std.testing.expectEqual(@as(u16, 200), result.status_code);
    try std.testing.expectEqualStrings("anthropic-1", result.provider_id);
    try std.testing.expectEqual(false, result.was_failover);
    try std.testing.expectEqual(false, result.was_rectified);
    try std.testing.expectEqualStrings(body, result.body);
}

test "forwarder - forward with multiple providers uses first (simulated success)" {
    const allocator = std.testing.allocator;
    var fwd = Forwarder.init(allocator, .{});
    defer fwd.deinit();

    const providers = [_]Forwarder.ProviderInfo{
        .{ .id = "primary", .name = "Primary", .base_url = "https://primary.example.com" },
        .{ .id = "fallback", .name = "Fallback", .base_url = "https://fallback.example.com" },
    };

    const body = "{\"prompt\":\"hello\"}";
    const result = fwd.forward(.{
        .app_type = "claude",
        .providers = &providers,
        .body = body,
    });
    defer allocator.free(result.body);

    // Simulated: first provider always succeeds, so no failover
    try std.testing.expectEqual(@as(u16, 200), result.status_code);
    try std.testing.expectEqualStrings("primary", result.provider_id);
    try std.testing.expectEqual(false, result.was_failover);
}

test "forwarder - forward with zero providers returns 503" {
    const allocator = std.testing.allocator;
    var fwd = Forwarder.init(allocator, .{});
    defer fwd.deinit();

    const providers = [_]Forwarder.ProviderInfo{};
    const result = fwd.forward(.{
        .app_type = "claude",
        .providers = &providers,
        .body = "{}",
    });

    try std.testing.expectEqual(@as(u16, 503), result.status_code);
    try std.testing.expectEqual(@as(usize, 0), result.body.len);
}

test "forwarder - prepareProviderBody returns independent copy" {
    const allocator = std.testing.allocator;
    var fwd = Forwarder.init(allocator, .{});
    defer fwd.deinit();

    const original = "{\"model\":\"claude-3\",\"max_tokens\":1024}";
    const provider = Forwarder.ProviderInfo{
        .id = "p1",
        .name = "Provider1",
        .base_url = "https://example.com",
    };

    const cloned = try fwd.prepareProviderBody(original, provider);
    defer allocator.free(cloned);

    // Content equal
    try std.testing.expectEqualStrings(original, cloned);
    // Pointers different (independent copy)
    try std.testing.expect(original.ptr != cloned.ptr);

    // Mutating clone does not affect original
    cloned[0] = 'X';
    try std.testing.expectEqual(@as(u8, '{'), original[0]);
}

test "forwarder - prepareProviderBody bedrock provider returns clone" {
    const allocator = std.testing.allocator;
    var fwd = Forwarder.init(allocator, .{});
    defer fwd.deinit();

    const original = "{\"model\":\"claude-3\"}";
    const bedrock_provider = Forwarder.ProviderInfo{
        .id = "bedrock-1",
        .name = "Bedrock",
        .base_url = "https://bedrock.amazonaws.com",
        .is_bedrock = true,
    };

    const cloned = try fwd.prepareProviderBody(original, bedrock_provider);
    defer allocator.free(cloned);

    // For now, Bedrock clone is identical (optimizations deferred to Task 27)
    try std.testing.expectEqualStrings(original, cloned);
    try std.testing.expect(original.ptr != cloned.ptr);
}

test "forwarder - ForwardContext and ProviderInfo struct creation" {
    const providers = [_]Forwarder.ProviderInfo{
        .{ .id = "claude-main", .name = "Claude", .base_url = "https://api.anthropic.com" },
        .{ .id = "bedrock-1", .name = "Bedrock", .base_url = "https://bedrock.amazonaws.com", .is_bedrock = true },
    };

    const ctx = Forwarder.ForwardContext{
        .app_type = "claude",
        .providers = &providers,
        .body = "{\"test\":true}",
        .is_streaming = true,
    };

    try std.testing.expectEqualStrings("claude", ctx.app_type);
    try std.testing.expectEqual(@as(usize, 2), ctx.providers.len);
    try std.testing.expectEqual(true, ctx.is_streaming);
    try std.testing.expectEqualStrings("claude-main", ctx.providers[0].id);
    try std.testing.expectEqual(false, ctx.providers[0].is_bedrock);
    try std.testing.expectEqual(true, ctx.providers[1].is_bedrock);
}

test "forwarder - forward body isolation between providers" {
    const allocator = std.testing.allocator;
    var fwd = Forwarder.init(allocator, .{});
    defer fwd.deinit();

    const providers = [_]Forwarder.ProviderInfo{
        .{ .id = "p1", .name = "P1", .base_url = "https://p1.example.com" },
    };

    const body = "{\"data\":\"sensitive\"}";

    // First forward — get a result with cloned body
    const result1 = fwd.forward(.{
        .app_type = "test",
        .providers = &providers,
        .body = body,
    });
    defer allocator.free(result1.body);

    // Second forward — get another result
    const result2 = fwd.forward(.{
        .app_type = "test",
        .providers = &providers,
        .body = body,
    });
    defer allocator.free(result2.body);

    // Both results have same content but different memory
    try std.testing.expectEqualStrings(result1.body, result2.body);
    try std.testing.expect(result1.body.ptr != result2.body.ptr);
}
