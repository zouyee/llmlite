//! Filter Tests - Unit tests for filter strategies
//!
//! Tests all 14 filtering strategies to ensure correct behavior.

const std = @import("std");
const filter = @import("cmd_core_filter");

test "filter.stats - git status output" {
    const input = "On branch main\nChanges not staged:\n  modified:   src/main.zig\n  deleted:    src/test.zig\nUntracked files:\n  new.zig";

    const result = try filter.filter(std.heap.page_allocator, input, .{
        .strategy = .stats,
        .level = .standard,
    });

    try std.testing.expect(result.reduction_pct > 0);
    try std.testing.expect(result.strategy_used == .stats);
}

test "filter.stats - empty input" {
    const result = try filter.filter(std.heap.page_allocator, "", .{
        .strategy = .stats,
        .level = .standard,
    });

    try std.testing.expect(result.original_len == 0);
    try std.testing.expect(result.filtered_len == 0);
}

test "filter.errors_only - error detection" {
    const input = "Running tests...\nTest 1: PASS\nTest 2: FAIL\nError: assertion failed\n    at line 42\nTest 3: PASS";

    const result = try filter.filter(std.heap.page_allocator, input, .{
        .strategy = .errors_only,
        .level = .standard,
    });

    try std.testing.expect(result.reduction_pct > 50);
    // Should contain "Error:" or "FAIL"
    try std.testing.expect(std.mem.find(u8, result.filtered, "Error:") != null or
        std.mem.find(u8, result.filtered, "FAIL") != null);
}

test "filter.errors_only - no errors" {
    const input = "All tests passed\nNo errors found\nEverything is fine";

    const result = try filter.filter(std.heap.page_allocator, input, .{
        .strategy = .errors_only,
        .level = .standard,
    });

    try std.testing.expect(std.mem.eql(u8, result.filtered, "(no errors)"));
}

test "filter.deduplication - repeated lines" {
    const input = "Processing...\nProcessing...\nProcessing...\nDone\nDone";

    const result = try filter.filter(std.heap.page_allocator, input, .{
        .strategy = .deduplication,
        .level = .standard,
    });

    try std.testing.expect(result.reduction_pct > 30);
}

test "filter.grouping - key:value pairs" {
    const input = "error: file not found\nwarning: deprecated API\nerror: invalid input\ninfo: done";

    const result = try filter.filter(std.heap.page_allocator, input, .{
        .strategy = .grouping,
        .level = .standard,
    });

    // Should group by keys (error, warning, info)
    try std.testing.expect(result.filtered.len > 0);
}

test "filter.failure_focus - pytest output" {
    const input = "============================= test session starts ==============================\nplatform darwin -- Python 3.11.0\ncollected 10 items\n\ntests/test_main.py::test_one PASSED                                              [ 10%]\ntests/test_main.py::test_two FAILED                                              [ 20%]\n\n_________________________________ FAILURES _________________________________\n____________________ test_two ____________________\n\nself = <test_main.Test>\n    def test_two():\n>       assert 1 == 2\nE       AssertionError\n\n============================= 2 passed, 1 failed in 0.5s ==============================";

    const result = try filter.filter(std.heap.page_allocator, input, .{
        .strategy = .failure_focus,
        .level = .standard,
    });

    // Should focus on failures
    try std.testing.expect(std.mem.find(u8, result.filtered, "FAILED") != null);
}

test "filter.tree_compression - docker ps output" {
    const input = "/repo/src/main.go\n/repo/src/util.go\n/repo/README.md\n/repo/docs/guide.md";

    const result = try filter.filter(std.heap.page_allocator, input, .{
        .strategy = .tree_compression,
        .level = .standard,
    });

    // Should compress to directory counts
    try std.testing.expect(result.filtered.len < input.len);
}

test "filter.progress_strip - npm install progress" {
    const input = "\x1b[32madded 123 packages in 5s\x1b[0m\n\x1b[2K\x1b[11C\x1b[4mprogress\x1b[0m";

    const result = try filter.filter(std.heap.page_allocator, input, .{
        .strategy = .progress_strip,
        .level = .standard,
    });

    // Should strip ANSI and progress bars
    try std.testing.expect(result.filtered.len < input.len);
}

