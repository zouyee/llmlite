//! Response Filter for llmlite-cmd
//!
//! Provides 14 filtering strategies for 60-90% token reduction

const std = @import("std");

// Zig 0.16.0 compat: managed StringArrayHashMap wrapper
fn StringArrayHashMap(comptime V: type) type {
    return struct {
        const Self = @This();
        unmanaged: std.StringArrayHashMapUnmanaged(V),
        allocator: std.mem.Allocator,
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .unmanaged = .empty, .allocator = allocator };
        }
        pub fn deinit(self: *Self) void { self.unmanaged.deinit(self.allocator); }
        pub fn put(self: *Self, key: []const u8, value: V) !void { return self.unmanaged.put(self.allocator, key, value); }
        pub fn get(self: Self, key: []const u8) ?V { return self.unmanaged.get(key); }
        pub fn getPtr(self: Self, key: []const u8) ?*V { return self.unmanaged.getPtr(key); }
        pub fn getOrPut(self: *Self, key: []const u8) !std.StringArrayHashMapUnmanaged(V).GetOrPutResult { return self.unmanaged.getOrPut(self.allocator, key); }
        pub fn getOrPutValue(self: *Self, key: []const u8, value: V) !std.StringArrayHashMapUnmanaged(V).GetOrPutResult { return self.unmanaged.getOrPutValue(self.allocator, key, value); }
        pub fn contains(self: Self, key: []const u8) bool { return self.unmanaged.contains(key); }
        pub fn count(self: Self) usize { return self.unmanaged.count(); }
        pub fn iterator(self: Self) std.StringArrayHashMapUnmanaged(V).Iterator { return self.unmanaged.iterator(); }
        pub fn fetchSwapRemove(self: *Self, key: []const u8) ?std.StringArrayHashMapUnmanaged(V).KV { return self.unmanaged.fetchSwapRemove(key); }
        pub fn fetchRemove(self: *Self, key: []const u8) ?std.StringArrayHashMapUnmanaged(V).KV { return self.unmanaged.fetchSwapRemove(key); }
        pub fn swapRemove(self: *Self, key: []const u8) bool { return self.unmanaged.swapRemove(key); }
        pub fn keys(self: Self) [][]const u8 { return self.unmanaged.keys(); }
        pub fn values(self: Self) []V { return self.unmanaged.values(); }
    };
}

pub const FilterStrategy = enum {
    none,
    stats,
    errors_only,
    grouping,
    deduplication,
    structure_only,
    code_filter,
    failure_focus,
    tree_compression,
    progress_strip,
    json_dual,
    state_machine,
    ndjson_stream,
    ultra_compact,
    git_log,
};

pub const FilterLevel = enum {
    none,
    minimal,
    standard,
    aggressive,
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

pub fn filter(
    allocator: std.mem.Allocator,
    input: []const u8,
    config: FilterConfig,
) !FilterResult {
    const original_len = input.len;

    const filtered = switch (config.strategy) {
        .none => try allocator.dupe(u8, input),
        .stats => try filterStats(allocator, input),
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
        .git_log => try filterGitLog(allocator, input),
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

fn filterStats(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);

    var line_count: usize = 0;
    var count_iter = std.mem.splitScalar(u8, input, '\n');
    while (count_iter.next()) |_| line_count += 1;

    var error_count: usize = 0;
    var warning_count: usize = 0;
    var pass_count: usize = 0;
    var fail_count: usize = 0;

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        if (std.mem.find(u8, line, "error") != null or std.mem.find(u8, line, "ERROR") != null) {
            error_count += 1;
        }
        if (std.mem.find(u8, line, "warning") != null or std.mem.find(u8, line, "WARNING") != null) {
            warning_count += 1;
        }
        if (std.mem.find(u8, line, "PASS") != null or std.mem.find(u8, line, "ok") != null) {
            pass_count += 1;
        }
        if (std.mem.find(u8, line, "FAIL") != null or std.mem.find(u8, line, "failed") != null) {
            fail_count += 1;
        }
    }

    try result.print("{} lines", .{line_count});
    if (error_count > 0) try result.print(", {d} errors", .{error_count});
    if (warning_count > 0) try result.print(", {d} warnings", .{warning_count});
    if (pass_count > 0) try result.print(", {d} passed", .{pass_count});
    if (fail_count > 0) try result.print(", {d} failed", .{fail_count});

    return result.toOwnedSlice();
}

fn filterErrorsOnly(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var found_errors = false;

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0) continue;

        const is_error = std.mem.find(u8, trimmed, "error") != null or
            std.mem.find(u8, trimmed, "Error") != null or
            std.mem.find(u8, trimmed, "ERROR") != null or
            std.mem.find(u8, trimmed, "failed") != null or
            std.mem.find(u8, trimmed, "FAILED") != null;

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

fn filterGrouping(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var groups = StringArrayHashMap(usize).init(allocator);
    defer groups.deinit();

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0) continue;

        var key = trimmed;
        if (std.mem.find(u8, trimmed, ":")) |idx| {
            key = trimmed[0..idx];
        }

        key = std.mem.trim(u8, key, "[]:");

        if (key.len > 0) {
            const count = groups.get(key) orelse 0;
            try groups.put(try allocator.dupe(u8, key), count + 1);
        }
    }

    var result = std.array_list.Managed(u8).init(allocator);
    const GroupCount = struct { key: []const u8, count: usize };
    var sorted = std.array_list.Managed(GroupCount).init(allocator);
    defer sorted.deinit();

    var it = groups.iterator();
    while (it.next()) |entry| {
        try sorted.append(.{ .key = entry.key_ptr.*, .count = entry.value_ptr.* });
    }

    std.sort.heap(GroupCount, sorted.items, {}, struct {
        fn less(_: void, a: GroupCount, b: GroupCount) bool {
            return a.count > b.count;
        }
    }.less);

    for (sorted.items[0..@min(10, sorted.items.len)], 0..) |item, i| {
        if (i > 0) try result.appendSlice(", ");
        try result.print("{s}: {d}", .{ item.key, item.count });
    }

    return result.toOwnedSlice();
}

