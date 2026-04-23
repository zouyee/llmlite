//! Read - Language-aware file reading with filtering
//!
//! Provides filtered file reading to save tokens when sending code to LLMs.
//! Inspired by RTK's read.rs.
//!
//! Features:
//! - Language detection from file extension
//! - Filter levels: none, minimal, aggressive
//! - Line window: head, tail, max-lines
//! - Line numbers option
//! - stdin support

const std = @import("std");
const filter = @import("cmd_core_filter");
const tee = @import("cmd_core_tee");

// Global Io instance set by cmd.zig dispatch.
pub var g_io: std.Io = undefined;

pub const ReadOptions = struct {
    /// Filter level
    level: filter.FilterLevel = .minimal,
    /// Maximum lines to show from start
    max_lines: ?usize = null,
    /// Show lines from end
    tail_lines: ?usize = null,
    /// Show line numbers
    line_numbers: bool = false,
    /// Verbosity
    verbose: u8 = 0,
};

/// Run read on a file
pub fn run(allocator: std.mem.Allocator, file_path: []const u8, options: ReadOptions) !void {
    if (options.verbose > 0) {
        std.debug.print("Reading: {s} (filter: {})\n", .{ file_path, options.level });
    }

    // Read file content
    const content = try readFile(allocator, file_path);
    defer allocator.free(content);

    // Detect language from extension
    const lang = detectLanguage(file_path);
    if (options.verbose > 1) {
        std.debug.print("Detected language: {}\n", .{lang});
    }

    // Apply filter
    const filtered = filter.filter(allocator, content, .{
        .strategy = .code_filter,
        .level = options.level,
        .language = lang,
    });
    defer allocator.free(filtered.filtered);

    // Safety: if filter emptied a non-empty file, fall back to raw content
    var final_content = filtered.filtered;
    if (filtered.filtered.len == 0 and content.len > 0) {
        if (options.verbose > 0) {
            std.debug.print("Warning: filter produced empty output, showing raw content\n", .{});
        }
        final_content = content;
    }

    if (options.verbose > 0) {
        const original_lines = countLines(content);
        const filtered_lines = countLines(final_content);
        const reduction = if (original_lines > 0) {
            ((original_lines - filtered_lines) * 100) / original_lines
        } else 0;
        std.debug.print("Lines: {} -> {} ({}% reduction)\n", .{
            original_lines,
            filtered_lines,
            reduction,
        });
    }

    // Apply line window
    final_content = try applyLineWindow(allocator, final_content, options.max_lines, options.tail_lines);

    // Format output
    const output = if (options.line_numbers) formatWithLineNumbers(final_content) else final_content;

    // TEE recovery hint for truncated content
    if (options.max_lines != null or options.tail_lines != null) {
        const hint = try std.fmt.allocPrint(allocator, "[full output: {s}]\n", .{file_path});
        defer allocator.free(hint);
        std.debug.print("{s}{s}", .{ output, hint });
    } else {
        std.debug.print("{s}", .{output});
    }
}

/// Run read on stdin
pub fn runStdin(allocator: std.mem.Allocator, options: ReadOptions) !void {
    if (options.verbose > 0) {
        std.debug.print("Reading from stdin (filter: {})\n", .{options.level});
    }

    // Read from stdin
    const content = try readStdin(allocator);
    defer allocator.free(content);

    // No language detection for stdin
    const lang: filter.Language = .unknown;

    // Apply filter
    const filtered = filter.filter(allocator, content, .{
        .strategy = .code_filter,
        .level = options.level,
        .language = lang,
    });
    defer allocator.free(filtered.filtered);

    var final_content = filtered.filtered;
    if (filtered.filtered.len == 0 and content.len > 0) {
        final_content = content;
    }

    // Apply line window
    final_content = try applyLineWindow(allocator, final_content, options.max_lines, options.tail_lines);

    // Format output
    const output = if (options.line_numbers) formatWithLineNumbers(final_content) else final_content;

    std.debug.print("{s}", .{output});
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.Io.Dir.openFileAbsolute(g_io, path, .{});
    defer file.close(g_io);

    var reader_buf: [8192]u8 = undefined;
    var file_reader = file.reader(g_io, &reader_buf);
    const content = try file_reader.interface.allocRemaining(allocator, .unlimited);
    return content;
}

