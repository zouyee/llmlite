//! Cargo - Rust Build and Test Filter
//!
//! Filters cargo output for build, test, clippy, and install commands.
//! Inspired by RTK's cargo_cmd.rs.
//!
//! ## Features
//!
//! - `cargo build` - Strip noise, keep errors/warnings
//! - `cargo test` - Support --json flag for structured output
//! - `cargo clippy` - Lint warnings filtering
//! - `cargo install` - Strip compilation noise
//!
//! ## Token Savings
//!
//! cargo install: ~200 lines → 2 lines (99% reduction)
//! cargo test: ~500 lines → ~30 lines (94% reduction)

const std = @import("std");

/// Cargo subcommand type
pub const CargoCommand = enum {
    build,
    @"test",
    clippy,
    check,
    install,
    nextest,
};

/// Filter cargo build/check output
pub fn filterCargoBuild(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var in_error = false;
    var error_count: usize = 0;
    var current_error_lines = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
    defer current_error_lines.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Skip noise lines
        if (std.mem.startsWith(u8, trimmed, "Compiling") or
            std.mem.startsWith(u8, trimmed, "Downloading") or
            std.mem.startsWith(u8, trimmed, "Locking") or
            std.mem.startsWith(u8, trimmed, "Updating") or
            std.mem.startsWith(u8, trimmed, "Adding") or
            std.mem.startsWith(u8, trimmed, "Finished") or
            std.mem.startsWith(u8, trimmed, "Blocking waiting"))
        {
            continue;
        }

        // Error detection
        if (std.mem.startsWith(u8, trimmed, "error[") or std.mem.startsWith(u8, trimmed, "error:")) {
            if (in_error and current_error_lines.items.len > 0) {
                // Save previous error
                error_count += 1;
                for (current_error_lines.items) |err_line| {
                    result.appendSlice(err_line) catch {};
                    result.append('\n') catch {};
                }
                current_error_lines.clear();
            }
            in_error = true;
            current_error_lines.append(trimmed) catch {};
        } else if (in_error) {
            if (trimmed.len == 0 and current_error_lines.items.len > 3) {
                // End of error block
                error_count += 1;
                for (current_error_lines.items) |err_line| {
                    result.appendSlice(err_line) catch {};
                    result.append('\n') catch {};
                }
                current_error_lines.clear();
                in_error = false;
            } else {
                current_error_lines.append(trimmed) catch {};
            }
        } else if (std.mem.startsWith(u8, trimmed, "warning:")) {
            // Keep actionable warnings
            if (!std.mem.containsAtLeast(u8, trimmed, 1, "generated") or
                !std.mem.containsAtLeast(u8, trimmed, 1, "warning"))
            {
                result.appendSlice(trimmed) catch {};
                result.append('\n') catch {};
            }
        }
    }

    // Handle trailing error
    if (in_error and current_error_lines.items.len > 0) {
        error_count += 1;
        for (current_error_lines.items) |err_line| {
            result.appendSlice(err_line) catch {};
            result.append('\n') catch {};
        }
    }

    if (result.items.len == 0) {
        return "cargo build: ok";
    }

    if (error_count > 0) {
        return result.toOwnedSlice() catch "";
    }

    return "cargo build: warnings";
}

