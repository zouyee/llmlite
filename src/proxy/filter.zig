//! Response Filter for llmlite Proxy
//!
//! Provides intelligent filtering and compression of LLM responses
//! Inspired by RTK's 12 filtering strategies for 60-90% token reduction
//!
//! Filter strategies:
//! 1. Stats Extraction - Aggregate and summarize
//! 2. Error Only - Extract errors/warnings
//! 3. Grouping - Group by pattern
//! 4. Deduplication - Remove duplicates with counts
//! 5. Structure Only - Keep schema, strip values
//! 6. Code Filtering - Strip comments/bodies
//! 7. Failure Focus - Show failures only
//! 8. Tree Compression - Directory tree format
//! 9. Progress Stripping - Remove progress bars
//! 10. Json Dual Mode - JSON when available
//! 11. State Machine - Track state for parsing
//! 12. Ndjson Streaming - Line-by-line JSON

const std = @import("std");

pub const FilterStrategy = enum {
    none, // No filtering
    stats, // Stats extraction
    errors_only, // Errors/warnings only
    grouping, // Group by pattern
    deduplication, // Remove duplicates
    structure_only, // Schema only
    code_filter, // Code filtering
    failure_focus, // Failures only
    tree_compression, // Directory tree
    progress_strip, // Remove progress
    json_dual, // JSON/text dual
    state_machine, // State machine parsing
    ndjson_stream, // NDJSON streaming
    ultra_compact, // ASCII icons for maximum compression
};

pub const FilterLevel = enum {
    none, // No filtering
    minimal, // Light filtering (~20-40% reduction)
    standard, // Standard filtering (~50-70% reduction)
    aggressive, // Heavy filtering (~70-90% reduction)
};

pub const FilterConfig = struct {
    strategy: FilterStrategy = .none,
    level: FilterLevel = .standard,
};

pub const FilterResult = struct {
    filtered: []const u8,
    original_len: usize,
    filtered_len: usize,
    reduction_pct: f64,
    strategy_used: FilterStrategy,
};

/// Main filter function - applies the configured strategy
pub fn filter(
    allocator: std.mem.Allocator,
    input: []const u8,
    config: FilterConfig,
) !FilterResult {
    const original_len = input.len;

    const filtered = switch (config.strategy) {
        .none => try allocator.dupe(u8, input),
        .stats => try filterStats(allocator, input, config.level),
        .errors_only => try filterErrorsOnly(allocator, input),
        .grouping => try filterGrouping(allocator, input),
        .deduplication => try filterDeduplication(allocator, input),
        .structure_only => try filterStructureOnly(allocator, input),
        .code_filter => try filterCode(allocator, input, config.level),
        .failure_focus => try filterFailureFocus(allocator, input),
        .tree_compression => try filterTreeCompression(allocator, input),
        .progress_strip => try filterProgressStrip(allocator, input),
        .json_dual => try filterJsonDual(allocator, input),
        .state_machine => try filterStateMachine(allocator, input),
        .ndjson_stream => try filterNdjsonStream(allocator, input),
        .ultra_compact => try filterUltraCompact(allocator, input),
    };

    const filtered_len = filtered.len;
    const reduction_pct = if (original_len > 0)
        @as(f64, @floatFromInt(original_len - filtered_len)) / @as(f64, @floatFromInt(original_len)) * 100.0
    else
        0.0;

    return .{
        .filtered = filtered,
        .original_len = original_len,
        .filtered_len = filtered_len,
        .reduction_pct = reduction_pct,
        .strategy_used = config.strategy,
    };
}

// ============ Strategy 1: Stats Extraction ============

