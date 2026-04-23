//! Gain - Token Savings Analytics
//!
//! Displays token savings statistics from tracking data.
//! Inspired by RTK's rtk gain command.

const std = @import("std");

// Global Io instance set by cmd.zig dispatch.
pub var g_io: std.Io = undefined;

// Zig 0.16.0 compat: replacement for removed _getEnvVarOwned
fn _getEnvVarOwned(allocator: std.mem.Allocator, key: [*:0]const u8) error{EnvironmentVariableNotFound, OutOfMemory}![]u8 {
    const ptr = std.c.getenv(key) orelse return error.EnvironmentVariableNotFound;
    const slice = std.mem.sliceTo(ptr, 0);
    return allocator.dupe(u8, slice);
}
const proxy_helpers = @import("proxy_helpers");
const shared = @import("shared_analytics");

pub const GainOptions = struct {
    /// Show ASCII graph
    show_graph: bool = false,
    /// Show history
    show_history: bool = false,
    /// Show daily breakdown
    show_daily: bool = false,
    /// Days of history to show
    days: u32 = 90,
    /// Output format
    format: enum { text, json, csv } = .text,
    /// Force local data (skip proxy)
    local: bool = false,
};

pub const GainStats = struct {
    total_commands: usize,
    total_input_tokens: usize,
    total_output_tokens: usize,
    total_saved_tokens: usize,
    avg_savings_pct: f64,
    total_exec_time_ms: u64,
    top_commands: []const TopCommand,
};

pub const TopCommand = struct {
    cmd: []const u8,
    count: usize,
    total_saved: usize,
};

pub fn showGain(allocator: std.mem.Allocator, options: GainOptions) !void {
    // If not in local mode, try proxy unified endpoint first
    if (!options.local) {
        if (try queryUnified(allocator)) |unified| {
            defer freeUnifiedResponse(allocator, unified);
            try showUnified(unified, options);
            return;
        }
    }

    // Fallback: local history.db reading
    const stats = try getGainStats(allocator, options.days);
    defer {
        for (stats.top_commands) |c| allocator.free(c.cmd);
        allocator.free(stats.top_commands);
    }

    switch (options.format) {
        .text => try showGainText(stats, options),
        .json => try showGainJson(stats),
        .csv => try showGainCsv(stats),
    }
}

fn queryUnified(allocator: std.mem.Allocator) !?shared.UnifiedResponse {
    const response = proxy_helpers.queryProxyApi(allocator, "/analytics/unified", 2000) catch return null;
    if (response) |body| {
        defer allocator.free(body);
        return shared.parseUnifiedResponse(allocator, body) catch null;
    }
    return null;
}

fn freeUnifiedResponse(allocator: std.mem.Allocator, response: shared.UnifiedResponse) void {
    for (response.api_cost.by_provider) |p| allocator.free(p.provider);
    allocator.free(response.api_cost.by_provider);
    for (response.api_cost.by_model) |m| allocator.free(m.model);
    allocator.free(response.api_cost.by_model);
    for (response.cmd_savings.by_command) |c| allocator.free(c.command);
    allocator.free(response.cmd_savings.by_command);
}

fn showUnified(response: shared.UnifiedResponse, options: GainOptions) !void {
    const stats = GainStats{
        .total_commands = @intCast(response.cmd_savings.total_commands),
        .total_input_tokens = 0,
        .total_output_tokens = 0,
        .total_saved_tokens = @intCast(response.cmd_savings.total_saved_tokens),
        .avg_savings_pct = response.cmd_savings.avg_savings_pct,
        .total_exec_time_ms = 0,
        .top_commands = &.{},
    };

    switch (options.format) {
        .text => {
            std.debug.print("Token Savings Report (Unified)\n", .{});
            std.debug.print("==============================\n\n", .{});
            std.debug.print("Commands:    {d}\n", .{stats.total_commands});
            std.debug.print("Saved:       {d} tokens\n", .{stats.total_saved_tokens});
            std.debug.print("Avg Savings: {d:.1}%\n", .{stats.avg_savings_pct});
            std.debug.print("Net Cost:    ${d:.4}\n", .{response.net_cost});
            if (options.show_graph) {
                std.debug.print("\nSavings Graph:\n", .{});
                const bars = @as(u8, @intFromFloat(stats.avg_savings_pct / 5.0));
                std.debug.print("[", .{});
                for (0..20) |i| {
                    if (i < bars) std.debug.print("#", .{}) else std.debug.print("-", .{});
                }
                std.debug.print("] {d:.1}%\n", .{stats.avg_savings_pct});
            }
        },
        .json => {
            const json_out = try shared.serializeUnifiedResponse(std.heap.page_allocator, response);
            defer std.heap.page_allocator.free(json_out);
            std.debug.print("{s}\n", .{json_out});
        },
        .csv => try showGainCsv(stats),
    }
}

