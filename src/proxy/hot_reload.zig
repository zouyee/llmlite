const std = @import("std");

pub const HotReloadConfig = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    config_path: []const u8,
    last_modified: std.Io.Timestamp,
    check_interval_ms: u32,
    reload_count: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, config_path: []const u8, check_interval_ms: u32) HotReloadConfig {
        return .{
            .allocator = allocator,
            .io = io,
            .config_path = config_path,
            .last_modified = .{ .nanoseconds = 0 },
            .check_interval_ms = check_interval_ms,
        };
    }

    pub fn deinit(self: *HotReloadConfig) void {
        _ = self;
    }

    pub fn checkAndReload(self: *HotReloadConfig) !bool {
        // Use cwd().openFile for relative paths, openFileAbsolute only for absolute paths
        const file = if (std.fs.path.isAbsolute(self.config_path))
            std.Io.Dir.openFileAbsolute(self.io, self.config_path, .{}) catch return false
        else
            std.Io.Dir.cwd().openFile(self.io, self.config_path, .{}) catch return false;
        defer file.close(self.io);

        const stat = file.stat(self.io) catch return false;
        const modified = stat.mtime;

        if (modified.nanoseconds != self.last_modified.nanoseconds) {
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
        const file = if (std.fs.path.isAbsolute(self.config_path))
            try std.Io.Dir.openFileAbsolute(self.io, self.config_path, .{})
        else
            try std.Io.Dir.cwd().openFile(self.io, self.config_path, .{});
        defer file.close(self.io);

        var reader_buffer: [8192]u8 = undefined;
        var file_reader = file.reader(self.io, &reader_buffer);
        const content = try file_reader.interface.allocRemaining(self.allocator, .limited(8192));
        defer self.allocator.free(content);

        // Parse JSON config
        const parsed = try std.json.parseFromSlice(EdgeRouterConfig, self.allocator, content, .{
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        var result = parsed.value;
        // Deep copy string fields so they survive parsed.deinit()
        if (result.enabled_providers) |ep| {
            result.enabled_providers = try self.allocator.dupe(u8, ep);
        }
        // Deep copy per-provider override strings
        inline for (.{
            "moonshot_base_url",   "moonshot_api_key_env",   "moonshot_user_agent", "moonshot_endpoint",
            "deepseek_base_url",   "deepseek_api_key_env",   "deepseek_user_agent",
            "minimax_base_url",    "minimax_api_key_env",    "minimax_user_agent",
            "openai_base_url",     "openai_api_key_env",
            "anthropic_base_url",  "anthropic_api_key_env",
            "google_base_url",     "google_api_key_env",
        }) |field_name| {
            if (@field(result, field_name)) |val| {
                @field(result, field_name) = try self.allocator.dupe(u8, val);
            }
        }
        return result;
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
    /// Comma-separated list of enabled provider names.
    /// Examples: "deepseek", "deepseek,openai,moonshot", "all"
    /// If null, empty, or "all", all providers are enabled.
    enabled_providers: ?[]const u8 = null,

    // ---- Per-provider overrides ----
    // Override the built-in base_url for a provider.
    // e.g. moonshot_base_url = "https://api.kimi.com/coding/v1"
    moonshot_base_url: ?[]const u8 = null,
    moonshot_api_key_env: ?[]const u8 = null,
    moonshot_user_agent: ?[]const u8 = null,
    moonshot_endpoint: ?[]const u8 = null,
    deepseek_base_url: ?[]const u8 = null,
    deepseek_api_key_env: ?[]const u8 = null,
    deepseek_user_agent: ?[]const u8 = null,
    minimax_base_url: ?[]const u8 = null,
    minimax_api_key_env: ?[]const u8 = null,
    minimax_user_agent: ?[]const u8 = null,
    openai_base_url: ?[]const u8 = null,
    openai_api_key_env: ?[]const u8 = null,
    anthropic_base_url: ?[]const u8 = null,
    anthropic_api_key_env: ?[]const u8 = null,
    google_base_url: ?[]const u8 = null,
    google_api_key_env: ?[]const u8 = null,
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
    const io = std.testing.io;
    var config = HotReloadConfig.init(allocator, io, "proxy.json", 5000);
    defer config.deinit();

    try std.testing.expectEqualStrings("proxy.json", config.config_path);
    try std.testing.expectEqual(@as(i128, 0), config.last_modified.nanoseconds);
    try std.testing.expectEqual(@as(u32, 5000), config.check_interval_ms);
    try std.testing.expectEqual(@as(u32, 0), config.reload_count);
}

test "hot_reload - getReloadCount" {
    const allocator = std.heap.page_allocator;
    const io = std.testing.io;
    var config = HotReloadConfig.init(allocator, io, "proxy.json", 5000);
    defer config.deinit();

    try std.testing.expectEqual(@as(u32, 0), config.getReloadCount());
}

test "hot_reload - checkAndReload returns false when file doesn't exist" {
    const allocator = std.heap.page_allocator;
    const io = std.testing.io;
    var config = HotReloadConfig.init(allocator, io, "nonexistent_file.json", 5000);
    defer config.deinit();

    const result = try config.checkAndReload();
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