fn filterDeduplication(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var lines = std.array_list.Managed(struct { text: []const u8, count: usize }).init(allocator);
    defer lines.deinit();

    var seen = StringArrayHashMap(usize).init(allocator);
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
            try result.print("{s} (x{d})", .{ item.text, item.count });
        } else {
            try result.appendSlice(item.text);
        }
    }

    return result.toOwnedSlice();
}

fn filterStructureOnly(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    if (std.json.parseFromSlice(std.json.Value, allocator, input, .{})) |parsed| {
        defer parsed.deinit();
        return extractJsonStructure(allocator, parsed.value);
    } else |_| {
        return filterGrouping(allocator, input);
    }
}

fn extractJsonStructure(allocator: std.mem.Allocator, value: std.json.Value) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    try extractJsonStructureInner(&result, value, 0);
    return result.toOwnedSlice();
}

fn extractJsonStructureInner(result: *std.array_list.Managed(u8), value: std.json.Value, _: usize) !void {
    switch (value) {
        .null => try result.appendSlice("null"),
        .bool => try result.appendSlice("boolean"),
        .integer, .float, .number_string => try result.appendSlice("number"),
        .string => try result.appendSlice("string"),
        .array => |arr| {
            if (arr.items.len == 0) {
                try result.appendSlice("[]");
            } else if (arr.items.len <= 3) {
                try result.appendSlice("[");
                for (arr.items, 0..) |item, i| {
                    if (i > 0) try result.appendSlice(", ");
                    try extractJsonStructureInner(result, item, 0);
                }
                try result.appendSlice("]");
            } else {
                try result.appendSlice("[");
                try extractJsonStructureInner(result, arr.items[0], 0);
                try result.print(", ... ({d} items)", .{arr.items.len});
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
                    if (first) first = false else try result.appendSlice(", ");
                    if (count >= 5) {
                        try result.print("... ({d} more)", .{obj.count() - count});
                        break;
                    }
                    try result.print("\"{s}\": ", .{entry.key_ptr.*});
                    try extractJsonStructureInner(result, entry.value_ptr.*, 0);
                    count += 1;
                }
                try result.appendSlice("}");
            }
        },
    }
}

