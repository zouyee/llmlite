//! Plugin System for llmlite Proxy
//!
//! Modular architecture allowing features to be enabled/disabled via configuration.
//! Default: zero dependencies, in-memory storage
//! Optional: zig-sqlite for persistent storage, semantic cache, guardrails, etc.

const std = @import("std");

// ============ Plugin Types ============

pub const PluginType = enum {
    kv_store,
    cache,
    cost_tracker,
    guardrail,
    router,
    observability,
    auth,
};

pub const PluginError = error{
    InitFailed,
    DependencyMissing,
    AlreadyLoaded,
    NotFound,
    Disabled,
};

// ============ Plugin Interface ============

pub const PluginInfo = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    plugin_type: PluginType,
    dependencies: []const []const u8,
};

// ============ Storage Backend Interface ============

pub const StorageBackend = union(enum) {
    memory,
    sqlite,

    pub const SqliteConfig = struct {
        path: []const u8,
    };
};

// ============ KV Store Interface ============

pub const KvStore = struct {
    interface: *anyopaque,
    vtable: *const KvStore.VTable,

    pub const VTable = struct {
        get: *const fn (*anyopaque, []const u8) ?[]const u8,
        set: *const fn (*anyopaque, []const u8, []const u8) anyerror!void,
        delete: *const fn (*anyopaque, []const u8) bool,
        list: *const fn (*anyopaque, []const u8) [][]const u8,
        close: *const fn (*anyopaque) void,
    };

    pub fn get(self: *const KvStore, key: []const u8) ?[]const u8 {
        return self.vtable.get(self.interface, key);
    }

    pub fn set(self: *const KvStore, key: []const u8, value: []const u8) !void {
        return self.vtable.set(self.interface, key, value);
    }

    pub fn delete(self: *const KvStore, key: []const u8) bool {
        return self.vtable.delete(self.interface, key);
    }

    pub fn list(self: *const KvStore, prefix: []const u8) [][]const u8 {
        return self.vtable.list(self.interface, prefix);
    }

    pub fn close(self: *const KvStore) void {
        self.vtable.close(self.interface);
    }
};

// ============ In-Memory KV Store (Default, Zero Dependency) ============