fn filterStats(allocator: std.mem.Allocator, input: []const u8, _: FilterLevel) ![]const u8 {
    // Try to extract useful stats from the output
    var result = std.array_list.Managed(u8).init(allocator);

    // Count lines
    const lines = std.mem.splitScalar(u8, input, '\n');
    const line_count = lines.count();

    // Look for common patterns
    var error_count: usize = 0;
    var warning_count: usize = 0;
    var pass_count: usize = 0;
    var fail_count: usize = 0;

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        if (std.mem.indexOf(u8, line, "error") != null or std.mem.indexOf(u8, line, "ERROR") != null or std.mem.indexOf(u8, line, "Error") != null) {
            error_count += 1;
        }
        if (std.mem.indexOf(u8, line, "warning") != null or std.mem.indexOf(u8, line, "WARNING") != null or std.mem.indexOf(u8, line, "Warn") != null) {
            warning_count += 1;
        }
        if (std.mem.indexOf(u8, line, "PASS") != null or std.mem.indexOf(u8, line, "ok") != null) {
            pass_count += 1;
        }
        if (std.mem.indexOf(u8, line, "FAIL") != null or std.mem.indexOf(u8, line, "failed") != null) {
            fail_count += 1;
        }
    }

    try std.fmt.format(&result, "{} lines", .{line_count});
    if (error_count > 0) try std.fmt.format(&result, ", {d} errors", .{error_count});
    if (warning_count > 0) try std.fmt.format(&result, ", {d} warnings", .{warning_count});
    if (pass_count > 0) try std.fmt.format(&result, ", {d} passed", .{pass_count});
    if (fail_count > 0) try std.fmt.format(&result, ", {d} failed", .{fail_count});

    return result.toOwnedSlice();
}

// ============ Strategy 2: Error Only ============

fn filterErrorsOnly(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var found_errors = false;

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0) continue;

        // Check for error indicators
        const is_error = std.mem.indexOf(u8, trimmed, "error") != null or
            std.mem.indexOf(u8, trimmed, "Error") != null or
            std.mem.indexOf(u8, trimmed, "ERROR") != null or
            std.mem.indexOf(u8, trimmed, "failed") != null or
            std.mem.indexOf(u8, trimmed, "FAILED") != null or
            std.mem.indexOf(u8, trimmed, "Exception") != null or
            std.mem.indexOf(u8, trimmed, "Traceback") != null;

        if (is_error) {
            if (!found_errors) {
                found_errors = true;
            } else {
                try result.append('\n');
            }
            try result.appendSlice(trimmed);
        }
    }

    if (!found_errors) {
        return allocator.dupe(u8, "(no errors)");
    }

    return result.toOwnedSlice();
}

// ============ Strategy 3: Grouping ============

fn filterGrouping(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var groups = std.StringArrayHashMap(usize).init(allocator);
    defer groups.deinit();

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0) continue;

        // Try to extract a group key (e.g., rule name, file path, error code)
        var key: []const u8 = trimmed;

        // Check for common patterns
        if (std.mem.indexOf(u8, trimmed, ":")) |idx| {
            key = trimmed[0..idx];
        } else if (std.mem.indexOf(u8, trimmed, " ")) |idx| {
            key = trimmed[0..idx];
        }

        // Normalize key
        key = std.mem.trim(u8, key, "[]:");

        if (key.len > 0) {
            const count = groups.get(key) orelse 0;
            try groups.put(try allocator.dupe(u8, key), count + 1);
        }
    }

    var result = std.array_list.Managed(u8).init(allocator);
    var sorted = std.array_list.Managed(struct { key: []const u8, count: usize }).init(allocator);
    defer sorted.deinit();

    var it = groups.iterator();
    while (it.next()) |entry| {
        try sorted.append(.{ .key = entry.key_ptr.*, .count = entry.value_ptr.* });
    }

    // Sort by count descending
    std.sort.heap(struct { key: []const u8, count: usize }, sorted.items, {}, struct {
        fn less(_: void, a: struct { key: []const u8, count: usize }, b: struct { key: []const u8, count: usize }) bool {
            return a.count > b.count;
        }
    }.less);

    for (sorted.items[0..@min(10, sorted.items.len)], 0..) |item, i| {
        if (i > 0) try result.appendSlice(", ");
        try std.fmt.format(&result, "{s}: {d}", .{ item.key, item.count });
    }

    return result.toOwnedSlice();
}

// ============ Strategy 4: Deduplication ============

fn filterDeduplication(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var lines = std.array_list.Managed(struct { text: []const u8, count: usize }).init(allocator);
    defer lines.deinit();

    var seen = std.StringArrayHashMap(usize).init(allocator);
    defer seen.deinit();

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        if (seen.get(trimmed)) |idx| {
            lines.items[idx].count += 1;
        } else {
            try seen.put(try allocator.dupe(u8, trimmed), lines.items.len);
            try lines.append(.{ .text = trimmed, .count = 1 });
        }
    }

    var result = std.array_list.Managed(u8).init(allocator);
    for (lines.items, 0..) |item, i| {
        if (i > 0) try result.append('\n');
        if (item.count > 1) {
            try std.fmt.format(&result, "{s} (x{d})", .{ item.text, item.count });
        } else {
            try result.appendSlice(item.text);
        }
    }

    return result.toOwnedSlice();
}

