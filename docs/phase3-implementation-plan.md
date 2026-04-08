# Phase 3: Proxy Server - Implementation Plan

## Overview

Phase 3 implements an OpenAI-compatible AI Gateway (Proxy Server) in Zig. This is an architectural change that enables:

- Virtual key management
- Load balancing/failover
- Rate limiting
- Request logging
- Cost tracking

## Current Status ✅ COMPLETE

**Completed:**
- [x] `src/proxy/server.zig` - HTTP server foundation
- [x] `/health` endpoint - Returns `{"status":"healthy","version":"0.2.0"}`
- [x] `/metrics` endpoint - Returns Prometheus metrics
- [x] `/v1/chat/completions` - Real provider connection
- [x] `/v1/embeddings` - Real provider connection
- [x] `src/proxy/virtual_key.zig` - Virtual key store
- [x] Virtual key validation middleware - `validateAuth()` in server.zig
- [x] `llmlite-proxy` binary builds successfully
- [x] `src/proxy/router.zig` - Multi-provider fallback with health tracking
- [x] `src/proxy/rate_limit.zig` - Rate limiting
- [x] `src/proxy/logger.zig` - Request logging + metrics
- [x] `src/proxy/middleware.zig` - Auth middleware
- [x] `src/proxy/handlers/key.zig` - Key management API
- [x] `src/proxy/handlers/team.zig` - Team/Project API
- [x] `src/proxy/persistence.zig` - JSON file persistence
- [x] `src/proxy/cost.zig` - Cost tracking
- [x] `src/proxy/team.zig` - Team/Project models
- [x] Plugin system (`src/proxy/plugin.zig`, `src/proxy/plugins/`)

**Remaining:**
- [ ] Guardrails (framework done, needs content filter logic)

**Completed (Phase 4 items):**
- [x] Simple Cache - TTL-based in-memory cache
- [x] Semantic Cache - Embedding-based similarity caching
  - `extractTextFromMessages()` - JSON to text normalization
  - `cosineSimilarity()` - Vector similarity calculation
  - `findSimilar()` - O(n) similarity search
  - `hashToEmbedding()` - Fallback when no embedding API
  - LRU eviction policy

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    llmlite-proxy                     │
├─────────────────────────────────────────────────────┤
│  HTTP Server (zig std.net)                         │
│  ├── /v1/chat/completions      (OpenAI compatible) │
│  ├── /v1/embeddings            (OpenAI compatible) │
│  ├── /v1/models                (List models)       │
│  ├── /health                   (Health check)      │
│  └── /metrics                  (Prometheus)         │
├─────────────────────────────────────────────────────┤
│  Middleware                                         │
│  ├── Virtual Key Validation                          │
│  ├── Rate Limiting                                   │
│  └── Request Logging                                 │
├─────────────────────────────────────────────────────┤
│  Router                                             │
│  ├── Load balancing (round-robin)                    │
│  ├── Fallback (primary → secondary)                │
│  └── Retry with backoff                             │
├─────────────────────────────────────────────────────┤
│  Backend Providers                                  │
│  ├── OpenAI                                         │
│  ├── Anthropic                                     │
│  ├── Google                                         │
│  └── ... (all Phase 2 providers)                   │
└─────────────────────────────────────────────────────┘
```

## Directory Structure

```
src/proxy/
├── server.zig        # HTTP server + routing ✅ DONE
├── virtual_key.zig   # Key management ✅ DONE
├── config.zig        # Configuration loading ✅ DONE
├── rate_limit.zig    # Rate limiting ✅ DONE
├── logger.zig        # Request logging ✅ DONE
├── middleware.zig    # Auth, rate limit middleware ✅ DONE
├── handlers/
│   ├── chat.zig      # /v1/chat/completions ✅ DONE
│   ├── embeddings.zig # /v1/embeddings ✅ DONE
│   └── health.zig    # /health, /metrics ✅ DONE
```

## Implementation Plan (12 weeks)

### Week 1-2: HTTP Server Foundation

#### 1.1 Server Core

```zig
// src/proxy/server.zig
const std = @import("std");

