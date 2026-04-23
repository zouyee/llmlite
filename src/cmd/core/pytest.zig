//! Pytest - Python Test Output Filter
//!
//! Filters pytest output using a state machine to show only failures and summary.
//! Inspired by RTK's pytest_cmd.rs.
//!
//! ## State Machine
//!
//! The parser tracks these states:
//! - Header: Initial output until "collected N items"
//! - TestProgress: Progress lines like "tests/test_foo.py .... [ 40%]"
//! - Failures: Detailed failure output between FAILURES and short summary
//! - Summary: Final summary line with pass/fail counts
//!
//! ## Token Savings
//!
//! Typical pytest output: 800+ lines
//! Filtered output: ~20 lines (90%+ reduction)

const std = @import("std");

/// Parse state for pytest output
const ParseState = enum {
    Header,
    TestProgress,
    Failures,
    Summary,
};

/// Failure information
const Failure = struct {
    test_name: []const u8,
    error_lines: [][]const u8,
};

/// Summary statistics
const TestStats = struct {
    passed: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,
};

/// Filter pytest output using state machine
pub fn filterPytestOutput(output: []const u8) []const u8 {
    var state: ParseState = .Header;
    var test_files = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
    defer test_files.deinit();

    var failures = std.array_list.Managed(Failure).init(std.heap.page_allocator);
    defer failures.deinit();

    var current_failure_lines = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
    defer current_failure_lines.deinit();

    var summary_line: []const u8 = "";
    var stats = TestStats{};

    var lines = std.mem.splitScalar(u8, output, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // State transitions
        if (std.mem.startsWith(u8, trimmed, "===") and std.mem.containsAtLeast(u8, trimmed, 1, "test session starts")) {
            state = .Header;
            continue;
        } else if (std.mem.startsWith(u8, trimmed, "===") and std.mem.containsAtLeast(u8, trimmed, 1, "FAILURES")) {
            state = .Failures;
            // Save current failure if any
            if (current_failure_lines.items.len > 0) {
                const test_name = extractTestName(current_failure_lines.items);
                failures.append(Failure{
                    .test_name = test_name,
                    .error_lines = current_failure_lines.toOwnedSlice(),
                }) catch {};
                current_failure_lines.clear();
            }
            continue;
        } else if (std.mem.startsWith(u8, trimmed, "===") and std.mem.containsAtLeast(u8, trimmed, 1, "short test summary")) {
            state = .Summary;
            // Save current failure if any
            if (current_failure_lines.items.len > 0) {
                const test_name = extractTestName(current_failure_lines.items);
                failures.append(Failure{
                    .test_name = test_name,
                    .error_lines = current_failure_lines.toOwnedSlice(),
                }) catch {};
                current_failure_lines.clear();
            }
            continue;
        } else if (std.mem.startsWith(u8, trimmed, "===") and (std.mem.containsAtLeast(u8, trimmed, 1, "passed") or std.mem.containsAtLeast(u8, trimmed, 1, "failed"))) {
            summary_line = trimmed;
            parseSummaryLine(trimmed, &stats);
            continue;
        }

        // Process based on state
        switch (state) {
            .Header => {
                if (std.mem.containsAtLeast(u8, trimmed, 1, "collected")) {
                    state = .TestProgress;
                }
            },
            .TestProgress => {
                // Progress lines like "tests/test_foo.py ....  [ 40%]"
                if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "===") and (std.mem.containsAtLeast(u8, trimmed, 1, ".py") or std.mem.containsAtLeast(u8, trimmed, 1, "%]"))) {
                    test_files.append(trimmed) catch {};
                }
            },
            .Failures => {
                // Collect failure details
                if (std.mem.startsWith(u8, trimmed, "___")) {
                    // New failure section
                    if (current_failure_lines.items.len > 0) {
                        const test_name = extractTestName(current_failure_lines.items);
                        failures.append(Failure{
                            .test_name = test_name,
                            .error_lines = current_failure_lines.toOwnedSlice(),
                        }) catch {};
                        current_failure_lines.clear();
                    }
                    current_failure_lines.append(trimmed) catch {};
                } else if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "===")) {
                    current_failure_lines.append(trimmed) catch {};
                }
            },
            .Summary => {
                // FAILED test lines in summary
                if (std.mem.startsWith(u8, trimmed, "FAILED") or std.mem.startsWith(u8, trimmed, "ERROR")) {
                    // Already counted in stats
                }
            },
        }
    }

    // Save last failure if any
    if (current_failure_lines.items.len > 0) {
        const test_name = extractTestName(current_failure_lines.items);
        failures.append(Failure{
            .test_name = test_name,
            .error_lines = current_failure_lines.toOwnedSlice(),
        }) catch {};
    }

    // Build compact output
    return buildPytestSummary(&stats, &failures);
}

