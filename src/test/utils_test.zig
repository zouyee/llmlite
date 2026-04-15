//! Utils Tests - Unit tests for utility functions

const std = @import("std");
const utils = @import("cmd_core_utils");

test "utils.commandExists - valid command" {
    // 'ls' should exist on Unix systems
    const exists = utils.commandExists("ls");
    try std.testing.expect(exists == true);
}

test "utils.commandExists - invalid command" {
    // This command should not exist
    const exists = utils.commandExists("this_command_does_not_exist_12345");
    try std.testing.expect(exists == false);
}

test "utils.fileExists - current directory" {
    // Current directory should exist
    const exists = utils.fileExists(".");
    try std.testing.expect(exists == true);
}

test "utils.fileExists - nonexistent file" {
    const exists = utils.fileExists("/nonexistent/path/to/file/12345.txt");
    try std.testing.expect(exists == false);
}

test "utils.truncate - short string" {
    const input = "short";
    const result = try utils.truncate(std.heap.page_allocator, input, 10);
    defer std.heap.page_allocator.free(result);

    try std.testing.expect(std.mem.eql(u8, result, "short"));
}

test "utils.truncate - long string" {
    const input = "this is a very long string that should be truncated";
    const result = try utils.truncate(std.heap.page_allocator, input, 10);
    defer std.heap.page_allocator.free(result);

    try std.testing.expect(result.len == 10);
    try std.testing.expect(std.mem.eql(u8, result[7..10], "..."));
}

test "utils.stripAnsi - remove ANSI codes" {
    const input = "\x1b[32mgreen\x1b[0m normal";
    const result = try utils.stripAnsi(std.heap.page_allocator, input);
    defer std.heap.page_allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "green") != null);
}

test "utils.countTokens - empty string" {
    const result = utils.countTokens("");
    try std.testing.expect(result == 0);
}

test "utils.countTokens - normal string" {
    const result = utils.countTokens("hello world");
    // Approximate: 11 chars / 4 = 2.75, ceil to 3
    try std.testing.expect(result >= 2);
}

test "utils.formatBytes - bytes" {
    const result = try utils.formatBytes(std.heap.page_allocator, 512);
    defer std.heap.page_allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "B") != null);
}

test "utils.formatBytes - kilobytes" {
    const result = try utils.formatBytes(std.heap.page_allocator, 2048);
    defer std.heap.page_allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "KB") != null);
}

test "utils.isCI - not CI" {
    // In test environment, CI might not be set
    const result = utils.isCI();
    _ = result; // Just verify it doesn't crash
}

test "PackageManager enum values" {
    try std.testing.expect(@intFromEnum(utils.PackageManager.npm) == 0);
    try std.testing.expect(@intFromEnum(utils.PackageManager.pnpm) == 1);
    try std.testing.expect(@intFromEnum(utils.PackageManager.yarn) == 2);
    try std.testing.expect(@intFromEnum(utils.PackageManager.bun) == 3);
    try std.testing.expect(@intFromEnum(utils.PackageManager.pip) == 4);
    try std.testing.expect(@intFromEnum(utils.PackageManager.poetry) == 5);
    try std.testing.expect(@intFromEnum(utils.PackageManager.cargo) == 6);
    try std.testing.expect(@intFromEnum(utils.PackageManager.unknown) == 7);
}

test "detectPackageManager - returns enum" {
    // Just verify it returns a valid enum value
    const pm = utils.detectPackageManager();
    _ = pm; // Just verify it doesn't crash
}

// ============================================================================
// RTK Migration: formatTokens tests
// ============================================================================

test "utils.formatTokens - millions" {
    const result = try utils.formatTokens(std.heap.page_allocator, 1_234_567);
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("1.2M", result);

    const result2 = try utils.formatTokens(std.heap.page_allocator, 12_345_678);
    defer std.heap.page_allocator.free(result2);
    try std.testing.expectEqualStrings("12.3M", result2);
}

