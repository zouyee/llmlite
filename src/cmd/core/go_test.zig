//! Go Test - Go Test Output Filter
//!
//! Filters `go test` output with support for -json flag (NDJSON format).
//! Inspired by RTK's go_cmd.rs.
//!
//! ## NDJSON Format
//!
//! Each line is a separate JSON object:
//! {"Action":"run","Package":"...","Test":"TestFoo"}
//! {"Action":"output","Package":"...","Test":"TestFoo","Output":"..."}
//! {"Action":"pass","Package":"...","Test":"TestFoo","Elapsed":0.001}
//!
//! ## Token Savings
//!
//! go test: ~500 lines → ~15 lines (97% reduction)

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

/// Go test event from NDJSON (matches RTK's GoTestEvent)
pub const GoTestEvent = struct {
    action: []const u8,
    package: ?[]const u8,
    @"test": ?[]const u8,
    output: ?[]const u8,
    elapsed: ?f64,
};

/// Package test result
const PackageResult = struct {
    pass: usize = 0,
    fail: usize = 0,
    skip: usize = 0,
    build_failed: bool = false,
    failed_tests: []const []const u8,
};

/// Filter go test output
pub fn filterGoTest(output: []const u8) []const u8 {
    // Check if JSON output
    if (std.mem.containsAtLeast(u8, output, 1, "{\"Action\":")) {
        return filterGoTestJson(output);
    }

    // Text output fallback
    return filterGoTestText(output);
}

/// Filter go test -json output (NDJSON)
fn filterGoTestJson(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var packages = StringArrayHashMap(PackageResult).init(std.heap.page_allocator);
    defer packages.deinit();

    var current_test_output = StringArrayHashMap(std.array_list.Managed([]const u8)).init(std.heap.page_allocator);
    defer {
        var it = current_test_output.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        current_test_output.deinit();
    }

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0 or trimmed[0] != '{') continue;

        const event = parseGoTestEvent(trimmed) catch continue;

        const pkg_name = event.package orelse "unknown";

        // Get or create package result
        if (!packages.contains(pkg_name)) {
            packages.put(pkg_name, PackageResult{}) catch {};
        }
        var pkg_result = packages.getPtr(pkg_name).?;

        switch (event.action[0]) {
            'p' => { // pass
                if (event.@"test" != null) {
                    pkg_result.pass += 1;
                    // Clean up test output
                    _ = current_test_output.remove(pkg_name ++ "::" ++ event.@"test".?);
                }
            },
            'f' => { // fail
                if (event.@"test" != null) {
                    pkg_result.fail += 1;
                    // Get collected output
                    const key = pkg_name ++ "::" ++ event.@"test".?;
                    if (current_test_output.get(key)) |outputs| {
                        pkg_result.failed_tests = outputs.toOwnedSlice();
                    }
                }
            },
            's' => { // skip
                if (event.@"test" != null) {
                    pkg_result.skip += 1;
                }
            },
            'b' => { // build-fail
                pkg_result.build_failed = true;
            },
            'o' => { // output - collect test output
                if (event.@"test" != null and event.output != null) {
                    const key = pkg_name ++ "::" ++ event.@"test".?;
                    var outputs = current_test_output.getOrPut(key) catch continue;
                    if (outputs.found_existing) {
                        outputs.value_ptr.append(event.output.?) catch {};
                    } else {
                        outputs.value_ptr.append(event.output.?) catch {};
                    }
                }
            },
            else => {},
        }
    }

    // Build output
    if (packages.count() == 0) {
        return "go test: no packages";
    }

    var total_pass: usize = 0;
    var total_fail: usize = 0;
    var total_skip: usize = 0;

    var it = packages.iterator();
    while (it.next()) |entry| {
        const pkg_result = entry.value_ptr;
        total_pass += pkg_result.pass;
        total_fail += pkg_result.fail;
        total_skip += pkg_result.skip;
    }

    if (total_fail == 0) {
        result.print( "go test: {d} passed", .{total_pass}) catch return "";
        if (total_skip > 0) {
            result.print( ", {d} skipped", .{total_skip}) catch return "";
        }
        return result.toOwnedSlice() catch "";
    }

    // Show failures
    result.print( "go test: {d} passed, {d} failed\n", .{ total_pass, total_fail }) catch return "";
    result.print( "═══════════════════════════════════════\n", .{}) catch return "";

    var shown_packages: usize = 0;
    it = packages.iterator();
    while (it.next()) |entry| {
        if (shown_packages >= 3) break;
        const pkg_result = entry.value_ptr;

        if (pkg_result.fail > 0) {
            result.print( "FAIL {s}\n", .{entry.key_ptr.*}) catch return "";

            for (pkg_result.failed_tests[0..@min(3, pkg_result.failed_tests.len)]) |test_name| {
                result.print( "    {s}\n", .{test_name}) catch return "";
            }

            if (pkg_result.failed_tests.len > 3) {
                result.print( "    ... +{d} more\n", .{pkg_result.failed_tests.len - 3}) catch return "";
            }
            shown_packages += 1;
        }
    }

    if (packages.count() > 3) {
        result.print( "... +{d} more packages\n", .{packages.count() - 3}) catch return "";
    }

    return result.toOwnedSlice() catch "";
}

/// Parse a Go test NDJSON event
fn parseGoTestEvent(line: []const u8) !GoTestEvent {
    const action = extractJsonString(line, "Action") orelse return error.MissingAction;
    const package = extractJsonString(line, "Package");
    const test_name = extractJsonString(line, "Test");
    const output = extractJsonString(line, "Output");
    const elapsed = extractJsonFloat(line, "Elapsed");

    return GoTestEvent{
        .action = action,
        .package = package,
        .@"test" = test_name,
        .output = output,
        .elapsed = elapsed,
    };
}

