//! Dotnet - .NET CLI
//!
//! Filters dotnet command outputs for compact representation.
//! Inspired by RTK's dotnet_cmd.rs.
//!
//! ## Supported Commands
//!
//! - dotnet build - Build output
//! - dotnet test - Test output
//! - dotnet format - Format report
//!
//! ## Token Savings
//!
//! dotnet build: ~200 lines → ~30 lines (85% reduction)

const std = @import("std");
const json = @import("cmd_core_json");

/// Filter dotnet output
pub fn filterDotnet(output: []const u8, subcommand: []const u8) []const u8 {
    if (std.mem.containsAtLeast(u8, subcommand, 1, "build")) {
        return filterDotnetBuild(output);
    }
    if (std.mem.containsAtLeast(u8, subcommand, 1, "test")) {
        return filterDotnetTest(output);
    }
    if (std.mem.containsAtLeast(u8, subcommand, 1, "format")) {
        return filterDotnetFormat(output);
    }

    return filterDotnetGeneric(output);
}

/// Filter dotnet build output
fn filterDotnetBuild(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;
    var has_errors = false;

    while (lines.next()) |line| {
        if (count >= 40) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Check for errors
        if (std.mem.containsAtLeast(u8, trimmed, 1, " error CS")) {
            has_errors = true;
            result.appendSlice(trimmed[0..@min(150, trimmed.len)]) catch {};
            result.append('\n') catch {};
            count += 1;
        }

        // Show summary
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Build succeeded") or
            std.mem.containsAtLeast(u8, trimmed, 1, "Build FAILED") or
            std.mem.containsAtLeast(u8, trimmed, 1, "Build started") or
            std.mem.containsAtLeast(u8, trimmed, 1, "Restore completed"))
        {
            result.appendSlice(trimmed) catch {};
            result.append('\n') catch {};
            count += 1;
        }
    }

    if (!has_errors and result.items.len == 0) {
        return "dotnet build: Build succeeded";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter dotnet test output
fn filterDotnetTest(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.portal_allocator);
    defer result.deinit();

    // Check for trx (XML) format or text
    if (std.mem.containsAtLeast(u8, output, 1, "<?xml")) {
        return filterDotnetTestTrx(output);
    }

    return filterDotnetTestText(output);
}

/// Filter dotnet test text output
fn filterDotnetTestText(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;
    var failed_count: usize = 0;
    var passed_count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 40) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Count results
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Failed!") or
            std.mem.containsAtLeast(u8, trimmed, 1, "Failed:"))
        {
            failed_count += 1;
        }
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Passed!") or
            std.mem.containsAtLeast(u8, trimmed, 1, "Passed:"))
        {
            passed_count += 1;
        }

        // Show failed tests
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Failed!") or
            std.mem.containsAtLeast(u8, trimmed, 1, "  Message:") or
            std.mem.containsAtLeast(u8, trimmed, 1, "  Stack:"))
        {
            result.appendSlice(trimmed[0..@min(150, trimmed.len)]) catch {};
            result.append('\n') catch {};
            count += 1;
        }
    }

    if (failed_count == 0 and passed_count == 0) {
        return "dotnet test: No test results";
    }

    if (failed_count == 0) {
        result.print( "dotnet test: {d} passed\n", .{passed_count}) catch return "";
        return result.toOwnedSlice() catch "";
    }

    result.print( "dotnet test: {d} passed, {d} failed\n", .{ passed_count, failed_count }) catch return "";
    return result.toOwnedSlice() catch "";
}

/// Filter dotnet test TRX output
fn filterDotnetTestTrx(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Extract from TRX XML (simplified)
    const total_tests = json.extractInteger(output, "totalTests") orelse 0;
    const passed_tests = json.extractInteger(output, "passedTests") orelse 0;
    const failed_tests = json.extractInteger(output, "failedTests") orelse 0;

    if (total_tests == 0) {
        return "dotnet test: No tests found";
    }

    if (failed_tests == 0) {
        result.print( "dotnet test: {d} passed\n", .{passed_tests}) catch return "";
    } else {
        result.print( "dotnet test: {d} passed, {d} failed\n", .{ passed_tests, failed_tests }) catch return "";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter dotnet format output
fn filterDotnetFormat(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 20) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        result.appendSlice(trimmed[0..@min(120, trimmed.len)]) catch {};
        result.append('\n') catch {};
        count += 1;
    }

    if (result.items.len == 0) {
        return "dotnet format: No changes needed";
    }

    return result.toOwnedSlice() catch "";
}

/// Generic dotnet filter
fn filterDotnetGeneric(output: []const u8) []const u8 {
    if (output.len == 0) {
        return "dotnet: No output";
    }
    return output[0..@min(output.len, 500)];
}

/// Run dotnet with filtering
pub fn runDotnet(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("dotnet");

    for (args) |arg| {
        try cmd_args.append(arg);
    }

    // Detect subcommand
    var subcommand: []const u8 = "";
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "build") or
            std.mem.eql(u8, arg, "test") or
            std.mem.eql(u8, arg, "format") or
            std.mem.eql(u8, arg, "restore") or
            std.mem.eql(u8, arg, "publish"))
        {
            subcommand = arg;
        }
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "dotnet", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
    });
}