fn getGainStats(allocator: std.mem.Allocator, days: u32) !GainStats {
    // Get base stats from tracker
    const base_stats = getBaseStats(allocator);

    // Get top commands
    const top_commands = getTopCommands(allocator, days);

    return GainStats{
        .total_commands = base_stats.total_commands,
        .total_input_tokens = base_stats.total_input_tokens,
        .total_output_tokens = base_stats.total_output_tokens,
        .total_saved_tokens = base_stats.total_saved_tokens,
        .avg_savings_pct = base_stats.avg_savings_pct,
        .total_exec_time_ms = 0,
        .top_commands = top_commands,
    };
}

const BaseStats = struct {
    total_commands: usize,
    total_input_tokens: usize,
    total_output_tokens: usize,
    total_saved_tokens: usize,
    avg_savings_pct: f64,
};

fn getBaseStats(allocator: std.mem.Allocator) BaseStats {
    const home_dir = _getEnvVarOwned(allocator, "HOME") catch {
        return BaseStats{ .total_commands = 0, .total_input_tokens = 0, .total_output_tokens = 0, .total_saved_tokens = 0, .avg_savings_pct = 0.0 };
    };
    defer allocator.free(home_dir);

    const db_path = std.fmt.allocPrint(allocator, "{s}/.local/share/llmlite/history.db", .{home_dir}) catch {
        return BaseStats{ .total_commands = 0, .total_input_tokens = 0, .total_output_tokens = 0, .total_saved_tokens = 0, .avg_savings_pct = 0.0 };
    };
    defer allocator.free(db_path);

    const file = std.Io.Dir.openFileAbsolute(g_io, db_path, .{}) catch {
        return BaseStats{ .total_commands = 0, .total_input_tokens = 0, .total_output_tokens = 0, .total_saved_tokens = 0, .avg_savings_pct = 0.0 };
    };
    defer file.close(g_io);

    var buf: [8192]u8 = undefined;
    var file_buffer = std.array_list.Managed(u8).init(allocator);
    defer file_buffer.deinit();

    while (true) {
        const bytes_read = file.readStreaming(g_io, &.{buf[0..]}) catch break;
        if (bytes_read == 0) break;
        file_buffer.appendSlice(buf[0..bytes_read]) catch break;
    }

    var stats = BaseStats{ .total_commands = 0, .total_input_tokens = 0, .total_output_tokens = 0, .total_saved_tokens = 0, .avg_savings_pct = 0.0 };

    var line_iter = std.mem.splitScalar(u8, file_buffer.items, '\n');
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        var field_iter = std.mem.splitScalar(u8, line, '|');
        _ = field_iter.next(); // timestamp
        _ = field_iter.next(); // original_cmd
        _ = field_iter.next(); // rtk_cmd

        const input_toks = std.fmt.parseInt(usize, field_iter.next() orelse continue, 10) catch continue;
        const output_toks = std.fmt.parseInt(usize, field_iter.next() orelse continue, 10) catch continue;
        const saved_toks = std.fmt.parseInt(usize, field_iter.next() orelse continue, 10) catch continue;
        const savings_pct = std.fmt.parseFloat(f64, field_iter.next() orelse continue) catch continue;

        stats.total_commands += 1;
        stats.total_input_tokens += input_toks;
        stats.total_output_tokens += output_toks;
        stats.total_saved_tokens += saved_toks;
        stats.avg_savings_pct += savings_pct;
    }

    if (stats.total_commands > 0) {
        stats.avg_savings_pct /= @as(f64, @floatFromInt(stats.total_commands));
    }

    return stats;
}

