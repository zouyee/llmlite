//! Rake - Ruby Task Runner
//!
//! Filters rake output for compact representation.
//! Inspired by RTK's rake_cmd.rs.
//!
//! ## Token Savings
//!
//! rake: ~200 lines → ~30 lines (85% reduction)

const std = @import("std");

/// Filter rake output
pub fn filterRake(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;
    var in_error = false;

    while (lines.next()) |line| {
        if (count >= 30) {
            std.fmt.format(result.writer(), "\n... +{d} more lines", .{count - 30}) catch return "";
            break;
        }

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Skip common noise
        if (std.mem.containsAtLeast(u8, trimmed, 1, "using")) continue;
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Installing")) continue;
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Fetching")) continue;
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Bundle complete")) continue;

        // Track errors
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Error:") or
            std.mem.containsAtLeast(u8, trimmed, 1, "FAILED"))
        {
            in_error = true;
        }

        // Show important lines
        if (std.mem.containsAtLeast(u8, trimmed, 1, "rake ") or
            std.mem.containsAtLeast(u8, trimmed, 1, "invoking") or
            std.mem.containsAtLeast(u8, trimmed, 1, "finished") or
            std.mem.containsAtLeast(u8, trimmed, 1, "Error:") or
            std.mem.containsAtLeast(u8, trimmed, 1, "FAILED") or
            in_error)
        {
            result.appendSlice(trimmed[0..@min(120, trimmed.len)]) catch {};
            result.append('\n') catch {};
            count += 1;
        }
    }

    if (result.items.len == 0) {
        return "rake: Completed";
    }

    return result.toOwnedSlice() catch "";
}

/// Run rake with filtering
pub fn runRake(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.ArrayList([]const u8).init(allocator);
    defer cmd_args.deinit();

    // Check for bundle exec
    var use_bundle = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "bundle")) use_bundle = true;
    }

    if (use_bundle) {
        try cmd_args.append("bundle");
        try cmd_args.append("exec");
        try cmd_args.append("rake");
    } else {
        try cmd_args.append("rake");
    }

    for (args) |arg| {
        if (!std.mem.eql(u8, arg, "bundle") and !std.mem.eql(u8, arg, "exec")) {
            try cmd_args.append(arg);
        }
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "rake", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
        .filter_fn = filterRake,
    });
}
