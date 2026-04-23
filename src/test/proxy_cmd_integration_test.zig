//! Integration Tests for Proxy-Cmd Integration
//!
//! Tests the core data flow: SavingsReport → JSON → SavingsStore → UnifiedResponse

const std = @import("std");
const shared = @import("shared_analytics");
const savings_store_mod = @import("proxy_savings_store");
const config_mod = @import("config");
const time_compat = @import("time_compat");

// ============================================================================
// SavingsStore Integration Tests
// ============================================================================

test "SavingsStore: add report and aggregate" {
    const allocator = std.testing.allocator;
    var store = savings_store_mod.SavingsStore.init(allocator, std.testing.io);
    defer store.deinit();

    try store.addReport(.{
        .timestamp = time_compat.timestamp(std.testing.io),
        .original_cmd = "git status",
        .raw_output_tokens = 1000,
        .filtered_output_tokens = 400,
        .saved_tokens = 600,
        .savings_pct = 60.0,
        .exit_code = 0,
        .hostname = "localhost",
    });

    try store.addReport(.{
        .timestamp = time_compat.timestamp(std.testing.io),
        .original_cmd = "cargo test",
        .raw_output_tokens = 2000,
        .filtered_output_tokens = 800,
        .saved_tokens = 1200,
        .savings_pct = 60.0,
        .exit_code = 0,
        .hostname = "localhost",
    });

    const summary = store.aggregate(null, null);
    try std.testing.expectEqual(@as(u64, 2), summary.total_commands);
    try std.testing.expectEqual(@as(u64, 1800), summary.total_saved_tokens);
}

test "SavingsStore: time range filtering" {
    const allocator = std.testing.allocator;
    var store = savings_store_mod.SavingsStore.init(allocator, std.testing.io);
    defer store.deinit();

    const now = time_compat.timestamp(std.testing.io);

    // Old report (10 days ago)
    try store.addReport(.{
        .timestamp = now - 86400 * 10,
        .original_cmd = "old cmd",
        .raw_output_tokens = 100,
        .filtered_output_tokens = 50,
        .saved_tokens = 50,
        .savings_pct = 50.0,
        .exit_code = 0,
        .hostname = "localhost",
    });

    // Recent report
    try store.addReport(.{
        .timestamp = now - 86400,
        .original_cmd = "recent cmd",
        .raw_output_tokens = 200,
        .filtered_output_tokens = 100,
        .saved_tokens = 100,
        .savings_pct = 50.0,
        .exit_code = 0,
        .hostname = "localhost",
    });

    const recent = store.aggregate(5, null);
    try std.testing.expectEqual(@as(u64, 1), recent.total_commands);
    try std.testing.expectEqual(@as(u64, 100), recent.total_saved_tokens);

    const all = store.aggregate(null, null);
    try std.testing.expectEqual(@as(u64, 2), all.total_commands);
}

test "SavingsStore: empty data returns zeros" {
    const allocator = std.testing.allocator;
    var store = savings_store_mod.SavingsStore.init(allocator, std.testing.io);
    defer store.deinit();

    const summary = store.aggregate(null, null);
    try std.testing.expectEqual(@as(u64, 0), summary.total_commands);
    try std.testing.expectEqual(@as(u64, 0), summary.total_saved_tokens);
    try std.testing.expectEqual(@as(f64, 0.0), summary.avg_savings_pct);
}

// ============================================================================
// Serialization Round-trip Tests
// ============================================================================

test "SavingsReport JSON round-trip" {
    const allocator = std.testing.allocator;

    const original = shared.SavingsReport{
        .timestamp = 1700000000,
        .original_cmd = "git status",
        .raw_output_tokens = 1000,
        .filtered_output_tokens = 400,
        .saved_tokens = 600,
        .savings_pct = 60.0,
        .exit_code = 0,
        .hostname = "test-host",
    };

    const json = try shared.serializeSavingsReport(allocator, original);
    defer allocator.free(json);

    const parsed = try shared.parseSavingsReport(allocator, json);
    defer {
        allocator.free(parsed.original_cmd);
        allocator.free(parsed.hostname);
    }

    try std.testing.expectEqual(original.timestamp, parsed.timestamp);
    try std.testing.expectEqualStrings(original.original_cmd, parsed.original_cmd);
    try std.testing.expectEqual(original.raw_output_tokens, parsed.raw_output_tokens);
    try std.testing.expectEqual(original.saved_tokens, parsed.saved_tokens);
    try std.testing.expectEqual(original.savings_pct, parsed.savings_pct);
    try std.testing.expectEqual(original.exit_code, parsed.exit_code);
    try std.testing.expectEqualStrings(original.hostname, parsed.hostname);
}