pub const Server = struct {
    allocator: std.mem.Allocator,
    port: u16,
    router: *Router,
    virtual_key_store: *VirtualKeyStore,

    pub fn start(self: *Server) !void {
        var server = std.http.Server.init(self.allocator, .{
            .reuse_address = true,
        });
        defer server.deinit();

        const address = try std.net.Address.parseIp("0.0.0.0", self.port);
        try server.listen(address);

        std.log.info("llmlite-proxy listening on {}/v1", .{address});

        while (true) {
            const response = try server.nextRequest();
            try self.handleRequest(response);
        }
    }

    fn handleRequest(self: *Server, request: std.http.Server.Request) !void {
        const path = request.path();
        
        if (std.mem.startsWith(u8, path, "/v1/chat/completions")) {
            try self.handleChatCompletions(request);
        } else if (std.mem.startsWith(u8, path, "/v1/embeddings")) {
            try self.handleEmbeddings(request);
        } else if (std.mem.eql(u8, path, "/health")) {
            try self.handleHealth(request);
        } else if (std.mem.eql(u8, path, "/metrics")) {
            try self.handleMetrics(request);
        } else {
            try request.respond(.{
                .status = .not_found,
                .body = "Not Found",
            });
        }
    }
};
```

#### 1.2 Configuration

```yaml
# config.yaml
server:
  host: "0.0.0.0"
  port: 4000

virtual_keys:
  - key: "sk-1234"
    user_id: "user1"
    rate_limit: 100  # RPS
    allowed_models: ["gpt-4o", "claude-3-5-sonnet"]
    
  - key: "sk-5678"
    user_id: "user2"
    rate_limit: 50

routing:
  - model: "gpt-4o"
    targets:
      - provider: "openai"
        weight: 3
      - provider: "azure"
        weight: 1
```

```zig
// src/proxy/config.zig
pub const Config = struct {
    server: ServerConfig,
    virtual_keys: []VirtualKeyConfig,
    routing: []RoutingRule,
};

pub const ServerConfig = struct {
    host: []const u8 = "0.0.0.0",
    port: u16 = 4000,
};

pub const VirtualKeyConfig = struct {
    key: []const u8,
    user_id: ?[]const u8 = null,
    rate_limit: ?u32 = null,
    allowed_models: ?[][]const u8 = null,
};

pub const RoutingRule = struct {
    model: []const u8,
    targets: []RouteTarget,
};
```

#### 1.3 Request Parsing

```zig
// src/proxy/handlers/chat.zig
pub const ChatCompletionRequest = struct {
    model: []const u8,
    messages: []ChatMessage,
    stream: ?bool = false,
    temperature: ?f32 = null,
    top_p: ?f32 = null,
    max_tokens: ?u32 = null,
    tools: ?[]Tool = null,
    tool_choice: ?ToolChoice = null,
};

pub const ChatMessage = struct {
    role: []const u8,
    content: []const u8,
    name: ?[]const u8 = null,
};

pub fn parseChatRequest(request: []const u8) !ChatCompletionRequest {
    // Parse JSON request body
}
```

### Week 3-4: Virtual Key System

#### 2.1 Key Store

```zig
// src/proxy/virtual_key.zig
pub const VirtualKeyStore = struct {
    allocator: std.mem.Allocator,
    keys: std.StringArrayHashMap(VirtualKey),

    pub fn init(allocator: std.mem.Allocator) VirtualKeyStore {
        return .{ .allocator = allocator, .keys = std.StringArrayHashMap(VirtualKey).init(allocator) };
    }

    pub fn validate(self: *VirtualKeyStore, key: []const u8) !?*const VirtualKey {
        if (self.keys.get(key)) |vk| {
            return vk;
        }
        return error.InvalidVirtualKey;
    }

    pub fn add(self: *VirtualKeyStore, config: VirtualKeyConfig) !void {
        const vk = try self.allocator.create(VirtualKey);
        vk.* = .{
            .id = config.key,
            .key_hash = try hashKey(config.key),
            .user_id = config.user_id,
            .rate_limit = config.rate_limit,
            .allowed_models = config.allowed_models,
            .created_at = std.time.timestamp(),
        };
        try self.keys.put(config.key, vk);
    }
};

