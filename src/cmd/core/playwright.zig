//! Playwright - E2E Testing Framework
//!
//! Filters playwright test output for compact representation.
//! Inspired by RTK's playwright_cmd.rs.
//!
//! ## Token Savings
//!
//! playwright test: ~500 lines → ~50 lines (90% reduction)

const std = @import("std");
const json = @import("cmd_core_json");

/// Filter playwright output
pub fn filterPlaywright(output: []const u8) []const u8 {
    // Check for JSON output
    if (std.mem.containsAtLeast(u8, output, 1, "{\"suites\":")) {
        return filterPlaywrightJson(output);
    }

    return filterPlaywrightText(output);
}

/// Filter playwright JSON output
fn filterPlaywrightJson(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Extract stats
    const stats = json.extractJsonObject(output, "stats");
    if (stats) |s| {
        const duration = json.extractInteger(s, "duration") orelse 0;
        const passed = json.extractInteger(s, "passed") orelse 0;
        const failed = json.extractInteger(s, "failed") orelse 0;
        const skipped = json.extractInteger(s, "skipped") orelse 0;

        std.fmt.format(result.writer(), "playwright: {d} passed", .{passed}) catch return "";
        if (failed > 0) {
            std.fmt.format(result.writer(), ", {d} failed", .{failed}) catch return "";
        }
        if (skipped > 0) {
            std.fmt.format(result.writer(), ", {d} skipped", .{skipped}) catch return "";
        }
        std.fmt.format(result.writer(), " ({d:.1f}s)\n", .{@as(f64, @floatFromInt(duration)) / 1000.0}) catch return "";

        if (failed > 0) {
            result.appendSlice("═══════════════════════════════════════\n") catch return "";
        }
    }

    // Extract failures
    const suites = json.extractJsonObject(output, "suites");
    if (suites) |suites_text| {
        var shown_failures: usize = 0;

        // Simple extraction of failed test names
        var pos: usize = 0;
        while (pos < suites_text.len and shown_failures < 10) {
            const search = "\"status\":\"failed\"";
            const idx = std.mem.indexOf(u8, suites_text[pos..], search);
            if (idx == null) break;

            pos += idx.? + search.len;

            // Try to find test name before this position
            const before = suites_text[0..pos];
            const name_search = "\"title\":\"";
            const name_idx = std.mem.lastIndexOf(u8, before, name_search);

            if (name_idx) |ns| {
                const name_start = ns + name_search.len;
                const name_end = std.mem.indexOf(u8, suites_text[name_start..], "\"") orelse continue;
                const test_name = suites_text[name_start .. name_start + name_end];

                std.fmt.format(result.writer(), "FAIL: {s}\n", .{test_name}) catch return "";
                shown_failures += 1;
            }
        }

        if (shown_failures > 0) {
            std.fmt.format(result.writer(), "... +{d} more failures\n", .{shown_failures}) catch return "";
        }
    }

    return result.toOwnedSlice() catch "";
}

/// Filter playwright text output
fn filterPlaywrightText(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 50) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Skip ANSI codes
        if (std.mem.containsAtLeast(u8, trimmed, 1, "\x1b[")) continue;

        // Show important lines
        if (std.mem.containsAtLeast(u8, trimmed, 1, "PASS") or
            std.mem.containsAtLeast(u8, trimmed, 1, "FAIL") or
            std.mem.containsAtLeast(u8, trimmed, 1, "Error:") or
            std.mem.containsAtLeast(u8, trimmed, 1, "Timeout") or
            std.mem.containsAtLeast(u8, trimmed, 1, "attach") or
            std.mem.containsAtLeast(u8, trimmed, 1, "browser"))
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

/// Run playwright with filtering
pub fn runPlaywright(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("playwright");

    for (args) |arg| {
        try cmd_args.append(arg);
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "playwright", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
        .filter_fn = filterPlaywright,
    });
}
