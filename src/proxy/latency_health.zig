const std = @import("std");
const time_compat = @import("time_compat");

// Zig 0.16.0 compat: managed StringArrayHashMap wrapper
fn StringArrayHashMap(comptime V: type) type {
    return struct {
        const Self = @This();
        unmanaged: std.StringArrayHashMapUnmanaged(V),
        allocator: std.mem.Allocator,
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .unmanaged = .empty, .allocator = allocator };
        }
        pub fn deinit(self: *Self) void { self.unmanaged.deinit(self.allocator); }
        pub fn put(self: *Self, key: []const u8, value: V) !void { return self.unmanaged.put(self.allocator, key, value); }
        pub fn get(self: Self, key: []const u8) ?V { return self.unmanaged.get(key); }
        pub fn getPtr(self: Self, key: []const u8) ?*V { return self.unmanaged.getPtr(key); }
        pub fn getOrPut(self: *Self, key: []const u8) !std.StringArrayHashMapUnmanaged(V).GetOrPutResult { return self.unmanaged.getOrPut(self.allocator, key); }
        pub fn getOrPutValue(self: *Self, key: []const u8, value: V) !std.StringArrayHashMapUnmanaged(V).GetOrPutResult { return self.unmanaged.getOrPutValue(self.allocator, key, value); }
        pub fn contains(self: Self, key: []const u8) bool { return self.unmanaged.contains(key); }
        pub fn count(self: Self) usize { return self.unmanaged.count(); }
        pub fn iterator(self: Self) std.StringArrayHashMapUnmanaged(V).Iterator { return self.unmanaged.iterator(); }
        pub fn fetchSwapRemove(self: *Self, key: []const u8) ?std.StringArrayHashMapUnmanaged(V).KV { return self.unmanaged.fetchSwapRemove(key); }
        pub fn fetchRemove(self: *Self, key: []const u8) ?std.StringArrayHashMapUnmanaged(V).KV { return self.unmanaged.fetchSwapRemove(key); }
        pub fn swapRemove(self: *Self, key: []const u8) bool { return self.unmanaged.swapRemove(key); }
        pub fn keys(self: Self) [][]const u8 { return self.unmanaged.keys(); }
        pub fn values(self: Self) []V { return self.unmanaged.values(); }
    };
}
const provider_types = @import("types");