test "UnifiedResponse JSON round-trip" {
    const allocator = std.testing.allocator;

    const original = shared.UnifiedResponse{
        .api_cost = .{
            .total_requests = 100,
            .total_input_tokens = 5000,
            .total_output_tokens = 2000,
            .total_cost_usd = 0.5,
            .by_provider = &[_]shared.ProviderBreakdown{
                .{ .provider = "openai", .requests = 80, .cost_usd = 0.4 },
            },
            .by_model = &[_]shared.ModelBreakdown{
                .{ .model = "gpt-4", .requests = 50, .cost_usd = 0.3 },
            },
        },
        .cmd_savings = .{
            .total_commands = 20,
            .total_saved_tokens = 10000,
            .avg_savings_pct = 45.5,
            .by_command = &[_]shared.CommandBreakdown{
                .{ .command = "git status", .count = 10, .saved_tokens = 5000 },
            },
        },
        .net_cost = 0.25,
    };

    const json = try shared.serializeUnifiedResponse(allocator, original);
    defer allocator.free(json);

    const parsed = try shared.parseUnifiedResponse(allocator, json);
    defer {
        allocator.free(parsed.api_cost.by_provider[0].provider);
        allocator.free(parsed.api_cost.by_model[0].model);
        allocator.free(parsed.cmd_savings.by_command[0].command);
        allocator.free(parsed.api_cost.by_provider);
        allocator.free(parsed.api_cost.by_model);
        allocator.free(parsed.cmd_savings.by_command);
    }

    try std.testing.expectEqual(original.api_cost.total_requests, parsed.api_cost.total_requests);
    try std.testing.expectEqual(original.cmd_savings.total_commands, parsed.cmd_savings.total_commands);
    try std.testing.expectEqualStrings(original.api_cost.by_provider[0].provider, parsed.api_cost.by_provider[0].provider);
    try std.testing.expectEqualStrings(original.cmd_savings.by_command[0].command, parsed.cmd_savings.by_command[0].command);
    try std.testing.expectEqual(original.net_cost, parsed.net_cost);
}

// ============================================================================
// Config Parsing Tests
// ============================================================================

test "Config: analytics defaults" {
    const allocator = std.testing.allocator;

    // Empty config should use defaults
    const cfg = try config_mod.parseConfig(allocator, "");
    defer allocator.free(cfg.analytics_proxy.host);

    try std.testing.expect(cfg.analytics.enabled);
    try std.testing.expectEqual(@as(u32, 90), cfg.analytics.retention_days);
    try std.testing.expectEqual(@as(u32, 300), cfg.analytics.sync_interval_secs);
    try std.testing.expectEqualStrings("localhost", cfg.analytics_proxy.host);
    try std.testing.expectEqual(@as(u16, 4001), cfg.analytics_proxy.port);
}

test "Config: analytics section parsing" {
    const allocator = std.testing.allocator;

    const toml =
        \\[analytics]
        \\enabled = false
        \\retention_days = 30
        \\sync_interval_secs = 60
        \\
        \\[analytics.proxy]
        \\host = "proxy.example.com"
        \\port = 8080
    ;

    const cfg = try config_mod.parseConfig(allocator, toml);
    defer allocator.free(cfg.analytics_proxy.host);

    try std.testing.expect(!cfg.analytics.enabled);
    try std.testing.expectEqual(@as(u32, 30), cfg.analytics.retention_days);
    try std.testing.expectEqual(@as(u32, 60), cfg.analytics.sync_interval_secs);
    try std.testing.expectEqualStrings("proxy.example.com", cfg.analytics_proxy.host);
    try std.testing.expectEqual(@as(u16, 8080), cfg.analytics_proxy.port);
}