fn getTopCommands(allocator: std.mem.Allocator, days: u32) []TopCommand {
    // Read history file and aggregate by command
    const home_dir = _getEnvVarOwned(allocator, "HOME") catch {
        return &[_]TopCommand{};
    };
    defer allocator.free(home_dir);

    const db_path = std.fmt.allocPrint(allocator, "{s}/.local/share/llmlite/history.db", .{home_dir}) catch {
        return &[_]TopCommand{};
    };
    defer allocator.free(db_path);

    const file = std.Io.Dir.openFileAbsolute(g_io, db_path, .{}) catch {
        return &[_]TopCommand{};
    };
    defer file.close(g_io);

    // Calculate cutoff timestamp
    const cutoff_time = @import("time_compat").timestamp(g_io) - (@as(i64, days) * 24 * 60 * 60);

    // Track command aggregates - use fixed-size arrays since we only need top 10
    const MAX_CMDS = 50;
    var cmd_names: [MAX_CMDS][]const u8 = undefined;
    var cmd_counts: [MAX_CMDS]usize = undefined;
    var cmd_saved: [MAX_CMDS]usize = undefined;
    var cmd_count: usize = 0;

    var buf: [8192]u8 = undefined;
    var file_buffer = std.array_list.Managed(u8).init(allocator);
    defer file_buffer.deinit();

    while (true) {
        const bytes_read = file.readStreaming(g_io, &.{buf[0..]}) catch break;
        if (bytes_read == 0) break;
        file_buffer.appendSlice(buf[0..bytes_read]) catch break;
    }

    var line_iter = std.mem.splitScalar(u8, file_buffer.items, '\n');
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        var field_iter = std.mem.splitScalar(u8, line, '|');
        const timestamp_str = field_iter.next() orelse continue;
        const timestamp = std.fmt.parseInt(i64, timestamp_str, 10) catch continue;

        // Filter by days
        if (timestamp < cutoff_time) continue;

        _ = field_iter.next(); // original_cmd
        const rtk_cmd = field_iter.next() orelse continue;

        _ = field_iter.next(); // input_toks
        _ = field_iter.next(); // output_toks
        const saved_toks = std.fmt.parseInt(usize, field_iter.next() orelse continue, 10) catch continue;

        // Normalize command
        const base_cmd = normalizeCommand(rtk_cmd);

        // Find existing or add new
        var found = false;
        for (0..cmd_count) |i| {
            if (std.mem.eql(u8, cmd_names[i], base_cmd)) {
                cmd_counts[i] += 1;
                cmd_saved[i] += saved_toks;
                found = true;
                break;
            }
        }

        if (!found and cmd_count < MAX_CMDS) {
            const key = allocator.dupe(u8, base_cmd) catch continue;
            cmd_names[cmd_count] = key;
            cmd_counts[cmd_count] = 1;
            cmd_saved[cmd_count] = saved_toks;
            cmd_count += 1;
        }
    }

    // Sort by saved tokens descending (simple bubble sort for small N)
    for (0..cmd_count) |i| {
        for (i + 1..cmd_count) |j| {
            if (cmd_saved[j] > cmd_saved[i]) {
                // Swap saved
                const temp_saved = cmd_saved[i];
                cmd_saved[i] = cmd_saved[j];
                cmd_saved[j] = temp_saved;
                // Swap count
                const temp_count = cmd_counts[i];
                cmd_counts[i] = cmd_counts[j];
                cmd_counts[j] = temp_count;
                // Swap names
                const temp_name = cmd_names[i];
                cmd_names[i] = cmd_names[j];
                cmd_names[j] = temp_name;
            }
        }
    }

    // Return top 10
    const max_results: usize = 10;
    const result_count = @min(max_results, cmd_count);
    if (result_count == 0) return &[_]TopCommand{};

    const result = allocator.alloc(TopCommand, result_count) catch {
        return &[_]TopCommand{};
    };

    for (0..result_count) |i| {
        result[i] = .{
            .cmd = cmd_names[i],
            .count = cmd_counts[i],
            .total_saved = cmd_saved[i],
        };
    }

    return result;
}

fn normalizeCommand(cmd: []const u8) []const u8 {
    // Normalize command to base form
    // e.g., "llmlite-cmd git status" -> "git status"
    // e.g., "llmlite-cmd cargo test" -> "cargo test"
    if (std.mem.startsWith(u8, cmd, "llmlite-cmd ")) {
        return cmd["llmlite-cmd ".len..];
    }
    if (std.mem.startsWith(u8, cmd, "rtk ")) {
        return cmd["rtk ".len..];
    }
    return cmd;
}

