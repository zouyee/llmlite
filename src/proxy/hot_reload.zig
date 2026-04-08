const std = @import("std");

pub const HotReloadConfig = struct {
    allocator: std.mem.Allocator,
    config_path: []const u8,
    last_modified: i128,
    check_interval_ms: u32,
    reload_count: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, config_path: []const u8, check_interval_ms: u32) HotReloadConfig {
        return .{
            .allocator = allocator,
            .config_path = config_path,
            .last_modified = 0,
            .check_interval_ms = check_interval_ms,
        };
    }

    pub fn deinit(self: *HotReloadConfig) void {
        _ = self;
    }

    pub fn checkAndReload(self: *HotReloadConfig) !bool {
        const file = std.fs.cwd().openFile(self.config_path, .{}) catch return false;
        defer file.close();

        const stat = file.stat() catch return false;
        const modified = stat.mtime;

        if (modified != self.last_modified) {
            self.last_modified = modified;
            self.reload_count += 1;
            std.log.info("config hot-reloaded from {s} (reload #{d})", .{ self.config_path, self.reload_count });
            return true;
        }

        return false;
    }

    pub fn getReloadCount(self: *HotReloadConfig) u32 {
        return self.reload_count;
    }

    /// Load and return a new EdgeRouterConfig from the config file
    /// Returns the new config if successful, or an error if parsing fails
    pub fn loadConfig(self: *HotReloadConfig) !EdgeRouterConfig {
        const file = try std.fs.cwd().openFile(self.config_path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 8192);
        defer self.allocator.free(content);

        // Parse JSON config
        const parsed = try std.json.parseFromSlice(EdgeRouterConfig, self.allocator, content, .{
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        return parsed.value;
    }
};

pub const EdgeRouterConfig = struct {
    enable_connection_pool: bool = true,
    max_conns_per_provider: usize = 10,
    idle_timeout_ms: u32 = 30000,
    enable_hot_reload: bool = true,
    config_check_interval_ms: u32 = 5000,
    enable_latency_tracking: bool = true,
    latency_window_size: usize = 100,
    enable_health_checker: bool = true,
    health_check_interval_ms: u32 = 30000,
    health_check_timeout_ms: u32 = 5000,
    enable_cost_aware_routing: bool = false,
    enable_semantic_cache: bool = false,
    cache_ttl_seconds: u32 = 3600,
    cache_max_entries: u32 = 1000,
};

pub fn getDefaultEdgeConfig() EdgeRouterConfig {
    return .{
        .enable_connection_pool = true,
        .max_conns_per_provider = 10,
        .idle_timeout_ms = 30000,
        .enable_hot_reload = true,
        .config_check_interval_ms = 5000,
        .enable_latency_tracking = true,
        .latency_window_size = 100,
        .enable_health_checker = true,
        .health_check_interval_ms = 30000,
        .health_check_timeout_ms = 5000,
        .enable_cost_aware_routing = false,
        .enable_semantic_cache = false,
        .cache_ttl_seconds = 3600,
        .cache_max_entries = 1000,
    };
}

// ============================================================================
// TESTS FOR HotReloadConfig
// ============================================================================

test "hot_reload - HotReloadConfig.init" {
    const allocator = std.heap.page_allocator;
    var config = HotReloadConfig.init(allocator, "proxy.json", 5000);
    defer config.deinit();

    try std.testing.expectEqualStrings("proxy.json", config.config_path);
    try std.testing.expectEqual(@as(i128, 0), config.last_modified);
    try std.testing.expectEqual(@as(u32, 5000), config.check_interval_ms);
    try std.testing.expectEqual(@as(u32, 0), config.reload_count);
}

test "hot_reload - getReloadCount" {
    const allocator = std.heap.page_allocator;
    var config = HotReloadConfig.init(allocator, "proxy.json", 5000);
    defer config.deinit();

    try std.testing.expectEqual(@as(u32, 0), config.getReloadCount());
}

test "hot_reload - checkAndReload returns false when file doesn't exist" {
    const allocator = std.heap.page_allocator;
    var config = HotReloadConfig.init(allocator, "nonexistent_file.json", 5000);
    defer config.deinit();

    const result = config.checkAndReload();
    try std.testing.expectEqual(false, result);
}

// ============================================================================
// TESTS FOR EdgeRouterConfig
// ============================================================================

test "hot_reload - EdgeRouterConfig defaults" {
    const config = EdgeRouterConfig{};

    try std.testing.expect(config.enable_connection_pool);
    try std.testing.expectEqual(@as(usize, 10), config.max_conns_per_provider);
    try std.testing.expectEqual(@as(u32, 30000), config.idle_timeout_ms);
    try std.testing.expect(config.enable_hot_reload);
    try std.testing.expectEqual(@as(u32, 5000), config.config_check_interval_ms);
    try std.testing.expect(config.enable_latency_tracking);
    try std.testing.expectEqual(@as(usize, 100), config.latency_window_size);
    try std.testing.expect(config.enable_health_checker);
    try std.testing.expectEqual(@as(u32, 30000), config.health_check_interval_ms);
    try std.testing.expectEqual(@as(u32, 5000), config.health_check_timeout_ms);
    try std.testing.expect(!config.enable_cost_aware_routing);
    try std.testing.expect(!config.enable_semantic_cache);
    try std.testing.expectEqual(@as(u32, 3600), config.cache_ttl_seconds);
    try std.testing.expectEqual(@as(u32, 1000), config.cache_max_entries);
}

test "hot_reload - getDefaultEdgeConfig" {
    const config = getDefaultEdgeConfig();

    try std.testing.expect(config.enable_connection_pool);
    try std.testing.expectEqual(@as(usize, 10), config.max_conns_per_provider);
    try std.testing.expectEqual(@as(u32, 30000), config.idle_timeout_ms);
    try std.testing.expect(config.enable_hot_reload);
    try std.testing.expectEqual(@as(u32, 5000), config.config_check_interval_ms);
    try std.testing.expect(config.enable_latency_tracking);
    try std.testing.expectEqual(@as(usize, 100), config.latency_window_size);
    try std.testing.expect(config.enable_health_checker);
    try std.testing.expectEqual(@as(u32, 30000), config.health_check_interval_ms);
    try std.testing.expectEqual(@as(u32, 5000), config.health_check_timeout_ms);
    try std.testing.expect(!config.enable_cost_aware_routing);
    try std.testing.expect(!config.enable_semantic_cache);
    try std.testing.expectEqual(@as(u32, 3600), config.cache_ttl_seconds);
    try std.testing.expectEqual(@as(u32, 1000), config.cache_max_entries);
}

test "hot_reload - EdgeRouterConfig custom values" {
    const config = EdgeRouterConfig{
        .enable_connection_pool = false,
        .max_conns_per_provider = 5,
        .idle_timeout_ms = 60000,
        .enable_hot_reload = false,
        .config_check_interval_ms = 10000,
        .enable_latency_tracking = false,
        .latency_window_size = 50,
        .enable_health_checker = false,
        .health_check_interval_ms = 60000,
        .health_check_timeout_ms = 10000,
        .enable_cost_aware_routing = true,
        .enable_semantic_cache = true,
        .cache_ttl_seconds = 7200,
        .cache_max_entries = 500,
    };

    try std.testing.expect(!config.enable_connection_pool);
    try std.testing.expectEqual(@as(usize, 5), config.max_conns_per_provider);
    try std.testing.expectEqual(@as(u32, 60000), config.idle_timeout_ms);
    try std.testing.expect(!config.enable_hot_reload);
    try std.testing.expectEqual(@as(u32, 10000), config.config_check_interval_ms);
    try std.testing.expect(!config.enable_latency_tracking);
    try std.testing.expectEqual(@as(usize, 50), config.latency_window_size);
    try std.testing.expect(!config.enable_health_checker);
    try std.testing.expectEqual(@as(u32, 60000), config.health_check_interval_ms);
    try std.testing.expectEqual(@as(u32, 10000), config.health_check_timeout_ms);
    try std.testing.expect(config.enable_cost_aware_routing);
    try std.testing.expect(config.enable_semantic_cache);
    try std.testing.expectEqual(@as(u32, 7200), config.cache_ttl_seconds);
    try std.testing.expectEqual(@as(u32, 500), config.cache_max_entries);
}