pub const LatencyTracker = struct {
    allocator: std.mem.Allocator,
    window_size: usize,
    provider_stats: StringArrayHashMap(ProviderLatencyStats),

    pub const ProviderLatencyStats = struct {
        samples: []u64,
        sum: u64 = 0,
        count: u64 = 0,
        p50: u64 = 0,
        p95: u64 = 0,
        p99: u64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator, window_size: usize) LatencyTracker {
        return .{
            .allocator = allocator,
            .window_size = window_size,
            .provider_stats = StringArrayHashMap(ProviderLatencyStats).init(allocator),
        };
    }

    pub fn deinit(self: *LatencyTracker) void {
        var it = self.provider_stats.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.samples);
        }
        self.provider_stats.deinit();
    }

    pub fn record(self: *LatencyTracker, provider: provider_types.ProviderType, latency_ms: u64) void {
        const provider_name = provider.toString();
        var stats = self.provider_stats.getOrPut(provider_name) catch return;
        if (!stats.found_existing) {
            stats.value_ptr.* = .{
                .samples = &.{},
                .sum = 0,
                .count = 0,
                .p50 = 0,
                .p95 = 0,
                .p99 = 0,
            };
        }

        // Grow samples array
        var new_samples = self.allocator.alloc(u64, stats.value_ptr.count + 1) catch return;
        @memcpy(new_samples[0..stats.value_ptr.count], stats.value_ptr.samples);
        new_samples[stats.value_ptr.count] = latency_ms;

        if (stats.value_ptr.samples.len > 0) {
            self.allocator.free(stats.value_ptr.samples);
        }
        stats.value_ptr.samples = new_samples;
        stats.value_ptr.sum += latency_ms;
        stats.value_ptr.count += 1;

        // Keep only window_size samples
        while (stats.value_ptr.count > self.window_size) {
            stats.value_ptr.sum -= stats.value_ptr.samples[0];
            stats.value_ptr.count -= 1;
            // Shift array
            for (1..stats.value_ptr.count + 1) |i| {
                stats.value_ptr.samples[i - 1] = stats.value_ptr.samples[i];
            }
        }

        self.calculatePercentiles(stats.value_ptr);
    }

    fn calculatePercentiles(self: *LatencyTracker, stats: *ProviderLatencyStats) void {
        _ = self;
        if (stats.count == 0) return;

        // Sort only the valid samples
        std.mem.sort(u64, stats.samples[0..stats.count], {}, std.sort.asc(u64));

        // Calculate percentile indices using linear interpolation
        // For count=100: idx50=49, idx95=94, idx99=98 (0-indexed)
        const count_minus_1 = stats.count - 1;
        const idx50 = (count_minus_1 * 50) / 100;
        const idx95 = (count_minus_1 * 95) / 100;
        const idx99 = (count_minus_1 * 99) / 100;

        stats.p50 = stats.samples[idx50];
        stats.p95 = stats.samples[idx95];
        stats.p99 = stats.samples[idx99];
    }

    pub fn getMovingAvg(self: *LatencyTracker, provider: provider_types.ProviderType) u64 {
        const provider_name = provider.toString();
        const stats = self.provider_stats.get(provider_name) orelse return 0;
        if (stats.count == 0) return 0;
        return stats.sum / stats.count;
    }

    pub fn getPercentile(self: *LatencyTracker, provider: provider_types.ProviderType, percentile: u8) u64 {
        const provider_name = provider.toString();
        const stats = self.provider_stats.get(provider_name) orelse return 0;
        return switch (percentile) {
            50 => stats.p50,
            95 => stats.p95,
            99 => stats.p99,
            else => 0,
        };
    }

    pub fn selectFastestProvider(self: *LatencyTracker, providers: []const provider_types.ProviderType) provider_types.ProviderType {
        var fastest: provider_types.ProviderType = providers[0];
        var fastest_avg: u64 = std.math.maxInt(u64);

        for (providers) |provider| {
            const avg = self.getMovingAvg(provider);
            if (avg > 0 and avg < fastest_avg) {
                fastest_avg = avg;
                fastest = provider;
            }
        }

        return fastest;
    }
};

pub const HealthChecker = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    check_interval_ms: u32,
    timeout_ms: u32,
    provider_health: StringArrayHashMap(HealthStatus),

    pub const HealthStatus = struct {
        is_healthy: bool = true,
        last_check: i64,
        consecutive_failures: u32 = 0,
        latency_ms: u64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator, io: std.Io, check_interval_ms: u32, timeout_ms: u32) HealthChecker {
        return .{
            .allocator = allocator,
            .io = io,
            .check_interval_ms = check_interval_ms,
            .timeout_ms = timeout_ms,
            .provider_health = StringArrayHashMap(HealthStatus).init(allocator),
        };
    }

    pub fn deinit(self: *HealthChecker) void {
        self.provider_health.deinit();
    }

    pub fn recordSuccess(self: *HealthChecker, provider: provider_types.ProviderType, latency_ms: u64) void {
        const provider_name = provider.toString();
        var status = self.provider_health.getOrPut(provider_name) catch return;
        if (!status.found_existing) {
            status.value_ptr.* = .{
                .last_check = time_compat.timestamp(self.io),
            };
        }

        status.value_ptr.is_healthy = true;
        status.value_ptr.consecutive_failures = 0;
        status.value_ptr.latency_ms = latency_ms;
        status.value_ptr.last_check = time_compat.timestamp(self.io);
    }

    pub fn recordFailure(self: *HealthChecker, provider: provider_types.ProviderType) void {
        const provider_name = provider.toString();
        var status = self.provider_health.getOrPut(provider_name) catch return;
        if (!status.found_existing) {
            status.value_ptr.* = .{
                .last_check = time_compat.timestamp(self.io),
            };
        }

        status.value_ptr.consecutive_failures += 1;
        status.value_ptr.last_check = time_compat.timestamp(self.io);

        if (status.value_ptr.consecutive_failures >= 3) {
            status.value_ptr.is_healthy = false;
        }
    }

    pub fn isHealthy(self: *HealthChecker, provider: provider_types.ProviderType) bool {
        const provider_name = provider.toString();
        const status = self.provider_health.get(provider_name) orelse return true;
        return status.is_healthy;
    }
};