/// Extract test name from failure lines
fn extractTestName(lines: [][]const u8) []const u8 {
    for (lines) |line| {
        if (std.mem.startsWith(u8, line, "___")) {
            // Format: "___ test_name ___"
            const trimmed = std.mem.trim(u8, line[3..], " _");
            if (trimmed.len > 0 and std.mem.endsWith(u8, trimmed, "___")) {
                return std.mem.trim(u8, trimmed[0 .. trimmed.len - 3], " _");
            }
            return trimmed;
        }
        if (std.mem.startsWith(u8, line, "FAILED")) {
            // Format: "FAILED tests/test_foo.py::test_bar - AssertionError"
            const parts = std.mem.splitScalar(u8, line, ' ');
            _ = parts.next(); // skip "FAILED"
            if (parts.next()) |path| {
                if (std.mem.containsAtLeast(u8, path, 1, "::")) {
                    const subparts = std.mem.splitScalar(u8, path, ':');
                    if (subparts.next()) |name| {
                        return name;
                    }
                }
                return path;
            }
        }
    }
    return "unknown";
}

/// Parse summary line to extract stats
fn parseSummaryLine(line: []const u8, stats: *TestStats) void {
    var parts = std.mem.splitScalar(u8, line, ',');
    while (parts.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " =");
        var word_iter = std.mem.splitScalar(u8, trimmed, ' ');
        const num_str = word_iter.next() orelse continue;
        const word = word_iter.next() orelse "";

        if (std.mem.containsAtLeast(u8, word, 1, "passed")) {
            stats.passed = std.fmt.parseInt(usize, num_str, 10) catch 0;
        } else if (std.mem.containsAtLeast(u8, word, 1, "failed")) {
            stats.failed = std.fmt.parseInt(usize, num_str, 10) catch 0;
        } else if (std.mem.containsAtLeast(u8, word, 1, "skipped")) {
            stats.skipped = std.fmt.parseInt(usize, num_str, 10) catch 0;
        }
    }
}

