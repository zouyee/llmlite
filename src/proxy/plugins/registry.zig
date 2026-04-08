//! Plugin Registry for llmlite Proxy
//!
//! Central registration and initialization of all plugins
//! Based on configuration, enables/disables features

const std = @import("std");
const plugin = @import("plugin");
const memory_kv = @import("plugin").MemoryKvStore;
const cache = @import("./cache.zig");
const guardrail = @import("./guardrail.zig");
const cost = @import("./cost.zig");

pub const PluginRegistry = struct {
    allocator: std.mem.Allocator,
    manager: plugin.PluginManager,
    memory_store: ?memory_kv,
    simple_cache_instance: ?cache.SimpleCache,
    semantic_cache_instance: ?cache.SemanticCache,
    guardrail_instance: ?guardrail.ContentFilter,
    cost_instance: ?cost.MemoryCostTracker,

    pub fn init(allocator: std.mem.Allocator) PluginRegistry {
        return .{
            .allocator = allocator,
            .manager = plugin.PluginManager.init(allocator),
            .memory_store = null,
            .simple_cache_instance = null,
            .semantic_cache_instance = null,
            .guardrail_instance = null,
            .cost_instance = null,
        };
    }

    pub fn deinit(self: *PluginRegistry) void {
        self.manager.deinit();
        if (self.memory_store) |*store| {
            store.deinit();
        }
        if (self.simple_cache_instance) |*c| {
            c.deinit();
        }
        if (self.semantic_cache_instance) |*c| {
            c.deinit();
        }
        if (self.guardrail_instance) |*g| {
            g.deinit();
        }
        if (self.cost_instance) |*ct| {
            ct.deinit();
        }
    }

    /// Initialize plugins based on configuration
    pub fn initWithConfig(self: *PluginRegistry, config: *const plugin.ProxyConfig) !void {
        // Always register the built-in memory KV store
        try self.manager.registerPlugin(plugin.PluginInfo{
            .name = "kvstore.memory",
            .version = "1.0.0",
            .description = "In-memory key-value store",
            .plugin_type = .kv_store,
            .dependencies = &.{},
        });

        // Initialize memory store
        var mem_store = memory_kv.init(self.allocator);
        self.memory_store = mem_store;

        // Initialize KV store pointer
        self.manager.kv_store = mem_store.toKvStore();

        // Initialize cache if enabled
        switch (config.features.cache) {
            .disabled => {},
            .simple => |cfg| {
                try self.manager.registerPlugin(cache.SIMPLE_CACHE_INFO);
                var cache_inst = cache.SimpleCache.init(self.allocator, cfg.ttl_seconds, cfg.max_entries);
                self.simple_cache_instance = cache_inst;
                self.manager.cache = cache_inst.toCache();
            },
            .semantic => |cfg| {
                try self.manager.registerPlugin(cache.SEMANTIC_CACHE_INFO);
                // Semantic cache with embedding-based similarity
                // Uses hash-based pseudo-embeddings when no HTTP client is available
                // For production, pass a real embedding API client
                var cache_inst = try cache.SemanticCache.init(
                    self.allocator,
                    cfg.ttl_seconds,
                    cfg.max_entries,
                    cfg.similarity_threshold,
                    "text-embedding-ada-002", // Default embedding model
                    null, // null = use hash-based fallback
                    1536, // Embedding dimension for ada-002
                );
                self.semantic_cache_instance = cache_inst;
                self.manager.cache = cache_inst.semanticCacheToCache();
            },
        }

        // Initialize guardrail if enabled
        switch (config.features.guardrail) {
            .disabled => {},
            .content_filter => |cfg| {
                try self.manager.registerPlugin(guardrail.CONTENT_FILTER_INFO);
                var g = guardrail.ContentFilter.init(self.allocator, cfg.blocked_words);
                self.guardrail_instance = g;
                self.manager.guardrail = g.toGuardrail();
            },
            .pii_detect => |cfg| {
                try self.manager.registerPlugin(guardrail.PII_DETECTOR_INFO);
                var g = guardrail.PiiDetector.init(self.allocator, cfg.detect_email, cfg.detect_phone, cfg.detect_ssn);
                self.guardrail_instance = undefined;
                self.manager.guardrail = g.toGuardrail();
            },
            .full => |cfg| {
                try self.manager.registerPlugin(guardrail.FULL_GUARDRAIL_INFO);
                var g = guardrail.FullGuardrail.init(
                    self.allocator,
                    cfg.content_filter.blocked_words,
                    cfg.pii_detect.detect_email,
                    cfg.pii_detect.detect_phone,
                    cfg.pii_detect.detect_ssn,
                );
                self.guardrail_instance = undefined;
                self.manager.guardrail = g.toGuardrail();
            },
        }

        // Initialize cost tracker if enabled
        if (config.features.cost_tracking) {
            try self.manager.registerPlugin(cost.COST_TRACKER_INFO);
            var ct = cost.MemoryCostTracker.init(self.allocator);
            self.cost_instance = ct;
            self.manager.cost_tracker = ct.toCostTracker();
        }

        std.log.info("Plugin registry initialized", .{});
        std.log.info("  KV Store: memory", .{});
        std.log.info("  Cache: {s}", .{@tagName(config.features.cache)});
        std.log.info("  Cost Tracking: {s}", .{if (config.features.cost_tracking) "enabled" else "disabled"});
        std.log.info("  Guardrail: {s}", .{@tagName(config.features.guardrail)});
    }

    /// Get KV store
    pub fn getKvStore(self: *PluginRegistry) ?*const plugin.KvStore {
        return self.manager.kv_store;
    }

    /// Get cache
    pub fn getCache(self: *PluginRegistry) ?*const plugin.Cache {
        return self.manager.cache;
    }

    /// Get cost tracker
    pub fn getCostTracker(self: *PluginRegistry) ?*const plugin.CostTracker {
        return self.manager.cost_tracker;
    }

    /// Get guardrail
    pub fn getGuardrail(self: *PluginRegistry) ?*const plugin.Guardrail {
        return self.manager.guardrail;
    }

    /// Check if a feature is enabled
    pub fn isFeatureEnabled(self: *PluginRegistry, feature: plugin.PluginType) bool {
        return self.manager.isEnabledType(feature);
    }
};

test "plugin registry" {
    std.debug.print("Plugin registry test\n", .{});
}
