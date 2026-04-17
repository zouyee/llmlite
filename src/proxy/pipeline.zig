//! Request Processing Pipeline for llmlite Proxy
//!
//! Defines the middleware chain configuration and result types for processing
//! proxy requests. This is a standalone module that server.zig can import later
//! to orchestrate the full request pipeline.
//!
//! Pipeline steps: detect format → transform → filter → forward → transform response → track usage

const std = @import("std");

/// Configuration for which pipeline stages are enabled.
pub const PipelineConfig = struct {
    format_transform_enabled: bool = true,
    body_filter_enabled: bool = true,
    model_mapper_enabled: bool = true,
    thinking_optimizer_enabled: bool = false,
    cache_injector_enabled: bool = false,
    copilot_optimizer_enabled: bool = false,
    header_case_enabled: bool = true,
};

/// Result of processing a request through the pipeline.
pub const PipelineResult = struct {
    status_code: u16,
    body: []const u8,
    content_type: []const u8 = "application/json",
    is_streaming: bool = false,
    provider_id: ?[]const u8 = null,
    was_failover: bool = false,
    was_rectified: bool = false,
    latency_ms: u64 = 0,
};

/// Request processing pipeline that coordinates middleware stages.
pub const Pipeline = struct {
    allocator: std.mem.Allocator,
    config: PipelineConfig,

    pub fn init(allocator: std.mem.Allocator, config: PipelineConfig) Pipeline {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Pipeline) void {
        _ = self;
    }

    /// Process a request through the full pipeline.
    ///
    /// Steps: detect format → transform → filter → forward → transform response → track usage
    ///
    /// This is a placeholder that will be wired up to real middleware in the
    /// server.zig integration task. For now it returns a stub result so the
    /// module compiles and the interface is locked in.
    pub fn processRequest(
        self: *Pipeline,
        path: []const u8,
        headers: []const [2][]const u8,
        body: []const u8,
        app_type: u3,
    ) !PipelineResult {
        _ = self;
        _ = path;
        _ = headers;
        _ = body;
        _ = app_type;
        return PipelineResult{
            .status_code = 200,
            .body = "",
        };
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "pipeline - PipelineConfig defaults" {
    const config = PipelineConfig{};
    try std.testing.expectEqual(true, config.format_transform_enabled);
    try std.testing.expectEqual(true, config.body_filter_enabled);
    try std.testing.expectEqual(true, config.model_mapper_enabled);
    try std.testing.expectEqual(false, config.thinking_optimizer_enabled);
    try std.testing.expectEqual(false, config.cache_injector_enabled);
    try std.testing.expectEqual(false, config.copilot_optimizer_enabled);
    try std.testing.expectEqual(true, config.header_case_enabled);
}

test "pipeline - PipelineConfig custom values" {
    const config = PipelineConfig{
        .format_transform_enabled = false,
        .thinking_optimizer_enabled = true,
        .cache_injector_enabled = true,
    };
    try std.testing.expectEqual(false, config.format_transform_enabled);
    try std.testing.expectEqual(true, config.body_filter_enabled);
    try std.testing.expectEqual(true, config.thinking_optimizer_enabled);
    try std.testing.expectEqual(true, config.cache_injector_enabled);
}

test "pipeline - PipelineResult defaults" {
    const result = PipelineResult{
        .status_code = 200,
        .body = "{}",
    };
    try std.testing.expectEqual(@as(u16, 200), result.status_code);
    try std.testing.expectEqualStrings("{}", result.body);
    try std.testing.expectEqualStrings("application/json", result.content_type);
    try std.testing.expectEqual(false, result.is_streaming);
    try std.testing.expectEqual(null, result.provider_id);
    try std.testing.expectEqual(false, result.was_failover);
    try std.testing.expectEqual(false, result.was_rectified);
    try std.testing.expectEqual(@as(u64, 0), result.latency_ms);
}

test "pipeline - PipelineResult with all fields" {
    const result = PipelineResult{
        .status_code = 502,
        .body = "{\"error\":\"bad gateway\"}",
        .content_type = "text/plain",
        .is_streaming = true,
        .provider_id = "anthropic-1",
        .was_failover = true,
        .was_rectified = true,
        .latency_ms = 1500,
    };
    try std.testing.expectEqual(@as(u16, 502), result.status_code);
    try std.testing.expectEqualStrings("{\"error\":\"bad gateway\"}", result.body);
    try std.testing.expectEqualStrings("text/plain", result.content_type);
    try std.testing.expectEqual(true, result.is_streaming);
    try std.testing.expectEqualStrings("anthropic-1", result.provider_id.?);
    try std.testing.expectEqual(true, result.was_failover);
    try std.testing.expectEqual(true, result.was_rectified);
    try std.testing.expectEqual(@as(u64, 1500), result.latency_ms);
}

test "pipeline - Pipeline init and deinit" {
    var pipeline = Pipeline.init(std.testing.allocator, .{});
    defer pipeline.deinit();

    try std.testing.expectEqual(true, pipeline.config.format_transform_enabled);
    try std.testing.expectEqual(true, pipeline.config.body_filter_enabled);
}

test "pipeline - Pipeline init with custom config" {
    const config = PipelineConfig{
        .thinking_optimizer_enabled = true,
        .cache_injector_enabled = true,
        .copilot_optimizer_enabled = true,
    };
    var pipeline = Pipeline.init(std.testing.allocator, config);
    defer pipeline.deinit();

    try std.testing.expectEqual(true, pipeline.config.thinking_optimizer_enabled);
    try std.testing.expectEqual(true, pipeline.config.cache_injector_enabled);
    try std.testing.expectEqual(true, pipeline.config.copilot_optimizer_enabled);
}

test "pipeline - processRequest returns stub result" {
    var pipeline = Pipeline.init(std.testing.allocator, .{});
    defer pipeline.deinit();

    const headers = [_][2][]const u8{
        .{ "Content-Type", "application/json" },
    };
    const result = try pipeline.processRequest("/v1/messages", &headers, "{}", 0);
    try std.testing.expectEqual(@as(u16, 200), result.status_code);
    try std.testing.expectEqualStrings("", result.body);
}