pub const VirtualKey = struct {
    id: []const u8,
    key_hash: []const u8,
    user_id: ?[]const u8,
    rate_limit: ?u32,
    allowed_models: ?[][]const u8,
    created_at: i64,
    spend: f64 = 0,
    request_count: u64 = 0,
};
```

#### 2.2 Middleware

```zig
// src/proxy/middleware.zig
pub fn authMiddleware(request: *Request, store: *VirtualKeyStore) !*const VirtualKey {
    const auth_header = request.headers.get("Authorization") orelse 
        return error.MissingAuthHeader;
    
    if (!std.mem.startsWith(u8, auth_header, "Bearer ")) {
        return error.InvalidAuthFormat;
    }
    
    const key = auth_header[7..]; // Skip "Bearer "
    return try store.validate(key);
}

pub fn rateLimitMiddleware(vk: *const VirtualKey, limiter: *RateLimiter) !void {
    if (vk.rate_limit) |limit| {
        if (!try limiter.check(vk.id, limit)) {
            return error.RateLimitExceeded;
        }
    }
}

pub fn modelRestrictionMiddleware(vk: *const VirtualKey, model: []const u8) !void {
    if (vk.allowed_models) |allowed| {
        var found = false;
        for (allowed) |m| {
            if (std.mem.eql(u8, m, model)) {
                found = true;
                break;
            }
        }
        if (!found) {
            return error.ModelNotAllowed;
        }
    }
}
```

### Week 5-6: Router + Load Balancing

#### 3.1 Router

```zig
// src/proxy/router.zig
pub const Router = struct {
    allocator: std.mem.Allocator,
    rules: std.StringArrayHashMap([]RouteTarget),

    pub fn init(allocator: std.mem.Allocator) Router {
        return .{ .allocator = allocator, .rules = std.StringArrayHashMap([]RouteTarget).init(allocator) };
    }

    pub fn addRule(self: *Router, model: []const u8, targets: []RouteTarget) !void {
        try self.rules.put(model, targets);
    }

    pub fn selectTarget(self: *Router, model: []const u8) !*const RouteTarget {
        const targets = self.rules.get(model) orelse return error.NoRouteForModel;
        if (targets.len == 0) return error.NoRouteForModel;

        // Weighted round-robin
        var total_weight: u32 = 0;
        for (targets) |t| total_weight += t.weight;

        const selection = @mod(std.time.timestamp(), total_weight);
        var running: u32 = 0;
        for (targets) |*t| {
            running += t.weight;
            if (running > selection) return t;
        }
        return &targets[0];
    }
};

pub const RouteTarget = struct {
    provider: ProviderType,
    model: []const u8,
    weight: u32 = 1,
};
```

#### 3.2 Retry with Backoff

```zig
pub const RetryConfig = struct {
    max_retries: u3 = 3,
    base_delay_ms: u32 = 100,
    max_delay_ms: u32 = 5000,
};

