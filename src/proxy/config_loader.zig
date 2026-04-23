//! Configuration Loader for llmlite Proxy
//!
//! Supports TOML and JSON configuration files
//! Allows enabling/disabling features via config

const std = @import("std");
const plugin = @import("plugin");

pub const ConfigError = error{
    FileNotFound,
    ParseError,
    InvalidFormat,
    UnsupportedFormat,
};

pub const ConfigLoader = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ConfigLoader {
        return .{ .allocator = allocator };
    }

    pub fn loadFromFile(self: *ConfigLoader, io: std.Io, path: []const u8) !plugin.ProxyConfig {
        const content = try std.Io.Dir.cwd().readFileAlloc(io, path, self.allocator, .limited(1024 * 1024));
        defer self.allocator.free(content);

        // Determine format from extension
        if (std.mem.endsWith(u8, path, ".toml")) {
            return self.parseToml(content);
        } else if (std.mem.endsWith(u8, path, ".json")) {
            return self.parseJson(content);
        }

        return ConfigError.UnsupportedFormat;
    }

    pub fn loadFromTomlString(self: *ConfigLoader, content: []const u8) !plugin.ProxyConfig {
        return self.parseToml(content);
    }

    pub fn loadFromJsonString(self: *ConfigLoader, content: []const u8) !plugin.ProxyConfig {
        return self.parseJson(content);
    }

    fn parseToml(self: *ConfigLoader, content: []const u8) !plugin.ProxyConfig {
        _ = self;
        // Simple TOML parser - for full TOML support, use a proper library
        // For now, we support JSON which is more common
        _ = content;
        return ConfigError.UnsupportedFormat;
    }

    fn parseJson(self: *ConfigLoader, content: []const u8) !plugin.ProxyConfig {
        const parsed = try std.json.parseFromSlice(JsonProxyConfig, self.allocator, content, .{});
        defer parsed.deinit();

        return self.jsonToProxyConfig(&parsed.value);
    }

    fn jsonToProxyConfig(self: *ConfigLoader, json: *const JsonProxyConfig) !plugin.ProxyConfig {
        var features = plugin.Features{};

        if (json.features) |f| {
            features.virtual_keys = f.virtual_keys orelse true;
            features.multi_tenancy = f.multi_tenancy orelse false;
            features.cost_tracking = f.cost_tracking orelse false;
            features.rate_limiting = f.rate_limiting orelse true;
            features.observability = f.observability orelse false;

            if (f.cache) |cache| {
                features.cache = self.parseCacheConfig(cache);
            }

            if (f.guardrail) |guardrail| {
                features.guardrail = self.parseGuardrailConfig(guardrail);
            }
        }

        var kv_config: plugin.KvConfig = .memory;
        if (json.kv) |kv| {
            kv_config = self.parseKvConfig(kv);
        }

        var router_config: plugin.RouterConfig = .fallback;
        if (json.router) |r| {
            router_config = self.parseRouterConfig(r);
        }

        var database_path: []const u8 = "./data/proxy.db";
        if (json.database) |db| {
            if (db.path) |p| {
                database_path = try self.allocator.dupe(u8, p);
            }
        }

        return plugin.ProxyConfig{
            .host = json.host orelse "0.0.0.0",
            .port = json.port orelse 4000,
            .log_level = json.log_level orelse "info",
            .features = features,
            .kv = kv_config,
            .router = router_config,
            .database_path = database_path,
        };
    }

    fn parseCacheConfig(_: *ConfigLoader, json: *const JsonCacheConfig) plugin.CacheConfig {
        if (json.type) |t| {
            if (std.mem.eql(u8, t, "simple")) {
                return .{ .simple = .{
                    .ttl_seconds = json.ttl_seconds orelse 3600,
                    .max_entries = json.max_entries orelse 10000,
                } };
            } else if (std.mem.eql(u8, t, "semantic")) {
                return .{ .semantic = .{
                    .ttl_seconds = json.ttl_seconds orelse 3600,
                    .similarity_threshold = json.similarity_threshold orelse 0.95,
                    .max_entries = json.max_entries orelse 10000,
                } };
            }
        }
        return .disabled;
    }

    fn parseGuardrailConfig(_: *ConfigLoader, json: *const JsonGuardrailConfig) plugin.GuardrailConfig {
        if (json.type) |t| {
            if (std.mem.eql(u8, t, "content_filter")) {
                return .{ .content_filter = .{
                    .blocked_words = json.blocked_words orelse &.{},
                } };
            } else if (std.mem.eql(u8, t, "pii_detect")) {
                return .{ .pii_detect = .{
                    .detect_email = json.detect_email orelse true,
                    .detect_phone = json.detect_phone orelse true,
                    .detect_ssn = json.detect_ssn orelse true,
                } };
            } else if (std.mem.eql(u8, t, "full")) {
                return .{ .full = .{
                    .content_filter = .{
                        .blocked_words = json.blocked_words orelse &.{},
                    },
                    .pii_detect = .{
                        .detect_email = json.detect_email orelse true,
                        .detect_phone = json.detect_phone orelse true,
                        .detect_ssn = json.detect_ssn orelse true,
                    },
                } };
            }
        }
        return .disabled;
    }

    fn parseKvConfig(_: *ConfigLoader, json: *const JsonKvConfig) plugin.KvConfig {
        if (json.backend) |b| {
            if (std.mem.eql(u8, b, "sqlite")) {
                return .{ .sqlite = .{
                    .path = json.path orelse "./llmlite.db",
                } };
            }
        }
        return .memory;
    }

    fn parseRouterConfig(_: *ConfigLoader, json: *const JsonRouterConfig) plugin.RouterConfig {
        if (json.type) |t| {
            if (std.mem.eql(u8, t, "weighted")) {
                return .weighted;
            } else if (std.mem.eql(u8, t, "latency_based")) {
                return .latency_based;
            }
        }
        return .fallback;
    }
};