pub const MemoryKvStore = struct {
    data: std.StringArrayHashMap([]u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MemoryKvStore {
        return .{
            .data = std.StringArrayHashMap([]u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MemoryKvStore) void {
        var it = self.data.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.deinit();
    }

    pub fn toKvStore(self: *MemoryKvStore) KvStore {
        return .{
            .interface = @ptrCast(self),
            .vtable = &.{
                .get = getWrapper,
                .set = setWrapper,
                .delete = deleteWrapper,
                .list = listWrapper,
                .close = closeWrapper,
            },
        };
    }

    fn getWrapper(interface: *anyopaque, key: []const u8) ?[]const u8 {
        const self: *MemoryKvStore = @ptrCast(@alignCast(interface));
        return self.data.get(key);
    }

    fn setWrapper(interface: *anyopaque, key: []const u8, value: []const u8) !void {
        const self: *MemoryKvStore = @ptrCast(@alignCast(interface));
        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = try self.allocator.dupe(u8, value);
        if (self.data.put(key_copy, value_copy)) |old| {
            self.allocator.free(old);
        }
    }

    fn deleteWrapper(interface: *anyopaque, key: []const u8) bool {
        const self: *MemoryKvStore = @ptrCast(@alignCast(interface));
        if (self.data.fetchRemove(key)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
            return true;
        }
        return false;
    }

    fn listWrapper(interface: *anyopaque, prefix: []const u8) [][]const u8 {
        const self: *MemoryKvStore = @ptrCast(@alignCast(interface));
        var result = std.ArrayList([]const u8).init(self.allocator);
        var it = self.data.iterator();
        while (it.next()) |entry| {
            if (std.mem.startsWith(u8, entry.key_ptr.*, prefix)) {
                result.append(entry.key_ptr.*) catch {};
            }
        }
        return result.toOwnedSlice();
    }

    fn closeWrapper(_: *anyopaque) void {
        // No-op for memory store
    }
};

// ============ Cache Interface ============

pub const Cache = struct {
    interface: *anyopaque,
    vtable: *const Cache.VTable,

    pub const VTable = struct {
        get: *const fn (*anyopaque, []const u8) ?[]const u8,
        set: *const fn (*anyopaque, []const u8, []const u8, ttl_seconds: u32) anyerror!void,
        delete: *const fn (*anyopaque, []const u8) bool,
        clear: *const fn (*anyopaque) void,
        close: *const fn (*anyopaque) void,
    };

    pub fn get(self: *const Cache, key: []const u8) ?[]const u8 {
        return self.vtable.get(self.interface, key);
    }

    pub fn set(self: *const Cache, key: []const u8, value: []const u8, ttl_seconds: u32) !void {
        return self.vtable.set(self.interface, key, value, ttl_seconds);
    }

    pub fn delete(self: *const Cache, key: []const u8) bool {
        return self.vtable.delete(self.interface, key);
    }

    pub fn clear(self: *const Cache) void {
        self.vtable.clear(self.interface);
    }

    pub fn close(self: *const Cache) void {
        self.vtable.close(self.interface);
    }
};

// ============ Guardrail Interface ============

pub const GuardrailResult = struct {
    allowed: bool,
    reason: ?[]const u8,
    filtered_content: ?[]const u8,
};

pub const Guardrail = struct {
    interface: *anyopaque,
    vtable: *const Guardrail.VTable,

    pub const VTable = struct {
        checkContent: *const fn (*anyopaque, []const u8) GuardrailResult,
        checkJson: *const fn (*anyopaque, []const u8) GuardrailResult,
        close: *const fn (*anyopaque) void,
    };

    pub fn checkContent(self: *const Guardrail, content: []const u8) GuardrailResult {
        return self.vtable.checkContent(self.interface, content);
    }

    pub fn checkJson(self: *const Guardrail, json: []const u8) GuardrailResult {
        return self.vtable.checkJson(self.interface, json);
    }

    pub fn close(self: *const Guardrail) void {
        self.vtable.close(self.interface);
    }
};

// ============ Cost Tracker Interface ============

pub const CostEntry = struct {
    key_id: []const u8,
    team_id: ?[]const u8,
    provider: []const u8,
    model: []const u8,
    prompt_tokens: u32,
    completion_tokens: u32,
    cost: f64,
    timestamp: i64,
};

pub const CostTracker = struct {
    interface: *anyopaque,
    vtable: *const CostTracker.VTable,

    pub const VTable = struct {
        record: *const fn (*anyopaque, CostEntry) anyerror!void,
        getTotalForKey: *const fn (*anyopaque, []const u8) f64,
        getTotalForTeam: *const fn (*anyopaque, []const u8) f64,
        getDailySpend: *const fn (*anyopaque, []const u8) f64,
        close: *const fn (*anyopaque) void,
    };

    pub fn record(self: *const CostTracker, entry: CostEntry) !void {
        return self.vtable.record(self.interface, entry);
    }

    pub fn getTotalForKey(self: *const CostTracker, key_id: []const u8) f64 {
        return self.vtable.getTotalForKey(self.interface, key_id);
    }

    pub fn getTotalForTeam(self: *const CostTracker, team_id: []const u8) f64 {
        return self.vtable.getTotalForTeam(self.interface, team_id);
    }

    pub fn getDailySpend(self: *const CostTracker, key_id: []const u8) f64 {
        return self.vtable.getDailySpend(self.interface, key_id);
    }

    pub fn close(self: *const CostTracker) void {
        self.vtable.close(self.interface);
    }
};

// ============ Plugin Manager ============

pub const PluginManager = struct {
    allocator: std.mem.Allocator,
    plugins: std.StringArrayHashMap(PluginInstance),
    kv_store: ?KvStore,
    cache: ?Cache,
    cost_tracker: ?CostTracker,
    guardrail: ?Guardrail,

    pub const PluginInstance = struct {
        info: PluginInfo,
        plugin_type: PluginType,
        enabled: bool,
    };

    pub fn init(allocator: std.mem.Allocator) PluginManager {
        return .{
            .allocator = allocator,
            .plugins = std.StringArrayHashMap(PluginInstance).init(allocator),
            .kv_store = null,
            .cache = null,
            .cost_tracker = null,
            .guardrail = null,
        };
    }

    pub fn deinit(self: *PluginManager) void {
        if (self.kv_store) |kv| {
            kv.close();
        }
        if (self.cache) |c| {
            c.close();
        }
        if (self.cost_tracker) |ct| {
            ct.close();
        }
        if (self.guardrail) |g| {
            g.close();
        }
        self.plugins.deinit();
    }

    pub fn registerPlugin(self: *PluginManager, info: PluginInfo) !void {
        if (self.plugins.contains(info.name)) {
            return PluginError.AlreadyLoaded;
        }
        try self.plugins.put(try self.allocator.dupe(u8, info.name), .{
            .info = info,
            .plugin_type = info.plugin_type,
            .enabled = true,
        });
    }

    pub fn enablePlugin(self: *PluginManager, name: []const u8) !void {
        const plugin = self.plugins.getPtr(name) orelse {
            return PluginError.NotFound;
        };
        plugin.enabled = true;
    }

    pub fn disablePlugin(self: *PluginManager, name: []const u8) !void {
        const plugin = self.plugins.getPtr(name) orelse {
            return PluginError.NotFound;
        };
        plugin.enabled = false;
    }

    pub fn isEnabled(self: *PluginManager, name: []const u8) bool {
        return self.plugins.get(name).?.enabled;
    }

    pub fn isEnabledType(self: *PluginManager, plugin_type: PluginType) bool {
        var it = self.plugins.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.plugin_type == plugin_type and entry.value_ptr.enabled) {
                return true;
            }
        }
        return false;
    }
};

// ============ Feature Flags ============

pub const Features = struct {
    /// Enable virtual key management (requires kv_store)
    virtual_keys: bool = true,
    /// Enable team/project management (requires kv_store)
    multi_tenancy: bool = false,
    /// Enable cost tracking
    cost_tracking: bool = false,
    /// Enable semantic/simple cache
    cache: CacheConfig = .disabled,
    /// Enable guardrails (content filter, PII detection)
    guardrail: GuardrailConfig = .disabled,
    /// Enable rate limiting
    rate_limiting: bool = true,
    /// Enable observability callbacks
    observability: bool = false,
};

pub const CacheConfig = union(enum) {
    disabled,
    simple: SimpleCacheConfig,
    semantic: SemanticCacheConfig,

    pub const SimpleCacheConfig = struct {
        ttl_seconds: u32 = 3600,
        max_entries: u32 = 10000,
    };

    pub const SemanticCacheConfig = struct {
        ttl_seconds: u32 = 3600,
        similarity_threshold: f32 = 0.95,
        max_entries: u32 = 10000,
    };
};

pub const GuardrailConfig = union(enum) {
    disabled,
    content_filter: ContentFilterConfig,
    pii_detect: PiiDetectConfig,
    full: FullGuardrailConfig,

    pub const ContentFilterConfig = struct {
        blocked_words: [][]const u8 = &.{},
    };

    pub const PiiDetectConfig = struct {
        detect_email: bool = true,
        detect_phone: bool = true,
        detect_ssn: bool = true,
    };

    pub const FullGuardrailConfig = struct {
        content_filter: ContentFilterConfig = .{},
        pii_detect: PiiDetectConfig = .{},
    };
};

pub const KvConfig = union(enum) {
    memory,
    sqlite: SqliteKvConfig,

    pub const SqliteKvConfig = struct {
        path: []const u8 = "./llmlite.db",
    };
};

pub const RouterConfig = union(enum) {
    fallback,
    weighted,
    latency_based,
};

pub const ProxyConfig = struct {
    host: []const u8 = "0.0.0.0",
    port: u16 = 4000,
    log_level: []const u8 = "info",
    features: Features = .{},
    kv: KvConfig = .memory,
    router: RouterConfig = .fallback,
};

test "plugin system basic" {
    std.debug.print("Plugin system test\n", .{});
}
