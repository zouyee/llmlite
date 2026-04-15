//! Learn - CLI Error Pattern Detection
//!
//! Analyzes command history to detect recurring CLI mistakes:
//! - Commands that fail then get corrected
//! - Unknown flags, wrong paths, missing args
//! - Generates .llmlite/rules/cli-corrections.md

const std = @import("std");
const fs = std.fs;

pub const ErrorType = enum {
    unknown_flag,
    command_not_found,
    wrong_syntax,
    wrong_path,
    missing_arg,
    permission_denied,
    other,
};

pub const CorrectionRule = struct {
    wrong_cmd: []const u8,
    right_cmd: []const u8,
    error_type: ErrorType,
    count: u32,
    confidence: f64,
};

pub const LearnOptions = struct {
    min_confidence: f64 = 0.5,
    min_occurrences: u32 = 2,
    output_format: LearnFormat = .text,
    write_rules: bool = false,
};

pub const LearnFormat = enum {
    text,
    json,
};

pub fn analyzeCorrections(allocator: std.mem.Allocator, options: LearnOptions) !void {
    // Get session history path
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
        std.debug.print("Learn: HOME not set\n", .{});
        return;
    };
    defer allocator.free(home);

    const history_path = std.fs.path.join(allocator, &.{
        home,
        ".local/share/llmlite/history.db",
    }) catch return;
    defer allocator.free(history_path);

    const file = std.fs.openFileAbsolute(history_path, .{ .mode = .read_only }) catch {
        std.debug.print("No history found. Run 'llmlite-cmd' commands first.\n", .{});
        return;
    };
    defer file.close();

    var buf: [8192]u8 = undefined;
    var file_buffer = std.array_list.Managed(u8).init(allocator);
    defer file_buffer.deinit();

    while (true) {
        const bytes_read = file.read(&buf) catch break;
        if (bytes_read == 0) break;
        file_buffer.appendSlice(buf[0..bytes_read]) catch break;
    }

    // Parse history and find fail->success patterns
    var correction_count: u32 = 0;
    var prev_failed: ?struct { cmd: []const u8, exit: u8 } = null;

    var line_iter = std.mem.splitScalar(u8, file_buffer.items, '\n');
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        var field_iter = std.mem.splitScalar(u8, line, '|');
        _ = field_iter.next(); // timestamp
        const original = field_iter.next() orelse continue;
        const rtk_cmd = field_iter.next() orelse continue;
        const exit_str = field_iter.next() orelse "0";
        const exit = @as(u8, @truncate(std.fmt.parseInt(u32, exit_str, 10) catch 0));

        // Detect fail->success pattern
        if (prev_failed) |pf| {
            if (exit == 0 and pf.exit != 0) {
                // Same base command?
                const base_wrong = getBaseCommand(pf.cmd);
                const base_right = getBaseCommand(rtk_cmd);

                if (std.mem.eql(u8, base_wrong, base_right)) {
                    const confidence = calculateConfidence(pf.cmd, rtk_cmd);

                    if (confidence >= options.min_confidence) {
                        correction_count += 1;
                    }
                }
            }
        }

        prev_failed = .{ .cmd = original, .exit = exit };
    }

    // Output results
    switch (options.output_format) {
        .text => std.debug.print("\n=== llmlite Learn - CLI Corrections ===\n\n", .{}),
        .json => std.debug.print("[\n", .{}),
    }

    std.debug.print("Detected {d} correction patterns (simplified view).\n", .{correction_count});
    std.debug.print("Run 'llmlite-cmd gain' for detailed analytics.\n", .{});
}

fn getBaseCommand(cmd: []const u8) []const u8 {
    // Get first word (base command)
    const space = std.mem.indexOfScalar(u8, cmd, ' ') orelse cmd.len;
    return cmd[0..space];
}

fn classifyError(wrong: []const u8, right: []const u8) ErrorType {
    _ = right; // Reserved for future more sophisticated detection
    // Simple heuristics
    if (std.mem.indexOf(u8, wrong, "unknown flag") != null or
        std.mem.indexOf(u8, wrong, "invalid flag") != null or
        std.mem.indexOf(u8, wrong, "-") != null)
    {
        return .unknown_flag;
    }

    if (std.mem.indexOf(u8, wrong, "No such file") != null or
        std.mem.indexOf(u8, wrong, "cannot find") != null)
    {
        return .wrong_path;
    }

    if (std.mem.indexOf(u8, wrong, "Permission denied") != null) {
        return .permission_denied;
    }

    if (std.mem.indexOf(u8, wrong, "missing") != null) {
        return .missing_arg;
    }

    return .other;
}

