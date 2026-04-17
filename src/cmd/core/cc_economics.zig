//! Claude Code Economics - Spending vs Savings Analysis
//!
//! Combines Claude API usage with llmlite token savings to show:
//! - Total Claude API spending
//! - llmlite token savings
//! - Net cost reduction
//!
//! Token weighting (mirrors RTK's cc_economics):
//!   - output tokens = 5x input weight
//!   - cache creation = 1.25x input weight
//!   - cache read = 0.1x input weight

const std = @import("std");
const proxy_helpers = @import("proxy_helpers");

/// Token weighting constants based on Claude API pricing
const WEIGHT_OUTPUT: f64 = 5.0;
const WEIGHT_CACHE_CREATE: f64 = 1.25;
const WEIGHT_CACHE_READ: f64 = 0.1;

pub const EconomicsOptions = struct {
    period: EconomicsPeriod = .daily,
    format: EconomicsFormat = .text,
};

pub const EconomicsPeriod = enum {
    daily,
    weekly,
    monthly,
};

pub const EconomicsFormat = enum {
    text,
    json,
    csv,
};

pub const PeriodEconomics = struct {
    label: []const u8,
    // Claude API metrics (from ccusage if available)
    cc_cost: ?f64,
    cc_total_tokens: ?u64,
    cc_input_tokens: ?u64,
    cc_output_tokens: ?u64,
    cc_cache_create_tokens: ?u64,
    cc_cache_read_tokens: ?u64,
    // llmlite metrics
    rtk_commands: u32,
    rtk_saved_tokens: usize,
    rtk_savings_pct: f64,
    // Derived metrics
    weighted_input_cpt: ?f64,
    savings_weighted: ?f64,
    blended_cpt: ?f64,
    active_cpt: ?f64,
};

pub fn showEconomics(allocator: std.mem.Allocator, options: EconomicsOptions) !void {
    // Try proxy API first for unified analytics
    if (proxy_helpers.queryProxyApi(allocator, "/analytics/economics", 2000) catch null) |proxy_response| {
        defer allocator.free(proxy_response);
        // Display proxy response directly (pre-formatted by proxy)
        std.debug.print("{s}\n", .{proxy_response});
        return;
    }

    // Fallback: local data sources
    // Try to read ccusage data (Claude Code usage tracking)
    const ccusage = readCcusageData(allocator) catch null;

    // Read llmlite tracking data
    const llmlite_stats = try readLlmliteStats(allocator);
    defer {
        for (llmlite_stats.top_commands) |cmd| allocator.free(cmd.cmd);
        allocator.free(llmlite_stats.top_commands);
    }

    // Calculate period economics
    const period_label = switch (options.period) {
        .daily => "Today",
        .weekly => "This Week",
        .monthly => "This Month",
    };

    var cc_cost: f64 = 0;
    var cc_input: u64 = 0;
    var cc_output: u64 = 0;
    var cc_cache_create: u64 = 0;
    var cc_cache_read: u64 = 0;
    var cc_total: u64 = 0;

    if (ccusage) |data| {
        cc_cost = data.cost;
        cc_input = data.input_tokens;
        cc_output = data.output_tokens;
        cc_cache_create = data.cache_create_tokens;
        cc_cache_read = data.cache_read_tokens;
        cc_total = data.total_tokens;
    }

    // Calculate weighted input CPT (output = 5x, cache_create = 1.25x, cache_read = 0.1x)
    const weighted_units = @as(f64, @floatFromInt(cc_input)) +
        @as(f64, @floatFromInt(cc_output)) * WEIGHT_OUTPUT +
        @as(f64, @floatFromInt(cc_cache_create)) * WEIGHT_CACHE_CREATE +
        @as(f64, @floatFromInt(cc_cache_read)) * WEIGHT_CACHE_READ;

    const weighted_input_cpt = if (weighted_units > 0) cc_cost / weighted_units else null;
    const blended_cpt = if (cc_total > 0) cc_cost / @as(f64, @floatFromInt(cc_total)) else null;
    const active_cpt = if (cc_input + cc_output > 0)
        cc_cost / @as(f64, @floatFromInt(cc_input + cc_output))
    else
        null;

    const savings = @as(f64, @floatFromInt(llmlite_stats.saved_tokens));
    const savings_weighted = if (weighted_input_cpt) |cpt| savings * cpt else null;

    const economics = PeriodEconomics{
        .label = period_label,
        .cc_cost = if (ccusage != null) cc_cost else null,
        .cc_total_tokens = if (ccusage != null) cc_total else null,
        .cc_input_tokens = if (ccusage != null) cc_input else null,
        .cc_output_tokens = if (ccusage != null) cc_output else null,
        .cc_cache_create_tokens = if (ccusage != null) cc_cache_create else null,
        .cc_cache_read_tokens = if (ccusage != null) cc_cache_read else null,
        .rtk_commands = llmlite_stats.commands,
        .rtk_saved_tokens = llmlite_stats.saved_tokens,
        .rtk_savings_pct = llmlite_stats.savings_pct,
        .weighted_input_cpt = weighted_input_cpt,
        .savings_weighted = savings_weighted,
        .blended_cpt = blended_cpt,
        .active_cpt = active_cpt,
    };

    switch (options.format) {
        .text => try showEconomicsText(economics),
        .json => try showEconomicsJson(economics),
        .csv => try showEconomicsCsv(economics),
    }
}

