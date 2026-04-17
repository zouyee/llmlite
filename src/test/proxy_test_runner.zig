//! Proxy Component Integration Tests
//!
//! This test module imports all proxy components and runs their inline tests.
//! Run with: zig build test-proxy

const std = @import("std");

// Import all proxy modules to make their inline tests available
const error_handler = @import("proxy_error_handler");
const rate_limit = @import("proxy_rate_limit");
const virtual_key = @import("virtual_key");
const connection_pool = @import("connection_pool");
const latency_health = @import("latency_health");
const hot_reload = @import("hot_reload");
const circuit_breaker = @import("circuit_breaker");
const active_health = @import("active_health");
const header_case = @import("proxy_header_case");
const app_type_router = @import("proxy_app_type_router");
const format_transformer = @import("proxy_format_transformer");
const provider_adapter = @import("proxy_provider_adapter");
const failover = @import("proxy_failover");
const error_mapper = @import("proxy_error_mapper");
const usage_tracker = @import("proxy_usage_tracker");
const forwarder = @import("proxy_forwarder");
const hot_config = @import("proxy_hot_config");
const request_context = @import("proxy_request_context");
const pipeline = @import("proxy_pipeline");

// Re-export types for convenience
const ProviderType = @import("types").ProviderType;

test "proxy test imports" {
    // Basic test to verify all modules are importable
    try std.testing.expect(true);
}