/// Filter cargo test output (supports --json flag)
pub fn filterCargoTest(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Check if JSON output
    if (std.mem.containsAtLeast(u8, output, 1, "{") and std.mem.containsAtLeast(u8, output, 1, "\"test\":")) {
        return filterCargoTestJson(output);
    }

    // Text output filtering
    var pass_count: usize = 0;
    var fail_count: usize = 0;

    var in_test_header = false;
    var in_failures = false;
    var failure_lines = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
    defer failure_lines.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        if (std.mem.startsWith(u8, trimmed, "running") and std.mem.containsAtLeast(u8, trimmed, 1, "test")) {
            in_test_header = true;
            continue;
        }

        if (std.mem.startsWith(u8, trimmed, "test result:")) {
            // Parse: "test result: ok. 5 passed, 1 failed"
            var it = std.mem.splitScalar(u8, trimmed, ' ');
            _ = it.next(); // "test"
            _ = it.next(); // "result:"
            const status = it.next() orelse "ok";
            _ = status; // suppress unused warning
            _ = it.next(); // "N"

            const remaining = it.rest();
            var count_it = std.mem.splitScalar(u8, remaining, ',');
            while (count_it.next()) |part| {
                const trimmed_part = std.mem.trim(u8, part, " ");
                var word_it = std.mem.splitScalar(u8, trimmed_part, ' ');
                const num_str = word_it.next() orelse "0";
                const word = word_it.rest();

                const num = std.fmt.parseInt(usize, num_str, 10) catch 0;
                if (std.mem.containsAtLeast(u8, word, 1, "passed")) {
                    pass_count = num;
                } else if (std.mem.containsAtLeast(u8, word, 1, "failed")) {
                    fail_count = num;
                }
            }

            continue;
        }

        if (in_test_header and std.mem.containsAtLeast(u8, trimmed, 1, "FAILED")) {
            in_failures = true;
        }

        if (in_failures) {
            if (trimmed.len > 0) {
                failure_lines.append(trimmed) catch {};
            }
        }
    }

    // Build output
    if (fail_count == 0 and pass_count > 0) {
        std.fmt.format(result.writer(), "cargo test: {d} passed", .{pass_count}) catch return "";
        return result.toOwnedSlice() catch "";
    }

    if (fail_count > 0) {
        std.fmt.format(result.writer(), "cargo test: {d} passed, {d} failed\n", .{ pass_count, fail_count }) catch return "";
        std.fmt.format(result.writer(), "═══════════════════════════════════════\n", .{}) catch return "";

        // Show first few failures
        var shown: usize = 0;
        for (failure_lines.items) |line| {
            if (shown >= 5) break;
            if (line.len > 0) {
                result.appendSlice(line) catch {};
                result.append('\n') catch {};
                shown += 1;
            }
        }

        if (failure_lines.items.len > 5) {
            std.fmt.format(result.writer(), "... +{d} more lines\n", .{failure_lines.items.len - 5}) catch return "";
        }

        return result.toOwnedSlice() catch "";
    }

    return "cargo test: ok";
}

/// Filter cargo test --json output (simplified JSON parsing)
fn filterCargoTestJson(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var pass_count: usize = 0;
    var fail_count: usize = 0;
    var failures = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
    defer failures.deinit();

    // Simple JSON line parsing
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0 or trimmed[0] != '{') continue;

        // Extract event type
        const event_type = extractJsonString(trimmed, "event") orelse continue;

        if (std.mem.eql(u8, event_type, "test")) {
            // {"event":"test","name":"test_foo","event":"ok"}
            const test_name = extractJsonString(trimmed, "name") orelse "unknown";
            const test_status = extractJsonString(trimmed, "event") orelse "ok";

            if (std.mem.eql(u8, test_status, "ok")) {
                pass_count += 1;
            } else if (std.mem.eql(u8, test_status, "FAILED")) {
                fail_count += 1;
                failures.append(test_name) catch {};
            }
        } else if (std.mem.eql(u8, event_type, "suite")) {
            // Final summary
            const passed = extractJsonInt(trimmed, "passed") orelse 0;
            const failed = extractJsonInt(trimmed, "failed") orelse 0;
            pass_count = passed;
            fail_count = failed;
        }
    }

    if (fail_count == 0) {
        std.fmt.format(result.writer(), "cargo test: {d} passed", .{pass_count}) catch return "";
    } else {
        std.fmt.format(result.writer(), "cargo test: {d} passed, {d} failed\n", .{ pass_count, fail_count }) catch return "";
        std.fmt.format(result.writer(), "═══════════════════════════════════════\n", .{}) catch return "";

        for (failures.items[0..@min(5, failures.items.len)]) |name| {
            std.fmt.format(result.writer(), "  FAILED: {s}\n", .{name}) catch return "";
        }

        if (fail_count > 5) {
            std.fmt.format(result.writer(), "  ... +{d} more\n", .{fail_count - 5}) catch return "";
        }
    }

    return result.toOwnedSlice() catch "";
}

/// Extract string field from simple JSON
fn extractJsonString(json: []const u8, field: []const u8) ?[]const u8 {
    const search = "\"" ++ field ++ "\":\"";
    const start = std.mem.indexOf(u8, json, search) orelse return null;
    const value_start = start + search.len;
    const value_end = std.mem.indexOf(u8, json[value_start..], "\"") orelse return null;
    return json[value_start .. value_start + value_end];
}

/// Extract integer field from simple JSON
fn extractJsonInt(json: []const u8, field: []const u8) ?usize {
    const search = "\"" ++ field ++ "\":";
    const start = std.mem.indexOf(u8, json, search) orelse return null;
    const value_start = start + search.len;

    var value_end = value_start;
    while (value_end < json.len) {
        const c = json[value_end];
        if (c < '0' or c > '9') break;
        value_end += 1;
    }

    if (value_end == value_start) return null;
    return std.fmt.parseInt(usize, json[value_start..value_end], 10) catch null;
}