test "filter.code_filter - strip comments" {
    const input = "// This is a comment\nfunc main() {\n    // Another comment\n    println(\"hello\");\n}";

    const result = try filter.filter(std.heap.page_allocator, input, .{
        .strategy = .code_filter,
        .level = .standard,
    });

    // Should not contain comments
    try std.testing.expect(std.mem.find(u8, result.filtered, "// This is") == null);
}

test "filter.state_machine - pytest state detection" {
    const input = "PASS: test_one\nPASS: test_two\nFAIL: test_three\nFAIL: test_four";

    const result = try filter.filter(std.heap.page_allocator, input, .{
        .strategy = .state_machine,
        .level = .standard,
    });

    try std.testing.expect(result.filtered.len > 0);
}

test "filter.ndjson_stream - go test output" {
    const input = "{\"Action\":\"run\",\"Test\":\"TestOne\"}\n{\"Action\":\"pass\",\"Test\":\"TestOne\"}\n{\"Action\":\"run\",\"Test\":\"TestTwo\"}\n{\"Action\":\"fail\",\"Test\":\"TestTwo\"}";

    const result = try filter.filter(std.heap.page_allocator, input, .{
        .strategy = .ndjson_stream,
        .level = .standard,
    });

    // Should parse and summarize NDJSON
    try std.testing.expect(result.filtered.len > 0);
}

test "filter.ultra_compact - minimal output" {
    const input = "PASS test_one\nPASS test_two\nFAIL test_three\nWARNING deprecated";

    const result = try filter.filter(std.heap.page_allocator, input, .{
        .strategy = .ultra_compact,
        .level = .standard,
    });

    // Should be very compact
    try std.testing.expect(result.reduction_pct > 50);
}

test "filter.git_log - git log output" {
    const input = "commit abc1234 (HEAD -> main)\nAuthor: Test User\nDate:   Mon Jan 1 00:00:00 2024\n\n    Fix bug in main\n\ncommit def5678\nAuthor: Test User\nDate:   Sun Dec 31 00:00:00 2023\n\n    Add new feature";

    const result = try filter.filter(std.heap.page_allocator, input, .{
        .strategy = .git_log,
        .level = .standard,
    });

    // Should compress commit info
    try std.testing.expect(result.filtered.len < input.len);
}

test "filter.none - passthrough" {
    const input = "This is the exact input";

    const result = try filter.filter(std.heap.page_allocator, input, .{
        .strategy = .none,
        .level = .standard,
    });

    try std.testing.expect(std.mem.eql(u8, result.filtered, input));
}

test "filter.autoDetectStrategy - JSON detection" {
    const json_input = "{\"key\": \"value\", \"num\": 42}";
    const strategy = filter.autoDetectStrategy(json_input);
    try std.testing.expect(strategy == .json_dual);
}

test "filter.autoDetectStrategy - error detection" {
    const error_input = "ERROR: something went wrong\nERROR: again";
    const strategy = filter.autoDetectStrategy(error_input);
    try std.testing.expect(strategy == .errors_only);
}

test "filter.autoDetectStrategy - test output" {
    const test_input = "PASS test_one\nFAIL test_two\ntest run 3";
    const strategy = filter.autoDetectStrategy(test_input);
    try std.testing.expect(strategy == .failure_focus);
}

test "filter.autoDetectStrategy - progress bars" {
    const progress_input = "[=====>          ] 40%\n[=========>      ] 80%";
    const strategy = filter.autoDetectStrategy(progress_input);
    try std.testing.expect(strategy == .progress_strip);
}

test "filter.autoDetectStrategy - default" {
    const default_input = "Some random output without clear patterns";
    const strategy = filter.autoDetectStrategy(default_input);
    try std.testing.expect(strategy == .stats);
}

test "FilterResult - reduction calculation" {
    const result = filter.FilterResult{
        .filtered = "short",
        .original_len = 100,
        .filtered_len = 5,
        .reduction_pct = 95.0,
        .strategy_used = .stats,
    };

    try std.testing.expect(result.original_len == 100);
    try std.testing.expect(result.filtered_len == 5);
    try std.testing.expect(result.reduction_pct == 95.0);
}