fn readStdin(allocator: std.mem.Allocator) ![]u8 {
    var reader_buf: [8192]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(g_io, &reader_buf);
    const content = try stdin_reader.interface.allocRemaining(allocator, .unlimited);
    return content;
}

fn detectLanguage(path: []const u8) filter.Language {
    const ext = std.fs.path.extension(path);
    if (ext.len == 0) return .unknown;

    // Skip the leading dot
    const ext_lower = std.ascii.lowerString(ext[1..]);

    return filter.Language.fromExtension(ext_lower);
}

fn formatWithLineNumbers(content: []const u8) []const u8 {
    // Count lines first
    const lines = std.mem.splitScalar(u8, content, '\n');
    const line_count = lines.count();
    const width = if (line_count > 0) numDigits(line_count) else 1;

    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var line_num: usize = 1;
    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |line| {
        result.print("{width:>width$} │ {s}\n", .{ line_num, line, width = width }) catch {};
        line_num += 1;
    }

    return result.toOwnedSlice();
}

fn numDigits(n: usize) usize {
    var count: usize = 1;
    var x = n;
    while (x >= 10) : (x /= 10) count += 1;
    return count;
}

fn countLines(content: []const u8) usize {
    var count: usize = 0;
    for (content) |c| if (c == '\n') count += 1;
    return count;
}

fn applyLineWindow(
    allocator: std.mem.Allocator,
    content: []const u8,
    max_lines: ?usize,
    tail_lines: ?usize,
) ![]const u8 {
    if (tail_lines) |n| {
        if (n == 0) return allocator.dupe(u8, "");

        const all_lines = std.mem.splitScalar(u8, content, '\n');
        const line_count = all_lines.count();

        if (n >= line_count) return allocator.dupe(u8, content);

        const start = line_count - n;
        var result = std.array_list.Managed(u8).init(allocator);
        errdefer result.deinit();

        var current_line: usize = 0;
        var it = std.mem.splitScalar(u8, content, '\n');
        while (it.next()) |line| {
            if (current_line >= start) {
                if (current_line > start) try result.append('\n');
                try result.appendSlice(line);
            }
            current_line += 1;
        }

        // Preserve trailing newline if original had it
        if (content.len > 0 and content[content.len - 1] == '\n') {
            try result.append('\n');
        }

        return result.toOwnedSlice();
    }

    if (max_lines) |n| {
        const all_lines = std.mem.splitScalar(u8, content, '\n');
        const line_count = all_lines.count();

        if (line_count <= n) return allocator.dupe(u8, content);

        var result = std.array_list.Managed(u8).init(allocator);
        errdefer result.deinit();

        var current_line: usize = 0;
        var it = std.mem.splitScalar(u8, content, '\n');
        while (it.next()) |line| {
            if (current_line > 0 and current_line < n) {
                try result.append('\n');
            }
            if (current_line < n) {
                try result.appendSlice(line);
            }
            current_line += 1;
        }

        if (line_count > n) {
            try result.appendSlice("\n// ... ");
            try result.print("{} more lines (total: {})", .{ line_count - n, line_count });
        }

        return result.toOwnedSlice();
    }

    return allocator.dupe(u8, content);
}

test "read detect language" {
    try std.testing.expect(detectLanguage("test.rs") == .rust);
    try std.testing.expect(detectLanguage("test.py") == .python);
    try std.testing.expect(detectLanguage("test.js") == .javascript);
    try std.testing.expect(detectLanguage("test.ts") == .typescript);
    try std.testing.expect(detectLanguage("test.go") == .go);
    try std.testing.expect(detectLanguage("test.rb") == .ruby);
    try std.testing.expect(detectLanguage("test.java") == .java);
    try std.testing.expect(detectLanguage("test.json") == .data);
    try std.testing.expect(detectLanguage("test") == .unknown);
}

test "read count lines" {
    try std.testing.expect(countLines("a\nb\nc") == 3);
    try std.testing.expect(countLines("a\nb\nc\n") == 4);
    try std.testing.expect(countLines("") == 0);
    try std.testing.expect(countLines("\n") == 1);
}

test "read num digits" {
    try std.testing.expect(numDigits(0) == 1);
    try std.testing.expect(numDigits(9) == 1);
    try std.testing.expect(numDigits(10) == 2);
    try std.testing.expect(numDigits(99) == 2);
    try std.testing.expect(numDigits(100) == 3);
}
