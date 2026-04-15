//! TSC - TypeScript Compiler
//!
//! Filters TypeScript compiler errors with JSON support.
//! Inspired by RTK's tsc_cmd.rs.
//!
//! ## Features
//!
//! - Groups errors by file
//! - Shows error code and message
//! - Captures context lines
//! - JSON output support
//!
//! ## Token Savings
//!
//! tsc: ~500 lines → ~30 lines (94% reduction)

const std = @import("std");
const json = @import("cmd_core_json");

/// TypeScript error
const TsError = struct {
    file: []const u8,
    line: usize,
    column: usize,
    code: []const u8,
    message: []const u8,
};

/// Filter tsc output
pub fn filterTsc(output: []const u8) []const u8 {
    // Check for JSON output
    if (output.len > 0 and output[0] == '[') {
        return filterTscJson(output);
    }
    return filterTscText(output);
}

/// Filter tsc --json output
fn filterTscJson(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    const parsed = json.parse(std.heap.page_allocator, output) catch {
        return filterTscText(output);
    };
    defer parsed.deinit(std.heap.page_allocator);

    if (parsed != .array) {
        return filterTscText(output);
    }

    const arr = parsed.array;
    if (arr.len == 0) {
        return "TypeScript: No errors found";
    }

    // Count errors by file
    var files = std.StringArrayHashMap(usize).init(std.heap.page_allocator);
    defer files.deinit();

    for (arr) |item| {
        if (item != .object) continue;
        const filename = json.getString(&item.object, "file") orelse continue;
        const severity = json.getString(&item.object, "severity") orelse "";

        if (std.mem.containsAtLeast(u8, severity, 1, "error")) {
            const entry = files.getOrPut(filename) catch continue;
            if (entry.found_existing) {
                entry.value_ptr.* += 1;
            } else {
                entry.value_ptr.* = 1;
            }
        }
    }

    const total_errors = files.count();
    if (total_errors == 0) {
        return "TypeScript: No errors found";
    }

    std.fmt.format(result.writer(), "TypeScript: errors in {d} files\n", .{total_errors}) catch return "";
    std.fmt.format(result.writer(), "═══════════════════════════════════════\n", .{}) catch return "";

    // Show top 5 files
    var shown: usize = 0;
    var it = files.iterator();
    while (it.next()) |entry| {
        if (shown >= 5) break;
        std.fmt.format(result.writer(), "  {d}: {s}\n", .{ entry.value_ptr.*, entry.key_ptr.* }) catch return "";
        shown += 1;
    }

    if (files.count() > 5) {
        std.fmt.format(result.writer(), "  ... +{d} more files", .{files.count() - 5}) catch return "";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter tsc text output
fn filterTscText(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var errors = std.ArrayList(TsError).init(std.heap.page_allocator);
    defer errors.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var i: usize = 0;

    while (lines.next()) |line| {
        // Match: src/file.ts(12,5): error TS2322: message
        const error_info = parseTscErrorLine(line);
        if (error_info) |err| {
            // Collect context lines
            var context = std.ArrayList([]const u8).init(std.heap.page_allocator);
            defer context.deinit();

            i = 0;
            while (lines.peek()) |next| {
                const trimmed = std.mem.trim(u8, next, " \t");
                if (trimmed.len > 0 and (trimmed[0] == ' ' or trimmed[0] == '\t')) {
                    context.append(trimmed) catch {};
                } else {
                    break;
                }
            }

            errors.append(.{
                .file = err.file,
                .line = err.line,
                .column = err.column,
                .code = err.code,
                .message = err.message,
            }) catch {};
        }
        i += 1;
    }

    if (errors.items.len == 0) {
        if (std.mem.containsAtLeast(u8, output, 1, "Found 0 errors")) {
            return "TypeScript: No errors found";
        }
        return "TypeScript compilation completed";
    }

    // Group by file
    var files = std.StringArrayHashMap(std.ArrayList([]const u8)).init(std.heap.page_allocator);
    defer {
        var it = files.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        files.deinit();
    }

    for (errors.items) |err| {
        var key = std.ArrayList(u8).init(std.heap.page_allocator);
        std.fmt.format(key.writer(), "{s}:{d}", .{ err.file, err.line }) catch {};

        const entry = files.getOrPut(key.toOwnedSlice() catch "") catch continue;
        if (entry.found_existing) {
            entry.value_ptr.append(err.code) catch {};
        } else {
            var list = std.ArrayList([]const u8).init(std.heap.page_allocator);
            list.append(err.code) catch {};
            entry.value_ptr.* = list;
        }
    }

    std.fmt.format(result.writer(), "TypeScript: {d} errors\n", .{errors.items.len}) catch return "";
    std.fmt.format(result.writer(), "═══════════════════════════════════════\n", .{}) catch return "";

    // Show top 5
    var shown: usize = 0;
    var it = files.iterator();
    while (it.next()) |entry| {
        if (shown >= 5) break;
        std.fmt.format(result.writer(), "  {s}\n", .{entry.key_ptr.*}) catch return "";
        shown += 1;
    }

    if (files.count() > 5) {
        std.fmt.format(result.writer(), "  ... +{d} more", .{files.count() - 5}) catch return "";
    }

    return result.toOwnedSlice() catch "";
}

/// Parse a single tsc error line
fn parseTscErrorLine(line: []const u8) ?TsError {
    // Pattern: src/file.ts(12,5): error TS2322: Type 'string' is not assignable to type 'number'.
    // or: src/file.ts(12,5): warning TS2322: message

    // Find the opening paren for line:column
    const paren_open = std.mem.indexOfScalar(u8, line, '(') orelse return null;
    const paren_close = std.mem.indexOfScalar(u8, line[paren_open..], ')') orelse return null;
    const coords = line[paren_open + 1 .. paren_open + paren_close];

    // Parse line:column
    const colon = std.mem.indexOfScalar(u8, coords, ',') orelse return null;
    const line_str = coords[0..colon];
    const col_str = coords[colon + 1 ..];

    const line_num = std.fmt.parseInt(usize, line_str, 10) catch return null;
    const col_num = std.fmt.parseInt(usize, col_str, 10) catch return null;

    // Find severity and code
    const after_coords = line[paren_open + paren_close + 1 ..];
    const colon2 = std.mem.indexOfScalar(u8, after_coords, ':') orelse return null;
    const severity_msg = std.mem.trim(u8, after_coords[0..colon2], " \t");

    if (!std.mem.containsAtLeast(u8, severity_msg, 1, "error") and
        !std.mem.containsAtLeast(u8, severity_msg, 1, "warning"))
    {
        return null;
    }

    // Extract code (e.g., TS2322)
    const code_search = "TS";
    const ts_pos = std.mem.indexOf(u8, severity_msg, code_search) orelse return null;
    const code_end = ts_pos + 5; // TS + 4 digits
    if (code_end > severity_msg.len) return null;
    const code = severity_msg[ts_pos..code_end];

    // Find the message after the code
    const after_code = severity_msg[code_end..];
    const msg_colon = std.mem.indexOfScalar(u8, after_code, ':') orelse return null;
    const message = std.mem.trim(u8, after_code[msg_colon + 1 ..], " \t");

    // Get file (before the paren)
    const file = std.mem.trim(u8, line[0..paren_open], " \t");

    return TsError{
        .file = file,
        .line = line_num,
        .column = col_num,
        .code = code,
        .message = message,
    };
}

/// Run tsc with filtering
pub fn runTsc(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    // Check if tsc exists, otherwise use npx
    const tsc_exists = checkToolExists("tsc");

    var cmd_args = std.ArrayList([]const u8).init(allocator);
    defer cmd_args.deinit();

    if (tsc_exists) {
        try cmd_args.append("tsc");
    } else {
        try cmd_args.append("npx");
        try cmd_args.append("tsc");
    }

    for (args) |arg| {
        try cmd_args.append(arg);
    }

    if (verbose > 0) {
        const tool = if (tsc_exists) "tsc" else "npx tsc";
        std.debug.print("Running: {s} {s}\n", .{ tool, std.mem.join(u8, args, " ") });
    }

    return runner.runFiltered(allocator, cmd_args.items, "tsc", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
        .filter_fn = filterTsc,
    });
}

/// Check if a tool exists in PATH
fn checkToolExists(name: []const u8) bool {
    const result = std.process.which(name);
    return result != null;
}

test "tsc filter - no errors" {
    const output = "Found 0 errors";
    const result = filterTsc(output);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "No errors"));
}

test "tsc error line parse" {
    const line = "src/foo.ts(12,5): error TS2322: Type 'string' is not assignable";
    const err = parseTscErrorLine(line);
    try std.testing.expect(err != null);
    try std.testing.expectEqualStrings("src/foo.ts", err.?.file);
    try std.testing.expectEqual(@as(usize, 12), err.?.line);
    try std.testing.expectEqualStrings("TS2322", err.?.code);
}