pub fn callWithRetry(
    router: *Router,
    request: *const ChatCompletionRequest,
    config: RetryConfig,
) !ChatResponse {
    var last_error: anyerror = error.NoProviderAvailable;
    
    var attempt: u3 = 0;
    while (attempt < config.max_retries) : (attempt += 1) {
        const target = try router.selectTarget(request.model);
        
        const response = callProvider(target.provider, target.model, request);
        
        if (response) |resp| {
            return resp;
        } else |err| {
            last_error = err;
            
            // Don't retry on auth errors
            if (err == error.InvalidAuth or err == error.InvalidModel) {
                return err;
            }
            
            // Exponential backoff
            const delay = @min(
                config.base_delay_ms * std.math.pow(u32, 2, attempt),
                config.max_delay_ms,
            );
            std.time.sleep(delay * std.time.ns_per_ms);
        }
    }
    
    return last_error;
}
```

### Week 7-8: Rate Limiting

```zig
// src/proxy/rate_limit.zig
pub const RateLimiter = struct {
    allocator: std.mem.Allocator,
    windows: std.StringArrayHashMap(RateWindow),

    pub const RateWindow = struct {
        hits: []i64,  // Timestamps of requests
        window_size_ns: u64,
    };

    pub fn init(allocator: std.mem.Allocator) RateLimiter {
        return .{ .allocator = allocator, .windows = std.StringArrayHashMap(RateWindow).init(allocator) };
    }

    pub fn check(self: *RateLimiter, key: []const u8, limit: u32) !bool {
        const now = std.time.timestamp();
        const window_ns = 1 * std.time.ns_per_s; // 1 second window

        var window = self.windows.getOrPut(key) catch return error.OutOfMemory;
        if (!window.found_existing) {
            window.value_ptr.* = .{
                .hits = &.{},
                .window_size_ns = window_ns,
            };
        }

        // Remove old hits outside the window
        var valid_hits = std.ArrayList(i64).init(self.allocator);
        defer valid_hits.deinit();
        
        for (window.value_ptr.hits) |hit| {
            if (now - hit < 1) {
                try valid_hits.append(hit);
            }
        }

        if (valid_hits.items.len >= limit) {
            return false; // Rate limited
        }

        try valid_hits.append(now);
        window.value_ptr.hits = try valid_hits.toOwnedSlice();
        return true;
    }
};
```

### Week 9-10: Logging + Metrics

#### 7.1 Request Logging

```zig
// src/proxy/logger.zig
pub const RequestLogger = struct {
    allocator: std.mem.Allocator,
    log_file: std.fs.File,

    pub const LogEntry = struct {
        timestamp: i64,
        method: []const u8,
        path: []const u8,
        status: u16,
        latency_ms: u64,
        virtual_key_id: ?[]const u8,
        model: ?[]const u8,
        prompt_tokens: ?u32,
        completion_tokens: ?u32,
        error: ?[]const u8,
    };

    pub fn log(self: *RequestLogger, entry: LogEntry) !void {
        const json = try std.json.stringifyAlloc(self.allocator, entry);
        defer self.allocator.free(json);
        
        try self.log_file.write(json);
        try self.log_file.write("\n");
    }
};
```

#### 7.2 Prometheus Metrics

```zig
// src/proxy/handlers/metrics.zig
pub const Metrics = struct {
    requests_total: u64 = 0,
    requests_success: u64 = 0,
    requests_error: u64 = 0,
    latency_sum_ms: u64 = 0,
    tokens_total: u64 = 0,
};

pub fn prometheusMetrics(metrics: *const Metrics) []const u8 {
    return std.fmt.comptimePrint(
        \\# HELP llmlite_requests_total Total requests
        \\# TYPE llmlite_requests_total counter
        \\llmlite_requests_total {d}
        \\# HELP llmlite_requests_success Successful requests
        \\# TYPE llmlite_requests_success counter
        \\llmlite_requests_success {d}
        \\# HELP llmlite_requests_error Failed requests
        \\# TYPE llmlite_requests_error counter
        \\llmlite_requests_error {d}
        \\# HELP llmlite_latency_ms Request latency
        \\# TYPE llmlite_latency_ms histogram
        \\llmlite_latency_ms_sum {d}
        \\# HELP llmlite_tokens_total Tokens processed
        \\# TYPE llmlite_tokens_total counter
        \\llmlite_tokens_total {d}
    , .{ metrics.requests_total, metrics.requests_success, metrics.requests_error, metrics.latency_sum_ms, metrics.tokens_total });
}
```

### Week 11-12: Testing + Deployment

#### 8.1 Integration Tests

```zig
// src/proxy/test/proxy_test.zig
test "proxy chat completions" {
    const proxy = try Proxy.init(test_allocator, .{
        .port = 18080,
    });
    defer proxy.deinit();

    try proxy.addVirtualKey(.{
        .key = "sk-test",
        .rate_limit = 100,
    });

    // Start proxy in background
    const server = try std.Thread.spawn(.{}, Server.start, .{&proxy});

    // Make request
    const response = try http.post(
        "http://127.0.0.1:18080/v1/chat/completions",
        \\{"model":"gpt-4o","messages":[{"role":"user","content":"Hello"}]}
    , "Bearer sk-test");

    try std.testing.expectEqual(@as(u16, 200), response.status);
}
```

#### 8.2 Dockerfile

```dockerfile
FROM scratch
COPY zig-linux-x86_64-0.15.2 /usr/local/bin/zig
COPY llmlite-proxy /usr/local/bin/
COPY config.yaml /etc/llmlite/config.yaml
EXPOSE 4000
ENTRYPOINT ["/usr/local/bin/llmlite-proxy", "--config", "/etc/llmlite/config.yaml"]
```

## API Endpoints

### POST /v1/chat/completions

```http
POST /v1/chat/completions
Authorization: Bearer sk-xxxx
Content-Type: application/json