fn filterCode(allocator: std.mem.Allocator, input: []const u8, level: FilterLevel) ![]const u8 {
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
            while (i < input.len and input[i] != '\n') i += 1;
        } else if (i + 1 < input.len and input[i] == '/' and input[i + 1] == '*') {
            i += 2;
            while (i + 1 < input.len and (input[i] != '*' or input[i + 1] != '/')) i += 1;
            i += 2;
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
            while (i < input.len and input[i] != '\n') i += 1;
            last_was_newline = true;
        } else if (i + 1 < input.len and input[i] == '/' and input[i + 1] == '*') {
            i += 2;
            while (i + 1 < input.len and (input[i] != '*' or input[i + 1] != '/')) i += 1;
            i += 2;
            last_was_newline = true;
        } else {
            if (input[i] == '\n') {
                if (!last_was_newline) try result.append('\n');
                last_was_newline = true;
            } else {
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
    var result = std.array_list.Managed(u8).init(allocator);
    var i: usize = 0;
    var in_block: usize = 0;
    var last_was_newline = false;

    while (i < input.len) {
        const c = input[i];

        if (c == '{') {
            in_block += 1;
            if (in_block == 1) {
                if (!last_was_newline) try result.append('\n');
                try result.appendSlice("{ ... }");
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
            if (!last_was_newline) try result.append('\n');
            last_was_newline = true;
            i += 1;
            continue;
        } else {
            last_was_newline = false;
        }

        if (in_block == 0) {
            try result.append(c);
        }
        i += 1;
    }

    return result.toOwnedSlice();
}

fn filterFailureFocus(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var found_failure = false;
    var in_failure_detail = false;

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        const is_failure = std.mem.find(u8, trimmed, "FAIL") != null or
            std.mem.find(u8, trimmed, "failed") != null or
            std.mem.find(u8, trimmed, "FAILED") != null or
            std.mem.find(u8, trimmed, "Error:") != null;

        if (is_failure) {
            if (found_failure) try result.append('\n');
            found_failure = true;
            try result.appendSlice(trimmed);
            in_failure_detail = true;
        } else if (in_failure_detail and trimmed.len > 0 and (trimmed[0] == ' ' or trimmed[0] == '\t')) {
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

    var dir_counts = StringArrayHashMap(usize).init(allocator);
    defer dir_counts.deinit();

    for (lines.items) |line| {
        var last_slash: ?usize = null;
        for (line, 0..) |c, idx| {
            if (c == '/') last_slash = idx;
        }

        const dir = if (last_slash) |idx| line[0..idx] else ".";
        const count = dir_counts.get(dir) orelse 0;
        try dir_counts.put(dir, count + 1);
    }

    var it = dir_counts.iterator();
    while (it.next()) |entry| {
        try result.print("{s}/ ({d} items)\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    return result.toOwnedSlice();
}

fn filterProgressStrip(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var i: usize = 0;

    while (i < input.len) {
        if (input[i] == '\x1b') {
            i += 1;
            while (i < input.len and input[i] != 'm') i += 1;
            i += 1;
            continue;
        }

        const remaining = input[i..];
        if (remaining.len > 10) {
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
                while (i < input.len and input[i] != '\n') i += 1;
                continue;
            }
        }

        try result.append(input[i]);
        i += 1;
    }

    return result.toOwnedSlice();
}

fn filterJsonDual(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    // In Zig 0.15+, json.stringify was removed.
    // For now, just validate JSON and return it as-is.
    if (std.json.parseFromSlice(std.json.Value, allocator, input, .{})) |parsed| {
        defer parsed.deinit();
        return allocator.dupe(u8, input);
    } else |_| {
        return allocator.dupe(u8, input);
    }
}

fn filterStateMachine(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var passed_count: usize = 0;
    var failed_count: usize = 0;
    var failed_tests = std.array_list.Managed([]const u8).init(allocator);
    defer failed_tests.deinit();

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        if (std.mem.find(u8, trimmed, "PASS") != null or std.mem.find(u8, trimmed, "ok") != null) {
            passed_count += 1;
        } else if (std.mem.find(u8, trimmed, "FAIL") != null or std.mem.find(u8, trimmed, "failed") != null) {
            failed_count += 1;
            if (trimmed.len < 100) {
                try failed_tests.append(trimmed);
            }
        }
    }

    if (failed_count > 0) {
        try result.print("FAILED: {d}/{d} tests\n", .{ failed_count, passed_count + failed_count });
        for (failed_tests.items) |t| {
            try result.print("  - {s}\n", .{t});
        }
    } else if (passed_count > 0) {
        try result.print("ok: {d} tests passed", .{passed_count});
    } else {
        return allocator.dupe(u8, input);
    }

    return result.toOwnedSlice();
}

fn filterNdjsonStream(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var events = std.array_list.Managed(struct { action: []const u8, test_name: []const u8 }).init(allocator);
    defer events.deinit();

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        if (std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{})) |parsed| {
            defer parsed.deinit();

            if (parsed.value == .object) {
                const obj = parsed.value.object;
                const action = obj.get("Action") orelse obj.get("action");
                const test_val = obj.get("Test") orelse obj.get("test");

                if (action != null and action.? == .string) {
                    const test_str = if (test_val != null and test_val.? == .string) test_val.?.string else "";
                    try events.append(.{ .action = action.?.string, .test_name = test_str });
                }
            }
        } else |_| {}
    }

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
        try result.print("FAILED: {d} tests\n", .{fail_count});
        for (fail_list.items[0..@min(5, fail_list.items.len)]) |t| {
            try result.print("  - {s}\n", .{t});
        }
    } else {
        try result.print("ok: {d} tests passed", .{pass_count});
    }

    return result.toOwnedSlice();
}

