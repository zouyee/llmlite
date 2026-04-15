//! Mypy - Python Type Checker
//!
//! Filters mypy output for compact representation.
//! Inspired by RTK patterns.
//!
//! ## Token Savings
//!
//! mypy: ~200 lines → ~30 lines (85% reduction)

const std = @import("std");
const json = @import("cmd_core_json");

/// Filter mypy output
pub fn filterMypy(output: []const u8) []const u8 {
    // Check if JSON output
    if (std.mem.containsAtLeast(u8, output, 1, "{\"file\":")) {
        return filterMypyJson(output);
    }

    return filterMypyText(output);
}

/// Filter mypy JSON output
fn filterMypyJson(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var errors = std.ArrayList(struct {
        file: []const u8,
        line: usize,
        column: usize,
        severity: []const u8,
        message: []const u8,
    }).init(std.heap.page_allocator);
    defer errors.deinit();

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
        const line = json.extractInteger(obj_text, "line") orelse 0;
        const column = json.extractInteger(obj_text, "column") orelse 0;
        const severity = json.extractString(obj_text, "severity") orelse "error";
        const message = json.extractString(obj_text, "message") orelse "";

        errors.append(.{
            .file = file,
            .line = @intCast(line),
            .column = @intCast(column),
            .severity = severity,
            .message = message,
        }) catch {};

        pos = obj_end + 1;
    }

    if (errors.items.len == 0) {
        return "mypy: No issues found";
    }

    // Group by file
    var files = std.StringArrayHashMap(usize).init(std.heap.page_allocator);
    defer files.deinit();

    for (errors.items) |e| {
        const entry = files.getOrPut(e.file) catch continue;
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }

    // Build output
    const total = errors.items.len;
    const file_count = files.count();

    std.fmt.format(result.writer(), "mypy: {d} issues in {d} files\n", .{ total, file_count }) catch return "";
    result.appendSlice("═══════════════════════════════════════\n") catch return "";

    // Show top files
    var shown: usize = 0;
    var file_it = files.iterator();
    while (file_it.next()) |entry| {
        if (shown >= 5) break;

        std.fmt.format(result.writer(), "{d}: {s}\n", .{ entry.value_ptr.*, entry.key_ptr.* }) catch return {};

        // Show first error from this file
        for (errors.items) |e| {
            if (std.mem.eql(u8, e.file, entry.key_ptr.*)) {
                std.fmt.format(result.writer(), "  {s}:{d}: {s}\n", .{ e.file, e.line, e.message }) catch return "";
                break;
            }
        }

        shown += 1;
    }

    return result.toOwnedSlice() catch "";
}

/// Filter mypy text output
fn filterMypyText(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 30) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Skip summary lines
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Success:")) continue;
        if (std.mem.containsAtLeast(u8, trimmed, 1, "dmypy")) continue;

        // Show error lines
        if (std.mem.containsAtLeast(u8, trimmed, 1, ": error:") or
            std.mem.containsAtLeast(u8, trimmed, 1, ": warning:"))
        {
            result.appendSlice(trimmed[0..@min(150, trimmed.len)]) catch {};
            result.append('\n') catch {};
            count += 1;
        }
    }

    if (result.items.len == 0) {
        return "mypy: No issues found";
    }

    return result.toOwnedSlice() catch "";
}

/// Run mypy with filtering
pub fn runMypy(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.ArrayList([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("mypy");

    var has_json = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--json")) has_json = true;
        try cmd_args.append(arg);
    }

    if (!has_json) {
        try cmd_args.append("--json");
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "mypy", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
        .filter_fn = filterMypy,
    });
}
