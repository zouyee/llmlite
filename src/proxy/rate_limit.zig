//! Rate Limiting for llmlite Proxy
//!
//! Token bucket rate limiting implementation per virtual key

const std = @import("std");

pub const RateLimiter = struct {
    allocator: std.mem.Allocator,
    windows: std.StringArrayHashMap(RateWindow),

    /// Rate window for a key
    pub const RateWindow = struct {
        hits: []i64,
        window_start: i64,
        limit: u32,
    };

    pub fn init(allocator: std.mem.Allocator) RateLimiter {
        return .{
            .allocator = allocator,
            .windows = std.StringArrayHashMap(RateWindow).init(allocator),
        };
    }

    pub fn deinit(self: *RateLimiter) void {
        var it = self.windows.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.hits);
        }
        self.windows.deinit();
    }

    /// Check if request is allowed under rate limit
    /// Returns true if allowed, false if rate limited
    pub fn check(self: *RateLimiter, key: []const u8, limit: u32) !bool {
        const now = std.time.timestamp();

        const window = try self.windows.getOrPut(key);
        if (!window.found_existing) {
            window.value_ptr.* = .{
                .hits = &.{},
                .window_start = now,
                .limit = limit,
            };
        }

        const rate_window = window.value_ptr;

        // Clean up old hits outside 1-second window and count valid ones
        var valid_count: u32 = 0;
        for (rate_window.hits) |hit| {
            if (now - hit < 1) {
                valid_count += 1;
            }
        }

        if (valid_count >= rate_window.limit) {
            return false;
        }

        // Build new hits slice with valid entries plus current
        const new_len = valid_count + 1;
        const new_hits = try self.allocator.alloc(i64, new_len);
        var idx: u32 = 0;
        for (rate_window.hits) |hit| {
            if (now - hit < 1) {
                new_hits[idx] = hit;
                idx += 1;
            }
        }
        new_hits[idx] = now;

        self.allocator.free(rate_window.hits);
        rate_window.hits = new_hits;

        return true;
    }

    /// Get current request count for a key
    pub fn getCount(self: *RateLimiter, key: []const u8) u32 {
        const now = std.time.timestamp();
        const rate_window = self.windows.get(key) orelse return 0;

        var count: u32 = 0;
        for (rate_window.hits) |hit| {
            if (now - hit < 1) {
                count += 1;
            }
        }
        return count;
    }

    /// Reset rate limit for a key
    pub fn reset(self: *RateLimiter, key: []const u8) void {
        if (self.windows.get(key)) |rate_window| {
            self.allocator.free(rate_window.hits);
            rate_window.hits = &.{};
            rate_window.window_start = std.time.timestamp();
        }
    }
};

/// Token bucket rate limiter for more flexible rate limiting
pub const TokenBucketLimiter = struct {
    allocator: std.mem.Allocator,
    buckets: std.StringArrayHashMap(TokenBucket),

    pub const TokenBucket = struct {
        tokens: f64,
        last_refill: i64,
        refill_rate: f64,
        capacity: f64,
    };

    pub fn init(allocator: std.mem.Allocator) TokenBucketLimiter {
        return .{
            .allocator = allocator,
            .buckets = std.StringArrayHashMap(TokenBucket).init(allocator),
        };
    }

    pub fn deinit(self: *TokenBucketLimiter) void {
        var it = self.buckets.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.buckets.deinit();
    }

    /// Try to acquire a token
    pub fn tryAcquire(self: *TokenBucketLimiter, key: []const u8, capacity: u32, refill_rate: f64) !bool {
        const now = std.time.timestamp();

        const bucket = try self.buckets.getOrPut(key);
        if (!bucket.found_existing) {
            bucket.value_ptr.* = .{
                .tokens = @as(f64, capacity),
                .last_refill = now,
                .refill_rate = refill_rate,
                .capacity = @as(f64, capacity),
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