/// Filter cargo clippy output
pub fn filterCargoClippy(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var warning_count: usize = 0;

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Skip noise
        if (std.mem.startsWith(u8, trimmed, "Compiling") or
            std.mem.startsWith(u8, trimmed, "Finished") or
            std.mem.startsWith(u8, trimmed, "Blocking") or
            std.mem.startsWith(u8, trimmed, "Checking"))
        {
            continue;
        }

        // Keep warnings and errors
        if (std.mem.startsWith(u8, trimmed, "warning:")) {
            result.appendSlice(trimmed) catch {};
            result.append('\n') catch {};
            warning_count += 1;
        } else if (std.mem.startsWith(u8, trimmed, "error:")) {
            result.appendSlice(trimmed) catch {};
            result.append('\n') catch {};
        }
    }

    if (result.items.len == 0) {
        return "cargo clippy: no warnings";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter cargo install output
pub fn filterCargoInstall(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var installed_crate: []const u8 = "";
    var installed_version: []const u8 = "";
    var error_count: usize = 0;
    var errors = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
    defer errors.deinit();

    var in_error = false;
    var current_error_lines = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
    defer current_error_lines.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Skip noise
        if (std.mem.startsWith(u8, trimmed, "Compiling") or
            std.mem.startsWith(u8, trimmed, "Downloading") or
            std.mem.startsWith(u8, trimmed, "Finished") or
            std.mem.startsWith(u8, trimmed, "Blocking"))
        {
            continue;
        }

        // Track installed
        if (std.mem.startsWith(u8, trimmed, "Installing") or std.mem.startsWith(u8, trimmed, "Installed")) {
            const rest = if (std.mem.startsWith(u8, trimmed, "Installing"))
                trimmed[10..]
            else
                trimmed[9..];

            const cleaned = std.mem.trim(u8, rest, " ");

            // Try to parse "name version"
            var it = std.mem.splitScalar(u8, cleaned, ' ');
            installed_crate = it.next() orelse cleaned;
            installed_version = it.rest();

            if (installed_version.len == 0) {
                installed_version = "(unknown)";
            }
            continue;
        }

        // Track errors
        if (std.mem.startsWith(u8, trimmed, "error[") or std.mem.startsWith(u8, trimmed, "error:")) {
            in_error = true;
            current_error_lines.append(trimmed) catch {};
        } else if (in_error) {
            if (trimmed.len == 0) {
                // End of error
                error_count += 1;
                errors.append(current_error_lines.items[0]) catch {};
                current_error_lines.clear();
                in_error = false;
            } else {
                current_error_lines.append(trimmed) catch {};
            }
        }
    }

    // Handle remaining error
    if (in_error and current_error_lines.items.len > 0) {
        error_count += 1;
        errors.append(current_error_lines.items[0]) catch {};
    }

    // Build result
    if (error_count > 0) {
        for (errors.items) |err| {
            result.appendSlice(err) catch {};
            result.append('\n') catch {};
        }
        return result.toOwnedSlice() catch "";
    }

    if (installed_crate.len > 0) {
        if (installed_version.len > 0) {
            return std.fmt.allocPrint(std.heap.page_allocator, "cargo install: {s} {s} installed", .{ installed_crate, installed_version }) catch "";
        }
        return std.fmt.allocPrint(std.heap.page_allocator, "cargo install: {s} installed", .{installed_crate}) catch "";
    }

    return "cargo install: ok";
}

/// Run cargo command with filtering
pub fn runCargo(allocator: std.mem.Allocator, cmd: CargoCommand, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    const subcommand = switch (cmd) {
        .build => "build",
        .@"test" => "test",
        .clippy => "clippy",
        .check => "check",
        .install => "install",
        .nextest => "nextest",
    };

    // Build command
    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("cargo");
    try cmd_args.append(subcommand);

    // Add args
    for (args) |arg| {
        try cmd_args.append(arg);
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    const filter_fn: *const fn ([]const u8) []const u8 = switch (cmd) {
        .build, .check => filterCargoBuild,
        .@"test" => filterCargoTest,
        .clippy => filterCargoClippy,
        .install => filterCargoInstall,
        .nextest => filterCargoTest, // Similar to test
    };

    return runner.runFiltered(allocator, cmd_args.items, std.fmt.allocPrint(allocator, "cargo {s}", .{subcommand}) catch "", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
        .filter_fn = filter_fn,
    });
}

test "cargo build filter - ok" {
    const input = "   Compiling mycrate v0.1.0\n   Finished dev [unoptimized] target(s) in 2.3s";
    const output = filterCargoBuild(input);
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "ok"));
}

test "cargo test filter - pass" {
    const input = "running 5 tests\ntest test_one ... ok\ntest test_two ... ok\n\ntest result: ok. 5 passed, 0 failed";
    const output = filterCargoTest(input);
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "5 passed"));
}