/// Extract string field from JSON
fn extractJsonString(input: []const u8, field: []const u8) ?[]const u8 {
    const search = "\"" ++ field ++ "\":\"";
    const start = std.mem.find(u8, input, search) orelse return null;
    const value_start = start + search.len;
    const value_end = std.mem.find(u8, input[value_start..], "\"") orelse return null;
    return input[value_start .. value_start + value_end];
}

/// Extract float field from JSON
fn extractJsonFloat(input: []const u8, field: []const u8) ?f64 {
    const search = "\"" ++ field ++ "\":";
    const start = std.mem.find(u8, input, search) orelse return null;
    const value_start = start + search.len;

    var value_end = value_start;
    while (value_end < input.len) {
        const c = input[value_end];
        if ((c < '0' or c > '9') and c != '.') break;
        value_end += 1;
    }

    if (value_end == value_start) return null;
    return std.fmt.parseFloat(f64, input[value_start..value_end]) catch null;
}

/// Filter go test text output
fn filterGoTestText(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var pass_count: usize = 0;
    var fail_count: usize = 0;
    var in_failures = false;
    var failure_lines = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
    defer failure_lines.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        if (std.mem.startsWith(u8, trimmed, "=== RUN")) {
            continue;
        }

        if (std.mem.startsWith(u8, trimmed, "--- PASS")) {
            pass_count += 1;
        } else if (std.mem.startsWith(u8, trimmed, "--- FAIL")) {
            fail_count += 1;
            in_failures = true;
        } else if (std.mem.startsWith(u8, trimmed, "FAIL")) {
            // Parse "FAIL github.com/user/package TestFoo"
            if (std.mem.containsAtLeast(u8, trimmed, 1, "FAIL")) {
                failure_lines.append(trimmed) catch {};
            }
        } else if (std.mem.startsWith(u8, trimmed, "ok")) {
            // Summary line like "ok  github.com/user/package 0.001s"
            continue;
        } else if (in_failures and trimmed.len > 0) {
            failure_lines.append(trimmed) catch {};
        }
    }

    if (fail_count == 0) {
        result.print( "go test: {d} passed", .{pass_count}) catch return "";
        return result.toOwnedSlice() catch "";
    }

    result.print( "go test: {d} passed, {d} failed\n", .{ pass_count, fail_count }) catch return "";
    result.print( "═══════════════════════════════════════\n", .{}) catch return "";

    for (failure_lines.items[0..@min(10, failure_lines.items.len)]) |line| {
        result.appendSlice(line) catch {};
        result.append('\n') catch {};
    }

    return result.toOwnedSlice() catch "";
}

/// Filter go build output
pub fn filterGoBuild(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var error_count: usize = 0;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        if (std.mem.startsWith(u8, trimmed, "#")) {
            // Package line like "# github.com/user/package"
            result.appendSlice(trimmed) catch {};
            result.append('\n') catch {};
        } else if (std.mem.startsWith(u8, trimmed, "error:") or
            std.mem.startsWith(u8, trimmed, "undefined:") or
            std.mem.startsWith(u8, trimmed, "cannot find"))
        {
            result.appendSlice(trimmed) catch {};
            result.append('\n') catch {};
            error_count += 1;
        }
    }

    if (error_count == 0) {
        return "go build: ok";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter go vet output
pub fn filterGoVet(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Skip ok lines
        if (std.mem.startsWith(u8, trimmed, "ok") or std.mem.startsWith(u8, trimmed, "PASS")) {
            continue;
        }

        if (trimmed.len > 0) {
            result.appendSlice(trimmed) catch {};
            result.append('\n') catch {};
        }
    }

    if (result.items.len == 0) {
        return "go vet: ok";
    }

    return result.toOwnedSlice() catch "";
}

/// Run go test with filtering
pub fn runGoTest(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    // Build command - always use -json for structured output
    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("go");
    try cmd_args.append("test");

    // Add -json if not present
    var has_json = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-json")) has_json = true;
        try cmd_args.append(arg);
    }

    if (!has_json) {
        try cmd_args.append("-json");
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "go test", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .ndjson_stream,
        .filter_fn = filterGoTest,
    });
}

/// Run go build with filtering
pub fn runGoBuild(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("go");
    try cmd_args.append("build");

    for (args) |arg| {
        try cmd_args.append(arg);
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "go build", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
        .filter_fn = filterGoBuild,
    });
}

/// Run go vet with filtering
pub fn runGoVet(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("go");
    try cmd_args.append("vet");

    for (args) |arg| {
        try cmd_args.append(arg);
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "go vet", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
        .filter_fn = filterGoVet,
    });
}

test "go test json - pass" {
    const input = "{\"Action\":\"run\",\"Package\":\"github.com/user/pkg\",\"Test\":\"TestFoo\"}\n{\"Action\":\"pass\",\"Package\":\"github.com/user/pkg\",\"Test\":\"TestFoo\",\"Elapsed\":0.001}";
    const output = filterGoTestJson(input);
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "1 passed"));
}

test "go test json - fail" {
    const input = "{\"Action\":\"run\",\"Package\":\"github.com/user/pkg\",\"Test\":\"TestFoo\"}\n{\"Action\":\"fail\",\"Package\":\"github.com/user/pkg\",\"Test\":\"TestFoo\"}";
    const output = filterGoTestJson(input);
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "1 failed"));
}