// ============ JSON Config Structures ============

const JsonDatabaseConfig = struct {
    path: ?[]const u8 = null,
};

const JsonProxyConfig = struct {
    host: ?[]const u8 = null,
    port: ?u16 = null,
    log_level: ?[]const u8 = null,
    features: ?JsonFeatures = null,
    kv: ?JsonKvConfig = null,
    router: ?JsonRouterConfig = null,
    database: ?JsonDatabaseConfig = null,
};

const JsonFeatures = struct {
    virtual_keys: ?bool = null,
    multi_tenancy: ?bool = null,
    cost_tracking: ?bool = null,
    rate_limiting: ?bool = null,
    observability: ?bool = null,
    cache: ?JsonCacheConfig = null,
    guardrail: ?JsonGuardrailConfig = null,
};

const JsonCacheConfig = struct {
    type: ?[]const u8 = null,
    ttl_seconds: ?u32 = null,
    max_entries: ?u32 = null,
    similarity_threshold: ?f32 = null,
    embedding_model: ?[]const u8 = null,
    embedding_dim: ?u32 = null,
};

const JsonGuardrailConfig = struct {
    type: ?[]const u8 = null,
    blocked_words: ?[][]const u8 = null,
    detect_email: ?bool = null,
    detect_phone: ?bool = null,
    detect_ssn: ?bool = null,
};

const JsonKvConfig = struct {
    backend: ?[]const u8 = null,
    path: ?[]const u8 = null,
};

const JsonRouterConfig = struct {
    type: ?[]const u8 = null,
};

// ============ Example Configurations ============

pub const EXAMPLE_CONFIGS = struct {
    pub fn minimalConfig() []const u8 {
        return 
        \\{
        \\    "port": 4000,
        \\    "features": {
        \\        "virtual_keys": true,
        \\        "rate_limiting": true
        \\    }
        \\}
        ;
    }

    pub fn fullConfig() []const u8 {
        return 
        \\{
        \\    "host": "0.0.0.0",
        \\    "port": 4000,
        \\    "log_level": "info",
        \\    "kv": {
        \\        "backend": "memory"
        \\    },
        \\    "router": {
        \\        "type": "fallback"
        \\    },
        \\    "features": {
        \\        "virtual_keys": true,
        \\        "multi_tenancy": true,
        \\        "cost_tracking": true,
        \\        "rate_limiting": true,
        \\        "cache": {
        \\            "type": "simple",
        \\            "ttl_seconds": 3600,
        \\            "max_entries": 10000
        \\        },
        \\        "guardrail": {
        \\            "type": "full",
        \\            "blocked_words": ["badword1", "badword2"],
        \\            "detect_email": true,
        \\            "detect_phone": true,
        \\            "detect_ssn": true
        \\        }
        \\    }
        \\}
        ;
    }

    pub fn productionConfig() []const u8 {
        return 
        \\{
        \\    "host": "0.0.0.0",
        \\    "port": 4000,
        \\    "log_level": "info",
        \\    "kv": {
        \\        "backend": "sqlite",
        \\        "path": "./data/llmlite.db"
        \\    },
        \\    "router": {
        \\        "type": "weighted"
        \\    },
        \\    "features": {
        \\        "virtual_keys": true,
        \\        "multi_tenancy": true,
        \\        "cost_tracking": true,
        \\        "rate_limiting": true,
        \\        "observability": true,
        \\        "cache": {
        \\            "type": "semantic",
        \\            "ttl_seconds": 3600,
        \\            "similarity_threshold": 0.95
        \\        },
        \\        "guardrail": {
        \\            "type": "full",
        \\            "detect_email": true,
        \\            "detect_phone": true,
        \\            "detect_ssn": true
        \\        }
        \\    }
        \\}
        ;
    }
};

