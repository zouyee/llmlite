//! Vitest - JavaScript/TypeScript Test Runner
//!
//! Filters vitest JSON output for compact representation.
//! Inspired by RTK's vitest_cmd.rs.
//!
//! ## Token Savings
//!
//! vitest run: ~500 lines → ~30 lines (94% reduction)

const std = @import("std");
const json = @import("cmd_core_json");

/// Vitest test result
pub const VitestTestResult = struct {
    name: []const u8,
    status: []const u8,
    duration: f64,
    @"error": ?[]const u8,
};

/// Vitest suite result
pub const VitestSuiteResult = struct {
    file: []const u8,
    tests: []const VitestTestResult,
    duration: f64,
};

/// Filter vitest JSON output
pub fn filterVitest(output: []const u8) []const u8 {
    // Check if JSON
    if (std.mem.containsAtLeast(u8, output, 1, "{\"type\":")) {
        return filterVitestJson(output);
    }

    return filterVitestText(output);
}

/// Filter vitest JSON output
fn filterVitestJson(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    const SuiteAccumulator = struct {
        pass: usize = 0,
        fail: usize = 0,
        skip: usize = 0,
        duration: f64 = 0,
        failed_tests: std.array_list.Managed(struct { name: []const u8, @"error": ?[]const u8 }),
    };

    var suites = std.StringArrayHashMap(SuiteAccumulator).init(std.heap.page_allocator);
    defer suites.deinit();

    // Parse each line as JSON object
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] != '{') continue;

        const typ = json.extractString(trimmed, "type") orelse continue;

        if (std.mem.eql(u8, typ, "suite")) {
            const file = json.extractString(trimmed, "file") orelse "???";
            const duration = json.extractFloat(trimmed, "duration") orelse 0;

            const acc = suites.getOrPut(file) catch continue;
            if (!acc.found_existing) {
                acc.value_ptr.* = SuiteAccumulator{
                    .failed_tests = std.array_list.Managed(struct { name: []const u8, @"error": ?[]const u8 }).init(std.heap.page_allocator),
                };
            }
            acc.value_ptr.*.duration += duration;
        } else if (std.mem.eql(u8, typ, "test")) {
            const file = json.extractString(trimmed, "file") orelse "???";
            const name = json.extractString(trimmed, "name") orelse "???";
            const status = json.extractString(trimmed, "status") orelse "???";
            const duration = json.extractFloat(trimmed, "duration") orelse 0;
            _ = duration; // suppress unused warning
            const err_msg = json.extractString(trimmed, "error");

            const acc = suites.getOrPut(file) catch continue;
            if (!acc.found_existing) {
                acc.value_ptr.* = SuiteAccumulator{
                    .failed_tests = std.array_list.Managed(struct { name: []const u8, @"error": ?[]const u8 }).init(std.heap.page_allocator),
                };
            }

            if (std.mem.eql(u8, status, "passed")) {
                acc.value_ptr.*.pass += 1;
            } else if (std.mem.eql(u8, status, "failed")) {
                acc.value_ptr.*.fail += 1;
                acc.value_ptr.*.failed_tests.append(.{ .name = name, .@"error" = err_msg }) catch {};
            } else if (std.mem.eql(u8, status, "skipped")) {
                acc.value_ptr.*.skip += 1;
            }
        }
    }

    if (suites.count() == 0) {
        return "vitest: No tests found";
    }

    // Calculate totals
    var total_pass: usize = 0;
    var total_fail: usize = 0;
    var total_skip: usize = 0;
    var total_duration: f64 = 0;

    var it = suites.iterator();
    while (it.next()) |entry| {
        total_pass += entry.value_ptr.*.pass;
        total_fail += entry.value_ptr.*.fail;
        total_skip += entry.value_ptr.*.skip;
        total_duration += entry.value_ptr.*.duration;
    }

    // Build output
    if (total_fail == 0) {
        std.fmt.format(result.writer(), "vitest: {d} passed", .{total_pass}) catch return "";
        if (total_skip > 0) {
            std.fmt.format(result.writer(), ", {d} skipped", .{total_skip}) catch return "";
        }
        std.fmt.format(result.writer(), " ({d:.1f}s)", .{total_duration / 1000.0}) catch return "";
        return result.toOwnedSlice() catch "";
    }

    std.fmt.format(result.writer(), "vitest: {d} passed, {d} failed ({d:.1f}s)\n", .{
        total_pass, total_fail, total_duration / 1000.0,
    }) catch return "";
    result.appendSlice("═══════════════════════════════════════\n") catch return "";

    // Show failed tests
    var shown_files: usize = 0;
    it = suites.iterator();
    while (it.next()) |entry| {
        if (shown_files >= 5) break;
        const acc = entry.value_ptr.*;

        if (acc.fail > 0) {
            std.fmt.format(result.writer(), "FAIL {s}\n", .{entry.key_ptr.*}) catch return "";

            const show_count = @min(3, acc.failed_tests.items.len);
            for (acc.failed_tests.items[0..show_count]) |failed| {
                std.fmt.format(result.writer(), "  {s}", .{failed.name}) catch return "";
                if (failed.@"error") |err| {
                    // Truncate error message
                    const err_trim = if (err.len > 100) err[0..100] else err;
                    std.fmt.format(result.writer(), ": {s}...", .{err_trim}) catch return "";
                }
                result.append('\n') catch return "";
            }

            if (acc.failed_tests.items.len > 3) {
                std.fmt.format(result.writer(), "  ... +{d} more\n", .{acc.failed_tests.items.len - 3}) catch return "";
            }

            shown_files += 1;
        }
    }

    return result.toOwnedSlice() catch "";
}

/// Filter vitest text output
fn filterVitestText(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 30) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Skip ANSI codes and noise
        if (std.mem.containsAtLeast(u8, trimmed, 1, "\x1b[")) continue;
        if (std.mem.containsAtLeast(u8, trimmed, 1, " PASS ") or
            std.mem.containsAtLeast(u8, trimmed, 1, " FAIL ") or
            std.mem.containsAtLeast(u8, trimmed, 1, " SKIP "))
        {
            result.appendSlice(trimmed) catch {};
            result.append('\n') catch {};
            count += 1;
        }
    }

    if (result.items.len == 0) {
        return output[0..@min(output.len, 500)];
    }

    return result.toOwnedSlice() catch "";
}

/// Run vitest with filtering
pub fn runVitest(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    // Build command - add --reporter=json
    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("vitest");
    try cmd_args.append("run");
    try cmd_args.append("--reporter=json");

    for (args) |arg| {
        if (!std.mem.eql(u8, arg, "run") and !std.mem.startsWith(u8, arg, "--reporter")) {
            try cmd_args.append(arg);
        }
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "vitest", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
        .filter_fn = filterVitest,
    });
}

test "vitest filter - pass" {
    const input = "{\"type\":\"suite\",\"file\":\"test/auth.test.ts\"}\n{\"type\":\"test\",\"name\":\"test auth\",\"status\":\"passed\",\"duration\":10}";
    const result = filterVitest(input);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "1 passed"));
}
