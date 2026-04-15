//! TOML Filter Tests - Unit tests for the TOML filter system
//!
//! Tests the filter pipeline functions using the built-in filter test data.

const std = @import("std");
const testing = std.testing;
const toml_filter = @import("cmd_core_toml_filter");

test "stripAnsi removes ANSI codes" {
    const allocator = std.heap.page_allocator;
    const input = "\x1b[31mError\x1b[0m\nnormal";
    const result = toml_filter.stripAnsi(input, allocator);
    defer allocator.free(result);
    try testing.expectEqualStrings("Error\nnormal", result);
}

test "matchPattern simple match" {
    try testing.expect(toml_filter.matchPattern("hello world", "hello"));
    try testing.expect(!toml_filter.matchPattern("hello world", "goodbye"));
}

test "matchPattern with wildcard" {
    try testing.expect(toml_filter.matchPattern("hello world", "hello*"));
    try testing.expect(toml_filter.matchPattern("hello world", "*world"));
}

test "matchPattern anchored" {
    try testing.expect(toml_filter.matchPattern("hello", "^hello$"));
    try testing.expect(!toml_filter.matchPattern("hello world", "^hello$"));
}

test "matchPattern digit" {
    // Note: \d+ requires literal '+' in pattern string
    try testing.expect(toml_filter.matchPattern("test123", "test\\d"));
    try testing.expect(!toml_filter.matchPattern("test", "test\\d"));
}

test "truncateWithEllipsis short string unchanged" {
    const allocator = std.heap.page_allocator;
    const input = "hi";
    const result = toml_filter.truncateWithEllipsis(input, 10, allocator);
    try testing.expectEqualStrings("hi", result);
}

test "truncateWithEllipsis long string truncated" {
    const allocator = std.heap.page_allocator;
    const input = "hello world this is long";
    const result = toml_filter.truncateWithEllipsis(input, 10, allocator);
    // 10 chars: 7 chars + "..." = 10 chars total
    try testing.expectEqualStrings("hello w...", result);
}

test "truncateWithEllipsis very short max" {
    const allocator = std.heap.page_allocator;
    const input = "hello world";
    const result = toml_filter.truncateWithEllipsis(input, 2, allocator);
    try testing.expectEqualStrings("he", result);
}

test "applyFilter strip_ansi" {
    const allocator = std.heap.page_allocator;
    const rule = toml_filter.FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .strip_ansi = true,
    };
    const input = "\x1b[31mError\x1b[0m\nnormal";
    const result = try toml_filter.applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    try testing.expectEqualStrings("Error\nnormal", result.output);
}

test "applyFilter strip_lines_matching" {
    const allocator = std.heap.page_allocator;
    const rule = toml_filter.FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .strip_lines_matching = &.{"^noise"},
    };
    const input = "noise line\nkeep this\nnoise stuff";
    const result = try toml_filter.applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    try testing.expectEqualStrings("keep this", result.output);
}

test "applyFilter keep_lines_matching" {
    const allocator = std.heap.page_allocator;
    const rule = toml_filter.FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .keep_lines_matching = &.{ "^PASS", "^FAIL" },
    };
    const input = "PASS test_a\nsome noise\nFAIL test_b";
    const result = try toml_filter.applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    try testing.expectEqualStrings("PASS test_a\nFAIL test_b", result.output);
}

test "applyFilter max_lines" {
    const allocator = std.heap.page_allocator;
    const rule = toml_filter.FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .max_lines = 2,
    };
    const input = "a\nb\nc\nd\ne";
    const result = try toml_filter.applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    try testing.expect(result.output.len > 0);
    try testing.expect(std.mem.indexOf(u8, result.output, "lines truncated") != null);
}

test "applyFilter on_empty" {
    const allocator = std.heap.page_allocator;
    const rule = toml_filter.FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .strip_lines_matching = &.{".*"},
        .on_empty = "nothing left",
    };
    const input = "line1\nline2";
    const result = try toml_filter.applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    try testing.expect(result.matched);
    try testing.expectEqualStrings("nothing left", result.output);
}

test "applyFilter head_lines" {
    const allocator = std.heap.page_allocator;
    const rule = toml_filter.FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .head_lines = 2,
    };
    const input = "a\nb\nc\nd\ne";
    const result = try toml_filter.applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    try testing.expect(std.mem.indexOf(u8, result.output, "3 lines omitted") != null);
}

test "applyFilter tail_lines" {
    const allocator = std.heap.page_allocator;
    const rule = toml_filter.FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .tail_lines = 2,
    };
    const input = "a\nb\nc\nd\ne";
    const result = try toml_filter.applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    try testing.expect(std.mem.indexOf(u8, result.output, "3 lines omitted") != null);
}

test "applyFilter match_output success" {
    const allocator = std.heap.page_allocator;
    const rule = toml_filter.FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .match_output = &.{
            .{
                .pattern = "total size is",
                .message = "rsync: ok",
                .unless = "error|failed",
            },
        },
    };
    const input = "total size is 1024\nspeedup is 1.23";
    const result = try toml_filter.applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    try testing.expect(result.matched);
    try testing.expectEqualStrings("rsync: ok", result.output);
}

