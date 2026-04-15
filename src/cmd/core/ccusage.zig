//! ccusage - Claude Code Usage Analytics
//!
//! Reads Claude Code usage data via ccusage npm package.
//! Gracefully degrades if ccusage is not available.
//!
//! Inspired by RTK's ccusage.rs

const std = @import("std");

pub const CcusageMetrics = struct {
    input_tokens: u64 = 0,
    output_tokens: u64 = 0,
    cache_creation_tokens: u64 = 0,
    cache_read_tokens: u64 = 0,
    total_tokens: u64 = 0,
    total_cost: f64 = 0.0,
};

pub const CcusagePeriod = struct {
    key: []const u8,
    metrics: CcusageMetrics,
};

pub const Granularity = enum {
    daily,
    weekly,
    monthly,
};

/// Result of ccusage fetch attempt
pub const CcusageResult = struct {
    periods: []CcusagePeriod,
    available: bool,
    error_message: ?[]const u8 = null,
};

var global_allocator: std.mem.Allocator = undefined;

/// Initialize ccusage module
pub fn init(allocator: std.mem.Allocator) void {
    global_allocator = allocator;
}

/// Check if ccusage binary is available in PATH
fn ccusageExists() bool {
    const result = std.process.which("ccusage");
    return result != null;
}

/// Check if npx is available
fn npxExists() bool {
    const result = std.process.which("npx");
    return result != null;
}

/// Fetch usage data from ccusage
pub fn fetch(granularity: Granularity) !CcusageResult {
    // Try ccusage binary first, then npx fallback
    const cmd_result = try findCcusageCommand();
    if (cmd_result == null) {
        return CcusageResult{
            .periods = &[_]CcusagePeriod{},
            .available = false,
            .error_message = "ccusage not found. Install: npm i -g ccusage (or use npx ccusage)",
        };
    }

    var cmd = cmd_result.?;
    const subcommand = switch (granularity) {
        .daily => "daily",
        .weekly => "weekly",
        .monthly => "monthly",
    };

    cmd.args(&.{ subcommand, "--json", "--since", "20250101" });

    const output = cmd.output() catch {
        return CcusageResult{
            .periods = &[_]CcusagePeriod{},
            .available = false,
            .error_message = "ccusage execution failed",
        };
    };

    if (!output.status.success()) {
        const stderr = std.mem.sliceTo(output.stderr, 0);
        return CcusageResult{
            .periods = &[_]CcusagePeriod{},
            .available = false,
            .error_message = std.fmt.allocPrint(global_allocator, "ccusage exited with error: {s}", .{stderr}) catch "ccusage error",
        };
    }

    const stdout = std.mem.sliceTo(output.stdout, 0);
    const periods = try parseJson(stdout, granularity);

    return CcusageResult{
        .periods = periods,
        .available = true,
    };
}

fn findCcusageCommand() !?std.process.Child.Builder {
    // Try ccusage binary
    if (ccusageExists()) {
        var cmd = std.process.Child.Builder.init(global_allocator, "ccusage");
        return cmd;
    }

    // Fallback to npx ccusage
    if (npxExists()) {
        var cmd = std.process.Child.Builder.init(global_allocator, "npx");
        cmd.addArg("ccusage");
        return cmd;
    }

    return null;
}

fn parseJson(json_text: []const u8, granularity: Granularity) ![]CcusagePeriod {
    // Simple JSON parsing without external dependencies
    // Expected format: { "daily|weekly|monthly": [{ ... }, ...] }
    
    const key = switch (granularity) {
        .daily => "daily",
        .weekly => "weekly",
        .monthly => "monthly",
    };

    // Find the array start for the granularity
    const array_start = std.mem.indexOf(u8, json_text, "\"" ++ key ++ "\"") orelse {
        return error.InvalidJson;
    };
    
    // Find opening bracket after the key
    const bracket_pos = std.mem.indexOf(u8, json_text[array_start..], "[") orelse {
        return error.InvalidJson;
    };
    const data_start = array_start + bracket_pos;

    // Find matching closing bracket
    var depth: usize = 0;
    var data_end: usize = data_start;
    var in_string = false;
    for (data_start..json_text.len) |i| {
        const c = json_text[i];
        if (c == '"' and (i == 0 or json_text[i-1] != '\\')) {
            in_string = !in_string;
        } else if (!in_string) {
            if (c == '[') depth += 1 else if (c == ']') {
                if (depth == 0) {
                    data_end = i;
                    break;
                }
                depth -= 1;
            }
        }
    }

    const array_text = json_text[data_start..data_end];
    
    // Parse each object in the array
    var periods = std.ArrayList(CcusagePeriod).init(global_allocator);
    errdefer periods.deinit();

    var pos: usize = 0;
    while (pos < array_text.len) {
        // Find next object start
        const obj_start = std.mem.indexOf(u8, array_text[pos..], "{") orelse break;
        pos += obj_start;

        // Find matching close brace
        depth = 0;
        var obj_end = pos;
        in_string = false;
        for (pos..array_text.len) |i| {
            const c = array_text[i];
            if (c == '"' and (i == 0 or array_text[i-1] != '\\')) {
                in_string = !in_string;
            } else if (!in_string) {
                if (c == '{') depth += 1 else if (c == '}') {
                    if (depth == 0) {
                        obj_end = i + 1;
                        break;
                    }
                    depth -= 1;
                }
            }
        }

        const obj_text = array_text[pos..obj_end];
        const period = try parsePeriodObject(obj_text, granularity);
        try periods.append(period);
        pos = obj_end;
    }

    return periods.toOwnedSlice();
}