// ============ Strategy 5: Structure Only ============

fn filterStructureOnly(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    // Try to parse as JSON and extract structure
    if (std.json.parseFromSlice(std.json.Value, allocator, input, .{})) |parsed| {
        defer parsed.deinit();
        return extractJsonStructure(allocator, parsed.value);
    } else |_| {
        // Not JSON, just extract key lines
        return filterGrouping(allocator, input);
    }
}

fn extractJsonStructure(allocator: std.mem.Allocator, value: std.json.Value) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    try extractJsonStructureInner(&result, value, 0);
    return result.toOwnedSlice();
}

fn extractJsonStructureInner(result: *std.array_list.Managed(u8), value: std.json.Value, depth: usize) !void {
    const indent = "  ";

    switch (value) {
        .null => try result.appendSlice("null"),
        .bool => try result.appendSlice("boolean"),
        .integer => try result.appendSlice("integer"),
        .float => try result.appendSlice("number"),
        .number_string => try result.appendSlice("number"),
        .string => {
            try result.appendSlice("string");
        },
        .array => |arr| {
            if (arr.items.len == 0) {
                try result.appendSlice("[]");
            } else if (arr.items.len <= 3) {
                try result.appendSlice("[");
                for (arr.items, 0..) |item, i| {
                    if (i > 0) try result.appendSlice(", ");
                    try extractJsonStructureInner(result, item, depth + 1);
                }
                try result.appendSlice("]");
            } else {
                try result.appendSlice("[");
                try extractJsonStructureInner(result, arr.items[0], depth + 1);
                try result.appendSlice(", ... ({d} items)", .{arr.items.len});
                try result.appendSlice("]");
            }
        },
        .object => |obj| {
            if (obj.count() == 0) {
                try result.appendSlice("{}");
            } else {
                try result.appendSlice("{");
                var first = true;
                var count: usize = 0;
                var it = obj.iterator();
                while (it.next()) |entry| {
                    if (first) {
                        first = false;
                    } else {
                        try result.appendSlice(", ");
                    }
                    if (count >= 5) {
                        try result.appendSlice("... ({d} more)", .{obj.count() - count});
                        break;
                    }
                    try result.appendSlice("\n");
                    try result.appendSlice(indent[0..@min(indent.len, depth + 1)]);
                    try result.appendFormat("\"{s}\": ", .{entry.key_ptr.*});
                    try extractJsonStructureInner(result, entry.value_ptr.*, depth + 1);
                    count += 1;
                }
                try result.appendSlice("\n}");
            }
        },
    }
}

// ============ Strategy 6: Code Filtering ============

pub const CodeFilterLevel = enum {
    none,
    minimal,
    aggressive,
};

fn filterCode(allocator: std.mem.Allocator, input: []const u8, level: FilterLevel) ![]const u8 {
    // Detect language and apply appropriate filtering
    // For now, apply based on level
    switch (level) {
        .none => return allocator.dupe(u8, input),
        .minimal => return stripComments(allocator, input),
        .standard => return stripCommentsAndEmptyLines(allocator, input),
        .aggressive => return stripFunctionBodies(allocator, input),
    }
}

