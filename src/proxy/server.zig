//! HTTP Server for llmlite Proxy - Edge Routing Edition
//!
//! Low-level HTTP server using std.net with provider routing, latency tracking,
//! health checking, connection pooling. Streaming support is simplified.

const std = @import("std");
const virtual_key = @import("virtual_key");
const rate_limit = @import("proxy_rate_limit");
const logger = @import("proxy_logger");
const error_handler = @import("error_handler");
const http = @import("http");
const types = @import("types");
const registry = @import("registry");
const chat = @import("chat");
const connection_pool = @import("connection_pool");
const latency_health = @import("latency_health");
const hot_reload = @import("hot_reload");
const circuit_breaker = @import("circuit_breaker");
const active_health = @import("active_health");
const tracking_analytics = @import("analytics");
const savings_store_mod = @import("proxy_savings_store");
const savings_handler_mod = @import("proxy_savings_handler");
const unified_handler_mod = @import("proxy_unified_handler");

// ==================== Provider Types ====================

pub const ProviderAuthType = enum {
    bearer,
    api_key,
    none,
};

pub const Provider = struct {
    id: []const u8,
    name: []const u8,
    base_url: []const u8,
    auth_type: ProviderAuthType,
    api_key: ?[]const u8,
    default_model: []const u8,
    supports: [][]const u8,
    is_official: bool,
    enabled: bool,
    sort_order: u32,
    created_at: i64,
    updated_at: i64,
    metadata: ?[]const u8,

    pub fn formatJson(self: *const Provider, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator,
            \\{{"id":"{s}","name":"{s}","base_url":"{s}","auth_type":"{s}","api_key":null,"default_model":"{s}","supports":[],"is_official":{s},"enabled":{s},"sort_order":{},"created_at":{},"updated_at":{},"metadata":null}}
        , .{
            self.id,
            self.name,
            self.base_url,
            @tagName(self.auth_type),
            self.default_model,
            if (self.is_official) "true" else "false",
            if (self.enabled) "true" else "false",
            self.sort_order,
            self.created_at,
            self.updated_at,
        });
    }
};

pub const ProviderPreset = struct {
    id: []const u8,
    name: []const u8,
    provider_type: []const u8,
    base_url: []const u8,
    auth_type: []const u8,
    default_models: [][]const u8,
    features: [][]const u8,
    website: []const u8,
    description: []const u8,
};

pub const ProviderStore = struct {
    allocator: std.mem.Allocator,
    providers: std.StringArrayHashMap(Provider),
    current_id: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) ProviderStore {
        return .{
            .allocator = allocator,
            .providers = std.StringArrayHashMap(Provider).init(allocator),
            .current_id = null,
        };
    }

    pub fn deinit(self: *ProviderStore) void {
        var it = self.providers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.id);
            self.allocator.free(entry.value_ptr.name);
            self.allocator.free(entry.value_ptr.base_url);
            if (entry.value_ptr.api_key) |key| self.allocator.free(key);
            self.allocator.free(entry.value_ptr.default_model);
            for (entry.value_ptr.supports) |s| self.allocator.free(s);
            self.allocator.free(entry.value_ptr.supports);
            if (entry.value_ptr.metadata) |m| self.allocator.free(m);
        }
        self.providers.deinit();
    }

    pub fn add(self: *ProviderStore, provider: Provider) !void {
        const id = try self.allocator.dupe(u8, provider.id);
        errdefer self.allocator.free(id);
        try self.providers.put(id, provider);
    }

    pub fn get(self: *const ProviderStore, id: []const u8) ?Provider {
        return self.providers.get(id);
    }

    pub fn getSorted(self: *ProviderStore) []*Provider {
        const count = self.providers.count();
        if (count == 0) return &.{};

        var sorted = self.allocator.alloc(*Provider, count) catch return &.{};
        var it = self.providers.iterator();
        var i: usize = 0;
        while (it.next()) |entry| {
            sorted[i] = entry.value_ptr;
            i += 1;
        }

        // Simple sort by sort_order
        for (sorted[0..count], 0..) |a, outer_i| {
            for (sorted[outer_i + 1 .. count], outer_i + 1..) |b, inner_j| {
                if (a.sort_order > b.sort_order) {
                    const tmp = sorted[outer_i];
                    sorted[outer_i] = sorted[inner_j];
                    sorted[inner_j] = tmp;
                }
            }
        }

        return sorted;
    }

    pub fn update(self: *ProviderStore, provider: Provider) !void {
        const existing = self.providers.get(provider.id) orelse return error.NotFound;

        // Free old strings
        self.allocator.free(existing.id);
        self.allocator.free(existing.name);
        self.allocator.free(existing.base_url);
        if (existing.api_key) |key| self.allocator.free(key);
        self.allocator.free(existing.default_model);
        for (existing.supports) |s| self.allocator.free(s);
        self.allocator.free(existing.supports);
        if (existing.metadata) |m| self.allocator.free(m);

        self.providers.put(provider.id, provider) catch return error.UpdateFailed;
    }

    pub fn delete(self: *ProviderStore, id: []const u8) bool {
        // In Zig 0.15, we use getPtr to check existence and mark as deleted
        if (self.providers.getPtr(id)) |ptr| {
            // Free the provider data
            self.allocator.free(ptr.id);
            self.allocator.free(ptr.name);
            self.allocator.free(ptr.base_url);
            if (ptr.api_key) |key| self.allocator.free(key);
            self.allocator.free(ptr.default_model);
            for (ptr.supports) |s| self.allocator.free(s);
            self.allocator.free(ptr.supports);
            if (ptr.metadata) |m| self.allocator.free(m);
            // Mark as deleted by clearing the id
            ptr.id = "";
            return true;
        }
        return false;
    }

    pub fn setCurrent(self: *ProviderStore, id: []const u8) void {
        if (self.current_id) |old| {
            self.allocator.free(old);
        }
        self.current_id = self.allocator.dupe(u8, id) catch null;
    }

    pub fn getCurrent(self: *const ProviderStore) ?*const Provider {
        if (self.current_id) |id| {
            return self.providers.get(id);
        }
        return null;
    }
};

pub const ProviderHandler = struct {
    allocator: std.mem.Allocator,
    store: *ProviderStore,

    pub fn init(allocator: std.mem.Allocator, store: *ProviderStore) ProviderHandler {
        return .{
            .allocator = allocator,
            .store = store,
        };
    }
};

pub const CreateProviderRequest = struct {
    id: []const u8,
    name: []const u8,
    base_url: []const u8,
    auth_type: []const u8,
    api_key: ?[]const u8,
    default_model: []const u8,
    supports: [][]const u8,
    is_official: bool,
    enabled: bool,
    sort_order: u32,
};

pub const UpdateProviderRequest = struct {
    name: ?[]const u8,
    base_url: ?[]const u8,
    auth_type: ?[]const u8,
    api_key: ?[]const u8,
    default_model: ?[]const u8,
    supports: ?[][]const u8,
    is_official: ?bool,
    enabled: ?bool,
    sort_order: ?u32,
    metadata: ?[]const u8,
};