{
  "model": "gpt-4o",
  "messages": [
    {"role": "system", "content": "You are helpful."},
    {"role": "user", "content": "Hello!"}
  ],
  "temperature": 0.7,
  "max_tokens": 100
}
```

Response (non-streaming):
```json
{
  "id": "chatcmpl-xxx",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "gpt-4o",
  "choices": [{
    "index": 0,
    "message": {
      "role": "assistant",
      "content": "Hello! How can I help?"
    },
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 20,
    "completion_tokens": 15,
    "total_tokens": 35
  }
}
```

### GET /health

```http
GET /health

{"status": "healthy", "version": "0.2.0", "uptime": 3600}
```

### GET /metrics

```http
GET /metrics

# HELP llmlite_requests_total Total requests
# TYPE llmlite_requests_total counter
llmlite_requests_total 12345
...
```

## Error Responses

```zig
pub const ProxyError = error{
    InvalidAuth,
    InvalidVirtualKey,
    RateLimitExceeded,
    ModelNotAllowed,
    NoRouteForModel,
    ProviderError,
    InternalError,
};

pub fn formatProxyError(err: ProxyError) struct { code: u16, message: []const u8 } {
    return switch (err) {
        .InvalidAuth => .{ .code = 401, .message = "Invalid authentication" },
        .InvalidVirtualKey => .{ .code = 401, .message = "Invalid virtual key" },
        .RateLimitExceeded => .{ .code = 429, .message = "Rate limit exceeded" },
        .ModelNotAllowed => .{ .code = 403, .message = "Model not allowed for this key" },
        .NoRouteForModel => .{ .code = 400, .message = "No route for model" },
        .ProviderError => .{ .code = 502, .message = "Provider error" },
        .InternalError => .{ .code = 500, .message = "Internal server error" },
    };
}
```

## Success Criteria

- [x] HTTP server starts and listens on port 4000 ✅
- [x] `/v1/chat/completions` endpoint exists ✅
- [x] `/health` returns healthy status ✅
- [x] `/metrics` returns Prometheus metrics ✅
- [x] Virtual key store implemented ✅
- [x] Virtual key validation middleware ✅
- [x] Rate limiting enforces limits ✅
- [x] Router selects targets correctly (model prefix routing) ✅
- [x] Request logging works ✅
- [x] Retry with backoff works ✅
- [x] Docker image builds and runs ✅
- [x] Team/Project API handlers ✅
- [x] Cost tracking ✅
- [x] JSON file persistence ✅
- [x] Plugin architecture ✅
- [ ] Load tests pass (100 RPS sustained)

## Implementation Status (Updated 2026-04-07)

### Completed Components

| Component | File | Status |
|-----------|------|--------|
| Server Core | `src/proxy/server.zig` | ✅ Done |
| Virtual Key Store | `src/proxy/virtual_key.zig` | ✅ Done |
| Rate Limiter | `src/proxy/rate_limit.zig` | ✅ Done |
| Request Logger | `src/proxy/logger.zig` | ✅ Done |
| Metrics Collector | `src/proxy/logger.zig` | ✅ Done |
| Middleware | `src/proxy/middleware.zig` | ✅ Done |
| Config | `src/proxy/config.zig` | ✅ Done |
| Chat Handler | `src/proxy/handlers/chat.zig` | ✅ Done |
| Embeddings Handler | `src/proxy/handlers/embeddings.zig` | ✅ Done |
| Proxy Main | `src/proxy_main.zig` | ✅ Done |
| Router with Retry | `src/proxy/router.zig` | ✅ Done |
| Connection Pool | `src/proxy/connection_pool.zig` | ✅ Done |
| Latency Health Tracker | `src/proxy/latency_health.zig` | ✅ Done |
| Hot Reload Config | `src/proxy/hot_reload.zig` | ✅ Done |
| Team/Project Models | `src/proxy/team.zig` | ✅ Done |
| Cost Tracking | `src/proxy/cost.zig` | ✅ Done |
| Persistence | `src/proxy/persistence.zig` | ✅ Done |
| Plugin System | `src/proxy/plugin.zig` + `plugins/` | ✅ Done |
| Docker Support | `Dockerfile` | ✅ Done |

### Edge Routing Features (Phase 3 Edge Optimization)

| Feature | File | Description |
|---------|------|-------------|
| Connection Pooling | `src/proxy/connection_pool.zig` | HTTP connection reuse with per-provider pools, idle timeout management |
| Latency Tracker | `src/proxy/latency_health.zig` | Moving average, P50/P95/P99 percentiles per provider (fixed percentile calculation) |
| Health Checker | `src/proxy/latency_health.zig` | Consecutive failure tracking with configurable thresholds |
| Circuit Breaker | `src/proxy/circuit_breaker.zig` | CLOSED/OPEN/HALF_OPEN states, prevents cascading failures (wired into server.zig) |
| Active Health Checker | `src/proxy/active_health.zig` | Periodic probe requests to detect provider issues proactively (wired into server.zig with probe loop) |
| Hot Reload Config | `src/proxy/hot_reload.zig` | File watching for zero-downtime config updates with applyEdgeConfig() |
| Edge Router Config | `src/proxy/hot_reload.zig` | Edge-specific defaults (672KB ReleaseSmall binary, no K8s/Docker) |
| Embeddings Provider Flow | `src/proxy/server.zig` | Real embeddings provider routing with circuit breaker, health tracking, and latency metrics |

### Edge Routing Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Basic health check |
| `GET /health/live` | Liveness probe (Kubernetes-compatible) |
| `GET /health/ready` | Readiness probe |
| `GET /metrics` | Prometheus metrics |
| `GET /metrics/latency` | Per-provider latency percentiles (P50/P95/P99) |
| `POST /v1/embeddings` | Real embeddings provider routing with failover |

### Comprehensive Test Coverage

| Component | Tests Added |
|-----------|-------------|
| `connection_pool.zig` | 6 unit tests (init, ProviderPool, getConnection, releaseConnection, closeIdleConnections, markUnhealthy) |
| `latency_health.zig` | 15 unit tests (LatencyTracker: init, record, moving avg, percentiles, window size, provider selection; HealthChecker: init, isHealthy, consecutive failures, success resets, multi-provider) |
| `router.zig` | 10 unit tests (init, RetryConfig, isRetryable, calculateBackoff, recordSuccess/recordFailure, isProviderUnhealthy, getStats, RoutingTable) |
| `circuit_breaker.zig` | 11 unit tests (state transitions, half-open recovery, stats tracking) |
| `active_health.zig` | 12 unit tests (init, shouldProbe, consecutive successes/failures, health summary) |
| `hot_reload.zig` | 5 unit tests (HotReloadConfig init, getReloadCount, checkAndReload, loadConfig; EdgeRouterConfig defaults, custom values) |