test "utils.formatTokens - thousands" {
    const result = try utils.formatTokens(std.heap.page_allocator, 59_234);
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("59.2K", result);

    const result2 = try utils.formatTokens(std.heap.page_allocator, 1_000);
    defer std.heap.page_allocator.free(result2);
    try std.testing.expectEqualStrings("1.0K", result2);
}

test "utils.formatTokens - small numbers" {
    const result = try utils.formatTokens(std.heap.page_allocator, 694);
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("694", result);

    const result2 = try utils.formatTokens(std.heap.page_allocator, 0);
    defer std.heap.page_allocator.free(result2);
    try std.testing.expectEqualStrings("0", result2);
}

// ============================================================================
// RTK Migration: formatUsd tests
// ============================================================================

test "utils.formatUsd - large amounts" {
    const result = try utils.formatUsd(std.heap.page_allocator, 1234.567);
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("$1234.57", result);

    const result2 = try utils.formatUsd(std.heap.page_allocator, 1000.0);
    defer std.heap.page_allocator.free(result2);
    try std.testing.expectEqualStrings("$1000.00", result2);
}

test "utils.formatUsd - medium amounts" {
    const result = try utils.formatUsd(std.heap.page_allocator, 12.345);
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("$12.35", result);

    const result2 = try utils.formatUsd(std.heap.page_allocator, 0.99);
    defer std.heap.page_allocator.free(result2);
    try std.testing.expectEqualStrings("$0.99", result2);
}

test "utils.formatUsd - small amounts" {
    const result = try utils.formatUsd(std.heap.page_allocator, 0.0096);
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("$0.0096", result);

    const result2 = try utils.formatUsd(std.heap.page_allocator, 0.0001);
    defer std.heap.page_allocator.free(result2);
    try std.testing.expectEqualStrings("$0.0001", result2);
}

test "utils.formatUsd - edge cases" {
    const result = try utils.formatUsd(std.heap.page_allocator, 0.01);
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("$0.01", result);

    const result2 = try utils.formatUsd(std.heap.page_allocator, 0.009);
    defer std.heap.page_allocator.free(result2);
    try std.testing.expectEqualStrings("$0.0090", result2);
}

// ============================================================================
// RTK Migration: formatCpt tests
// ============================================================================

test "utils.formatCpt - normal values" {
    const result = try utils.formatCpt(std.heap.page_allocator, 0.000003);
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("$3.00/MTok", result);

    const result2 = try utils.formatCpt(std.heap.page_allocator, 0.0000038);
    defer std.heap.page_allocator.free(result2);
    try std.testing.expectEqualStrings("$3.80/MTok", result2);

    const result3 = try utils.formatCpt(std.heap.page_allocator, 0.00000386);
    defer std.heap.page_allocator.free(result3);
    try std.testing.expectEqualStrings("$3.86/MTok", result3);
}

test "utils.formatCpt - edge cases" {
    // Zero
    const result = try utils.formatCpt(std.heap.page_allocator, 0.0);
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("$0.00/MTok", result);

    // Negative
    const result2 = try utils.formatCpt(std.heap.page_allocator, -0.000001);
    defer std.heap.page_allocator.free(result2);
    try std.testing.expectEqualStrings("$0.00/MTok", result2);

    // Infinity
    const result3 = try utils.formatCpt(std.heap.page_allocator, std.math.inf(f64));
    defer std.heap.page_allocator.free(result3);
    try std.testing.expectEqualStrings("$0.00/MTok", result3);
}

// ============================================================================
// RTK Migration: okConfirmation tests
// ============================================================================

test "utils.okConfirmation - with detail" {
    const result = try utils.okConfirmation(std.heap.page_allocator, "merged", "#42");
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("ok merged #42", result);

    const result2 = try utils.okConfirmation(std.heap.page_allocator, "created", "PR #5 https://github.com/foo/bar/pull/5");
    defer std.heap.page_allocator.free(result2);
    try std.testing.expectEqualStrings("ok created PR #5 https://github.com/foo/bar/pull/5", result2);
}

test "utils.okConfirmation - no detail" {
    const result = try utils.okConfirmation(std.heap.page_allocator, "commented", "");
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("ok commented", result);
}