/// Build compact pytest summary
fn buildPytestSummary(stats: *const TestStats, failures: *const []Failure) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    if (stats.failed == 0 and stats.passed > 0) {
        result.print( "Pytest: {d} passed", .{stats.passed}) catch return "";
        return result.toOwnedSlice() catch "";
    }

    if (stats.passed == 0 and stats.failed == 0) {
        return "Pytest: No tests collected";
    }

    // Main summary line
    result.print( "Pytest: {d} passed", .{stats.passed}) catch return "";
    if (stats.failed > 0) {
        result.print( ", {d} failed", .{stats.failed}) catch return "";
    }
    if (stats.skipped > 0) {
        result.print( ", {d} skipped", .{stats.skipped}) catch return "";
    }
    result.append('\n') catch return "";

    // Separator
    result.appendSlice("═══════════════════════════════════════\n") catch return "";

    if (failures.len == 0) {
        return result.toOwnedSlice() catch "";
    }

    // Show failures (limit to 5)
    const max_failures = @min(5, failures.len);
    result.print( "\nFailures:\n", .{}) catch return "";

    for (failures[0..max_failures], 0..) |failure, i| {
        result.print( "{d}. [FAIL] {s}\n", .{ i + 1, failure.test_name }) catch return "";

        // Show relevant error lines (assertions, errors, file locations)
        var relevant_shown: usize = 0;
        for (failure.error_lines) |err_line| {
            if (relevant_shown >= 3) break;

            const trimmed = std.mem.trim(u8, err_line, " ");
            if (trimmed.len == 0) continue;
            if (std.mem.startsWith(u8, trimmed, "___")) continue;

            const is_relevant = std.mem.startsWith(u8, trimmed, ">") or
                trimmed[0] == 'E' or
                std.mem.containsAtLeast(u8, trimmed, 1, "assert") or
                std.mem.containsAtLeast(u8, trimmed, 1, "Error") or
                std.mem.containsAtLeast(u8, trimmed, 1, ".py:");

            if (is_relevant) {
                const truncated = if (trimmed.len > 100) trimmed[0..100] else trimmed;
                result.print( "     {s}\n", .{truncated}) catch return "";
                relevant_shown += 1;
            }
        }

        if (i < max_failures - 1) {
            result.append('\n') catch return "";
        }
    }

    if (failures.len > max_failures) {
        result.print( "\n... +{d} more failures\n", .{failures.len - max_failures}) catch return "";
    }

    return result.toOwnedSlice() catch "";
}

/// Run pytest with filtering
pub fn runPytest(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    // Build command
    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    // Check if pytest or python -m pytest
    const pytest_exists = checkToolExists("pytest");
    if (pytest_exists) {
        try cmd_args.append("pytest");
    } else {
        try cmd_args.append("python");
        try cmd_args.append("-m");
        try cmd_args.append("pytest");
    }

    // Check for existing flags
    var has_tb_flag = false;
    var has_quiet_flag = false;

    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--tb")) has_tb_flag = true;
        if (std.mem.eql(u8, arg, "-q") or std.mem.eql(u8, arg, "--quiet")) has_quiet_flag = true;
        try cmd_args.append(arg);
    }

    // Add default flags if not present
    if (!has_tb_flag) {
        try cmd_args.append("--tb=short");
    }
    if (!has_quiet_flag) {
        try cmd_args.append("-q");
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "pytest", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
        .filter_fn = filterPytestOutput,
    });
}

/// Check if a tool exists in PATH
fn checkToolExists(name: []const u8) bool {
    const result = std.process.which(name);
    return result != null;
}

test "pytest filter - all pass" {
    const input = "============================= test session starts ==============================\nplatform darwin -- Python 3.11.0\ncollected 4 items\n\ntests/test_main.py ....                                              [ 25%]\n\n============================= 4 passed in 0.50s ==============================";

    const output = filterPytestOutput(input);
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "4 passed"));
}

test "pytest filter - with failure" {
    const input = "============================= test session starts ==============================\nplatform darwin -- Python 3.11.0\ncollected 2 items\n\ntests/test_main.py::test_one PASSED                                              [ 50%]\ntests/test_main.py::test_two FAILED                                              [100%]\n\n_________________________________ FAILURES _________________________________\n____________________ test_two ____________________\n\n    def test_two():\n>       assert 1 == 2\nE       AssertionError\n\ntests/test_main.py:10: AssertionError\n\n============================= 1 passed, 1 failed in 0.5s ==============================";

    const output = filterPytestOutput(input);
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "1 passed"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "1 failed"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "test_two"));
}

test "pytest filter - no tests" {
    const input = "============================= test session starts ==============================\nplatform darwin -- Python 3.11.0\ncollected 0 items\n\n============================= 0 passed in 0.00s ==============================";

    const output = filterPytestOutput(input);
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "No tests collected"));
}
