//! Rate Limiting for llmlite Proxy
//!
//! Token bucket rate limiting implementation per virtual key

const std = @import("std");
const time_compat = @import("time_compat");

pub const RateLimiter = struct {
    allocator: std.mem.Allocator,
    windows: std.array_hash_map.String(RateWindow),

    /// Rate window for a key
    pub const RateWindow = struct {
        hits: std.ArrayList(i64),
        window_start: i64,
        limit: u32,
    };

    pub fn init(allocator: std.mem.Allocator) RateLimiter {
        return .{
            .allocator = allocator,
            .windows = std.array_hash_map.String(RateWindow){},
        };
    }

    pub fn deinit(self: *RateLimiter) void {
        var it = self.windows.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.hits.deinit(self.allocator);
        }
        self.windows.deinit(self.allocator);
    }

    /// Check if request is allowed under rate limit
    /// Returns true if allowed, false if rate limited
    pub fn check(self: *RateLimiter, io: std.Io, key: []const u8, limit: u32) !bool {
        const now = time_compat.timestamp(io);

        const window = try self.windows.getOrPut(self.allocator, key);
        if (!window.found_existing) {
            window.value_ptr.* = .{
                .hits = .empty,
                .window_start = now,
                .limit = limit,
            };
        }

        const rate_window = window.value_ptr;

        // Clean up old hits outside 1-second window
        var i: usize = 0;
        while (i < rate_window.hits.items.len) {
            if (now - rate_window.hits.items[i] >= 1) {
                _ = rate_window.hits.orderedRemove(i);
            } else {
                i += 1;
            }
        }

        if (rate_window.hits.items.len >= rate_window.limit) {
            return false;
        }

        try rate_window.hits.append(self.allocator, now);
        return true;
    }

    /// Get current request count for a key
    pub fn getCount(self: *RateLimiter, io: std.Io, key: []const u8) u32 {
        const now = time_compat.timestamp(io);
        const rate_window = self.windows.get(key) orelse return 0;

        var count: u32 = 0;
        for (rate_window.hits.items) |hit| {
            if (now - hit < 1) {
                count += 1;
            }
        }
        return count;
    }

    /// Reset rate limit for a key
    pub fn reset(self: *RateLimiter, io: std.Io, key: []const u8) void {
        if (self.windows.getPtr(key)) |rate_window| {
            rate_window.hits.clearAndFree(self.allocator);
            rate_window.window_start = time_compat.timestamp(io);
        }
    }
};

/// Token bucket rate limiter for more flexible rate limiting
pub const TokenBucketLimiter = struct {
    allocator: std.mem.Allocator,
    buckets: std.array_hash_map.String(TokenBucket),

    pub const TokenBucket = struct {
        tokens: f64,
        last_refill: i64,
        refill_rate: f64,
        capacity: f64,
    };

    pub fn init(allocator: std.mem.Allocator) TokenBucketLimiter {
        return .{
            .allocator = allocator,
            .buckets = std.array_hash_map.String(TokenBucket){},
        };
    }

    pub fn deinit(self: *TokenBucketLimiter) void {
        var it = self.buckets.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.buckets.deinit(self.allocator);
    }

    /// Try to acquire a token
    pub fn tryAcquire(self: *TokenBucketLimiter, io: std.Io, key: []const u8, capacity: u32, refill_rate: f64) !bool {
        const now = time_compat.timestamp(io);

        const bucket = try self.buckets.getOrPut(self.allocator, key);
        if (!bucket.found_existing) {
            bucket.value_ptr.* = .{
                .tokens = @as(f64, @floatFromInt(capacity)),
                .last_refill = now,
                .refill_rate = refill_rate,
                .capacity = @as(f64, @floatFromInt(capacity)),
            };
        }

        const tb = bucket.value_ptr;

        // Refill tokens based on time elapsed
        const elapsed = @as(f64, @floatFromInt(now - tb.last_refill));
        tb.tokens = @min(tb.capacity, tb.tokens + elapsed * tb.refill_rate);
        tb.last_refill = now;

        // Try to acquire a token
        if (tb.tokens >= 1.0) {
            tb.tokens -= 1.0;
            return true;
        }

        return false;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "RateLimiter - check allows requests under limit" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var limiter = RateLimiter.init(allocator);
    defer limiter.deinit();

    const key = try allocator.dupe(u8, "test-key");
    // Should allow first request
    const allowed = try limiter.check(io, key, 5);
    try std.testing.expect(allowed);
}

test "RateLimiter - check blocks requests over limit" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var limiter = RateLimiter.init(allocator);
    defer limiter.deinit();

    const key = try allocator.dupe(u8, "test-key");
    // Fill up the limit
    for (0..3) |_| {
        _ = try limiter.check(io, key, 3);
    }

    // Next request should be blocked
    const allowed = try limiter.check(io, key, 3);
    try std.testing.expect(!allowed);
}

test "RateLimiter - getCount returns current count" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var limiter = RateLimiter.init(allocator);
    defer limiter.deinit();

    const key = try allocator.dupe(u8, "test-key");
    // No requests yet
    try std.testing.expectEqual(@as(u32, 0), limiter.getCount(io, key));

    // Make some requests
    _ = try limiter.check(io, key, 10);
    _ = try limiter.check(io, key, 10);

    try std.testing.expectEqual(@as(u32, 2), limiter.getCount(io, key));
}

test "RateLimiter - reset clears hits" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var limiter = RateLimiter.init(allocator);
    defer limiter.deinit();

    const key = try allocator.dupe(u8, "test-key");
    _ = try limiter.check(io, key, 10);
    _ = try limiter.check(io, key, 10);

    limiter.reset(io, key);

    // After reset, count should be 0
    try std.testing.expectEqual(@as(u32, 0), limiter.getCount(io, key));
}

test "RateLimiter - different keys are independent" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var limiter = RateLimiter.init(allocator);
    defer limiter.deinit();

    const key_a = try allocator.dupe(u8, "key-a");
    const key_b = try allocator.dupe(u8, "key-b");

    // Fill up key-a
    for (0..2) |_| {
        _ = try limiter.check(io, key_a, 2);
    }
    const blocked = try limiter.check(io, key_a, 2);
    try std.testing.expect(!blocked);

    // key-b should still be allowed
    const allowed = try limiter.check(io, key_b, 2);
    try std.testing.expect(allowed);
}

test "TokenBucketLimiter - tryAcquire allows when tokens available" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var limiter = TokenBucketLimiter.init(allocator);
    defer limiter.deinit();

    const key = try allocator.dupe(u8, "test-key");
    const allowed = try limiter.tryAcquire(io, key, 5, 1.0);
    try std.testing.expect(allowed);
}

test "TokenBucketLimiter - tryAcquire blocks when tokens exhausted" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var limiter = TokenBucketLimiter.init(allocator);
    defer limiter.deinit();

    const key = try allocator.dupe(u8, "test-key");
    // Exhaust all tokens (capacity=2)
    _ = try limiter.tryAcquire(io, key, 2, 1.0);
    _ = try limiter.tryAcquire(io, key, 2, 1.0);

    // Should be blocked now (no time elapsed for refill)
    const allowed = try limiter.tryAcquire(io, key, 2, 1.0);
    try std.testing.expect(!allowed);
}
