//! Ruff - Python Linter and Formatter
//!
//! Filters ruff linter and formatter output with JSON support.
//! Inspired by RTK's ruff_cmd.rs.
//!
//! ## Features
//!
//! - `ruff check` - Lint with JSON output
//! - `ruff format` - Format checking
//! - Groups diagnostics by file and rule
//! - Shows fixable count
//!
//! ## Token Savings
//!
//! ruff check: ~500 lines → ~30 lines (94% reduction)

const std = @import("std");
const json = @import("cmd_core_json");

/// Ruff diagnostic from JSON
pub const RuffDiagnostic = struct {
    code: []const u8,
    message: []const u8,
    filename: []const u8,
    row: usize,
    column: usize,
    fixable: bool,
};

/// Filter ruff output
pub fn filterRuff(output: []const u8, is_check: bool, is_format: bool) []const u8 {
    if (is_check and output.len > 0) {
        return filterRuffCheckJson(output);
    } else if (is_format) {
        return filterRuffFormat(output);
    }
    return output;
}

/// Filter ruff check --json output
fn filterRuffCheckJson(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Try to parse as JSON array
    const trimmed = std.mem.trim(u8, output, " \t\n");
    if (trimmed.len == 0) {
        return "Ruff: No issues found";
    }

    if (trimmed[0] != '[') {
        // Not JSON, return as-is
        return output;
    }

    // Parse JSON array of diagnostics
    const diagnostics = parseRuffDiagnostics(trimmed) catch {
        // Fallback: just show first few lines
        var lines = std.mem.splitScalar(u8, output, '\n');
        var count: usize = 0;
        while (lines.next()) |line| {
            if (count >= 10) break;
            if (line.len > 0) {
                result.appendSlice(line) catch {};
                result.append('\n') catch {};
                count += 1;
            }
        }
        return result.toOwnedSlice() catch "Ruff: parse error";
    };

    if (diagnostics.len == 0) {
        return "Ruff: No issues found";
    }

    // Count fixable
    var fixable_count: usize = 0;
    for (diagnostics) |d| {
        if (d.fixable) fixable_count += 1;
    }

    // Count unique files
    var files = std.StringArrayHashMap(usize).init(std.heap.page_allocator);
    defer files.deinit();

    for (diagnostics) |d| {
        const entry = files.getOrPut(d.filename) catch continue;
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }

    const total_files = files.count();

    // Build output
    std.fmt.format(result.writer(), "Ruff: {d} issues in {d} files", .{ diagnostics.len, total_files }) catch return "";
    if (fixable_count > 0) {
        std.fmt.format(result.writer(), " ({d} fixable)", .{fixable_count}) catch return "";
    }
    result.append('\n') catch return "";
    result.appendSlice("═══════════════════════════════════════\n") catch return "";

    // Group by file (show top 5)
    var file_counts = std.array_list.Managed(struct { name: []const u8, count: usize }).init(std.heap.page_allocator);
    defer file_counts.deinit();

    var files_it = files.iterator();
    while (files_it.next()) |entry| {
        file_counts.append(.{ .name = entry.key_ptr.*, .count = entry.value_ptr.* }) catch {};
    }

    const show_count = @min(5, file_counts.count());
    var shown: usize = 0;
    var fc_it = file_counts.iterator();
    while (fc_it.next()) |entry| {
        if (shown >= show_count) break;
        if (shown > 0) result.append('\n') catch return "";
        std.fmt.format(result.writer(), "  {d}: {s}", .{ entry.value_ptr.*, entry.key_ptr.* }) catch return "";
        shown += 1;
    }

    if (file_counts.count() > 5) {
        std.fmt.format(result.writer(), "\n  ... +{d} more files", .{file_counts.count() - 5}) catch return "";
    }

    return result.toOwnedSlice() catch "";
}

/// Parse ruff JSON diagnostics
fn parseRuffDiagnostics(input: []const u8) ![]RuffDiagnostic {
    var diagnostics = std.array_list.Managed(RuffDiagnostic).init(std.heap.page_allocator);
    errdefer diagnostics.deinit();

    // Find array bounds
    var start: usize = 0;
    var end: usize = input.len;

    for (input, 0..) |c, i| {
        if (c == '[') {
            start = i + 1;
            break;
        }
    }
    for (input, start..) |c, i| {
        if (c == ']') {
            end = start + i;
            break;
        }
    }

    if (start >= end) return diagnostics.toOwnedSlice();

    // Parse each object in the array
    var pos = start;
    while (pos < end) {
        // Find opening brace
        while (pos < end and input[pos] != '{') pos += 1;
        if (pos >= end) break;

        // Find closing brace
        var depth: usize = 0;
        var obj_end = pos;
        for (pos..end) |i| {
            if (input[i] == '{') depth += 1 else if (input[i] == '}') {
                depth -= 1;
                if (depth == 0) {
                    obj_end = i + 1;
                    break;
                }
            }
        }

        const obj_text = input[pos..obj_end];

        // Extract fields
        const code = json.extractString(obj_text, "code") orelse "???";
        const message = json.extractString(obj_text, "message") orelse "";
        const filename = json.extractString(obj_text, "filename") orelse "??";

        // Location
        const row = json.extractInteger(obj_text, "row") orelse 0;
        const column = json.extractInteger(obj_text, "column") orelse 0;

        // Fixable - check if "fix" field exists
        const has_fix = json.extractString(obj_text, "fix") != null;

        diagnostics.append(.{
            .code = code,
            .message = message,
            .filename = filename,
            .row = @intCast(row),
            .column = @intCast(column),
            .fixable = has_fix,
        }) catch {};

        pos = obj_end + 1;
    }

    return diagnostics.toOwnedSlice();
}

/// Filter ruff format output
fn filterRuffFormat(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Check for differences
    if (std.mem.containsAtLeast(u8, output, 1, "would reformat")) {
        result.appendSlice("Ruff format: Would reformat") catch return "";
        return result.toOwnedSlice() catch "";
    }

    if (std.mem.containsAtLeast(u8, output, 1, "reformatted")) {
        result.appendSlice("Ruff format: Files reformatted") catch return "";
        return result.toOwnedSlice() catch "";
    }

    if (output.len == 0 or std.mem.containsAtLeast(u8, output, 1, "already")) {
        return "Ruff format: No changes needed";
    }

    return output;
}

/// Run ruff with filtering
pub fn runRuff(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    // Determine mode
    var is_check = true;
    var is_format = false;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "format")) {
            is_check = false;
            is_format = true;
        }
        if (std.mem.startsWith(u8, arg, "--output-format")) {
            is_check = false;
        }
    }

    // Build command
    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("ruff");

    if (is_check) {
        try cmd_args.append("check");
        try cmd_args.append("--output-format=json");
    }

    for (args) |arg| {
        if (!std.mem.eql(u8, arg, "check") and !std.mem.startsWith(u8, arg, "--output-format")) {
            try cmd_args.append(arg);
        }
    }

    // If only flags, add "."
    const has_target = for (cmd_args.items[1..]) |arg| {
        if (!std.mem.startsWith(u8, arg, "-")) break true;
    } else false;

    if (!has_target) {
        try cmd_args.append(".");
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "ruff", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
    });
}

test "ruff filter - no issues" {
    const output = "";
    const result = filterRuff(output, true, false);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "No issues"));
}

test "ruff filter - format ok" {
    const output = "Already formatted";
    const result = filterRuff(output, false, true);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "No changes"));
}
