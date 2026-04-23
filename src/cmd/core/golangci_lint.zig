//! Golangci-lint - Go Linter with JSON Output
//!
//! Filters golangci-lint output with JSON support.
//! Inspired by RTK's golangci_cmd.rs.
//!
//! ## Token Savings
//!
//! golangci-lint run: ~500 lines → ~30 lines (94% reduction)

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

/// Golangci-lint diagnostic from JSON
pub const GolangciDiagnostic = struct {
    from_linter: []const u8,
    message: []const u8,
    file: []const u8,
    line: usize,
    column: usize,
    severity: []const u8,
};

/// Filter golangci-lint JSON output
pub fn filterGolangciLint(output: []const u8) []const u8 {
    // Check if JSON output
    if (std.mem.containsAtLeast(u8, output, 1, "{\"FromLinter\":")) {
        return filterGolangciLintJson(output);
    }

    // Text output fallback
    return filterGolangciLintText(output);
}

/// Filter golangci-lint JSON output
fn filterGolangciLintJson(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var diagnostics = std.array_list.Managed(GolangciDiagnostic).init(std.heap.page_allocator);
    defer diagnostics.deinit();

    // Parse each line as JSON object
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] != '{') continue;

        const from_linter = json.extractString(trimmed, "FromLinter") orelse continue;
        const message = json.extractString(trimmed, "Message") orelse "";
        const file = json.extractString(trimmed, "File") orelse "???";
        const line_num = json.extractInteger(trimmed, "Line") orelse 0;
        const column = json.extractInteger(trimmed, "Column") orelse 0;
        const severity = json.extractString(trimmed, "Severity") orelse "error";

        diagnostics.append(.{
            .from_linter = from_linter,
            .message = message,
            .file = file,
            .line = @intCast(line_num),
            .column = @intCast(column),
            .severity = severity,
        }) catch {};
    }

    if (diagnostics.items.len == 0) {
        return "golangci-lint: No issues found";
    }

    // Group by file
    var files = StringArrayHashMap(std.array_list.Managed(usize)).init(std.heap.page_allocator);
    defer {
        var it = files.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        files.deinit();
    }

    for (diagnostics.items, 0..) |d, idx| {
        var file_diagnostics = files.getOrPut(d.file) catch continue;
        if (file_diagnostics.found_existing) {
            file_diagnostics.value_ptr.append(idx) catch {};
        } else {
            var list = std.array_list.Managed(usize).init(std.heap.page_allocator);
            list.append(idx) catch {};
            file_diagnostics.value_ptr.* = list;
        }
    }

    // Build output
    const total = diagnostics.items.len;
    const file_count = files.count();

    result.print( "golangci-lint: {d} issues in {d} files\n", .{ total, file_count }) catch return "";
    result.appendSlice("═══════════════════════════════════════\n") catch return "";

    // Show top 5 files
    var shown_files: usize = 0;
    var file_it = files.iterator();
    while (file_it.next()) |entry| {
        if (shown_files >= 5) break;

        result.print( "{d}: {s}\n", .{ entry.value_ptr.items.len, entry.key_ptr.* }) catch return "";

        // Show up to 3 issues per file
        const show_count = @min(3, entry.value_ptr.items.len);
        for (entry.value_ptr.items[0..show_count]) |diag_idx| {
            const d = diagnostics.items[diag_idx];
            result.print( "  {s}:{d}:{d} {s} [{s}]\n", .{
                d.file,
                d.line,
                d.column,
                d.message,
                d.from_linter,
            }) catch return "";
        }

        if (entry.value_ptr.items.len > 3) {
            result.print( "  ... +{d} more\n", .{entry.value_ptr.items.len - 3}) catch return "";
        }

        shown_files += 1;
    }

    if (file_count > 5) {
        result.print( "... +{d} more files\n", .{file_count - 5}) catch return "";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter golangci-lint text output
fn filterGolangciLintText(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 20) {
            result.print( "\n... +{d} more lines", .{(std.mem.count(u8, output, &.{'\n'}) - 20)}) catch return "";
            break;
        }

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Skip noise lines
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Loading")) continue;
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Makefile")) continue;
        if (std.mem.containsAtLeast(u8, trimmed, 1, "go:")) continue;
        if (std.mem.containsAtLeast(u8, trimmed, 1, " level=warning")) continue;

        result.appendSlice(trimmed) catch {};
        result.append('\n') catch {};
        count += 1;
    }

    if (result.items.len == 0) {
        return "golangci-lint: No issues found";
    }

    return result.toOwnedSlice() catch "";
}

/// Run golangci-lint with filtering
pub fn runGolangciLint(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    // Build command - add --format=json
    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("golangci-lint");
    try cmd_args.append("run");
    try cmd_args.append("--format=json");

    for (args) |arg| {
        if (!std.mem.eql(u8, arg, "run") and !std.mem.startsWith(u8, arg, "--format=")) {
            try cmd_args.append(arg);
        }
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "golangci-lint", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
        .filter_fn = filterGolangciLint,
    });
}

test "golangci-lint filter - basic" {
    const input = "{\"FromLinter\":\"govet\",\"Message\":\"nilness\",\"File\":\"src/main.go\",\"Line\":42,\"Column\":5,\"Severity\":\"error\"}";
    const result = filterGolangciLint(input);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "1 issues"));
}
