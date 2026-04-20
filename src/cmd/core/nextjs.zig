//! Next.js - React Framework
//!
//! Filters Next.js build output for compact representation.
//! Inspired by RTK's next_cmd.rs.
//!
//! ## Token Savings
//!
//! next build: ~500 lines → ~50 lines (90% reduction)

const std = @import("std");

/// Filter Next.js output
pub fn filterNext(output: []const u8, subcommand: []const u8) []const u8 {
    if (std.mem.containsAtLeast(u8, subcommand, 1, "build")) {
        return filterNextBuild(output);
    }
    if (std.mem.containsAtLeast(u8, subcommand, 1, "dev")) {
        return filterNextDev(output);
    }

    return filterNextGeneric(output);
}

/// Filter next build output
fn filterNextBuild(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 50) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Show errors
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Error:") or
            std.mem.containsAtLeast(u8, trimmed, 1, "error TS") or
            std.mem.containsAtLeast(u8, trimmed, 1, "ENOENT"))
        {
            result.appendSlice(trimmed[0..@min(150, trimmed.len)]) catch {};
            result.append('\n') catch {};
            count += 1;
        }

        // Show important info
        if (std.mem.containsAtLeast(u8, trimmed, 1, "✓") or
            std.mem.containsAtLeast(u8, trimmed, 1, "✗") or
            std.mem.containsAtLeast(u8, trimmed, 1, "Route") or
            std.mem.containsAtLeast(u8, trimmed, 1, "Generated") or
            std.mem.containsAtLeast(u8, trimmed, 1, "Build completed") or
            std.mem.containsAtLeast(u8, trimmed, 1, "Failed"))
        {
            result.appendSlice(trimmed[0..@min(120, trimmed.len)]) catch {};
            result.append('\n') catch {};
            count += 1;
        }
    }

    // Build summary
    if (result.items.len == 0) {
        result.appendSlice("next build: Completed successfully") catch return "";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter next dev output
fn filterNextDev(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 20) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Show ready/complile messages
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Ready") or
            std.mem.containsAtLeast(u8, trimmed, 1, "started") or
            std.mem.containsAtLeast(u8, trimmed, 1, "localhost") or
            std.mem.containsAtLeast(u8, trimmed, 1, "Error") or
            std.mem.containsAtLeast(u8, trimmed, 1, " Compiled"))
        {
            result.appendSlice(trimmed[0..@min(100, trimmed.len)]) catch {};
            result.append('\n') catch {};
            count += 1;
        }
    }

    if (result.items.len == 0) {
        return "next dev: Running";
    }

    return result.toOwnedSlice() catch "";
}

/// Generic next filter
fn filterNextGeneric(output: []const u8) []const u8 {
    if (output.len == 0) {
        return "next: No output";
    }
    return output[0..@min(output.len, 500)];
}

/// Run next with filtering
pub fn runNext(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("next");

    for (args) |arg| {
        try cmd_args.append(arg);
    }

    // Detect subcommand
    var subcommand: []const u8 = "";
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "build") or
            std.mem.eql(u8, arg, "dev") or
            std.mem.eql(u8, arg, "start") or
            std.mem.eql(u8, arg, "lint"))
        {
            subcommand = arg;
        }
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "next", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
    });
}