fn showGainText(stats: GainStats, options: GainOptions) !void {
    var output = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer output.deinit();

    try output.print("Token Savings Report ({d} days)\n", .{options.days});
    try output.print("========================================\n\n", .{});

    try output.print("Commands executed:  {}\n", .{stats.total_commands});
    try output.print("Average savings:    {:.1}%\n", .{stats.avg_savings_pct});
    try output.print("Total tokens saved: {}\n", .{stats.total_saved_tokens});
    try output.print("Input tokens:       {}\n", .{stats.total_input_tokens});
    try output.print("Output tokens:      {}\n", .{stats.total_output_tokens});

    if (options.show_graph) {
        try output.print("\nSavings Graph (last 30 days):\n", .{});
        const bars = @as(u8, @intFromFloat(stats.avg_savings_pct / 5.0)); // 5% per bar
        try output.print("[", .{});
        for (0..20) |i| {
            if (i < bars) {
                try output.print("#", .{});
            } else {
                try output.print("-", .{});
            }
        }
        try output.print("] {:.1}%\n", .{stats.avg_savings_pct});
    }

    if (stats.top_commands.len > 0) {
        try output.print("\nTop commands:\n", .{});
        for (stats.top_commands[0..@min(5, stats.top_commands.len)]) |cmd| {
            try output.print("  - {s}  ({} uses, {} tokens saved)\n", .{ cmd.cmd, cmd.count, cmd.total_saved });
        }
    }

    if (options.show_history) {
        try showHistory(options.days);
    }

    if (options.show_daily) {
        try showDaily(options.days);
    }

    std.debug.print("{s}", .{output.items});
}

fn showHistory(days: u32) !void {
    const home_dir = _getEnvVarOwned(std.heap.page_allocator, "HOME") catch return;
    defer std.heap.page_allocator.free(home_dir);

    const db_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/.local/share/llmlite/history.db", .{home_dir}) catch return;
    defer std.heap.page_allocator.free(db_path);

    const file = std.Io.Dir.openFileAbsolute(g_io, db_path, .{}) catch return;
    defer file.close(g_io);

    const cutoff_time = @import("time_compat").timestamp(g_io) - (@as(i64, days) * 24 * 60 * 60);

    var buf: [8192]u8 = undefined;
    var file_buffer = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer file_buffer.deinit();

    while (true) {
        const bytes_read = file.readStreaming(g_io, &.{buf[0..]}) catch break;
        if (bytes_read == 0) break;
        file_buffer.appendSlice(buf[0..bytes_read]) catch break;
    }

    std.debug.print("\nRecent History (last {d} commands):\n", .{days});
    std.debug.print("----------------------------------------\n", .{});

    var count: usize = 0;
    var line_iter = std.mem.splitScalar(u8, file_buffer.items, '\n');
    while (line_iter.next()) |line| : (count += 1) {
        if (line.len == 0 or count > 20) continue;

        var field_iter = std.mem.splitScalar(u8, line, '|');
        const timestamp_str = field_iter.next() orelse continue;
        const timestamp = std.fmt.parseInt(i64, timestamp_str, 10) catch continue;

        if (timestamp < cutoff_time) continue;

        const original_cmd = field_iter.next() orelse continue;
        const rtk_cmd = field_iter.next() orelse continue;
        const saved_toks = field_iter.next() orelse continue;

        std.debug.print("  {s} -> {s}  ({s} saved)\n", .{ original_cmd, rtk_cmd, saved_toks });
    }
}

