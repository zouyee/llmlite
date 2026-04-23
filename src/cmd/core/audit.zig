//! Hook Audit - Analyze llmlite hook usage and savings
//!
//! Scans history database to show:
//! - Which commands were rewritten via hooks
//! - Total savings from hook usage
//! - Per-command breakdown
//! - Time-based analysis

const std = @import("std");
const time_compat = @import("time_compat");

// Zig 0.16.0 compat: replacement for removed _getEnvVarOwned
fn _getEnvVarOwned(allocator: std.mem.Allocator, key: [*:0]const u8) error{EnvironmentVariableNotFound, OutOfMemory}![]u8 {
    const ptr = std.c.getenv(key) orelse return error.EnvironmentVariableNotFound;
    const slice = std.mem.sliceTo(ptr, 0);
    return allocator.dupe(u8, slice);
}
const tracking = @import("cmd_core_tracking");

pub const AuditOptions = struct {
    since_days: u32 = 30,
    format: AuditFormat = .text,
    verbose: bool = false,
};

pub const AuditFormat = enum {
    text,
    json,
};

pub const AuditStats = struct {
    total_commands: u32,
    rewritten_commands: u32,
    direct_commands: u32,
    total_input_tokens: usize,
    total_output_tokens: usize,
    total_saved_tokens: usize,
    avg_savings_pct: f64,
    top_rewritten: []const RewrittenCommand,
};

pub const RewrittenCommand = struct {
    original: []const u8,
    count: u32,
    saved_tokens: usize,
};

pub fn showAudit(io: std.Io, allocator: std.mem.Allocator, options: AuditOptions) !void {
    const db_path = try getHistoryPath(allocator);
    defer allocator.free(db_path);

    const file = std.Io.Dir.openFileAbsolute(io, db_path, .{}) catch {
        std.debug.print("No history found. Run 'llmlite-cmd init -g' first.\n", .{});
        return;
    };
    defer file.close(io);

    var buf: [8192]u8 = undefined;
    var file_buffer = std.array_list.Managed(u8).init(allocator);
    defer file_buffer.deinit();

    while (true) {
        const bytes_read = file.readStreaming(io, &.{buf[0..]}) catch break;
        if (bytes_read == 0) break;
        file_buffer.appendSlice(buf[0..bytes_read]) catch break;
    }

    // Parse history and compute stats
    var total_commands: u32 = 0;
    var rewritten_commands: u32 = 0;
    var direct_commands: u32 = 0;
    var total_input_tokens: usize = 0;
    var total_output_tokens: usize = 0;
    var total_saved_tokens: usize = 0;
    var rewritten_counts = std.StringHashMap(struct { count: u32, saved: usize }).init(allocator);
    defer rewritten_counts.deinit();

    const cutoff = @as(i64, @intCast(time_compat.timestamp(io))) - (@as(i64, @intCast(options.since_days)) * 86400);

    var line_iter = std.mem.splitScalar(u8, file_buffer.items, '\n');
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        var field_iter = std.mem.splitScalar(u8, line, '|');
        const timestamp_str = field_iter.next() orelse continue;
        const timestamp = std.fmt.parseInt(i64, timestamp_str, 10) catch continue;

        // Filter by cutoff
        if (timestamp < cutoff) continue;

        const original = field_iter.next() orelse continue;
        const rtk_cmd = field_iter.next() orelse continue;
        const input_tokens_str = field_iter.next() orelse "0";
        const output_tokens_str = field_iter.next() orelse "0";
        const saved_str = field_iter.next() orelse "0";

        total_commands += 1;
        total_input_tokens += std.fmt.parseInt(usize, input_tokens_str, 10) catch 0;
        total_output_tokens += std.fmt.parseInt(usize, output_tokens_str, 10) catch 0;
        const saved = std.fmt.parseInt(usize, saved_str, 10) catch 0;
        total_saved_tokens += saved;

        // Check if this was a rewrite (original != rtk_cmd)
        if (!std.mem.eql(u8, original, rtk_cmd)) {
            rewritten_commands += 1;

            if (rewritten_counts.getPtr(original)) |entry| {
                entry.count += 1;
                entry.saved += saved;
            } else {
                rewritten_counts.put(original, .{ .count = 1, .saved = saved }) catch continue;
            }
        } else {
            direct_commands += 1;
        }
    }

    // Count unique rewritten commands
    var unique_count: u32 = 0;
    var it = rewritten_counts.iterator();
    while (it.next()) |_| {
        unique_count += 1;
    }

    const stats = AuditStats{
        .total_commands = total_commands,
        .rewritten_commands = rewritten_commands,
        .direct_commands = direct_commands,
        .total_input_tokens = total_input_tokens,
        .total_output_tokens = total_output_tokens,
        .total_saved_tokens = total_saved_tokens,
        .avg_savings_pct = if (total_commands > 0) @as(f64, @floatFromInt(total_saved_tokens)) / @as(f64, @floatFromInt(total_input_tokens + total_output_tokens)) * 100.0 else 0,
        .top_rewritten = &.{},
    };

    switch (options.format) {
        .text => try showAuditText(stats, options.verbose, rewritten_counts),
        .json => try showAuditJson(stats),
    }
}

fn showAuditText(stats: AuditStats, verbose: bool, rewritten_counts: anytype) !void {
    _ = verbose;
    _ = rewritten_counts;
    std.debug.print("\n=== llmlite Hook Audit ===\n\n", .{});
    std.debug.print("Total commands: {d}\n", .{stats.total_commands});
    std.debug.print("  Rewritten via hook: {d} ({d:.1}%)\n", .{ stats.rewritten_commands, if (stats.total_commands > 0) @as(f64, @floatFromInt(stats.rewritten_commands)) / @as(f64, @floatFromInt(stats.total_commands)) * 100.0 else 0 });
    std.debug.print("  Direct execution: {d}\n", .{stats.direct_commands});

    std.debug.print("\nToken Statistics:\n", .{});
    std.debug.print("  Input tokens: {d}\n", .{stats.total_input_tokens});
    std.debug.print("  Output tokens: {d}\n", .{stats.total_output_tokens});
    std.debug.print("  Saved tokens: {d} ({d:.1}%)\n", .{ stats.total_saved_tokens, stats.avg_savings_pct });

    std.debug.print("\nRun 'llmlite-cmd gain' for full analytics.\n", .{});
}

fn showAuditJson(stats: AuditStats) !void {
    std.debug.print("{{\n", .{});
    std.debug.print("  \"total_commands\": {d},\n", .{stats.total_commands});
    std.debug.print("  \"rewritten_commands\": {d},\n", .{stats.rewritten_commands});
    std.debug.print("  \"direct_commands\": {d},\n", .{stats.direct_commands});
    std.debug.print("  \"total_input_tokens\": {d},\n", .{stats.total_input_tokens});
    std.debug.print("  \"total_output_tokens\": {d},\n", .{stats.total_output_tokens});
    std.debug.print("  \"total_saved_tokens\": {d},\n", .{stats.total_saved_tokens});
    std.debug.print("  \"avg_savings_pct\": {d:.2}\n", .{stats.avg_savings_pct});
    std.debug.print("}}\n", .{});
}

fn getHistoryPath(allocator: std.mem.Allocator) ![]u8 {
    const home = _getEnvVarOwned(allocator, "HOME") catch return error.HomeNotFound;
    defer allocator.free(home);
    return std.fmt.allocPrint(allocator, "{s}/.local/share/llmlite/history.db", .{home});
}