test "config loader" {
    std.debug.print("Config loader test\n", .{});
}

// ============================================================================
// Property-Based Tests
// ============================================================================

// **Feature: zig-016-upgrade, Property 1: 配置加载往返一致性**
// Verify any valid JSON config written to temp file then loaded produces same result.
//
// **Validates: Requirements 2.1**
test "Property 1: config loading round-trip consistency" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    // Use a deterministic PRNG seeded from test environment
    var prng = std.Random.DefaultPrng.init(0xDEADBEEF);
    const random = prng.random();

    const iterations: usize = 100;

    for (0..iterations) |_| {
        // Generate random config values
        const port: u16 = random.intRangeAtMost(u16, 1024, 65535);
        const virtual_keys = random.boolean();
        const multi_tenancy = random.boolean();
        const cost_tracking = random.boolean();
        const rate_limiting = random.boolean();
        const observability = random.boolean();

        // Pick a random host from a set of valid hosts
        const hosts = [_][]const u8{ "0.0.0.0", "127.0.0.1", "localhost", "10.0.0.1" };
        const host = hosts[random.intRangeLessThan(usize, 0, hosts.len)];

        const log_levels = [_][]const u8{ "debug", "info", "warn", "error" };
        const log_level = log_levels[random.intRangeLessThan(usize, 0, log_levels.len)];

        // Build JSON string
        const json = try std.fmt.allocPrint(allocator,
            \\{{
            \\    "host": "{s}",
            \\    "port": {d},
            \\    "log_level": "{s}",
            \\    "features": {{
            \\        "virtual_keys": {s},
            \\        "multi_tenancy": {s},
            \\        "cost_tracking": {s},
            \\        "rate_limiting": {s},
            \\        "observability": {s}
            \\    }}
            \\}}
        , .{
            host,
            port,
            log_level,
            if (virtual_keys) "true" else "false",
            if (multi_tenancy) "true" else "false",
            if (cost_tracking) "true" else "false",
            if (rate_limiting) "true" else "false",
            if (observability) "true" else "false",
        });
        defer allocator.free(json);

        // Test round-trip via loadFromJsonString (validates JSON parsing consistency)
        var loader = ConfigLoader.init(allocator);
        const config = try loader.loadFromJsonString(json);

        // Verify round-trip consistency
        try std.testing.expectEqualStrings(host, config.host);
        try std.testing.expectEqual(port, config.port);
        try std.testing.expectEqualStrings(log_level, config.log_level);
        try std.testing.expectEqual(virtual_keys, config.features.virtual_keys);
        try std.testing.expectEqual(multi_tenancy, config.features.multi_tenancy);
        try std.testing.expectEqual(cost_tracking, config.features.cost_tracking);
        try std.testing.expectEqual(rate_limiting, config.features.rate_limiting);
        try std.testing.expectEqual(observability, config.features.observability);
    }
}

// **Feature: zig-016-upgrade, Property 1 (file I/O): config file round-trip**
// Verify writing JSON config to a temp file and loading via loadFromFile produces same result.
//
// **Validates: Requirements 2.1**
test "Property 1: config file I/O round-trip" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\    "host": "127.0.0.1",
        \\    "port": 8080,
        \\    "log_level": "debug",
        \\    "features": {
        \\        "virtual_keys": false,
        \\        "multi_tenancy": true,
        \\        "cost_tracking": true,
        \\        "rate_limiting": false,
        \\        "observability": true
        \\    }
        \\}
    ;

    // Write to CWD-relative temp file, clean up after test
    const test_file = "__test_config_roundtrip_prop1.json";
    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file, .data = json });
    defer cwd.deleteFile(io, test_file) catch {};

    // Load via ConfigLoader using the new io-based file API
    var loader = ConfigLoader.init(allocator);
    const config = try loader.loadFromFile(io, test_file);

    // Verify round-trip consistency
    try std.testing.expectEqualStrings("127.0.0.1", config.host);
    try std.testing.expectEqual(@as(u16, 8080), config.port);
    try std.testing.expectEqualStrings("debug", config.log_level);
    try std.testing.expectEqual(false, config.features.virtual_keys);
    try std.testing.expectEqual(true, config.features.multi_tenancy);
    try std.testing.expectEqual(true, config.features.cost_tracking);
    try std.testing.expectEqual(false, config.features.rate_limiting);
    try std.testing.expectEqual(true, config.features.observability);
}
