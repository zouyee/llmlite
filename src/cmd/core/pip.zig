//! Pip - Python Package Manager
//!
//! Filters pip output for compact representation.
//!
//! ## Token Savings
//!
//! pip list: ~200 lines → ~30 lines (85% reduction)

const std = @import("std");
const json = @import("cmd_core_json");

/// Filter pip output
pub fn filterPip(output: []const u8, subcommand: []const u8) []const u8 {
    if (std.mem.containsAtLeast(u8, subcommand, 1, "list")) {
        return filterPipList(output);
    }
    if (std.mem.containsAtLeast(u8, subcommand, 1, "outdated")) {
        return filterPipOutdated(output);
    }

    return filterPipGeneric(output);
}

/// Filter pip list output
fn filterPipList(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Check for JSON format
    if (output.len > 0 and output[0] == '[') {
        return filterPipListJson(output);
    }

    // Text format
    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 30) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Skip header lines
        if (std.mem.containsAtLeast(u8, trimmed, 1, "-") or
            std.mem.containsAtLeast(u8, trimmed, 1, "Package"))
        {
            continue;
        }

        result.appendSlice(trimmed[0..@min(80, trimmed.len)]) catch {};
        result.append('\n') catch {};
        count += 1;
    }

    if (result.items.len == 0) {
        return "pip list: No packages";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter pip list --json output
fn filterPipListJson(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var packages = std.array_list.Managed(struct {
        name: []const u8,
        version: []const u8,
    }).init(std.heap.page_allocator);
    defer packages.deinit();

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
        const name = json.extractString(obj_text, "name") orelse "???";
        const version = json.extractString(obj_text, "version") orelse "?";

        packages.append(.{ .name = name, .version = version }) catch {};
        pos = obj_end + 1;
    }

    if (packages.items.len == 0) {
        return "pip list: No packages";
    }

    std.fmt.format(result.writer(), "pip list: {d} packages\n", .{packages.items.len}) catch return "";
    result.appendSlice("═══════════════════════════════════════\n") catch return "";

    const show_count = @min(20, packages.items.len);
    for (packages.items[0..show_count]) |pkg| {
        std.fmt.format(result.writer(), "{s} {s}\n", .{ pkg.name, pkg.version }) catch return {};
    }

    if (packages.items.len > 20) {
        std.fmt.format(result.writer(), "... +{d} more\n", .{packages.items.len - 20}) catch return "";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter pip outdated output
fn filterPipOutdated(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 20) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        if (std.mem.containsAtLeast(u8, trimmed, 1, "-") or
            std.mem.containsAtLeast(u8, trimmed, 1, "Package"))
        {
            continue;
        }

        result.appendSlice(trimmed[0..@min(100, trimmed.len)]) catch {};
        result.append('\n') catch {};
        count += 1;
    }

    if (result.items.len == 0) {
        return "pip outdated: All packages up to date";
    }

    return result.toOwnedSlice() catch "";
}

/// Generic pip filter
fn filterPipGeneric(output: []const u8) []const u8 {
    if (output.len == 0) {
        return "pip: No output";
    }
    return output[0..@min(output.len, 500)];
}

/// Run pip with filtering
pub fn runPip(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("pip");

    // Add --json for list command if not present
    var needs_json = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "list")) needs_json = true;
        try cmd_args.append(arg);
    }

    if (needs_json and !std.mem.containsAtLeast(u8, std.mem.join(u8, args, " "), 1, "--json")) {
        try cmd_args.append("--json");
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "pip", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
    });
}
