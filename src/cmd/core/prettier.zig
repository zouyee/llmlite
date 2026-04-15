//! Prettier - Code Formatter
//!
//! Filters prettier output for compact representation.
//! Inspired by RTK's prettier_cmd.rs.
//!
//! ## Token Savings
//!
//! prettier --check: ~100 lines → ~20 lines (80% reduction)

const std = @import("std");
const json = @import("cmd_core_json");

/// Filter prettier output
pub fn filterPrettier(output: []const u8, args: []const []const u8) []const u8 {
    // Check if --check mode
    var is_check = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--check") or std.mem.eql(u8, arg, "-c")) {
            is_check = true;
            break;
        }
    }

    if (is_check) {
        return filterPrettierCheck(output);
    }

    return filterPrettierFormat(output);
}

/// Filter prettier --check output
fn filterPrettierCheck(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Check for "Checking formatting..." message
    if (std.mem.containsAtLeast(u8, output, 1, "Checking formatting")) {
        // Usually followed by "X files need formatting" or "Everything is fine"
        var lines = std.mem.splitScalar(u8, output, '\n');
        var needs_formatting = false;
        var file_count: usize = 0;
        var files = std.ArrayList([]const u8).init(std.heap.page_allocator);
        defer files.deinit();

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;

            if (std.mem.containsAtLeast(u8, trimmed, 1, "need")) {
                needs_formatting = true;
                // Try to parse file count
                var words = std.mem.splitScalar(u8, trimmed, ' ');
                while (words.next()) |word| {
                    const n = std.fmt.parseInt(usize, word, 10) catch continue;
                    file_count = n;
                    break;
                }
            }

            // File paths usually end with .js, .ts, etc
            if (std.mem.containsAtLeast(u8, trimmed, 1, ".js") or
                std.mem.containsAtLeast(u8, trimmed, 1, ".ts") or
                std.mem.containsAtLeast(u8, trimmed, 1, ".jsx") or
                std.mem.containsAtLeast(u8, trimmed, 1, ".tsx") or
                std.mem.containsAtLeast(u8, trimmed, 1, ".json") or
                std.mem.containsAtLeast(u8, trimmed, 1, ".css") or
                std.mem.containsAtLeast(u8, trimmed, 1, ".md"))
            {
                files.append(trimmed) catch {};
            }
        }

        if (needs_formatting) {
            std.fmt.format(result.writer(), "Prettier: {d} files need formatting\n", .{file_count}) catch return "";
            result.appendSlice("═══════════════════════════════════════\n") catch return "";

            const show_count = @min(10, files.items.len);
            for (files.items[0..show_count]) |file| {
                result.appendSlice(file) catch {};
                result.append('\n') catch {};
            }

            if (files.items.len > 10) {
                std.fmt.format(result.writer(), "... +{d} more files\n", .{files.items.len - 10}) catch return "";
            }

            return result.toOwnedSlice() catch "";
        } else {
            return "Prettier: All files formatted correctly";
        }
    }

    // Check for JSON output
    if (output.len > 0 and output[0] == '{') {
        return filterPrettierJson(output);
    }

    // Fallback
    if (std.mem.containsAtLeast(u8, output, 1, "error") or
        std.mem.containsAtLeast(u8, output, 1, "Error"))
    {
        return output[0..@min(output.len, 500)];
    }

    return "Prettier: No issues";
}

/// Filter prettier JSON output
fn filterPrettierJson(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Try to extract file paths from JSON
    var files = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer files.deinit();

    // Simple JSON parsing for file paths
    var pos: usize = 0;
    while (pos < output.len) {
        // Look for "filePath" field
        const search = "\"filePath\":\"";
        const start = std.mem.indexOf(u8, output[pos..], search);
        if (start == null) break;

        const file_start = pos + start.? + search.len;
        const file_end = std.mem.indexOf(u8, output[file_start..], "\"") orelse break;
        const file = output[file_start .. file_start + file_end];

        files.append(file) catch {};
        pos = file_start + file_end;
    }

    if (files.items.len == 0) {
        return "Prettier: No formatting issues";
    }

    std.fmt.format(result.writer(), "Prettier: {d} files need formatting\n", .{files.items.len}) catch return "";
    result.appendSlice("═══════════════════════════════════════\n") catch return "";

    const show_count = @min(10, files.items.len);
    for (files.items[0..show_count]) |file| {
        result.appendSlice(file) catch {};
        result.append('\n') catch {};
    }

    if (files.items.len > 10) {
        std.fmt.format(result.writer(), "... +{d} more files\n", .{files.items.len - 10}) catch return "";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter prettier format output
fn filterPrettierFormat(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // prettier format mode - usually shows what was changed
    if (std.mem.containsAtLeast(u8, output, 1, "reformatted")) {
        var lines = std.mem.splitScalar(u8, output, '\n');
        var count: usize = 0;

        while (lines.next()) |line| {
            if (count >= 20) break;

            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;

            result.appendSlice(trimmed[0..@min(100, trimmed.len)]) catch {};
            result.append('\n') catch {};
            count += 1;
        }

        return result.toOwnedSlice() catch "";
    }

    if (output.len == 0) {
        return "Prettier: No output";
    }

    return output[0..@min(output.len, 500)];
}

/// Run prettier with filtering
pub fn runPrettier(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.ArrayList([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("prettier");

    // Add --check if not present
    var has_check = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--check") or std.mem.eql(u8, arg, "-c")) {
            has_check = true;
        }
        try cmd_args.append(arg);
    }

    if (!has_check) {
        try cmd_args.append("--check");
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "prettier", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
    });
}
