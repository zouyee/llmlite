//! RuboCop - Ruby Linter
//!
//! Filters rubocop JSON output for compact representation.
//! Inspired by RTK's rubocop_cmd.rs.
//!
//! ## Token Savings
//!
//! rubocop: ~500 lines → ~50 lines (90% reduction)

const std = @import("std");
const json = @import("cmd_core_json");

/// Filter rubocop output
pub fn filterRubocop(output: []const u8, args: []const []const u8) []const u8 {
    // Check for JSON format
    var has_json_format = false;
    for (args) |arg| {
        if (std.mem.containsAtLeast(u8, arg, 1, "--format")) has_json_format = true;
    }

    if (has_json_format or std.mem.containsAtLeast(u8, output, 1, "[{\"type\":")) {
        return filterRubocopJson(output);
    }

    return filterRubocopText(output);
}

/// Filter rubocop JSON output
fn filterRubocopJson(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var files = std.StringArrayHashMap(usize).init(std.heap.page_allocator);
    defer files.deinit();

    // Parse JSON array
    var start: usize = 0;
    var end: usize = output.len;

    for (output, 0..) |c, i| {
        if (c == '[') {
            start = i + 1;
            break;
        }
    }
    for (output, start..) |c, i| {
        if (c == ']') {
            end = start + i;
            break;
        }
    }

    var pos = start;
    while (pos < end) {
        while (pos < end and output[pos] != '{') pos += 1;
        if (pos >= end) break;

        var depth: usize = 0;
        var obj_end = pos;
        for (pos..end) |i| {
            if (output[i] == '{') depth += 1 else if (output[i] == '}') {
                depth -= 1;
                if (depth == 0) {
                    obj_end = i + 1;
                    break;
                }
            }
        }

        const obj_text = output[pos..obj_end];
        const file = json.extractString(obj_text, "file") orelse "???";
        const offense_count = json.extractInteger(obj_text, "offense_count") orelse 0;

        if (offense_count > 0) {
            const entry = files.getOrPut(file) catch continue;
            if (entry.found_existing) {
                entry.value_ptr.* += offense_count;
            } else {
                entry.value_ptr.* = offense_count;
            }
        }

        pos = obj_end + 1;
    }

    if (files.count() == 0) {
        return "rubocop: No offenses found";
    }

    // Calculate totals
    var total_offenses: usize = 0;
    var it = files.iterator();
    while (it.next()) |entry| {
        total_offenses += entry.value_ptr.*;
    }

    std.fmt.format(result.writer(), "rubocop: {d} offenses in {d} files\n", .{ total_offenses, files.count() }) catch return "";
    result.appendSlice("═══════════════════════════════════════\n") catch return "";

    // Show top files
    var shown: usize = 0;
    it = files.iterator();
    while (it.next()) |entry| {
        if (shown >= 10) break;
        std.fmt.format(result.writer(), "{d}: {s}\n", .{ entry.value_ptr.*, entry.key_ptr.* }) catch return {};
        shown += 1;
    }

    return result.toOwnedSlice() catch "";
}

/// Filter rubocop text output
fn filterRubocopText(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 50) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Show offense lines
        if (std.mem.containsAtLeast(u8, trimmed, 1, ":") and
            (std.mem.containsAtLeast(u8, trimmed, 1, "C:") or
                std.mem.containsAtLeast(u8, trimmed, 1, "W:") or
                std.mem.containsAtLeast(u8, trimmed, 1, "E:") or
                std.mem.containsAtLeast(u8, trimmed, 1, "F:")))
        {
            result.appendSlice(trimmed[0..@min(150, trimmed.len)]) catch {};
            result.append('\n') catch {};
            count += 1;
        }
    }

    if (result.items.len == 0) {
        return output[0..@min(output.len, 500)];
    }

    return result.toOwnedSlice() catch "";
}

/// Run rubocop with filtering
pub fn runRubocop(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    // Check for bundle exec
    var use_bundle = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "bundle")) use_bundle = true;
    }

    if (use_bundle) {
        try cmd_args.append("bundle");
        try cmd_args.append("exec");
        try cmd_args.append("rubocop");
    } else {
        try cmd_args.append("rubocop");
    }

    // Add --format json if not present
    var has_format = false;
    for (args) |arg| {
        if (std.mem.containsAtLeast(u8, arg, 1, "--format")) has_format = true;
        if (!std.mem.eql(u8, arg, "bundle") and !std.mem.eql(u8, arg, "exec") and !std.mem.eql(u8, arg, "rubocop")) {
            try cmd_args.append(arg);
        }
    }

    if (!has_format) {
        try cmd_args.append("--format=json");
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "rubocop", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
        .filter_fn = struct {
            fn filter(output: []const u8) []const u8 {
                return filterRubocop(output, &.{});
            }
        }.filter,
    });
}