fn calculateConfidence(wrong: []const u8, right: []const u8) f64 {
    // Higher confidence if commands are similar
    const wrong_len = wrong.len;
    const right_len = right.len;

    if (wrong_len == 0 or right_len == 0) return 0.0;

    // Levenshtein-like similarity
    const max_len = @max(wrong_len, right_len);
    var matches: usize = 0;
    var i: usize = 0;
    while (i < @min(wrong_len, right_len)) : (i += 1) {
        if (wrong[i] == right[i]) matches += 1;
    }

    const similarity = @as(f64, @floatFromInt(matches)) / @as(f64, @floatFromInt(max_len));
    return similarity;
}

fn showLearnText(corrections: []CorrectionRule) !void {
    std.debug.print("\n=== llmlite Learn - CLI Corrections ===\n\n", .{});

    if (corrections.len == 0) {
        std.debug.print("No patterns detected. Keep using llmlite-cmd to build history.\n", .{});
        return;
    }

    std.debug.print("Detected {d} correction patterns:\n\n", .{corrections.len});

    for (corrections) |c| {
        const error_str = switch (c.error_type) {
            .unknown_flag => "unknown flag",
            .command_not_found => "command not found",
            .wrong_syntax => "wrong syntax",
            .wrong_path => "wrong path",
            .missing_arg => "missing argument",
            .permission_denied => "permission denied",
            .other => "other",
        };

        std.debug.print("[{s}] x{d} (confidence: {d:.0%})\n", .{
            error_str,
            c.count,
            c.confidence,
        });
        std.debug.print("  Wrong:  {s}\n", .{c.wrong_cmd});
        std.debug.print("  Right:  {s}\n\n", .{c.right_cmd});
    }

    std.debug.print("Run 'llmlite-cmd learn --write-rules' to generate correction rules.\n", .{});
}

fn showLearnJson(corrections: []CorrectionRule) !void {
    std.debug.print("[\n", .{});
    for (corrections) |c| {
        std.debug.print("  {{\n", .{});
        std.debug.print("    \"wrong\": \"{s}\",\n", .{c.wrong_cmd});
        std.debug.print("    \"right\": \"{s}\",\n", .{c.right_cmd});
        std.debug.print("    \"error\": \"{s}\",\n", .{
            @tagName(c.error_type),
        });
        std.debug.print("    \"count\": {d},\n", .{c.count});
        std.debug.print("    \"confidence\": {d:.2}\n", .{c.confidence});
        std.debug.print("  }},\n", .{});
    }
    std.debug.print("]\n", .{});
}

fn writeRulesFile(allocator: std.mem.Allocator, corrections: []CorrectionRule) !void {
    const rules_dir = try std.fmt.allocPrint(allocator, ".llmlite/rules", .{});
    defer allocator.free(rules_dir);

    try fs.makeDirAbsolute(rules_dir);

    const rules_path = try std.fs.path.join(allocator, &.{ rules_dir, "cli-corrections.md" });
    defer allocator.free(rules_path);

    const file = try fs.createFileAbsolute(rules_path, .{});
    defer file.close();

    try file.writeAll("# CLI Corrections\n\n");
    try file.writeAll("Auto-generated by llmlite-cmd learn\n\n");

    for (corrections) |c| {
        try file.writeAll("## ");
        try file.writeAll(@tagName(c.error_type));
        try file.writeAll(" (confidence: ");
        try file.writeAll(std.fmt.fmtFloat2Exp(c.confidence));
        try file.writeAll(")\n\n");
        try file.writeAll("- Don't run: `");
        try file.writeAll(c.wrong_cmd);
        try file.writeAll("`\n");
        try file.writeAll("- Run instead: `");
        try file.writeAll(c.right_cmd);
        try file.writeAll("`\n\n");
    }

    std.debug.print("Written: {s}\n", .{rules_path});
}