pub const SortProvidersRequest = struct {
    ids: [][]const u8,
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    port: u16,
    key_store: *virtual_key.VirtualKeyStore,
    rate_limiter: *rate_limit.RateLimiter,
    request_logger: *logger.RequestLogger,
    metrics: *logger.MetricsCollector,

    // Edge routing components
    connection_pool: ?*connection_pool.ConnectionPool,
    latency_tracker: latency_health.LatencyTracker,
    health_checker: latency_health.HealthChecker,
    active_health: ?*active_health.ActiveHealthChecker,
    circuit_breaker: circuit_breaker.CircuitBreaker,
    hot_reload: ?*hot_reload.HotReloadConfig,
    edge_config: hot_reload.EdgeRouterConfig,

    // Analytics components
    tracking_store: tracking_analytics.TrackingStore,
    tracking_handler: tracking_analytics.TrackingHandler,
    savings_store: savings_store_mod.SavingsStore,
    savings_handler: savings_handler_mod.SavingsHandler,
    unified_handler: unified_handler_mod.UnifiedHandler,

    // Provider management
    provider_store: ProviderStore,
    provider_handler: ProviderHandler,

    pub fn init(
        allocator: std.mem.Allocator,
        port: u16,
        key_store: *virtual_key.VirtualKeyStore,
        rate_limiter: *rate_limit.RateLimiter,
        request_logger: *logger.RequestLogger,
        metrics: *logger.MetricsCollector,
    ) !Server {
        return Server.initWithEdgeConfig(allocator, port, key_store, rate_limiter, request_logger, metrics, hot_reload.getDefaultEdgeConfig());
    }

    pub fn initWithEdgeConfig(
        allocator: std.mem.Allocator,
        port: u16,
        key_store: *virtual_key.VirtualKeyStore,
        rate_limiter: *rate_limit.RateLimiter,
        request_logger: *logger.RequestLogger,
        metrics: *logger.MetricsCollector,
        edge_config: hot_reload.EdgeRouterConfig,
    ) !Server {
        var server = Server{
            .allocator = allocator,
            .port = port,
            .key_store = key_store,
            .rate_limiter = rate_limiter,
            .request_logger = request_logger,
            .metrics = metrics,
            .connection_pool = null,
            .latency_tracker = undefined,
            .health_checker = undefined,
            .active_health = null,
            .circuit_breaker = undefined,
            .hot_reload = null,
            .edge_config = edge_config,
            .tracking_store = undefined,
            .tracking_handler = undefined,
            .savings_store = undefined,
            .savings_handler = undefined,
            .unified_handler = undefined,
            .provider_store = undefined,
            .provider_handler = undefined,
        };

        // Initialize provider store and handler
        server.provider_store = ProviderStore.init(allocator);
        server.provider_handler = ProviderHandler.init(allocator, &server.provider_store);

        // Initialize latency tracker
        server.latency_tracker = latency_health.LatencyTracker.init(
            allocator,
            edge_config.latency_window_size,
        );

        // Initialize health checker
        server.health_checker = latency_health.HealthChecker.init(
            allocator,
            edge_config.health_check_interval_ms,
            edge_config.health_check_timeout_ms,
        );

        // Initialize circuit breaker
        server.circuit_breaker = circuit_breaker.CircuitBreaker.init(
            allocator,
            circuit_breaker.CircuitBreakerConfig{
                .failure_threshold = 3,
                .recovery_timeout_ms = 30000,
                .half_open_success_threshold = 2,
            },
        );

        // Initialize active health checker if enabled
        if (edge_config.enable_health_checker) {
            server.active_health = try allocator.create(active_health.ActiveHealthChecker);
            server.active_health.?.* = active_health.ActiveHealthChecker.init(
                allocator,
                active_health.ActiveHealthCheckerConfig{
                    .probe_interval_ms = edge_config.health_check_interval_ms,
                    .probe_timeout_ms = edge_config.health_check_timeout_ms,
                    .enabled = true,
                },
            );
        }

        // Initialize connection pool if enabled
        if (edge_config.enable_connection_pool) {
            server.connection_pool = try allocator.create(connection_pool.ConnectionPool);
            server.connection_pool.?.* = connection_pool.ConnectionPool.init(
                allocator,
                edge_config.max_conns_per_provider,
                edge_config.idle_timeout_ms,
            );
        }

        // Initialize tracking store and handler for analytics
        server.tracking_store = try tracking_analytics.TrackingStore.init(allocator);
        server.tracking_handler = tracking_analytics.TrackingHandler.init(allocator, &server.tracking_store);

        // Initialize savings store and handlers for proxy-cmd integration
        server.savings_store = savings_store_mod.SavingsStore.init(allocator);
        server.savings_handler = savings_handler_mod.SavingsHandler.init(allocator, &server.savings_store);
        server.unified_handler = unified_handler_mod.UnifiedHandler.init(allocator, &server.savings_store);

        return server;
    }

    pub fn deinit(self: *Server) void {
        if (self.connection_pool) |pool| {
            pool.deinit();
            self.allocator.destroy(pool);
        }
        if (self.active_health) |ah| {
            ah.deinit();
            self.allocator.destroy(ah);
        }
        self.latency_tracker.deinit();
        self.health_checker.deinit();
        self.circuit_breaker.deinit();
        if (self.hot_reload) |hr| {
            hr.deinit();
            self.allocator.destroy(hr);
        }
        self.tracking_store.deinit();
        self.savings_store.deinit();
        self.provider_store.deinit();
    }

    /// Apply new edge config from hot reload
    /// This recreates components that need to be reconfigured
    pub fn applyEdgeConfig(self: *Server) !void {
        if (self.hot_reload == null) return;

        // Load new config from file
        const new_config = try self.hot_reload.?.loadConfig();

        std.log.info("applying new edge config:", .{});
        std.log.info("  enable_connection_pool: {}", .{new_config.enable_connection_pool});
        std.log.info("  max_conns_per_provider: {}", .{new_config.max_conns_per_provider});
        std.log.info("  latency_window_size: {}", .{new_config.latency_window_size});
        std.log.info("  enable_health_checker: {}", .{new_config.enable_health_checker});
        std.log.info("  health_check_interval_ms: {}", .{new_config.health_check_interval_ms});

        // Update edge_config
        self.edge_config = new_config;

        // Note: Full recreation of components would require more complex logic
        // to migrate state. For now, we just update the config values.
        // Components will use new settings on next initialization.
    }

    pub fn start(self: *Server) !void {
        const address = try std.net.Address.parseIp("0.0.0.0", self.port);
        var listener = try address.listen(.{ .reuse_address = true });
        defer listener.deinit();

        std.log.info("llmlite-proxy listening on http://0.0.0.0:{d} (edge routing)", .{self.port});
        std.log.info("  connection_pool: {}", .{self.edge_config.enable_connection_pool});
        std.log.info("  latency_tracking: {}", .{self.edge_config.enable_latency_tracking});
        std.log.info("  health_checker: {}", .{self.edge_config.enable_health_checker});
        std.log.info("  hot_reload: {}", .{self.edge_config.enable_hot_reload});

        // Initialize hot reload if enabled
        if (self.edge_config.enable_hot_reload) {
            self.hot_reload = try self.allocator.create(hot_reload.HotReloadConfig);
            self.hot_reload.?.* = hot_reload.HotReloadConfig.init(
                self.allocator,
                "proxy.json",
                self.edge_config.config_check_interval_ms,
            );
        }

        var last_config_check: i64 = 0;

        while (true) {
            const now = std.time.timestamp();

            // Check for config hot reload periodically
            if (self.hot_reload) |hr| {
                if (@as(u64, @intCast(now - last_config_check)) * 1000 > hr.check_interval_ms) {
                    const reloaded = hr.checkAndReload() catch |err| blk: {
                        std.log.warn("hot reload check failed: {}", .{err});
                        break :blk false;
                    };
                    if (reloaded) {
                        std.log.info("config reloaded, reloading settings...", .{});
                        self.applyEdgeConfig() catch |err| {
                            std.log.warn("failed to apply new config: {}", .{err});
                        };
                    }
                    last_config_check = now;
                }
            }

            // Active health probing
            self.probeProviders();

            const connection = try listener.accept();
            self.handleConnection(connection) catch |err| {
                std.log.err("Error handling connection: {}", .{err});
            };
        }
    }

    /// Probe all configured providers for active health checking
    fn probeProviders(self: *Server) void {
        if (self.active_health == null) return;
        if (!self.active_health.?.shouldProbe()) return;

        // Probe each provider
        self.probeSingleProvider(.openai);
        self.probeSingleProvider(.anthropic);
        self.probeSingleProvider(.google);
        self.probeSingleProvider(.moonshot);
        self.probeSingleProvider(.minimax);
        self.probeSingleProvider(.deepseek);

        self.active_health.?.markProbeCycleComplete();
    }

    /// Probe a single provider for health
    fn probeSingleProvider(self: *Server, provider: types.ProviderType) void {
        const start_time = std.time.timestamp();
        const endpoint = active_health.ActiveHealthChecker.getProbeEndpoint(provider);

        // Try to make a lightweight probe request
        const result = self.probeProvider(provider, endpoint);
        const latency_ms = @as(u64, @intCast(std.time.timestamp() - start_time));

        switch (result) {
            .success => {
                self.active_health.?.recordProbeSuccess(provider, latency_ms);
                std.log.debug("probe {s} succeeded: {d}ms", .{ provider.toString(), latency_ms });
            },
            .failure => {
                self.active_health.?.recordProbeFailure(provider);
                std.log.warn("probe {s} failed", .{provider.toString()});
            },
        }
    }

    const ProbeResult = union(enum) {
        success: void,
        failure: void,
    };

    /// Make a lightweight probe request to a provider
    fn probeProvider(self: *Server, provider: types.ProviderType, endpoint: []const u8) ProbeResult {
        const provider_config = registry.getProviderConfig(provider);

        var probe_client = http.HttpClient.initWithAuthType(
            self.allocator,
            provider_config.base_url,
            "",
            null,
            5000, // 5 second timeout for probes
            provider_config.auth_type,
        );
        defer probe_client.deinit();

        // For probe, we just check if the endpoint responds (not actual data)
        const response = probe_client.get(endpoint) catch return .failure;
        defer self.allocator.free(response);

        // Any response (even error) means provider is reachable
        return .success;
    }

    fn handleConnection(self: *Server, connection: std.net.Server.Connection) !void {
        var buf: [16384]u8 = undefined;
        const bytes_read = try connection.stream.read(&buf);
        if (bytes_read == 0) return;

        const request_text = buf[0..bytes_read];
        std.log.info("request: {s}", .{request_text[0..@min(request_text.len, 200)]});

        if (std.mem.startsWith(u8, request_text, "GET /health")) {
            try self.writeJsonResponse(connection, 200, "{\"status\":\"healthy\",\"version\":\"0.2.0\",\"edge\":true}");
        } else if (std.mem.startsWith(u8, request_text, "GET /health/live")) {
            // Liveness probe - just确认 server is alive
            try self.writeJsonResponse(connection, 200, "{\"status\":\"alive\"}");
        } else if (std.mem.startsWith(u8, request_text, "GET /health/ready")) {
            // Readiness probe - check if ready to serve traffic
            // For now, always ready - could check health_checker.getHealthyProviders in future
            try self.writeJsonResponse(connection, 200, "{\"status\":\"ready\"}");
        } else if (std.mem.startsWith(u8, request_text, "GET /metrics")) {
            const metrics_text = self.metrics.prometheusMetrics(@intCast(std.time.timestamp()));
            try connection.stream.writeAll("HTTP/1.1 200 OK\r\n");
            try connection.stream.writeAll("Content-Type: text/plain\r\n");
            try connection.stream.writeAll("\r\n");
            try connection.stream.writeAll(metrics_text);
        } else if (std.mem.startsWith(u8, request_text, "GET /metrics/latency")) {
            // Latency metrics per provider
            try self.writeLatencyMetrics(connection);
        } else if (std.mem.startsWith(u8, request_text, "POST /v1/chat/completions")) {
            try self.handleChatCompletions(connection, request_text);
        } else if (std.mem.startsWith(u8, request_text, "GET /v1/models")) {
            try self.handleListModels(connection);
        } else if (std.mem.startsWith(u8, request_text, "POST /v1/embeddings")) {
            try self.handleEmbeddings(connection, request_text);
        } else if (std.mem.startsWith(u8, request_text, "POST /tracking/sync")) {
            try self.handleTrackingSync(connection, request_text);
        } else if (std.mem.startsWith(u8, request_text, "GET /analytics/gain")) {
            try self.handleAnalyticsGain(connection);
        } else if (std.mem.startsWith(u8, request_text, "GET /analytics/team")) {
            try self.handleAnalyticsTeam(connection);
        } else if (std.mem.startsWith(u8, request_text, "GET /analytics/sessions")) {
            try self.handleAnalyticsSessions(connection);
        } else if (std.mem.startsWith(u8, request_text, "POST /tracking/savings")) {
            try self.handlePostSavings(connection, request_text);
        } else if (std.mem.startsWith(u8, request_text, "GET /analytics/unified")) {
            try self.handleGetUnified(connection, request_text);
        } else if (std.mem.startsWith(u8, request_text, "/api/providers")) {
            try self.handleProviderApi(connection, request_text);
        } else {
            try self.writeJsonResponse(connection, 404, "{\"error\":{\"message\":\"Not Found\",\"type\":\"invalid_request_error\"}}");
        }
    }

    fn handleChatCompletions(self: *Server, connection: std.net.Server.Connection, request_text: []const u8) !void {
        const start_time = std.time.timestamp();
        var model: []const u8 = "unknown";
        var provider_str: ?[]const u8 = null;
        var prompt_tokens: u32 = 0;
        var completion_tokens: u32 = 0;
        var total_tokens: u32 = 0;

        // Extract API key
        const api_key = self.extractApiKey(request_text) catch |err| {
            const normalized = error_handler.normalizeError(err, null);
            try self.writeError(connection, normalized);
            return;
        };

        // Validate key
        self.key_store.validate(api_key) catch {
            const normalized = error_handler.normalizeError(error.InvalidApiKey, null);
            try self.writeError(connection, normalized);
            return;
        };

        // Check rate limit
        if (self.key_store.keys.get(api_key)) |vk| {
            if (vk.rate_limit) |limit| {
                if (!try self.rate_limiter.check(api_key, limit)) {
                    const normalized = error_handler.normalizeError(error.RateLimitExceeded, null);
                    try self.writeError(connection, normalized);
                    return;
                }
            }
        }

        // Read request body
        const body_start = std.mem.indexOf(u8, request_text, "\r\n\r\n");
        if (body_start == null) {
            const normalized = error_handler.normalizeError(error.InvalidRequest, null);
            try self.writeError(connection, normalized);
            return;
        }

        const body = request_text[body_start.? + 4 ..];

        // Route to provider and call
        const route = self.routeChatRequest(body);
        model = route.model;
        provider_str = route.provider.toString();

        // Check provider health before calling
        if (!self.health_checker.isHealthy(route.provider)) {
            std.log.warn("provider {s} marked unhealthy, attempting anyway", .{provider_str orelse "unknown"});
        }

        // Call provider and get response
        try self.handleNonStreamingChatCompletions(connection, route, body, start_time, &model, &provider_str, &prompt_tokens, &completion_tokens, &total_tokens);
    }

    fn handleNonStreamingChatCompletions(
        self: *Server,
        connection: std.net.Server.Connection,
        route: Route,
        body: []const u8,
        start_time: i64,
        model: *[]const u8,
        provider_str: *?[]const u8,
        prompt_tokens: *u32,
        completion_tokens: *u32,
        total_tokens: *u32,
    ) !void {
        const call_start = std.time.timestamp();

        // Check circuit breaker before making request
        if (self.circuit_breaker.isOpen(route.provider)) {
            std.log.warn("circuit breaker open for {s}, failing fast", .{route.provider.toString()});
            const normalized = error_handler.normalizeError(error.ServiceUnavailable, provider_str.*);
            try self.writeError(connection, normalized);
            return;
        }

        const response = self.callProvider(route, body) catch |err| {
            std.log.warn("provider call failed: {}", .{err});
            // Record failure for health tracking and circuit breaker
            self.health_checker.recordFailure(route.provider);
            self.circuit_breaker.recordFailure(route.provider);
            const normalized = error_handler.normalizeError(err, provider_str.*);
            try self.writeError(connection, normalized);
            return;
        };

        // Record success to health tracker, latency tracker, and circuit breaker
        const latency_ms = @as(u64, @intCast(std.time.timestamp() - call_start));
        self.latency_tracker.record(route.provider, latency_ms);
        self.health_checker.recordSuccess(route.provider, latency_ms);
        self.circuit_breaker.recordSuccess(route.provider);

        // Parse response for usage stats
        if (std.json.parseFromSlice(chat.ChatCompletion, self.allocator, response, .{})) |parsed| {
            defer parsed.deinit();
            prompt_tokens.* = parsed.value.usage.prompt_tokens;
            completion_tokens.* = parsed.value.usage.completion_tokens;
            total_tokens.* = parsed.value.usage.total_tokens;
        } else |_| {}

        const total_latency = @as(u64, @intCast(std.time.timestamp() - start_time));
        self.metrics.recordRequest(true, total_latency, total_tokens.*);

        try self.request_logger.log(.{
            .timestamp = start_time,
            .method = "POST",
            .path = "/v1/chat/completions",
            .status = 200,
            .latency_ms = total_latency,
            .virtual_key_id = "",
            .model = model.*,
            .provider = provider_str.*,
            .prompt_tokens = prompt_tokens.*,
            .completion_tokens = completion_tokens.*,
            .total_tokens = total_tokens.*,
            .error_msg = null,
        });

        try connection.stream.writeAll("HTTP/1.1 200 OK\r\n");
        try connection.stream.writeAll("Content-Type: application/json\r\n");
        try connection.stream.writeAll("\r\n");
        try connection.stream.writeAll(response);
    }

    fn handleEmbeddings(self: *Server, connection: std.net.Server.Connection, request_text: []const u8) !void {
        const start_time = std.time.timestamp();

        // Extract API key
        const api_key = self.extractApiKey(request_text) catch |err| {
            const normalized = error_handler.normalizeError(err, null);
            try self.writeError(connection, normalized);
            return;
        };

        // Validate key
        self.key_store.validate(api_key) catch {
            const normalized = error_handler.normalizeError(error.InvalidApiKey, null);
            try self.writeError(connection, normalized);
            return;
        };

        // Check rate limit
        if (self.key_store.keys.get(api_key)) |vk| {
            if (vk.rate_limit) |limit| {
                if (!try self.rate_limiter.check(api_key, limit)) {
                    const normalized = error_handler.normalizeError(error.RateLimitExceeded, null);
                    try self.writeError(connection, normalized);
                    return;
                }
            }
        }

        const body_start = std.mem.indexOf(u8, request_text, "\r\n\r\n");
        if (body_start == null) {
            const normalized = error_handler.normalizeError(error.InvalidRequest, null);
            try self.writeError(connection, normalized);
            return;
        }

        const body = request_text[body_start.? + 4 ..];

        // Route embeddings request
        const route = self.routeEmbeddingsRequest(body);
        const provider_str: ?[]const u8 = route.provider.toString();

        const call_start = std.time.timestamp();

        // Check circuit breaker before making request
        if (self.circuit_breaker.isOpen(route.provider)) {
            std.log.warn("circuit breaker open for {s} embeddings, failing fast", .{provider_str orelse "unknown"});
            const normalized = error_handler.normalizeError(error.ServiceUnavailable, provider_str);
            try self.writeError(connection, normalized);
            return;
        }

        // Call embeddings provider
        const response_body = self.callEmbeddingsProvider(route, body, api_key) catch |err| {
            std.log.warn("embeddings provider call failed: {}", .{err});
            // Record failure for health tracking and circuit breaker
            self.health_checker.recordFailure(route.provider);
            self.circuit_breaker.recordFailure(route.provider);
            const normalized = error_handler.normalizeError(err, provider_str);
            try self.writeError(connection, normalized);
            return;
        };

        // Record success to health tracker, latency tracker, and circuit breaker
        const latency_ms = @as(u64, @intCast(std.time.timestamp() - call_start));
        self.latency_tracker.record(route.provider, latency_ms);
        self.health_checker.recordSuccess(route.provider, latency_ms);
        self.circuit_breaker.recordSuccess(route.provider);

        // Parse response for usage stats (simplified)
        const total_latency = @as(u64, @intCast(std.time.timestamp() - start_time));
        self.metrics.recordRequest(true, total_latency, 10);

        try self.request_logger.log(.{
            .timestamp = start_time,
            .method = "POST",
            .path = "/v1/embeddings",
            .status = 200,
            .latency_ms = total_latency,
            .virtual_key_id = api_key,
            .model = route.model,
            .provider = provider_str,
            .prompt_tokens = 10,
            .completion_tokens = 0,
            .total_tokens = 10,
            .error_msg = null,
        });

        try connection.stream.writeAll("HTTP/1.1 200 OK\r\n");
        try connection.stream.writeAll("Content-Type: application/json\r\n");
        try connection.stream.writeAll("\r\n");
        try connection.stream.writeAll(response_body);
    }

    fn handleListModels(self: *Server, connection: std.net.Server.Connection) !void {
        const body = "{\"object\":\"list\",\"data\":[{\"id\":\"gpt-4o\",\"object\":\"model\",\"created\":1234567890,\"owned_by\":\"openai\"},{\"id\":\"claude-3-5-sonnet\",\"object\":\"model\",\"created\":1234567890,\"owned_by\":\"anthropic\"},{\"id\":\"gemini-2.0-flash\",\"object\":\"model\",\"created\":1234567890,\"owned_by\":\"google\"},{\"id\":\"moonshot-v1-8k\",\"object\":\"model\",\"created\":1234567890,\"owned_by\":\"kimi\"},{\"id\":\"abab6-chat\",\"object\":\"model\",\"created\":1234567890,\"owned_by\":\"minimax\"},{\"id\":\"deepseek-chat\",\"object\":\"model\",\"created\":1234567890,\"owned_by\":\"deepseek\"}]}";
        try self.writeJsonResponse(connection, 200, body);
    }

    fn extractApiKey(_: *Server, request_text: []const u8) ![]const u8 {
        const auth_header_start = std.mem.indexOf(u8, request_text, "Authorization: Bearer ");
        if (auth_header_start == null) {
            return error.MissingAuthHeader;
        }

        const auth_start = auth_header_start.? + 19;
        const auth_end = std.mem.indexOf(u8, request_text[auth_start..], "\r\n");
        if (auth_end == null) {
            return error.InvalidAuthFormat;
        }

        return request_text[auth_start .. auth_start + auth_end.?];
    }

    const Route = struct {
        provider: types.ProviderType,
        model: []const u8,
    };

    fn routeChatRequest(self: *Server, body: []const u8) Route {
        // Extract model from request body
        const model = self.extractModelFromBody(body) catch "gpt-4o";

        // Check if model has provider prefix (e.g., "openai/gpt-4o")
        if (std.mem.indexOf(u8, model, "/")) |idx| {
            const provider_str = model[0..idx];
            const model_name = model[idx + 1 ..];
            if (types.ProviderType.fromString(provider_str)) |provider_type| {
                // Check health before routing
                if (self.health_checker.isHealthy(provider_type)) {
                    return .{ .provider = provider_type, .model = model_name };
                } else {
                    std.log.warn("requested provider {s} is unhealthy, using fallback", .{provider_str});
                }
            }
        }

        // Use latency-based provider selection for edge routing
        if (self.edge_config.enable_latency_tracking) {
            const providers = &.{ types.ProviderType.openai, types.ProviderType.anthropic, types.ProviderType.google };
            const fastest = self.latency_tracker.selectFastestProvider(providers);
            if (self.health_checker.isHealthy(fastest)) {
                std.log.info("routing to fastest healthy provider: {s}", .{fastest.toString()});
                return .{ .provider = fastest, .model = model };
            }
        }

        // Default to OpenAI
        return .{ .provider = .openai, .model = model };
    }

    fn routeEmbeddingsRequest(self: *Server, body: []const u8) Route {
        // Extract model from request body
        const model = self.extractEmbeddingsModelFromBody(body) catch "text-embedding-ada-002";

        // Check if model has provider prefix (e.g., "openai/text-embedding-ada-002")
        if (std.mem.indexOf(u8, model, "/")) |idx| {
            const provider_str = model[0..idx];
            const model_name = model[idx + 1 ..];
            if (types.ProviderType.fromString(provider_str)) |provider_type| {
                // Check health before routing
                if (self.health_checker.isHealthy(provider_type)) {
                    return .{ .provider = provider_type, .model = model_name };
                } else {
                    std.log.warn("requested provider {s} is unhealthy for embeddings, using fallback", .{provider_str});
                }
            }
        }

        // Default to OpenAI for embeddings
        return .{ .provider = .openai, .model = model };
    }

    fn extractEmbeddingsModelFromBody(_: *Server, body: []const u8) ![]const u8 {
        const model_start = std.mem.indexOf(u8, body, "\"model\":\"") orelse {
            return error.ModelNotFound;
        };
        const idx = model_start + 9;
        const value_end = std.mem.indexOf(u8, body[idx..], "\"") orelse {
            return error.InvalidJson;
        };
        return body[idx .. idx + value_end];
    }

    fn extractModelFromBody(_: *Server, body: []const u8) ![]const u8 {
        const model_start = std.mem.indexOf(u8, body, "\"model\":\"") orelse {
            return error.ModelNotFound;
        };
        const idx = model_start + 9;
        const value_end = std.mem.indexOf(u8, body[idx..], "\"") orelse {
            return error.InvalidJson;
        };
        return body[idx .. idx + value_end];
    }

    fn callProvider(self: *Server, route: Route, body: []const u8) ![]u8 {
        const provider_config = registry.getProviderConfig(route.provider);

        // Create provider HTTP client
        var provider_http = http.HttpClient.initWithAuthType(
            self.allocator,
            provider_config.base_url,
            "",
            null,
            30000,
            provider_config.auth_type,
        );
        defer provider_http.deinit();

        // Get endpoint
        const endpoint = switch (route.provider) {
            .google => try std.fmt.allocPrint(self.allocator, "/models/{s}:generateContent", .{route.model}),
            else => try self.allocator.dupe(u8, "/chat/completions"),
        };
        defer self.allocator.free(endpoint);

        // Transform request to provider format
        const transformed = try self.transformRequest(route.provider, body);
        defer self.allocator.free(transformed);

        // Call provider
        return try provider_http.post(endpoint, transformed);
    }

    fn callEmbeddingsProvider(self: *Server, route: Route, body: []const u8, api_key: []const u8) ![]u8 {
        const provider_config = registry.getProviderConfig(route.provider);

        // Create provider HTTP client
        var provider_http = http.HttpClient.initWithAuthType(
            self.allocator,
            provider_config.base_url,
            api_key,
            null,
            30000,
            provider_config.auth_type,
        );
        defer provider_http.deinit();

        // Embeddings endpoint is the same for most providers
        const endpoint = try self.allocator.dupe(u8, "/embeddings");
        defer self.allocator.free(endpoint);

        // Most providers use OpenAI format for embeddings
        // Google may need transformation
        const transformed = switch (route.provider) {
            .google => try self.transformEmbeddingsToGoogle(body),
            else => try self.allocator.dupe(u8, body),
        };
        defer self.allocator.free(transformed);

        // Call provider
        return try provider_http.post(endpoint, transformed);
    }

    fn transformEmbeddingsToGoogle(server: *Server, body: []const u8) ![]u8 {
        // Google embeddings API uses a different format
        // Parse the input and transform
        const parsed = try std.json.parseFromSlice(struct {
            input: struct {
                text: []const u8,
            },
            model: []const u8,
        }, server.allocator, body, .{});
        defer parsed.deinit();

        // Transform to Google format
        return try std.fmt.allocPrint(server.allocator,
            \\{{"input":{{"content": "{s}"}},"model": "{s}"}}
        , .{ parsed.value.input.text, parsed.value.model });
    }

    fn transformRequest(self: *Server, provider: types.ProviderType, body: []const u8) ![]u8 {
        // Most providers use OpenAI format, only Anthropic and Google need transformation
        return switch (provider) {
            .anthropic => try self.transformToAnthropic(body),
            .google => try self.transformToGoogle(body),
            else => try self.allocator.dupe(u8, body),
        };
    }

    fn transformToAnthropic(self: *Server, body: []const u8) ![]u8 {
        const parsed = try std.json.parseFromSlice(struct {
            model: []const u8,
            messages: []struct {
                role: []const u8,
                content: []const u8,
            },
            temperature: ?f32,
            max_tokens: ?u32,
        }, self.allocator, body, .{});
        defer parsed.deinit();

        var system_content: ?[]const u8 = null;
        var user_content = std.ArrayList(u8).empty;
        defer user_content.deinit(self.allocator);

        for (parsed.value.messages) |msg| {
            if (std.mem.eql(u8, msg.role, "system")) {
                system_content = msg.content;
            } else if (std.mem.eql(u8, msg.role, "user")) {
                if (user_content.items.len > 0) {
                    try user_content.appendSlice(self.allocator, "\n");
                }
                try user_content.appendSlice(self.allocator, msg.content);
            }
        }

        var result = std.ArrayList(u8).empty;
        errdefer result.deinit(self.allocator);

        try std.fmt.format(result.writer(self.allocator), "{{\"model\":\"{s}\",\"messages\":[{{\"role\":\"user\",\"content\":\"{s}\"}}]", .{
            parsed.value.model,
            try user_content.toOwnedSlice(self.allocator),
        });

        if (system_content) |sys| {
            try std.fmt.format(result.writer(self.allocator), ",\"system\":\"{s}\"", .{sys});
        }
        if (parsed.value.max_tokens) |v| {
            try std.fmt.format(result.writer(self.allocator), ",\"max_tokens\":{d}", .{v});
        }
        if (parsed.value.temperature) |v| {
            try std.fmt.format(result.writer(self.allocator), ",\"temperature\":{d}", .{v});
        }

        try result.append(self.allocator, '}');
        return result.toOwnedSlice(self.allocator);
    }

    fn transformToGoogle(self: *Server, body: []const u8) ![]u8 {
        const parsed = try std.json.parseFromSlice(struct {
            model: []const u8,
            messages: []struct {
                role: []const u8,
                content: []const u8,
            },
        }, self.allocator, body, .{});
        defer parsed.deinit();

        var contents_json = std.ArrayList(u8).empty;
        defer contents_json.deinit(self.allocator);

        try contents_json.appendSlice(self.allocator, "[");
        for (parsed.value.messages, 0..) |msg, i| {
            if (i > 0) try contents_json.appendSlice(self.allocator, ",");
            const role_str = if (std.mem.eql(u8, msg.role, "user")) "user" else "model";
            try std.fmt.format(contents_json.writer(self.allocator), "{{\"role\":\"{s}\",\"parts\":[{{\"text\":\"{s}\"}}]}}", .{ role_str, msg.content });
        }
        try contents_json.appendSlice(self.allocator, "]");

        return try std.fmt.allocPrint(self.allocator,
            \\{{"contents":{s}}}
        , .{try contents_json.toOwnedSlice(self.allocator)});
    }

    fn writeError(self: *Server, connection: std.net.Server.Connection, err: error_handler.NormalizedError) !void {
        const status_text = error_handler.getStatusText(err.status);
        const json_body = error_handler.formatErrorJson(err, self.allocator) catch {
            try connection.stream.writeAll("HTTP/1.1 500 Internal Server Error\r\n");
            try connection.stream.writeAll("Content-Type: application/json\r\n");
            try connection.stream.writeAll("\r\n");
            try connection.stream.writeAll("{\"error\":{\"message\":\"Internal error\",\"type\":\"internal_error\"}}");
            return;
        };
        defer self.allocator.free(json_body);

        var buf: [64]u8 = undefined;
        const status_line = try std.fmt.bufPrint(&buf, "HTTP/1.1 {d} {s}\r\n", .{ err.status, status_text });
        try connection.stream.writeAll(status_line);
        try connection.stream.writeAll("Content-Type: application/json\r\n");
        try connection.stream.writeAll("\r\n");
        try connection.stream.writeAll(json_body);
    }

    fn writeJsonResponse(self: *Server, connection: std.net.Server.Connection, status: u16, body: []const u8) !void {
        _ = self;
        var buf: [32]u8 = undefined;
        const status_line = try std.fmt.bufPrint(&buf, "HTTP/1.1 {d} OK\r\n", .{status});
        try connection.stream.writeAll(status_line);
        try connection.stream.writeAll("Content-Type: application/json\r\n");
        try connection.stream.writeAll("\r\n");
        try connection.stream.writeAll(body);
    }

    fn writeLatencyMetrics(self: *Server, connection: std.net.Server.Connection) !void {
        // Build latency metrics response from actual tracker data
        const providers = &.{ .openai, .anthropic, .google, .moonshot, .minimax, .deepseek };

        // Get metrics for each provider
        inline for (providers) |provider| {
            const avg = self.latency_tracker.getMovingAvg(provider);
            const p50 = self.latency_tracker.getPercentile(provider, 50);
            const p95 = self.latency_tracker.getPercentile(provider, 95);
            const p99 = self.latency_tracker.getPercentile(provider, 99);
            const healthy = self.health_checker.isHealthy(provider);
            const state = self.circuit_breaker.getState(provider);

            _ = avg;
            _ = p50;
            _ = p95;
            _ = p99;
            _ = healthy;
            _ = state;
        }

        // Build a simple response with provider stats
        const response = try std.fmt.allocPrint(self.allocator,
            \\{{"latency":{{"openai":{{"avg":{d},"p50":{d},"p95":{d},"p99":{d},"healthy":{}}},"anthropic":{{"avg":{d},"p50":{d},"p95":{d},"p99":{d},"healthy":{}}},"google":{{"avg":{d},"p50":{d},"p95":{d},"p99":{d},"healthy":{}}},"circuit_breaker":{{"openai":"{s}","anthropic":"{s}","google":"{s}"}}}}
        , .{
            self.latency_tracker.getMovingAvg(.openai),
            self.latency_tracker.getPercentile(.openai, 50),
            self.latency_tracker.getPercentile(.openai, 95),
            self.latency_tracker.getPercentile(.openai, 99),
            self.health_checker.isHealthy(.openai),
            self.latency_tracker.getMovingAvg(.anthropic),
            self.latency_tracker.getPercentile(.anthropic, 50),
            self.latency_tracker.getPercentile(.anthropic, 95),
            self.latency_tracker.getPercentile(.anthropic, 99),
            self.health_checker.isHealthy(.anthropic),
            self.latency_tracker.getMovingAvg(.google),
            self.latency_tracker.getPercentile(.google, 50),
            self.latency_tracker.getPercentile(.google, 95),
            self.latency_tracker.getPercentile(.google, 99),
            self.health_checker.isHealthy(.google),
            @tagName(self.circuit_breaker.getState(.openai)),
            @tagName(self.circuit_breaker.getState(.anthropic)),
            @tagName(self.circuit_breaker.getState(.google)),
        });
        defer self.allocator.free(response);

        try connection.stream.writeAll("HTTP/1.1 200 OK\r\n");
        try connection.stream.writeAll("Content-Type: application/json\r\n");
        try connection.stream.writeAll("\r\n");
        try connection.stream.writeAll(response);
    }

    // =========================================================================
    // Tracking Analytics Handlers
    // =========================================================================

    fn handleTrackingSync(self: *Server, connection: std.net.Server.Connection, request_text: []const u8) !void {
        // Read request body
        const body_start = std.mem.indexOf(u8, request_text, "\r\n\r\n");
        if (body_start == null) {
            try self.writeJsonResponse(connection, 400, "{\"error\":{\"message\":\"Missing request body\"}}");
            return;
        }
        const body = request_text[body_start.? + 4 ..];

        // Parse the sync request
        const parsed = std.json.parseFromSlice(
            tracking_analytics.SyncRequest,
            self.allocator,
            body,
            .{},
        ) catch {
            try self.writeJsonResponse(connection, 400, "{\"error\":{\"message\":\"Invalid request body\"}}");
            return;
        };
        defer parsed.deinit();

        var synced: usize = 0;
        var errors: usize = 0;

        for (parsed.value.records) |record| {
            self.tracking_store.addRecord(record) catch {
                errors += 1;
                continue;
            };
            synced += 1;
        }

        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .synced = synced,
            .errors = errors,
        }, .{});
        defer self.allocator.free(response);
        try self.writeJsonResponse(connection, 200, response);
    }

    fn handleAnalyticsGain(self: *Server, connection: std.net.Server.Connection) !void {
        const stats = try self.tracking_store.getGainStats(.{});
        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .total_saved_tokens = stats.total_saved_tokens,
            .total_requests = stats.total_requests,
            .avg_savings_pct = stats.avg_savings_pct,
            .breakdown = stats.breakdown,
        }, .{});
        defer self.allocator.free(response);
        try self.writeJsonResponse(connection, 200, response);
    }

    fn handleAnalyticsTeam(self: *Server, connection: std.net.Server.Connection) !void {
        const stats = try self.tracking_store.getTeamStats(.{});
        const adoption_rate: f64 = if (stats.total_requests > 0)
            @as(f64, @floatFromInt(stats.total_llmlite_requests)) / @as(f64, @floatFromInt(stats.total_requests)) * 100.0
        else
            0.0;
        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .team_id = null,
            .total_saved_tokens = stats.total_saved_tokens,
            .total_requests = stats.total_requests,
            .avg_savings_pct = stats.avg_savings_pct,
            .adoption_rate = adoption_rate,
            .users = stats.by_user,
            .daily = stats.by_day,
        }, .{});
        defer self.allocator.free(response);
        try self.writeJsonResponse(connection, 200, response);
    }

    fn handleAnalyticsSessions(self: *Server, connection: std.net.Server.Connection) !void {
        const sessions = try self.tracking_store.getSessionOverview(.{});
        var total_cmds: usize = 0;
        var total_llmlite: usize = 0;
        for (sessions) |s| {
            total_cmds += s.total_cmds;
            total_llmlite += s.llmlite_cmds;
        }
        const adoption_rate: f64 = if (total_cmds > 0)
            @as(f64, @floatFromInt(total_llmlite)) / @as(f64, @floatFromInt(total_cmds)) * 100.0
        else
            0.0;
        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .sessions_scanned = sessions.len,
            .total_commands = total_cmds,
            .llmlite_commands = total_llmlite,
            .adoption_rate = adoption_rate,
            .sessions = sessions,
        }, .{});
        defer self.allocator.free(response);
        try self.writeJsonResponse(connection, 200, response);
    }

    // =========================================================================
    // Provider API Handlers
    // =========================================================================

    fn handleProviderApi(self: *Server, connection: std.net.Server.Connection, request_text: []const u8) !void {
        // Extract method and path from request_text
        const space1 = std.mem.indexOfScalar(u8, request_text, ' ') orelse {
            try self.writeJsonResponse(connection, 400, "{\"error\":{\"message\":\"Invalid request\"}}");
            return;
        };
        const method = request_text[0..space1];
        const after_space = request_text[space1 + 1 ..];
        const space2 = std.mem.indexOfScalar(u8, after_space, ' ') orelse {
            try self.writeJsonResponse(connection, 400, "{\"error\":{\"message\":\"Invalid request\"}}");
            return;
        };
        const path = after_space[0..space2];

        // Handle /api/providers/presets specially
        if (std.mem.startsWith(u8, path, "/api/providers/presets")) {
            if (std.mem.eql(u8, method, "GET")) {
                try self.handleListProviderPresets(connection);
            } else if (std.mem.startsWith(u8, path, "/api/providers/presets/") and std.mem.eql(u8, method, "POST")) {
                // POST /api/providers/presets/:id/import
                const remainder = path[22..]; // Skip "/api/providers/presets/"
                const slash_idx = std.mem.indexOfScalar(u8, remainder, '/') orelse remainder.len;
                const preset_id = remainder[0..slash_idx];
                try self.handleImportProviderPreset(connection, preset_id);
            } else {
                try self.writeJsonResponse(connection, 405, "{\"error\":{\"message\":\"Method not allowed\"}}");
            }
            return;
        }

        // Route based on path
        if (std.mem.eql(u8, path, "/api/providers") or std.mem.eql(u8, path, "/api/providers/")) {
            if (std.mem.eql(u8, method, "GET")) {
                try self.handleListProviders(connection);
            } else if (std.mem.eql(u8, method, "POST")) {
                try self.handleCreateProvider(connection, request_text);
            } else {
                try self.writeJsonResponse(connection, 405, "{\"error\":{\"message\":\"Method not allowed\"}}");
            }
        } else if (std.mem.startsWith(u8, path, "/api/providers/")) {
            const id = path[15..];
            // Check for actions like /api/providers/:id/switch
            if (std.mem.indexOfScalar(u8, id, '/')) |slash_idx| {
                const actual_id = id[0..slash_idx];
                const action = id[slash_idx + 1 ..];
                if (std.mem.eql(u8, method, "POST")) {
                    if (std.mem.eql(u8, action, "switch")) {
                        try self.handleSwitchProvider(connection, actual_id);
                    } else if (std.mem.eql(u8, action, "test")) {
                        try self.handleTestProvider(connection, actual_id);
                    } else {
                        try self.writeJsonResponse(connection, 404, "{\"error\":{\"message\":\"Action not found\"}}");
                    }
                } else {
                    try self.writeJsonResponse(connection, 405, "{\"error\":{\"message\":\"Method not allowed\"}}");
                }
            } else {
                // Provider by ID
                if (std.mem.eql(u8, method, "GET")) {
                    try self.handleGetProvider(connection, id);
                } else if (std.mem.eql(u8, method, "PUT")) {
                    try self.handleUpdateProvider(connection, id, request_text);
                } else if (std.mem.eql(u8, method, "DELETE")) {
                    try self.handleDeleteProvider(connection, id);
                } else {
                    try self.writeJsonResponse(connection, 405, "{\"error\":{\"message\":\"Method not allowed\"}}");
                }
            }
        } else if (std.mem.eql(u8, path, "/api/providers/sort") and std.mem.eql(u8, method, "PUT")) {
            try self.handleSortProviders(connection, request_text);
        } else {
            try self.writeJsonResponse(connection, 404, "{\"error\":{\"message\":\"Not Found\",\"type\":\"invalid_request_error\"}}");
        }
    }

    fn handleListProviders(self: *Server, connection: std.net.Server.Connection) !void {
        const sorted = self.provider_store.getSorted();

        try self.writeJsonResponse(connection, 200, "{\"object\":\"list\",\"data\":[]}");
        _ = sorted;
    }

    fn handleGetProvider(self: *Server, connection: std.net.Server.Connection, id: []const u8) !void {
        const provider = self.provider_store.get(id) orelse {
            try self.writeJsonResponse(connection, 404, "{\"error\":{\"message\":\"Provider not found\"}}");
            return;
        };

        const response = try provider.formatJson(self.allocator);
        defer self.allocator.free(response);

        try self.writeJsonResponse(connection, 200, response);
    }

    fn handleCreateProvider(self: *Server, connection: std.net.Server.Connection, request_text: []const u8) !void {
        const body_start = std.mem.indexOf(u8, request_text, "\r\n\r\n") orelse {
            try self.writeJsonResponse(connection, 400, "{\"error\":{\"message\":\"Missing body\"}}");
            return;
        };
        const body = request_text[body_start + 4 ..];

        const create_req = std.json.parseFromSlice(
            CreateProviderRequest,
            self.allocator,
            body,
            .{},
        ) catch {
            try self.writeJsonResponse(connection, 400, "{\"error\":{\"message\":\"Invalid request body\"}}");
            return;
        };
        defer create_req.deinit();

        const now = std.time.timestamp();
        const auth_type: ProviderAuthType = if (std.mem.eql(u8, create_req.value.auth_type, "bearer")) .bearer else if (std.mem.eql(u8, create_req.value.auth_type, "api_key")) .api_key else .none;

        const provider = Provider{
            .id = create_req.value.id,
            .name = create_req.value.name,
            .base_url = create_req.value.base_url,
            .auth_type = auth_type,
            .api_key = create_req.value.api_key,
            .default_model = create_req.value.default_model,
            .supports = create_req.value.supports,
            .is_official = create_req.value.is_official,
            .enabled = create_req.value.enabled,
            .sort_order = create_req.value.sort_order,
            .created_at = now,
            .updated_at = now,
            .metadata = null,
        };

        self.provider_store.add(provider) catch {
            try self.writeJsonResponse(connection, 500, "{\"error\":{\"message\":\"Failed to add provider\"}}");
            return;
        };

        const response = try provider.formatJson(self.allocator);
        defer self.allocator.free(response);

        try self.writeJsonResponse(connection, 201, response);
    }

    fn handleUpdateProvider(self: *Server, connection: std.net.Server.Connection, id: []const u8, request_text: []const u8) !void {
        const existing = self.provider_store.get(id) orelse {
            try self.writeJsonResponse(connection, 404, "{\"error\":{\"message\":\"Provider not found\"}}");
            return;
        };

        const body_start = std.mem.indexOf(u8, request_text, "\r\n\r\n") orelse {
            try self.writeJsonResponse(connection, 400, "{\"error\":{\"message\":\"Missing body\"}}");
            return;
        };
        const body = request_text[body_start + 4 ..];

        const update_req = std.json.parseFromSlice(
            UpdateProviderRequest,
            self.allocator,
            body,
            .{},
        ) catch {
            try self.writeJsonResponse(connection, 400, "{\"error\":{\"message\":\"Invalid request body\"}}");
            return;
        };
        defer update_req.deinit();

        const updated = Provider{
            .id = existing.id,
            .name = update_req.value.name orelse existing.name,
            .base_url = update_req.value.base_url orelse existing.base_url,
            .auth_type = if (update_req.value.auth_type) |at|
                if (std.mem.eql(u8, at, "bearer")) ProviderAuthType.bearer else if (std.mem.eql(u8, at, "api_key")) ProviderAuthType.api_key else ProviderAuthType.none
            else
                existing.auth_type,
            .api_key = update_req.value.api_key orelse existing.api_key,
            .default_model = update_req.value.default_model orelse existing.default_model,
            .supports = update_req.value.supports orelse existing.supports,
            .is_official = update_req.value.is_official orelse existing.is_official,
            .enabled = update_req.value.enabled orelse existing.enabled,
            .sort_order = update_req.value.sort_order orelse existing.sort_order,
            .created_at = existing.created_at,
            .updated_at = std.time.timestamp(),
            .metadata = update_req.value.metadata orelse existing.metadata,
        };

        self.provider_store.update(updated) catch {
            try self.writeJsonResponse(connection, 500, "{\"error\":{\"message\":\"Failed to update provider\"}}");
            return;
        };

        const response = try updated.formatJson(self.allocator);
        defer self.allocator.free(response);

        try self.writeJsonResponse(connection, 200, response);
    }

    fn handleDeleteProvider(self: *Server, connection: std.net.Server.Connection, id: []const u8) !void {
        if (self.provider_store.delete(id)) {
            const response = try std.fmt.allocPrint(self.allocator, "{{\"deleted\":true,\"id\":\"{s}\"}}", .{id});
            defer self.allocator.free(response);
            try self.writeJsonResponse(connection, 200, response);
        } else {
            try self.writeJsonResponse(connection, 404, "{\"error\":{\"message\":\"Provider not found\"}}");
        }
    }

    fn handleSwitchProvider(self: *Server, connection: std.net.Server.Connection, id: []const u8) !void {
        const provider = self.provider_store.get(id) orelse {
            try self.writeJsonResponse(connection, 404, "{\"error\":{\"message\":\"Provider not found\"}}");
            return;
        };

        self.provider_store.setCurrent(id);

        const response = try provider.formatJson(self.allocator);
        defer self.allocator.free(response);

        const full_response = try std.fmt.allocPrint(self.allocator, "{{\"switched\":true,\"provider\":{s}}}", .{response});
        defer self.allocator.free(full_response);
        try self.writeJsonResponse(connection, 200, full_response);
    }

    fn handleTestProvider(self: *Server, connection: std.net.Server.Connection, id: []const u8) !void {
        const provider = self.provider_store.get(id) orelse {
            try self.writeJsonResponse(connection, 404, "{\"error\":{\"message\":\"Provider not found\"}}");
            return;
        };

        // Simple connectivity test - for now just return success with mock latency
        _ = provider;
        const response = try std.fmt.allocPrint(self.allocator, "{{\"success\":true,\"latency_ms\":0,\"provider_id\":\"{s}\"}}", .{id});
        defer self.allocator.free(response);
        try self.writeJsonResponse(connection, 200, response);
    }

    fn handleSortProviders(self: *Server, connection: std.net.Server.Connection, request_text: []const u8) !void {
        const body_start = std.mem.indexOf(u8, request_text, "\r\n\r\n") orelse {
            try self.writeJsonResponse(connection, 400, "{\"error\":{\"message\":\"Missing body\"}}");
            return;
        };
        const body = request_text[body_start + 4 ..];

        const sort_req = std.json.parseFromSlice(
            SortProvidersRequest,
            self.allocator,
            body,
            .{},
        ) catch {
            try self.writeJsonResponse(connection, 400, "{\"error\":{\"message\":\"Invalid request body\"}}");
            return;
        };
        defer sort_req.deinit();

        for (sort_req.value.ids, 0..) |provider_id, index| {
            if (self.provider_store.get(provider_id)) |p| {
                var updated = p;
                updated.sort_order = @intCast(index);
                self.provider_store.update(updated) catch continue;
            }
        }

        try self.writeJsonResponse(connection, 200, "{\"sorted\":true}");
    }

    fn handleListProviderPresets(self: *Server, connection: std.net.Server.Connection) !void {
        const presets_response = "{\"object\":\"list\",\"data\":[" ++
            "{\"id\":\"openai\",\"name\":\"OpenAI\",\"provider_type\":\"openai\",\"base_url\":\"https://api.openai.com\",\"auth_type\":\"bearer\",\"default_models\":[\"gpt-4o\",\"gpt-4o-mini\"],\"features\":[\"chat\",\"embeddings\"],\"website\":\"https://openai.com\",\"description\":\"OpenAI\"}," ++
            "{\"id\":\"anthropic\",\"name\":\"Anthropic\",\"provider_type\":\"anthropic\",\"base_url\":\"https://api.anthropic.com\",\"auth_type\":\"bearer\",\"default_models\":[\"claude-3-5-sonnet\"],\"features\":[\"chat\"],\"website\":\"https://anthropic.com\",\"description\":\"Anthropic\"}," ++
            "{\"id\":\"google\",\"name\":\"Google Gemini\",\"provider_type\":\"google\",\"base_url\":\"https://generativelanguage.googleapis.com\",\"auth_type\":\"api_key\",\"default_models\":[\"gemini-2.0-flash\"],\"features\":[\"chat\",\"embeddings\"],\"website\":\"https://ai.google.dev\",\"description\":\"Google\"}," ++
            "{\"id\":\"moonshot\",\"name\":\"Moonshot (Kimi)\",\"provider_type\":\"moonshot\",\"base_url\":\"https://api.moonshot.cn\",\"auth_type\":\"bearer\",\"default_models\":[\"moonshot-v1-8k\"],\"features\":[\"chat\"],\"website\":\"https://platform.moonshot.cn\",\"description\":\"Moonshot\"}," ++
            "{\"id\":\"minimax\",\"name\":\"Minimax\",\"provider_type\":\"minimax\",\"base_url\":\"https://api.minimax.chat\",\"auth_type\":\"bearer\",\"default_models\":[\"abab6-chat\"],\"features\":[\"chat\",\"embeddings\",\"tts\"],\"website\":\"https://www.minimax.chat\",\"description\":\"Minimax\"}," ++
            "{\"id\":\"deepseek\",\"name\":\"DeepSeek\",\"provider_type\":\"deepseek\",\"base_url\":\"https://api.deepseek.com\",\"auth_type\":\"bearer\",\"default_models\":[\"deepseek-chat\"],\"features\":[\"chat\"],\"website\":\"https://deepseek.com\",\"description\":\"DeepSeek\"}" ++
            "]}";
        try self.writeJsonResponse(connection, 200, presets_response);
    }

    fn handleImportProviderPreset(self: *Server, connection: std.net.Server.Connection, preset_id: []const u8) !void {
        const provider_json = if (std.mem.eql(u8, preset_id, "openai"))
            "{\"id\":\"openai\",\"name\":\"OpenAI\",\"base_url\":\"https://api.openai.com\",\"auth_type\":\"bearer\",\"api_key\":null,\"default_model\":\"gpt-4o\",\"supports\":[\"chat\"],\"is_official\":true,\"enabled\":true,\"sort_order\":0,\"created_at\":0,\"updated_at\":0,\"metadata\":null}"
        else if (std.mem.eql(u8, preset_id, "anthropic"))
            "{\"id\":\"anthropic\",\"name\":\"Anthropic\",\"base_url\":\"https://api.anthropic.com\",\"auth_type\":\"bearer\",\"api_key\":null,\"default_model\":\"claude-3-5-sonnet\",\"supports\":[\"chat\"],\"is_official\":true,\"enabled\":true,\"sort_order\":0,\"created_at\":0,\"updated_at\":0,\"metadata\":null}"
        else if (std.mem.eql(u8, preset_id, "google"))
            "{\"id\":\"google\",\"name\":\"Google Gemini\",\"base_url\":\"https://generativelanguage.googleapis.com\",\"auth_type\":\"api_key\",\"api_key\":null,\"default_model\":\"gemini-2.0-flash\",\"supports\":[\"chat\",\"embeddings\"],\"is_official\":true,\"enabled\":true,\"sort_order\":0,\"created_at\":0,\"updated_at\":0,\"metadata\":null}"
        else if (std.mem.eql(u8, preset_id, "moonshot"))
            "{\"id\":\"moonshot\",\"name\":\"Moonshot (Kimi)\",\"base_url\":\"https://api.moonshot.cn\",\"auth_type\":\"bearer\",\"api_key\":null,\"default_model\":\"moonshot-v1-8k\",\"supports\":[\"chat\"],\"is_official\":true,\"enabled\":true,\"sort_order\":0,\"created_at\":0,\"updated_at\":0,\"metadata\":null}"
        else if (std.mem.eql(u8, preset_id, "minimax"))
            "{\"id\":\"minimax\",\"name\":\"Minimax\",\"base_url\":\"https://api.minimax.chat\",\"auth_type\":\"bearer\",\"api_key\":null,\"default_model\":\"abab6-chat\",\"supports\":[\"chat\",\"embeddings\",\"tts\"],\"is_official\":true,\"enabled\":true,\"sort_order\":0,\"created_at\":0,\"updated_at\":0,\"metadata\":null}"
        else if (std.mem.eql(u8, preset_id, "deepseek"))
            "{\"id\":\"deepseek\",\"name\":\"DeepSeek\",\"base_url\":\"https://api.deepseek.com\",\"auth_type\":\"bearer\",\"api_key\":null,\"default_model\":\"deepseek-chat\",\"supports\":[\"chat\"],\"is_official\":true,\"enabled\":true,\"sort_order\":0,\"created_at\":0,\"updated_at\":0,\"metadata\":null}"
        else {
            try self.writeJsonResponse(connection, 404, "{\"error\":{\"message\":\"Preset not found\"}}");
            return;
        };

        const response = try std.fmt.allocPrint(self.allocator, "{{\"imported\":true,\"provider\":{s}}}", .{provider_json});
        defer self.allocator.free(response);
        try self.writeJsonResponse(connection, 201, response);
    }

    fn handlePostSavings(self: *Server, connection: std.net.Server.Connection, request_text: []const u8) !void {
        if (std.mem.startsWith(u8, request_text, "POST /tracking/savings/batch")) {
            try self.savings_handler.handleBatchPost(connection, request_text);
        } else {
            try self.savings_handler.handlePost(connection, request_text);
        }
    }

    fn handleGetUnified(self: *Server, connection: std.net.Server.Connection, request_text: []const u8) !void {
        try self.unified_handler.handleGet(connection, request_text);
    }
};

// Re-export commonly used types from submodules for cleaner imports
pub const VirtualKeyStore = @import("virtual_key").VirtualKeyStore;
pub const RateLimiter = @import("proxy_rate_limit").RateLimiter;
pub const RequestLogger = @import("proxy_logger").RequestLogger;
pub const MetricsCollector = @import("proxy_logger").MetricsCollector;
