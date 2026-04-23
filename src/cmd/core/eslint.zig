//! ESLint - JavaScript/TypeScript Linter
//!
//! Filters ESLint JSON output for compact representation.
//! Inspired by RTK patterns.
//!
//! ## Token Savings
//!
//! eslint: ~500 lines → ~50 lines (90% reduction)

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
const json = @import("cmd_core_json");

/// Filter ESLint output
pub fn filterEslint(output: []const u8) []const u8 {
    // Check for JSON format
    if (output.len > 0 and output[0] == '[') {
        return filterEslintJson(output);
    }

    return filterEslintText(output);
}

/// Filter ESLint JSON output
fn filterEslintJson(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Parse JSON array
    var start: usize = 0;
    var end: usize = output.len;

    for (output, 0..) |c, i| {
        if (c == '[') {
            start = i + 1;
            break;
        }
    }
    for (output, start..) |c, i| {
        if (c == ']') {
            end = start + i;
            break;
        }
    }

    var files = StringArrayHashMap(usize).init(std.heap.page_allocator);
    defer files.deinit();

    var errors = std.array_list.Managed(struct {
        file: []const u8,
        line: usize,
        message: []const u8,
        rule: []const u8,
    }).init(std.heap.page_allocator);
    defer errors.deinit();

    var pos = start;
    while (pos < end) {
        while (pos < end and output[pos] != '{') pos += 1;
        if (pos >= end) break;

        var depth: usize = 0;
        var obj_end = pos;
        for (pos..end) |i| {
            if (output[i] == '{') depth += 1 else if (output[i] == '}') {
                depth -= 1;
                if (depth == 0) {
                    obj_end = i + 1;
                    break;
                }
            }
        }

        const obj_text = output[pos..obj_end];
        const file = json.extractString(obj_text, "filePath") orelse json.extractString(obj_text, "filename") orelse "???";
        const line = json.extractInteger(obj_text, "line") orelse 0;
        const message = json.extractString(obj_text, "message") orelse "";
        const rule = json.extractString(obj_text, "ruleId") orelse "";

        const entry = files.getOrPut(file) catch continue;
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }

        if (errors.items.len < 20) {
            errors.append(.{
                .file = file,
                .line = @intCast(line),
                .message = message,
                .rule = rule,
            }) catch {};
        }

        pos = obj_end + 1;
    }

    if (files.count() == 0) {
        return "eslint: No issues found";
    }

    // Calculate totals
    var total_issues: usize = 0;
    var it = files.iterator();
    while (it.next()) |entry| {
        total_issues += entry.value_ptr.*;
    }

    result.print( "eslint: {d} issues in {d} files\n", .{ total_issues, files.count() }) catch return "";
    result.appendSlice("═══════════════════════════════════════\n") catch return "";

    // Show top files
    var shown: usize = 0;
    it = files.iterator();
    while (it.next()) |entry| {
        if (shown >= 10) break;
        result.print( "{d}: {s}\n", .{ entry.value_ptr.*, entry.key_ptr.* }) catch return {};
        shown += 1;
    }

    return result.toOwnedSlice() catch "";
}

/// Filter ESLint text output
fn filterEslintText(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 50) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Skip summary
        if (std.mem.containsAtLeast(u8, trimmed, 1, "✗") or
            std.mem.containsAtLeast(u8, trimmed, 1, "✓"))
        {
            result.appendSlice(trimmed[0..@min(100, trimmed.len)]) catch {};
            result.append('\n') catch {};
            count += 1;
        }
    }

    if (result.items.len == 0) {
        return "eslint: No issues";
    }

    return result.toOwnedSlice() catch "";
}

/// Run ESLint with filtering
pub fn runEslint(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("eslint");

    // Add --format json if not present
    var has_format = false;
    for (args) |arg| {
        if (std.mem.containsAtLeast(u8, arg, 1, "--format")) has_format = true;
        try cmd_args.append(arg);
    }

    if (!has_format) {
        try cmd_args.append("--format=json");
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "eslint", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
        .filter_fn = filterEslint,
    });
}
