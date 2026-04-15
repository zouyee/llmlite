//! Java - Java Build and Test Filter
//!
//! Filters Java output for javac, maven (mvn), and gradle commands.
//! Note: RTK does not have Java support; this is llmlite's extension.
//!
//! ## Supported Commands
//!
//! - `javac` - Java compiler output
//! - `mvn test` - Maven test output
//! - `mvn compile` - Maven compilation
//! - `gradle test` - Gradle test output
//! - `gradle build` - Gradle build output
//!
//! ## Token Savings
//!
//! mvn test: ~1000 lines → ~30 lines (97% reduction)
//! gradle build: ~500 lines → ~20 lines (96% reduction)

const std = @import("std");

/// Java command type
pub const JavaCommand = enum {
    javac,
    maven,
    gradle,
    kotlin,
};

/// Filter javac output
pub fn filterJavac(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var error_count: usize = 0;
    var warning_count: usize = 0;

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Skip noise
        if (std.mem.startsWith(u8, trimmed, "Parsing") or
            std.mem.startsWith(u8, trimmed, "Compiling") or
            std.mem.startsWith(u8, trimmed, "Writing") or
            std.mem.startsWith(u8, trimmed, "Note:") or
            trimmed.len == 0)
        {
            continue;
        }

        // Keep errors and important warnings
        if (std.mem.startsWith(u8, trimmed, "error:") or
            std.mem.startsWith(u8, trimmed, "Error:") or
            std.mem.containsAtLeast(u8, trimmed, 1, ".java:"))
        {
            result.appendSlice(trimmed) catch {};
            result.append('\n') catch {};
            error_count += 1;
        } else if (std.mem.startsWith(u8, trimmed, "warning:")) {
            warning_count += 1;
        }
    }

    if (error_count == 0 and warning_count == 0) {
        return "javac: ok";
    }

    if (error_count > 0) {
        return result.toOwnedSlice() catch "";
    }

    return std.fmt.allocPrint(std.heap.page_allocator, "javac: {d} warnings", .{warning_count}) catch "";
}

/// Filter maven output (mvn test, mvn compile)
pub fn filterMaven(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var test_passed: usize = 0;
    var test_failures: usize = 0;
    var test_skipped: usize = 0;
    var build_success = true;

    var in_test_results = false;
    var in_failures = false;
    var failure_lines = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer failure_lines.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Detect test results section
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Tests run:") and std.mem.containsAtLeast(u8, trimmed, 1, "Failures:")) {
            in_test_results = true;

            // Parse "Tests run: N, Failures: M, Errors: E, Skipped: S"
            var it = std.mem.splitScalar(u8, trimmed, ',');
            while (it.next()) |part| {
                const p = std.mem.trim(u8, part, " ");
                var word_it = std.mem.splitScalar(u8, p, ':');
                const num_str = word_it.next() orelse continue;
                const word = word_it.rest();

                const num = std.fmt.parseInt(usize, num_str, 10) catch 0;

                if (std.mem.containsAtLeast(u8, word, 1, "Failures:") or std.mem.containsAtLeast(u8, word, 1, "Errors:")) {
                    if (num > 0) test_failures += num;
                } else if (std.mem.containsAtLeast(u8, word, 1, "Skipped:")) {
                    test_skipped = num;
                } else if (std.mem.containsAtLeast(u8, word, 1, "run:")) {
                    // Total is first number, already handled
                }
            }
            continue;
        }

        // Parse individual test results
        if (std.mem.startsWith(u8, trimmed, "Tests run:")) {
            // Format: "Tests run: N, Failures: M, Errors: E, Skipped: S"
            const parts = std.mem.splitScalar(u8, trimmed, ',');
            var parsed_fail = false;
            for (parts) |part| {
                const p = std.mem.trim(u8, part, " ");
                if (std.mem.startsWith(u8, p, "Failures:")) {
                    const val = std.mem.trim(u8, p[9..], " :");
                    test_failures = std.fmt.parseInt(usize, val, 10) catch test_failures;
                    parsed_fail = true;
                } else if (!parsed_fail and std.mem.startsWith(u8, p, "Tests run:")) {
                    const val = std.mem.trim(u8, p[10..], " :");
                    const total = std.fmt.parseInt(usize, val, 10) catch 0;
                    if (test_failures == 0) {
                        test_passed = total;
                    }
                }
            }
        } else if (std.mem.startsWith(u8, trimmed, "Results :")) {
            // Final results line
            in_failures = false;
        } else if (std.mem.startsWith(u8, trimmed, "FAILURE!")) {
            build_success = false;
            in_failures = true;
        } else if (std.mem.startsWith(u8, trimmed, "ERROR!")) {
            build_success = false;
            result.appendSlice(trimmed) catch {};
            result.append('\n') catch {};
        } else if (in_failures and trimmed.len > 0) {
            failure_lines.append(trimmed) catch {};
        } else if (std.mem.startsWith(u8, trimmed, "BUILD SUCCESS") or std.mem.startsWith(u8, trimmed, "BUILD FAILURE")) {
            build_success = std.mem.containsAtLeast(u8, trimmed, 1, "SUCCESS");
        }
    }

    // Build output
    if (!build_success) {
        std.fmt.format(result.writer(), "mvn: BUILD FAILURE", .{}) catch return "";
        if (failure_lines.items.len > 0) {
            result.append('\n') catch {};
            for (failure_lines.items[0..@min(10, failure_lines.items.len)]) |line| {
                result.appendSlice(line) catch {};
                result.append('\n') catch {};
            }
        }
        return result.toOwnedSlice() catch "";
    }

    if (test_failures > 0) {
        std.fmt.format(result.writer(), "mvn: {d} passed, {d} failed", .{ test_passed, test_failures }) catch return "";
        if (test_skipped > 0) {
            std.fmt.format(result.writer(), ", {d} skipped", .{test_skipped}) catch return "";
        }
        return result.toOwnedSlice() catch "";
    }

    if (test_passed > 0) {
        std.fmt.format(result.writer(), "mvn: {d} passed", .{test_passed}) catch return "";
        if (test_skipped > 0) {
            std.fmt.format(result.writer(), ", {d} skipped", .{test_skipped}) catch return "";
        }
        return result.toOwnedSlice() catch "";
    }

    return "mvn: ok";
}

