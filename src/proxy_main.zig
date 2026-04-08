const std = @import("std");
const proxy = @import("proxy");
const virtual_key = @import("virtual_key");
const rate_limit = @import("proxy_rate_limit");
const logger = @import("proxy_logger");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("llmlite-proxy starting...", .{});

    // Initialize components
    var key_store = virtual_key.VirtualKeyStore.init(allocator);
    defer key_store.deinit();

    var rate_limiter = rate_limit.RateLimiter.init(allocator);
    defer rate_limiter.deinit();

    var request_logger = try logger.RequestLogger.init(allocator, null, true);
    defer request_logger.deinit();

    var metrics = logger.MetricsCollector{};

    // Add test API key
    try key_store.add("sk-test-key", .{
        .user_id = "test-user",
        .rate_limit = 100,
        .allowed_models = null,
    });

    std.log.info("Added test API key: sk-test-key", .{});
    std.log.info("Virtual Keys: enabled", .{});
    std.log.info("Multi-tenancy: disabled (set via config)", .{});
    std.log.info("Cost Tracking: disabled (set via config)", .{});
    std.log.info("Cache: disabled (set via config)", .{});
    std.log.info("KV Backend: memory (in-memory, zero dependency)", .{});

    const port = 4000;
    var server = try proxy.Server.init(
        allocator,
        port,
        &key_store,
        &rate_limiter,
        &request_logger,
        &metrics,
    );
    errdefer server.deinit();

    std.log.info("llmlite-proxy listening on http://0.0.0.0:{d}", .{port});

    try server.start();
}