fn stripComments(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var i: usize = 0;

    while (i < input.len) {
        if (i + 1 < input.len and input[i] == '/' and input[i + 1] == '/') {
            // Line comment - skip to end of line
            while (i < input.len and input[i] != '\n') i += 1;
        } else if (i + 1 < input.len and input[i] == '/' and input[i + 1] == '*') {
            // Block comment
            i += 2;
            while (i + 1 < input.len and (input[i] != '*' or input[i + 1] != '/')) i += 1;
            i += 2; // Skip */
        } else {
            try result.append(input[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

fn stripCommentsAndEmptyLines(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var i: usize = 0;
    var last_was_newline = false;

    while (i < input.len) {
        if (i + 1 < input.len and input[i] == '/' and input[i + 1] == '/') {
            // Line comment - skip to end of line
            while (i < input.len and input[i] != '\n') i += 1;
            last_was_newline = true;
        } else if (i + 1 < input.len and input[i] == '/' and input[i + 1] == '*') {
            // Block comment
            i += 2;
            while (i + 1 < input.len and (input[i] != '*' or input[i + 1] != '/')) i += 1;
            i += 2;
            last_was_newline = true;
        } else {
            if (input[i] == '\n') {
                if (!last_was_newline) {
                    try result.append('\n');
                }
                last_was_newline = true;
            } else if (last_was_newline) {
                last_was_newline = false;
            }
            if (!last_was_newline or input[i] != '\n') {
                try result.append(input[i]);
            }
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

fn stripFunctionBodies(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    // Simplified - just show function signatures
    var result = std.array_list.Managed(u8).init(allocator);
    var i: usize = 0;
    var in_block: usize = 0;
    var last_was_newline = false;

    while (i < input.len) {
        const c = input[i];

        if (c == '{') {
            in_block += 1;
            if (in_block == 1) {
                // End of function signature
                if (!last_was_newline) try result.append('\n');
                try result.appendSlice("{ ... }");
                // Skip to end of block
                var depth: usize = 1;
                i += 1;
                while (i < input.len and depth > 0) {
                    if (input[i] == '{') depth += 1;
                    if (input[i] == '}') depth -= 1;
                    i += 1;
                }
                last_was_newline = true;
                continue;
            }
        } else if (c == '}') {
            if (in_block > 0) in_block -= 1;
        } else if (c == '\n') {
            if (!last_was_newline) {
                try result.append('\n');
            }
            last_was_newline = true;
            i += 1;
            continue;
        } else if (last_was_newline) {
            last_was_newline = false;
        }

        if (in_block == 0) {
            try result.append(c);
        }
        i += 1;
    }

    return result.toOwnedSlice();
}

// ============ Strategy 7: Failure Focus ============

fn filterFailureFocus(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var found_failure = false;
    var in_failure_detail = false;

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Check if this is a failure line
        const is_failure = std.mem.indexOf(u8, trimmed, "FAIL") != null or
            std.mem.indexOf(u8, trimmed, "failed") != null or
            std.mem.indexOf(u8, trimmed, "FAILED") != null or
            std.mem.indexOf(u8, trimmed, "AssertionError") != null or
            std.mem.indexOf(u8, trimmed, "Error:") != null;

        // Check for test failure pattern
        const is_test_fail = std.mem.startsWith(u8, trimmed, "test ") and
            (std.mem.indexOf(u8, trimmed, " FAILED") != null or std.mem.indexOf(u8, trimmed, " failed") != null);

        if (is_failure or is_test_fail) {
            if (found_failure) try result.append('\n');
            found_failure = true;
            try result.appendSlice(trimmed);
            in_failure_detail = true;
        } else if (in_failure_detail and (trimmed.len == 0 or trimmed[0] == ' ' or trimmed[0] == '\t')) {
            // Continuation of failure detail
            try result.append('\n');
            try result.appendSlice(trimmed);
        } else {
            in_failure_detail = false;
        }
    }

    if (!found_failure) {
        return allocator.dupe(u8, "(all tests passed)");
    }

    return result.toOwnedSlice();
}

// ============ Strategy 8: Tree Compression ============

fn filterTreeCompression(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var lines = std.array_list.Managed([]const u8).init(allocator);
    defer lines.deinit();

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len > 0) {
            try lines.append(trimmed);
        }
    }

    // Simple tree building - group by directory prefix
    var dir_counts = std.StringArrayHashMap(usize).init(allocator);
    defer dir_counts.freeEntries();

    for (lines.items) |line| {
        // Extract directory part
        var last_slash: ?usize = null;
        for (line, 0..) |c, idx| {
            if (c == '/') last_slash = idx;
        }

        const dir = if (last_slash) |idx| line[0..idx] else ".";
        const count = dir_counts.get(dir) orelse 0;
        try dir_counts.put(dir, count + 1);
    }

    // Output as tree
    var it = dir_counts.iterator();
    while (it.next()) |entry| {
        try std.fmt.format(&result, "{s}/ ({d} items)\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    return result.toOwnedSlice();
}

// ============ Strategy 9: Progress Stripping ============

fn filterProgressStrip(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var i: usize = 0;

    while (i < input.len) {
        // Check for ANSI escape sequences
        if (input[i] == '\x1b') {
            // Skip ANSI escape sequence
            i += 1;
            while (i < input.len and input[i] != 'm' and input[i] != 'A' and input[i] != 'B' and input[i] != 'C' and input[i] != 'D') {
                i += 1;
            }
            i += 1;
            continue;
        }

        // Check for progress bar patterns like "[=====>    ]" or "  50%"
        const remaining = input[i..];
        if (remaining.len > 10) {
            // Skip lines that are just progress
            var is_progress = true;
            var j: usize = 0;
            while (j < remaining.len and j < 50) : (j += 1) {
                const c = remaining[j];
                if (c == '\n') break;
                if (c != '=' and c != '>' and c != ' ' and c != '[' and c != ']' and c != '%' and !std.ascii.isDigit(c)) {
                    is_progress = false;
                    break;
                }
            }
            if (is_progress) {
                // Skip this line
                while (i < input.len and input[i] != '\n') i += 1;
                continue;
            }
        }

        try result.append(input[i]);
        i += 1;
    }

    return result.toOwnedSlice();
}

// ============ Strategy 10: JSON Dual Mode ============

fn filterJsonDual(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    // Try to parse as JSON first
    if (std.json.parseFromSlice(std.json.Value, allocator, input, .{})) |parsed| {
        defer parsed.deinit();

        // Format as compact JSON
        return std.json.Stringify.valueAlloc(allocator, parsed.value, .{ .whitespace = .indent_tab });
    } else |_| {
        // Not JSON, return as-is
        return allocator.dupe(u8, input);
    }
}

// ============ Strategy 11: State Machine ============

fn filterStateMachine(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var state: enum { idle, running, passed, failed, summary } = .idle;
    var passed_count: usize = 0;
    var failed_count: usize = 0;
    var failed_tests = std.array_list.Managed([]const u8).init(allocator);
    defer failed_tests.deinit();

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Simple state machine for test output
        if (std.mem.indexOf(u8, trimmed, "running") != null) {
            state = .running;
        } else if (std.mem.indexOf(u8, trimmed, "PASS") != null or std.mem.indexOf(u8, trimmed, "ok") != null) {
            state = .passed;
            passed_count += 1;
        } else if (std.mem.indexOf(u8, trimmed, "FAIL") != null or std.mem.indexOf(u8, trimmed, "failed") != null) {
            state = .failed;
            failed_count += 1;
            if (trimmed.len < 100) {
                try failed_tests.append(trimmed);
            }
        } else if (std.mem.indexOf(u8, trimmed, "Test") != null and std.mem.indexOf(u8, trimmed, "...") != null) {
            state = .running;
        }
    }

    // Output summary
    if (failed_count > 0) {
        try std.fmt.format(&result, "FAILED: {d}/{d} tests\n", .{ failed_count, passed_count + failed_count });
        for (failed_tests.items) |t| {
            try std.fmt.format(&result, "  - {s}\n", .{t});
        }
    } else if (passed_count > 0) {
        try std.fmt.format(&result, "ok: {d} tests passed", .{passed_count});
    } else {
        return allocator.dupe(u8, input);
    }

    return result.toOwnedSlice();
}

// ============ Strategy 12: NDJSON Streaming ============

fn filterNdjsonStream(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var events = std.array_list.Managed(struct { action: []const u8, package: []const u8, test_name: []const u8 }).init(allocator);
    defer events.deinit();

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Try to parse as NDJSON (newline-delimited JSON)
        if (std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{})) |parsed| {
            defer parsed.deinit();

            // Extract fields
            if (parsed.value == .object) {
                const obj = parsed.value.object;

                const action = obj.get("Action") orelse obj.get("action");
                const package = obj.get("Package") orelse obj.get("package");
                const test_val = obj.get("Test") orelse obj.get("test");

                if (action != null) {
                    const action_str = if (action.? == .string) action.?.string else "";
                    const package_str = if (package != null and package.? == .string) package.?.string else "";
                    const test_str = if (test_val != null and test_val.? == .string) test_val.?.string else "";

                    try events.append(.{ .action = action_str, .package = package_str, .test_name = test_str });
                }
            }
        }
    }

    // Aggregate and summarize
    var pass_count: usize = 0;
    var fail_count: usize = 0;
    var fail_list = std.array_list.Managed([]const u8).init(allocator);
    defer fail_list.deinit();

    for (events.items) |event| {
        if (std.mem.eql(u8, event.action, "fail")) {
            fail_count += 1;
            if (event.test_name.len > 0) {
                try fail_list.append(event.test_name);
            }
        } else if (std.mem.eql(u8, event.action, "pass") or std.mem.eql(u8, event.action, "ok")) {
            pass_count += 1;
        }
    }

    if (fail_count > 0) {
        try std.fmt.format(&result, "FAILED: {d} tests\n", .{fail_count});
        for (fail_list.items[0..@min(5, fail_list.items.len)]) |t| {
            try std.fmt.format(&result, "  - {s}\n", .{t});
        }
    } else {
        try std.fmt.format(&result, "ok: {d} tests passed", .{pass_count});
    }

    return result.toOwnedSlice();
}

// ============ Strategy 13: Ultra-Compact (ASCII Icons) ============

/// Ultra-compact filtering using ASCII icons for maximum compression
/// Uses single characters to represent common patterns: ✓ ✗ ⚠ → ↓ ↑ 💾 📁 etc.
fn filterUltraCompact(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var line_iter = std.mem.splitScalar(u8, input, '\n');
    var has_content = false;

    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Check for pass/success
        if (std.mem.indexOf(u8, trimmed, "PASS") != null or
            std.mem.indexOf(u8, trimmed, "passed") != null or
            std.mem.indexOf(u8, trimmed, "success") != null)
        {
            try result.appendSlice(allocator, "✓ ");
            has_content = true;
            continue;
        }

        // Check for fail/error
        if (std.mem.indexOf(u8, trimmed, "FAIL") != null or
            std.mem.indexOf(u8, trimmed, "failed") != null or
            std.mem.indexOf(u8, trimmed, "error") != null or
            std.mem.indexOf(u8, trimmed, "Error") != null)
        {
            try result.appendSlice(allocator, "✗ ");
            has_content = true;
            // Append truncated error message
            if (trimmed.len > 60) {
                try result.appendSlice(allocator, trimmed[0..60]);
                try result.appendSlice(allocator, "...");
            } else {
                try result.appendSlice(allocator, trimmed);
            }
            try result.append(allocator, '\n');
            continue;
        }

        // Check for warning
        if (std.mem.indexOf(u8, trimmed, "warning") != null or
            std.mem.indexOf(u8, trimmed, "WARN") != null)
        {
            try result.appendSlice(allocator, "⚠ ");
            has_content = true;
            if (trimmed.len > 60) {
                try result.appendSlice(allocator, trimmed[0..60]);
                try result.appendSlice(allocator, "...");
            } else {
                try result.appendSlice(allocator, trimmed);
            }
            try result.append(allocator, '\n');
            continue;
        }

        // Check for file path
        if (std.mem.indexOf(u8, trimmed, "/") != null and trimmed.len > 10) {
            // Extract filename from path
            if (std.mem.lastIndexOfScalar(u8, trimmed, '/')) |idx| {
                try result.appendSlice(allocator, "📁 ");
                try result.appendSlice(allocator, trimmed[idx + 1 ..]);
                try result.append(allocator, '\n');
                has_content = true;
                continue;
            }
        }

        // Check for numbers/stats (lines, bytes, etc.)
        if (trimmed.len < 80) {
            // Could be a stat line - keep it
            try result.appendSlice(allocator, "→ ");
            try result.appendSlice(allocator, trimmed);
            try result.append(allocator, '\n');
            has_content = true;
            continue;
        }

        // Skip long lines
    }

    if (!has_content) {
        return allocator.dupe(u8, "○ no output");
    }

    return result.toOwnedSlice();
}

// ============ Auto-Detection ============

/// Auto-detect the best filter strategy based on content
pub fn autoDetectStrategy(input: []const u8) FilterStrategy {
    // Check for JSON
    if (std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, input, .{})) |_| {
        return .json_dual;
    } else |_| {}

    // Check for NDJSON (multiple JSON lines)
    var json_line_count: usize = 0;
    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len > 0 and trimmed[0] == '{') {
            json_line_count += 1;
        }
    }
    if (json_line_count > 2) {
        return .ndjson_stream;
    }

    // Check for error patterns
    if (std.mem.indexOf(u8, input, "error") != null or
        std.mem.indexOf(u8, input, "Error") != null or
        std.mem.indexOf(u8, input, "ERROR") != null or
        std.mem.indexOf(u8, input, "failed") != null)
    {
        return .errors_only;
    }

    // Check for test output
    if (std.mem.indexOf(u8, input, "PASS") != null or
        std.mem.indexOf(u8, input, "FAIL") != null or
        std.mem.indexOf(u8, input, "test ") != null)
    {
        return .failure_focus;
    }

    // Check for progress bars
    if (std.mem.indexOf(u8, input, "=") != null and std.mem.indexOf(u8, input, "%") != null) {
        return .progress_strip;
    }

    // Default
    return .stats;
}