// ============================================================================
// TESTS FOR LatencyTracker
// ============================================================================

test "latency tracker - init and deinit" {
    const allocator = std.heap.page_allocator;
    var tracker = LatencyTracker.init(allocator, 100);
    defer tracker.deinit();

    try std.testing.expectEqual(@as(usize, 100), tracker.window_size);
    try std.testing.expectEqual(@as(usize, 0), tracker.provider_stats.count());
}

test "latency tracker - record single sample" {
    const allocator = std.heap.page_allocator;
    var tracker = LatencyTracker.init(allocator, 100);
    defer tracker.deinit();

    tracker.record(.openai, 100);

    const avg = tracker.getMovingAvg(.openai);
    try std.testing.expectEqual(@as(u64, 100), avg);
}

test "latency tracker - record multiple samples calculates average" {
    const allocator = std.heap.page_allocator;
    var tracker = LatencyTracker.init(allocator, 100);
    defer tracker.deinit();

    // Record 5 samples: 100, 200, 300, 400, 500 = sum 1500, avg 300
    tracker.record(.openai, 100);
    tracker.record(.openai, 200);
    tracker.record(.openai, 300);
    tracker.record(.openai, 400);
    tracker.record(.openai, 500);

    const avg = tracker.getMovingAvg(.openai);
    try std.testing.expectEqual(@as(u64, 300), avg);
}

test "latency tracker - percentiles" {
    const allocator = std.heap.page_allocator;
    var tracker = LatencyTracker.init(allocator, 100);
    defer tracker.deinit();

    // Record 100 samples from 1 to 100
    var i: u64 = 1;
    while (i <= 100) : (i += 1) {
        tracker.record(.openai, i);
    }

    // P50 should be around 50-51
    const p50 = tracker.getPercentile(.openai, 50);
    try std.testing.expect(p50 >= 49 and p50 <= 51);

    // P95 should be around 95
    const p95 = tracker.getPercentile(.openai, 95);
    try std.testing.expect(p95 >= 94 and p95 <= 96);

    // P99 should be around 99
    const p99 = tracker.getPercentile(.openai, 99);
    try std.testing.expect(p99 >= 98 and p99 <= 100);
}

test "latency tracker - window size limits samples" {
    const allocator = std.heap.page_allocator;
    var tracker = LatencyTracker.init(allocator, 10); // Window of 10
    defer tracker.deinit();

    // Record 20 samples
    var i: u64 = 1;
    while (i <= 20) : (i += 1) {
        tracker.record(.openai, i * 10); // 10, 20, 30, ... 200
    }

    // Average should be of last 10 samples (110-200 = 1550 / 10 = 155)
    const avg = tracker.getMovingAvg(.openai);
    try std.testing.expectEqual(@as(u64, 155), avg);
}

test "latency tracker - getPercentile for unknown provider returns 0" {
    const allocator = std.heap.page_allocator;
    var tracker = LatencyTracker.init(allocator, 100);
    defer tracker.deinit();

    const p50 = tracker.getPercentile(.openai, 50);
    try std.testing.expectEqual(@as(u64, 0), p50);
}

test "latency tracker - getMovingAvg for unknown provider returns 0" {
    const allocator = std.heap.page_allocator;
    var tracker = LatencyTracker.init(allocator, 100);
    defer tracker.deinit();

    const avg = tracker.getMovingAvg(.openai);
    try std.testing.expectEqual(@as(u64, 0), avg);
}

test "latency tracker - selectFastestProvider" {
    const allocator = std.heap.page_allocator;
    var tracker = LatencyTracker.init(allocator, 100);
    defer tracker.deinit();

    // OpenAI: avg 100ms, Anthropic: avg 200ms, Google: avg 150ms
    tracker.record(.openai, 100);
    tracker.record(.anthropic, 200);
    tracker.record(.google, 150);

    const providers = &.{ .openai, .anthropic, .google };
    const fastest = tracker.selectFastestProvider(providers);

    try std.testing.expect(fastest == .openai);
}

