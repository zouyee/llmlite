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
        };

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

    fn transformEmbeddingsToGoogle(_: *Server, body: []const u8) ![]u8 {
        // Google embeddings API uses a different format
        // Parse the input and transform
        const parsed = try std.json.parseFromSlice(struct {
            input: struct {
                text: []const u8,
            },
            model: []const u8,
        }, std.heap.page_allocator, body, .{});
        defer parsed.deinit();

        // Transform to Google format
        return try std.fmt.allocPrint(std.heap.page_allocator,
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
};
