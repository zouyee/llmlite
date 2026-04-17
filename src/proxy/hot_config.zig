const std = @import("std");

/// Number of app types (matches AppType enum in app_type_router.zig)
pub const APP_TYPE_COUNT = 8;

/// Per-app proxy configuration (inline copy to avoid circular deps with app_type_router)
pub const AppConfig = struct {
    enabled: bool = true,
    failover_enabled: bool = true,
    stream_first_byte_timeout_ms: u32 = 30000,
    stream_idle_timeout_ms: u32 = 60000,
    non_stream_timeout_ms: u32 = 120000,
};

/// Full proxy configuration with per-app configs and global settings
pub const ProxyFullConfig = struct {
    app_configs: [APP_TYPE_COUNT]AppConfig = initDefaultAppConfigs(),
    global_address: [64]u8 = initDefaultAddress(),
    global_address_len: u8 = 7,
    global_port: u16 = 4000,
    enable_logging: bool = true,

    fn initDefaultAddress() [64]u8 {
        var buf: [64]u8 = .{0} ** 64;
        const default = "0.0.0.0";
        @memcpy(buf[0..default.len], default);
        return buf;
    }

    fn initDefaultAppConfigs() [APP_TYPE_COUNT]AppConfig {
        var configs: [APP_TYPE_COUNT]AppConfig = undefined;
        for (&configs) |*c| {
            c.* = AppConfig{};
        }
        return configs;
    }

    pub fn getGlobalAddress(self: *const ProxyFullConfig) []const u8 {
        return self.global_address[0..self.global_address_len];
    }
};