const CcusageData = struct {
    cost: f64,
    total_tokens: u64,
    input_tokens: u64,
    output_tokens: u64,
    cache_create_tokens: u64,
    cache_read_tokens: u64,
};

fn readCcusageData(allocator: std.mem.Allocator) !CcusageData {
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    const path = try std.fs.path.join(allocator, &.{ home, ".claude/ccusage/summary.json" });
    defer allocator.free(path);

    const file = std.fs.openFileAbsolute(path, .{ .mode = .read_only }) catch return error.FileNotFound;
    defer file.close();

    var content: [4096]u8 = undefined;
    _ = file.readAll(&content) catch return error.ReadError;

    // Simple JSON parsing - just extract what we need
    // In production, use a proper JSON parser
    return error.ParseError;
}

const TopCommand = struct {
    cmd: []const u8,
    count: usize,
    total_saved: usize,
};

const LlmliteStats = struct {
    commands: u32,
    saved_tokens: usize,
    savings_pct: f64,
    top_commands: []TopCommand,
};

fn readLlmliteStats(allocator: std.mem.Allocator) !LlmliteStats {
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    const path = try std.fs.path.join(allocator, &.{ home, ".local/share/llmlite/history.db" });
    defer allocator.free(path);

    const file = std.fs.openFileAbsolute(path, .{ .mode = .read_only }) catch {
        return LlmliteStats{
            .commands = 0,
            .saved_tokens = 0,
            .savings_pct = 0,
            .top_commands = &.{},
        };
    };
    defer file.close();

    var buf: [8192]u8 = undefined;
    var file_buffer = std.array_list.Managed(u8).init(allocator);
    defer file_buffer.deinit();

    while (true) {
        const bytes_read = file.read(&buf) catch break;
        if (bytes_read == 0) break;
        file_buffer.appendSlice(buf[0..bytes_read]) catch break;
    }

    var commands: u32 = 0;
    var saved_tokens: usize = 0;
    var total_input: usize = 0;

    var cmd_counts = std.StringHashMap(struct { count: usize, saved: usize }).init(allocator);
    defer cmd_counts.deinit();

    var line_iter = std.mem.splitScalar(u8, file_buffer.items, '\n');
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        var field_iter = std.mem.splitScalar(u8, line, '|');
        _ = field_iter.next(); // timestamp
        const original = field_iter.next() orelse continue;
        _ = field_iter.next(); // rtk_cmd
        const input_str = field_iter.next() orelse "0";
        const output_str = field_iter.next() orelse "0";
        const saved_str = field_iter.next() orelse "0";

        commands += 1;
        const input_t = std.fmt.parseInt(usize, input_str, 10) catch 0;
        const output_t = std.fmt.parseInt(usize, output_str, 10) catch 0;
        _ = output_t; // suppress unused warning
        const saved_t = std.fmt.parseInt(usize, saved_str, 10) catch 0;

        total_input += input_t;
        saved_tokens += saved_t;

        // Aggregate by command
        if (cmd_counts.getPtr(original)) |entry| {
            entry.count += 1;
            entry.saved += saved_t;
        } else {
            try cmd_counts.put(try allocator.dupe(u8, original), .{ .count = 1, .saved = saved_t });
        }
    }

    const savings_pct = if (total_input > 0)
        @as(f64, @floatFromInt(saved_tokens)) / @as(f64, @floatFromInt(total_input)) * 100.0
    else
        0;

    // Build top commands
    var top_list = try std.ArrayList(TopCommand).initCapacity(allocator, 0);
    var it = cmd_counts.iterator();
    while (it.next()) |entry| {
        try top_list.append(allocator, .{
            .cmd = entry.key_ptr.*,
            .count = entry.value_ptr.count,
            .total_saved = entry.value_ptr.saved,
        });
    }

    // Sort by saved descending, keep top 5
    for (0..top_list.items.len) |i| {
        for (i + 1..top_list.items.len) |j| {
            if (top_list.items[j].total_saved > top_list.items[i].total_saved) {
                const tmp = top_list.items[i];
                top_list.items[i] = top_list.items[j];
                top_list.items[j] = tmp;
            }
        }
    }

    const top_count = @min(5, top_list.items.len);
    const top_commands = try allocator.alloc(TopCommand, top_count);
    @memcpy(top_commands, top_list.items[0..top_count]);

    return LlmliteStats{
        .commands = commands,
        .saved_tokens = saved_tokens,
        .savings_pct = savings_pct,
        .top_commands = top_commands,
    };
}