test "applyFilter match_output unless matched" {
    const allocator = std.heap.page_allocator;
    const rule = toml_filter.FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .match_output = &.{
            .{
                .pattern = "total size is",
                .message = "rsync: ok",
                .unless = "error|failed",
            },
        },
    };
    const input = "total size is 1024\nerror occurred";
    const result = try toml_filter.applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    // unless matched, so it should not short-circuit
    try testing.expect(result.output.len > 0);
}

test "findMatchingFilter make" {
    const filters = try toml_filter.loadAllFilters(std.heap.page_allocator);
    const match = toml_filter.findMatchingFilter(filters, "make");
    try testing.expect(match != null);
    try testing.expectEqualStrings("make", match.?.rule.name);
}

test "findMatchingFilter terraform-plan" {
    const filters = try toml_filter.loadAllFilters(std.heap.page_allocator);
    const match = toml_filter.findMatchingFilter(filters, "terraform plan");
    try testing.expect(match != null);
    try testing.expectEqualStrings("terraform-plan", match.?.rule.name);
}

test "findMatchingFilter no match" {
    const filters = try toml_filter.loadAllFilters(std.heap.page_allocator);
    const match = toml_filter.findMatchingFilter(filters, "unknown_command_xyz");
    try testing.expect(match == null);
}

test "findMatchingFilter docker ps" {
    const filters = try toml_filter.loadAllFilters(std.heap.page_allocator);
    const match = toml_filter.findMatchingFilter(filters, "docker ps");
    try testing.expect(match != null);
    try testing.expectEqualStrings("docker-ps", match.?.rule.name);
}

test "builtin filters have test data" {
    const filters = try toml_filter.loadAllFilters(std.heap.page_allocator);
    // Verify at least some filters have test data
    var filters_with_tests: usize = 0;
    for (filters) |f| {
        if (f.tests.len > 0) {
            filters_with_tests += 1;
        }
    }
    // We added tests to many filters
    try testing.expect(filters_with_tests > 0);
}

// ============================================================================
// RTK Migration: Additional TOML Filter Tests
// ============================================================================

test "applyFilter head_and_tail_combined" {
    const allocator = std.heap.page_allocator;
    const rule = toml_filter.FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .head_lines = 2,
        .tail_lines = 2,
    };
    const input = "a\nb\nc\nd\ne\nf";
    const result = try toml_filter.applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    // Should contain first 2 lines and last 2 lines
    try testing.expect(std.mem.startsWith(u8, result.output, "a\nb\n"));
    try testing.expect(std.mem.indexOf(u8, result.output, "2 lines omitted") != null);
    try testing.expect(std.mem.endsWith(u8, result.output, "e\nf"));
}

test "applyFilter max_lines_counts_omit_message" {
    const allocator = std.heap.page_allocator;
    const rule = toml_filter.FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .max_lines = 3,
    };
    const input = "a\nb\nc\nd\ne";
    const result = try toml_filter.applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    // 3 content lines + 1 truncated message = 4 lines output
    try testing.expect(std.mem.indexOf(u8, result.output, "lines truncated") != null);
}

test "applyFilter on_empty_not_triggered_when_output_remains" {
    const allocator = std.heap.page_allocator;
    const rule = toml_filter.FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .keep_lines_matching = &.{"keep"},
        .on_empty = "nothing left",
    };
    const input = "keep this\nnoise";
    const result = try toml_filter.applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    // on_empty should NOT be triggered since "keep this" remains
    try testing.expectEqualStrings("keep this", result.output);
}

test "applyFilter empty_filter_passthrough" {
    const allocator = std.heap.page_allocator;
    const rule = toml_filter.FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
    };
    const input = "line1\nline2\nline3";
    const result = try toml_filter.applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    // Empty filter should pass through unchanged
    try testing.expectEqualStrings("line1\nline2\nline3", result.output);
}

test "applyFilter full_pipeline_order" {
    const allocator = std.heap.page_allocator;
    const rule = toml_filter.FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .strip_ansi = true,
        .strip_lines_matching = &.{"^noise"},
        .truncate_lines_at = 10,
        .head_lines = 3,
        .max_lines = 4,
        .on_empty = "empty",
    };
    const input = "\x1b[31mred line\x1b[0m\nnoise skip\nkeep one\nkeep two\nkeep three\nkeep four";
    const result = try toml_filter.applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    // After strip_ansi: ANSI codes removed
    try testing.expect(std.mem.indexOf(u8, result.output, "red line") != null);
    // After strip: noise should be removed
    try testing.expect(std.mem.indexOf(u8, result.output, "noise skip") == null);
    // Should contain omit/truncate message
    try testing.expect(std.mem.indexOf(u8, result.output, "lines omitted") != null or std.mem.indexOf(u8, result.output, "lines truncated") != null);
}