test "latency tracker - selectFastestProvider returns first if all same" {
    const allocator = std.heap.page_allocator;
    var tracker = LatencyTracker.init(allocator, 100);
    defer tracker.deinit();

    // All same latency
    tracker.record(.openai, 100);
    tracker.record(.anthropic, 100);
    tracker.record(.google, 100);

    const providers = &.{ .openai, .anthropic, .google };
    const fastest = tracker.selectFastestProvider(providers);

    // Should return first provider with lowest (equal) latency
    try std.testing.expect(fastest == .openai);
}

test "latency tracker - selectFastestProvider ignores zero latency" {
    const allocator = std.heap.page_allocator;
    var tracker = LatencyTracker.init(allocator, 100);
    defer tracker.deinit();

    // OpenAI has no samples (returns 0), Anthropic has 100ms
    tracker.record(.anthropic, 100);
    tracker.record(.google, 200);

    const providers = &.{ .openai, .anthropic, .google };
    const fastest = tracker.selectFastestProvider(providers);

    // Should skip OpenAI (0 latency) and pick Anthropic
    try std.testing.expect(fastest == .anthropic);
}

// ============================================================================
// TESTS FOR HealthChecker
// ============================================================================

test "health checker - init and deinit" {
    const allocator = std.heap.page_allocator;
    var checker = HealthChecker.init(allocator, 30000, 5000);
    defer checker.deinit();

    try std.testing.expectEqual(@as(u32, 30000), checker.check_interval_ms);
    try std.testing.expectEqual(@as(u32, 5000), checker.timeout_ms);
    try std.testing.expectEqual(@as(usize, 0), checker.provider_health.count());
}

test "health checker - isHealthy returns true for unknown provider" {
    const allocator = std.heap.page_allocator;
    var checker = HealthChecker.init(allocator, 30000, 5000);
    defer checker.deinit();

    // Unknown provider is considered healthy
    try std.testing.expect(checker.isHealthy(.openai));
}

test "health checker - recordSuccess marks healthy" {
    const allocator = std.heap.page_allocator;
    var checker = HealthChecker.init(allocator, 30000, 5000);
    defer checker.deinit();

    checker.recordSuccess(.openai, 100);

    try std.testing.expect(checker.isHealthy(.openai));
}

test "health checker - consecutive failures mark unhealthy after threshold" {
    const allocator = std.heap.page_allocator;
    var checker = HealthChecker.init(allocator, 30000, 5000);
    defer checker.deinit();

    // 2 failures - still healthy
    checker.recordFailure(.openai);
    checker.recordFailure(.openai);
    try std.testing.expect(checker.isHealthy(.openai));

    // 3rd failure - now unhealthy
    checker.recordFailure(.openai);
    try std.testing.expect(!checker.isHealthy(.openai));
}

test "health checker - success resets consecutive failures" {
    const allocator = std.heap.page_allocator;
    var checker = HealthChecker.init(allocator, 30000, 5000);
    defer checker.deinit();

    // 2 failures
    checker.recordFailure(.openai);
    checker.recordFailure(.openai);
    try std.testing.expect(checker.isHealthy(.openai));

    // Success resets
    checker.recordSuccess(.openai, 100);

    // Now need 3 more failures to become unhealthy
    checker.recordFailure(.openai);
    checker.recordFailure(.openai);
    try std.testing.expect(checker.isHealthy(.openai));

    checker.recordFailure(.openai);
    try std.testing.expect(!checker.isHealthy(.openai));
}

test "health checker - multiple providers independent" {
    const allocator = std.heap.page_allocator;
    var checker = HealthChecker.init(allocator, 30000, 5000);
    defer checker.deinit();

    // OpenAI becomes unhealthy
    checker.recordFailure(.openai);
    checker.recordFailure(.openai);
    checker.recordFailure(.openai);
    try std.testing.expect(!checker.isHealthy(.openai));

    // Anthropic is still healthy
    try std.testing.expect(checker.isHealthy(.anthropic));

    // Google is still healthy
    try std.testing.expect(checker.isHealthy(.google));
}

test "health checker - recordSuccess updates latency" {
    const allocator = std.heap.page_allocator;
    var checker = HealthChecker.init(allocator, 30000, 5000);
    defer checker.deinit();

    checker.recordSuccess(.openai, 250);

    // Check via stats
    const stats = checker.provider_health.get("openai");
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u64, 250), stats.?.latency_ms);
}