fn showEconomicsText(econ: PeriodEconomics) !void {
    std.debug.print("\n=== llmlite Economics ({s}) ===\n\n", .{econ.label});

    // Claude API costs
    if (econ.cc_cost) |cost| {
        std.debug.print("Claude API Spending:\n", .{});
        std.debug.print("  Total cost: ${d:.2}\n", .{cost});
        if (econ.cc_total_tokens) |t| std.debug.print("  Total tokens: {d}\n", .{t});
        if (econ.cc_input_tokens) |t| std.debug.print("  Input tokens: {d}\n", .{t});
        if (econ.cc_output_tokens) |t| std.debug.print("  Output tokens: {d}\n", .{t});
        if (econ.cc_cache_create_tokens) |t| std.debug.print("  Cache created: {d}\n", .{t});
        if (econ.cc_cache_read_tokens) |t| std.debug.print("  Cache read: {d}\n", .{t});
        std.debug.print("\n", .{});

        // CPT metrics
        std.debug.print("Claude API CPT (Cost Per Token):\n", .{});
        if (econ.weighted_input_cpt) |cpt| {
            std.debug.print("  Weighted (input+output*5+caches): ${d:.6}/token\n", .{cpt});
        }
        if (econ.blended_cpt) |cpt| {
            std.debug.print("  Blended (all tokens): ${d:.6}/token\n", .{cpt});
        }
        if (econ.active_cpt) |cpt| {
            std.debug.print("  Active (input+output): ${d:.6}/token\n", .{cpt});
        }
    } else {
        std.debug.print("Claude API Spending: N/A (ccusage not found)\n", .{});
        std.debug.print("  Install ccusage: npm install -g ccusage\n", .{});
    }

    // llmlite savings
    std.debug.print("\nllmlite Token Savings:\n", .{});
    std.debug.print("  Commands tracked: {d}\n", .{econ.rtk_commands});
    std.debug.print("  Tokens saved: {d} ({d:.1}%)\n", .{ econ.rtk_saved_tokens, econ.rtk_savings_pct });

    // Net value
    if (econ.savings_weighted) |savings| {
        std.debug.print("\nEstimated Value:\n", .{});
        std.debug.print("  Weighted savings: ${d:.4}\n", .{savings});
    }

    std.debug.print("\nRun 'llmlite-cmd gain' for detailed analytics.\n", .{});
}

fn showEconomicsJson(econ: PeriodEconomics) !void {
    std.debug.print("{{\n", .{});
    std.debug.print("  \"period\": \"{s}\",\n", .{econ.label});

    if (econ.cc_cost) |cost| {
        std.debug.print("  \"cc_cost\": {d:.2},\n", .{cost});
        if (econ.cc_total_tokens) |t| std.debug.print("  \"cc_total_tokens\": {d},\n", .{t});
        if (econ.cc_input_tokens) |t| std.debug.print("  \"cc_input_tokens\": {d},\n", .{t});
        if (econ.cc_output_tokens) |t| std.debug.print("  \"cc_output_tokens\": {d},\n", .{t});
        if (econ.cc_cache_create_tokens) |t| std.debug.print("  \"cc_cache_create_tokens\": {d},\n", .{t});
        if (econ.cc_cache_read_tokens) |t| std.debug.print("  \"cc_cache_read_tokens\": {d},\n", .{t});
    } else {
        std.debug.print("  \"cc_cost\": null,\n", .{});
    }

    std.debug.print("  \"rtk_commands\": {d},\n", .{econ.rtk_commands});
    std.debug.print("  \"rtk_saved_tokens\": {d},\n", .{econ.rtk_saved_tokens});
    std.debug.print("  \"rtk_savings_pct\": {d:.2},\n", .{econ.rtk_savings_pct});

    if (econ.savings_weighted) |savings| {
        std.debug.print("  \"savings_dollars\": {d:.4}\n", .{savings});
    } else {
        std.debug.print("  \"savings_dollars\": null\n", .{});
    }

    std.debug.print("}}\n", .{});
}

fn showEconomicsCsv(econ: PeriodEconomics) !void {
    std.debug.print("metric,value\n", .{});
    std.debug.print("period,{s}\n", .{econ.label});

    if (econ.cc_cost) |cost| {
        std.debug.print("cc_cost,{d:.2}\n", .{cost});
    }
    if (econ.cc_total_tokens) |t| std.debug.print("cc_total_tokens,{d}\n", .{t});
    if (econ.cc_input_tokens) |t| std.debug.print("cc_input_tokens,{d}\n", .{t});
    if (econ.cc_output_tokens) |t| std.debug.print("cc_output_tokens,{d}\n", .{t});
    if (econ.cc_cache_create_tokens) |t| std.debug.print("cc_cache_create_tokens,{d}\n", .{t});
    if (econ.cc_cache_read_tokens) |t| std.debug.print("cc_cache_read_tokens,{d}\n", .{t});

    std.debug.print("rtk_commands,{d}\n", .{econ.rtk_commands});
    std.debug.print("rtk_saved_tokens,{d}\n", .{econ.rtk_saved_tokens});
    std.debug.print("rtk_savings_pct,{d:.2}\n", .{econ.rtk_savings_pct});

    if (econ.savings_weighted) |savings| {
        std.debug.print("savings_dollars,{d:.4}\n", .{savings});
    }
}