fn filterUltraCompact(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var line_iter = std.mem.splitScalar(u8, input, '\n');
    var has_content = false;

    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        if (std.mem.find(u8, trimmed, "PASS") != null or
            std.mem.find(u8, trimmed, "passed") != null or
            std.mem.find(u8, trimmed, "success") != null)
        {
            try result.appendSlice("ok ");
            has_content = true;
            continue;
        }

        if (std.mem.find(u8, trimmed, "FAIL") != null or
            std.mem.find(u8, trimmed, "failed") != null or
            std.mem.find(u8, trimmed, "error") != null or
            std.mem.find(u8, trimmed, "Error") != null)
        {
            try result.appendSlice("err ");
            has_content = true;
            if (trimmed.len > 60) {
                try result.appendSlice(trimmed[0..60]);
                try result.appendSlice("...");
            } else {
                try result.appendSlice(trimmed);
            }
            try result.append('\n');
            continue;
        }

        if (std.mem.find(u8, trimmed, "warning") != null or std.mem.find(u8, trimmed, "WARN") != null) {
            try result.appendSlice("warn ");
            has_content = true;
            if (trimmed.len > 60) {
                try result.appendSlice(trimmed[0..60]);
                try result.appendSlice("...");
            } else {
                try result.appendSlice(trimmed);
            }
            try result.append('\n');
            continue;
        }

        if (trimmed.len < 80) {
            try result.appendSlice("   ");
            try result.appendSlice(trimmed);
            try result.append('\n');
            has_content = true;
            continue;
        }
    }

    if (!has_content) {
        return allocator.dupe(u8, "no output");
    }

    return result.toOwnedSlice();
}

/// Git log filter - RTK-style compact git log output
/// Shows commit hash (short), branch, and first line of commit message
/// Input: git log output
/// Output: compact oneline format
fn filterGitLog(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var line_iter = std.mem.splitScalar(u8, input, '\n');
    var count: usize = 0;
    const max_lines: usize = 20; // Limit output to 20 commits

    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Skip merge commit lines, blank lines, and diff lines
        if (std.mem.startsWith(u8, trimmed, "Merge:")) continue;
        if (std.mem.startsWith(u8, trimmed, "commit ")) continue;
        if (std.mem.startsWith(u8, trimmed, "diff --")) continue;
        if (std.mem.startsWith(u8, trimmed, "index ")) continue;
        if (std.mem.startsWith(u8, trimmed, "---")) continue;
        if (std.mem.startsWith(u8, trimmed, "+++")) continue;

        // Parse author/date lines
        if (std.mem.startsWith(u8, trimmed, "Author:")) {
            // Skip author line, we'll show it differently
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "Date:")) {
            continue;
        }

        // This is likely a commit message line
        if (count >= max_lines) {
            if (count == max_lines) {
                try result.print("... ({d} more commits)\n", .{count});
            }
            count += 1;
            continue;
        }

        // Compact format: short hash + first line of message
        if (trimmed.len > 7) {
            try result.print("{s} | {s}\n", .{ trimmed[0..7], trimmed });
        } else {
            try result.print("{s}\n", .{trimmed});
        }
        count += 1;
    }

    if (count == 0) {
        return allocator.dupe(u8, "(no commits)");
    }

    return result.toOwnedSlice();
}

pub fn autoDetectStrategy(input: []const u8) FilterStrategy {
    if (std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, input, .{})) |_| {
        return .json_dual;
    } else |_| {}

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

    if (std.mem.find(u8, input, "error") != null or
        std.mem.find(u8, input, "Error") != null or
        std.mem.find(u8, input, "ERROR") != null or
        std.mem.find(u8, input, "failed") != null)
    {
        return .errors_only;
    }

    if (std.mem.find(u8, input, "PASS") != null or
        std.mem.find(u8, input, "FAIL") != null or
        std.mem.find(u8, input, "test ") != null)
    {
        return .failure_focus;
    }

    if (std.mem.find(u8, input, "=") != null and std.mem.find(u8, input, "%") != null) {
        return .progress_strip;
    }

    return .stats;
}