/// In-memory hot configuration manager with backup/rollback support
pub const HotConfigManager = struct {
    allocator: std.mem.Allocator,
    current_config: ProxyFullConfig,
    backup_config: ?ProxyFullConfig,
    config_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, config_path: []const u8) HotConfigManager {
        return .{
            .allocator = allocator,
            .current_config = ProxyFullConfig{},
            .backup_config = null,
            .config_path = config_path,
        };
    }

    pub fn deinit(self: *HotConfigManager) void {
        _ = self;
    }

    /// Apply a new config, backing up the current one first
    pub fn applyConfig(self: *HotConfigManager, new_config: ProxyFullConfig) void {
        self.backup_config = self.current_config;
        self.current_config = new_config;
    }

    /// Rollback to the backup config. Returns error if no backup exists.
    pub fn rollback(self: *HotConfigManager) !void {
        if (self.backup_config) |backup| {
            self.current_config = backup;
            self.backup_config = null;
        } else {
            return error.NoBackupConfig;
        }
    }

    /// Get a pointer to the current config
    pub fn getConfig(self: *const HotConfigManager) *const ProxyFullConfig {
        return &self.current_config;
    }

    /// Get config for a specific app type by index
    pub fn getAppConfig(self: *const HotConfigManager, app_type_index: usize) AppConfig {
        if (app_type_index >= APP_TYPE_COUNT) {
            return AppConfig{};
        }
        return self.current_config.app_configs[app_type_index];
    }

    /// Update a single app config (auto-backup before update)
    pub fn updateAppConfig(self: *HotConfigManager, app_type_index: usize, config: AppConfig) void {
        if (app_type_index >= APP_TYPE_COUNT) return;
        self.backup_config = self.current_config;
        self.current_config.app_configs[app_type_index] = config;
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "hot_config - applyConfig backs up old config" {
    var mgr = HotConfigManager.init(std.testing.allocator, "proxy.json");
    defer mgr.deinit();

    // Default config has port 4000
    try std.testing.expectEqual(@as(u16, 4000), mgr.getConfig().global_port);
    try std.testing.expect(mgr.backup_config == null);

    // Apply new config with port 5000
    var new_config = ProxyFullConfig{};
    new_config.global_port = 5000;
    mgr.applyConfig(new_config);

    // Current should be new, backup should be old
    try std.testing.expectEqual(@as(u16, 5000), mgr.getConfig().global_port);
    try std.testing.expect(mgr.backup_config != null);
    try std.testing.expectEqual(@as(u16, 4000), mgr.backup_config.?.global_port);
}

test "hot_config - rollback restores backup" {
    var mgr = HotConfigManager.init(std.testing.allocator, "proxy.json");
    defer mgr.deinit();

    // Apply new config
    var new_config = ProxyFullConfig{};
    new_config.global_port = 9999;
    mgr.applyConfig(new_config);

    try std.testing.expectEqual(@as(u16, 9999), mgr.getConfig().global_port);

    // Rollback
    try mgr.rollback();
    try std.testing.expectEqual(@as(u16, 4000), mgr.getConfig().global_port);
    try std.testing.expect(mgr.backup_config == null);
}

test "hot_config - rollback with no backup returns error" {
    var mgr = HotConfigManager.init(std.testing.allocator, "proxy.json");
    defer mgr.deinit();

    const result = mgr.rollback();
    try std.testing.expectError(error.NoBackupConfig, result);
}

test "hot_config - getConfig returns current config" {
    var mgr = HotConfigManager.init(std.testing.allocator, "proxy.json");
    defer mgr.deinit();

    const cfg = mgr.getConfig();
    try std.testing.expectEqual(@as(u16, 4000), cfg.global_port);
    try std.testing.expect(cfg.enable_logging);
    try std.testing.expectEqualStrings("0.0.0.0", cfg.getGlobalAddress());
}

test "hot_config - updateAppConfig auto-backups" {
    var mgr = HotConfigManager.init(std.testing.allocator, "proxy.json");
    defer mgr.deinit();

    try std.testing.expect(mgr.backup_config == null);

    // Update app config at index 0
    const custom = AppConfig{
        .enabled = false,
        .failover_enabled = false,
        .stream_first_byte_timeout_ms = 5000,
        .stream_idle_timeout_ms = 10000,
        .non_stream_timeout_ms = 20000,
    };
    mgr.updateAppConfig(0, custom);

    // Backup should exist with old defaults
    try std.testing.expect(mgr.backup_config != null);
    try std.testing.expectEqual(true, mgr.backup_config.?.app_configs[0].enabled);

    // Current should have updated config
    const app_cfg = mgr.getAppConfig(0);
    try std.testing.expectEqual(false, app_cfg.enabled);
    try std.testing.expectEqual(false, app_cfg.failover_enabled);
    try std.testing.expectEqual(@as(u32, 5000), app_cfg.stream_first_byte_timeout_ms);

    // Other app configs should be unchanged
    const other_cfg = mgr.getAppConfig(1);
    try std.testing.expectEqual(true, other_cfg.enabled);
    try std.testing.expectEqual(@as(u32, 30000), other_cfg.stream_first_byte_timeout_ms);
}

test "hot_config - getAppConfig out of bounds returns default" {
    var mgr = HotConfigManager.init(std.testing.allocator, "proxy.json");
    defer mgr.deinit();

    const cfg = mgr.getAppConfig(99);
    try std.testing.expectEqual(true, cfg.enabled);
    try std.testing.expectEqual(@as(u32, 30000), cfg.stream_first_byte_timeout_ms);
}

test "hot_config - ProxyFullConfig defaults" {
    const cfg = ProxyFullConfig{};
    try std.testing.expectEqual(@as(u16, 4000), cfg.global_port);
    try std.testing.expectEqual(@as(u8, 7), cfg.global_address_len);
    try std.testing.expect(cfg.enable_logging);
    try std.testing.expectEqualStrings("0.0.0.0", cfg.getGlobalAddress());

    // All app configs should be defaults
    for (cfg.app_configs) |app_cfg| {
        try std.testing.expectEqual(true, app_cfg.enabled);
        try std.testing.expectEqual(true, app_cfg.failover_enabled);
        try std.testing.expectEqual(@as(u32, 30000), app_cfg.stream_first_byte_timeout_ms);
        try std.testing.expectEqual(@as(u32, 60000), app_cfg.stream_idle_timeout_ms);
        try std.testing.expectEqual(@as(u32, 120000), app_cfg.non_stream_timeout_ms);
    }
}