fn showDaily(days: u32) !void {
    // Show daily breakdown - simplified since timestamp-to-date is complex in Zig
    const home_dir = _getEnvVarOwned(std.heap.page_allocator, "HOME") catch return;
    defer std.heap.page_allocator.free(home_dir);

    const db_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/.local/share/llmlite/history.db", .{home_dir}) catch return;
    defer std.heap.page_allocator.free(db_path);

    const file = std.Io.Dir.openFileAbsolute(g_io, db_path, .{}) catch return;
    defer file.close(g_io);

    const cutoff_time = @import("time_compat").timestamp(g_io) - (@as(i64, days) * 24 * 60 * 60);

    var buf: [8192]u8 = undefined;
    var file_buffer = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer file_buffer.deinit();

    while (true) {
        const bytes_read = file.readStreaming(g_io, &.{buf[0..]}) catch break;
        if (bytes_read == 0) break;
        file_buffer.appendSlice(buf[0..bytes_read]) catch break;
    }

    std.debug.print("\nDaily Breakdown (last {d} days):\n", .{days});
    std.debug.print("----------------------------------------\n", .{});

    var total_saved: usize = 0;
    var day_count: usize = 0;
    var line_iter = std.mem.splitScalar(u8, file_buffer.items, '\n');
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        var field_iter = std.mem.splitScalar(u8, line, '|');
        const timestamp_str = field_iter.next() orelse continue;
        const timestamp = std.fmt.parseInt(i64, timestamp_str, 10) catch continue;

        if (timestamp < cutoff_time) continue;

        _ = field_iter.next(); // original_cmd
        _ = field_iter.next(); // rtk_cmd
        _ = field_iter.next(); // input_toks
        _ = field_iter.next(); // output_toks
        const saved_toks = std.fmt.parseInt(usize, field_iter.next() orelse continue, 10) catch continue;

        total_saved += saved_toks;
        day_count += 1;
    }

    if (day_count > 0) {
        const avg_per_day = total_saved / @as(usize, @intCast(@min(days, day_count)));
        std.debug.print("  Total saved: {d} tokens over {d} days\n", .{ total_saved, day_count });
        std.debug.print("  Average per day: {d} tokens\n", .{avg_per_day});
    } else {
        std.debug.print("  No data available\n", .{});
    }
}

fn showGainJson(stats: GainStats) !void {
    var output = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer output.deinit();

    try output.print("{{\n", .{});
    try output.print("  \"total_commands\": {},\n", .{stats.total_commands});
    try output.print("  \"avg_savings_pct\": {:.1},\n", .{stats.avg_savings_pct});
    try output.print("  \"total_saved_tokens\": {},\n", .{stats.total_saved_tokens});
    try output.print("  \"input_tokens\": {},\n", .{stats.total_input_tokens});
    try output.print("  \"output_tokens\": {}\n", .{stats.total_output_tokens});
    try output.print("}}\n", .{});

    std.debug.print("{s}", .{output.items});
}

fn showGainCsv(stats: GainStats) !void {
    var output = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer output.deinit();

    // CSV header
    try output.print("metric,value\n", .{});
    try output.print("total_commands,{}\n", .{stats.total_commands});
    try output.print("avg_savings_pct,{:.1}\n", .{stats.avg_savings_pct});
    try output.print("total_saved_tokens,{}\n", .{stats.total_saved_tokens});
    try output.print("input_tokens,{}\n", .{stats.total_input_tokens});
    try output.print("output_tokens,{}\n", .{stats.total_output_tokens});

    // Top commands
    if (stats.top_commands.len > 0) {
        try output.print("\ncommand,count,tokens_saved\n", .{});
        for (stats.top_commands) |cmd| {
            try output.print("{s},{},{}\n", .{ cmd.cmd, cmd.count, cmd.total_saved });
        }
    }

    std.debug.print("{s}", .{output.items});
}

// ============================================================================
// Unit Tests
// ============================================================================

test "normalizeCommand strips llmlite-cmd and rtk prefixes" {
    try std.testing.expectEqualStrings("git status", normalizeCommand("llmlite-cmd git status"));
    try std.testing.expectEqualStrings("cargo test", normalizeCommand("llmlite-cmd cargo test"));
    try std.testing.expectEqualStrings("npm run build", normalizeCommand("rtk npm run build"));
    try std.testing.expectEqualStrings("docker ps", normalizeCommand("docker ps"));
    try std.testing.expectEqualStrings("ls -la", normalizeCommand("ls -la"));
}

test "GainOptions defaults" {
    const opts = GainOptions{};
    try std.testing.expect(!opts.show_graph);
    try std.testing.expect(!opts.show_history);
    try std.testing.expect(!opts.show_daily);
    try std.testing.expectEqual(@as(u32, 90), opts.days);
    try std.testing.expectEqual(@as(@TypeOf(opts.format), .text), opts.format);
    try std.testing.expect(!opts.local);
}

test "showGain with local mode and no history file" {
    // When local=true and no history.db exists, showGain should not error
    // (it falls back to empty stats and prints them)
    const allocator = std.testing.allocator;
    const opts = GainOptions{ .local = true };
    try showGain(allocator, opts);
}

test "showGain with local mode json format" {
    const allocator = std.testing.allocator;
    const opts = GainOptions{ .local = true, .format = .json };
    try showGain(allocator, opts);
}

test "showGain with local mode csv format" {
    const allocator = std.testing.allocator;
    const opts = GainOptions{ .local = true, .format = .csv };
    try showGain(allocator, opts);
}