fn parsePeriodObject(obj_text: []const u8, granularity: Granularity) !CcusagePeriod {
    var period = CcusagePeriod{
        .key = "",
        .metrics = CcusageMetrics{},
    };

    // Find the key field (date/week/month)
    const key_field = switch (granularity) {
        .daily => "date",
        .weekly => "week",
        .monthly => "month",
    };

    period.key = try parseStringField(obj_text, key_field);
    period.metrics = try parseMetrics(obj_text);

    return period;
}

fn parseStringField(json: []const u8, field: []const u8) ![]const u8 {
    const search = "\"" ++ field ++ "\":\"";
    const start = std.mem.indexOf(u8, json, search) orelse {
        return error.FieldNotFound;
    };
    const value_start = start + search.len;
    const value_end = std.mem.indexOf(u8, json[value_start..], "\"") orelse {
        return error.InvalidFormat;
    };
    return json[value_start..value_start+value_end];
}

fn parseMetrics(json: []const u8) !CcusageMetrics {
    var metrics = CcusageMetrics{};

    metrics.input_tokens = try parseIntField(json, "inputTokens");
    metrics.output_tokens = try parseIntField(json, "outputTokens");
    metrics.cache_creation_tokens = parseOptionalIntField(json, "cacheCreationTokens");
    metrics.cache_read_tokens = parseOptionalIntField(json, "cacheReadTokens");
    metrics.total_tokens = try parseIntField(json, "totalTokens");
    metrics.total_cost = try parseFloatField(json, "totalCost");

    return metrics;
}

fn parseIntField(json: []const u8, field: []const u8) !u64 {
    const search = "\"" ++ field ++ "\":";
    const start = std.mem.indexOf(u8, json, search) orelse {
        return error.FieldNotFound;
    };
    const value_start = start + search.len;
    
    // Find end of number
    var value_end = value_start;
    while (value_end < json.len) {
        const c = json[value_end];
        if (c < '0' or c > '9') break;
        value_end += 1;
    }
    
    const num_str = json[value_start..value_end];
    return try std.fmt.parseInt(u64, num_str, 10);
}

fn parseOptionalIntField(json: []const u8, field: []const u8) u64 {
    return parseIntField(json, field) catch return 0;
}

fn parseFloatField(json: []const u8, field: []const u8) !f64 {
    const search = "\"" ++ field ++ "\":";
    const start = std.mem.indexOf(u8, json, search) orelse {
        return error.FieldNotFound;
    };
    const value_start = start + search.len;
    
    // Find end of number (including decimal)
    var value_end = value_start;
    var has_dot = false;
    while (value_end < json.len) {
        const c = json[value_end];
        if (c == '.') {
            if (has_dot) break;
            has_dot = true;
            value_end += 1;
            continue;
        }
        if (c < '0' or c > '9') break;
        value_end += 1;
    }
    
    const num_str = json[value_start..value_end];
    return try std.fmt.parseFloat(f64, num_str);
}

/// Print ccusage data in human-readable format
pub fn printCcusage(periods: []CcusagePeriod, granularity: Granularity) void {
    if (periods.len == 0) {
        std.debug.print("No usage data available.\n", .{});
        return;
    }

    const granularity_str = switch (granularity) {
        .daily => "Daily",
        .weekly => "Weekly",
        .monthly => "Monthly",
    };

    std.debug.print("{s} Claude Code Usage\n", .{granularity_str});
    std.debug.print("========================\n\n", .{});

    var total_cost: f64 = 0;
    var total_tokens: u64 = 0;

    for (periods) |period| {
        std.debug.print("{s}: {s}\n", .{ granularity_str, period.key });
        std.debug.print("  Input tokens:       {}\n", .{period.metrics.input_tokens});
        std.debug.print("  Output tokens:      {}\n", .{period.metrics.output_tokens});
        std.debug.print("  Cache read tokens:  {}\n", .{period.metrics.cache_read_tokens});
        std.debug.print("  Total tokens:       {}\n", .{period.metrics.total_tokens});
        std.debug.print("  Cost:               ${:.2f}\n\n", .{period.metrics.total_cost});
        
        total_cost += period.metrics.total_cost;
        total_tokens += period.metrics.total_tokens;
    }

    std.debug.print("------------------------\n", .{});
    std.debug.print("Total: ${:.2f} ({d} tokens)\n", .{ total_cost, total_tokens });
}

test "ccusage parse daily" {
    init(std.testing.allocator);
    const json = `{"daily": [{"date": "2026-01-30", "inputTokens": 100, "outputTokens": 50, "cacheCreationTokens": 10, "cacheReadTokens": 20, "totalTokens": 180, "totalCost": 0.15}]}`;
    
    const periods = try parseJson(json, .daily);
    defer std.testing.allocator.free(periods);
    
    try std.testing.expect(periods.len == 1);
    try std.testing.expectEqualStrings("2026-01-30", periods[0].key);
    try std.testing.expect(periods[0].metrics.input_tokens == 100);
    try std.testing.expect(periods[0].metrics.total_cost == 0.15);
}

test "ccusage parse monthly" {
    init(std.testing.allocator);
    const json = `{"monthly": [{"month": "2026-01", "inputTokens": 1000, "outputTokens": 500, "totalTokens": 1800, "totalCost": 12.34}]}`;
    
    const periods = try parseJson(json, .monthly);
    defer std.testing.allocator.free(periods);
    
    try std.testing.expect(periods.len == 1);
    try std.testing.expectEqualStrings("2026-01", periods[0].key);
    try std.testing.expect(periods[0].metrics.total_cost == 12.34);
}