/// Filter gradle output
pub fn filterGradle(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var test_passed: usize = 0;
    var test_failures: usize = 0;
    var in_failures = false;
    var failure_lines = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer failure_lines.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Skip noise
        if (std.mem.startsWith(u8, trimmed, "> Task :") or
            std.mem.startsWith(u8, trimmed, "BUILD") or
            std.mem.startsWith(u8, trimmed, "Starting") or
            std.mem.startsWith(u8, trimmed, "Deprecated") or
            std.mem.startsWith(u8, trimmed, "Waiting") or
            std.mem.startsWith(u8, trimmed, "Publishing") or
            trimmed.len == 0)
        {
            continue;
        }

        // Parse test results
        if (std.mem.containsAtLeast(u8, trimmed, 1, "tests completed") or
            std.mem.containsAtLeast(u8, trimmed, 1, "tests passed"))
        {

            // Format: "274 tests completed, 6 failures" or "164 tests passed"
            if (std.mem.containsAtLeast(u8, trimmed, 1, "failures")) {
                var it = std.mem.splitScalar(u8, trimmed, ' ');
                while (it.next()) |part| {
                    if (std.mem.startsWith(u8, part, "completed")) {
                        const num_str = it.next() orelse break;
                        test_passed = std.fmt.parseInt(usize, num_str, 10) catch 0;
                    }
                    if (std.mem.startsWith(u8, part, "failures")) {
                        const num_str = it.peek() orelse continue;
                        test_failures = std.fmt.parseInt(usize, num_str, 10) catch 0;
                    }
                }
            }
            continue;
        }

        // Failures section
        if (std.mem.containsAtLeast(u8, trimmed, 1, "FAILED") or
            std.mem.startsWith(u8, trimmed, "AssertionError") or
            std.mem.startsWith(u8, trimmed, "expected:") or
            std.mem.startsWith(u8, trimmed, "but was:"))
        {
            in_failures = true;
            failure_lines.append(trimmed) catch {};
        } else if (in_failures) {
            if (trimmed.len > 0) {
                failure_lines.append(trimmed) catch {};
            } else {
                in_failures = false;
            }
        }
    }

    // Build output
    if (test_failures > 0) {
        std.fmt.format(result.writer(), "gradle: {d} passed, {d} failed\n", .{ test_passed, test_failures }) catch return "";
        std.fmt.format(result.writer(), "═══════════════════════════════════════\n", .{}) catch return "";

        for (failure_lines.items[0..@min(10, failure_lines.items.len)]) |line| {
            result.appendSlice(line) catch {};
            result.append('\n') catch {};
        }

        if (failure_lines.items.len > 10) {
            std.fmt.format(result.writer(), "... +{d} more\n", .{failure_lines.items.len - 10}) catch return "";
        }

        return result.toOwnedSlice() catch "";
    }

    if (test_passed > 0) {
        std.fmt.format(result.writer(), "gradle: {d} passed", .{test_passed}) catch return "";
        return result.toOwnedSlice() catch "";
    }

    return "gradle: ok";
}

/// Filter kotlinc output
pub fn filterKotlinc(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var error_count: usize = 0;

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Skip noise
        if (std.mem.startsWith(u8, trimmed, "Compiling") or
            std.mem.startsWith(u8, trimmed, "warning:") or
            std.mem.startsWith(u8, trimmed, "Note:") or
            trimmed.len == 0)
        {
            continue;
        }

        // Keep errors
        if (std.mem.startsWith(u8, trimmed, "error:") or
            std.mem.containsAtLeast(u8, trimmed, 1, ".kt:"))
        {
            result.appendSlice(trimmed) catch {};
            result.append('\n') catch {};
            error_count += 1;
        }
    }

    if (error_count == 0) {
        return "kotlinc: ok";
    }

    return result.toOwnedSlice() catch "";
}

/// Run javac with filtering
pub fn runJavac(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.ArrayList([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("javac");
    for (args) |arg| {
        try cmd_args.append(arg);
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "javac", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
        .filter_fn = filterJavac,
    });
}

/// Run maven with filtering
pub fn runMaven(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.ArrayList([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("mvn");
    for (args) |arg| {
        try cmd_args.append(arg);
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "mvn", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
        .filter_fn = filterMaven,
    });
}

/// Run gradle with filtering
pub fn runGradle(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.ArrayList([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("gradle");
    for (args) |arg| {
        try cmd_args.append(arg);
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "gradle", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
        .filter_fn = filterGradle,
    });
}

test "maven filter - pass" {
    const input = "[INFO] Tests run: 25, Failures: 0, Errors: 0, Skipped: 0\n[INFO] BUILD SUCCESS";
    const output = filterMaven(input);
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "25 passed"));
}

test "gradle filter - pass" {
    const input = "164 tests completed, 0 failures\nBUILD SUCCESSFUL";
    const output = filterGradle(input);
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "164 passed"));
}
