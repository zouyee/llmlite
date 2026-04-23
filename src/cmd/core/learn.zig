//! Learn - CLI Error Pattern Detection
//!
//! Analyzes command history to detect recurring CLI mistakes:
//! - Commands that fail then get corrected
//! - Unknown flags, wrong paths, missing args
//! - Generates .llmlite/rules/cli-corrections.md
//!
//! Ported from RTK detector.rs with:
//! - Jaccard similarity (replaces character matching)
//! - Sliding window correction detection (window=3)
//! - TDD cycle filtering
//! - Path exploration filtering
//! - Diff token extraction
//! - Deduplication by (base_command, error_type, diff_token)

const std = @import("std");

// Global Io instance set by cmd.zig dispatch.
pub var g_io: std.Io = undefined;

// Zig 0.16.0 compat: replacement for removed _getEnvVarOwned
fn _getEnvVarOwned(allocator: std.mem.Allocator, key: [*:0]const u8) error{EnvironmentVariableNotFound, OutOfMemory}![]u8 {
    const ptr = std.c.getenv(key) orelse return error.EnvironmentVariableNotFound;
    const slice = std.mem.sliceTo(ptr, 0);
    return allocator.dupe(u8, slice);
}
const fs = std.fs;

// ===== Constants =====
const CORRECTION_WINDOW: usize = 3;
const MIN_CONFIDENCE: f64 = 0.6;

// ===== Data Types =====

pub const ErrorType = enum {
    unknown_flag,
    command_not_found,
    wrong_syntax,
    wrong_path,
    missing_arg,
    permission_denied,
    other,

    pub fn asStr(self: ErrorType) []const u8 {
        return switch (self) {
            .unknown_flag => "Unknown Flag",
            .command_not_found => "Command Not Found",
            .wrong_syntax => "Wrong Syntax",
            .wrong_path => "Wrong Path",
            .missing_arg => "Missing Argument",
            .permission_denied => "Permission Denied",
            .other => "General Error",
        };
    }
};

pub const CorrectionPair = struct {
    wrong_command: []const u8,
    right_command: []const u8,
    error_output: []const u8,
    error_type: ErrorType,
    confidence: f64,
};

pub const CorrectionRule = struct {
    wrong_pattern: []const u8,
    right_pattern: []const u8,
    error_type: ErrorType,
    occurrences: usize,
    base_command: []const u8,
    example_error: []const u8,
};

pub const CommandExecution = struct {
    command: []const u8,
    is_error: bool,
    output: []const u8,
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

// ===== Task 1.1: Jaccard Similarity =====

/// Extract base command (first 1-2 tokens), stripping env variable prefixes.
/// e.g. "RUST_BACKTRACE=1 cargo test --release" -> "cargo test"
/// e.g. "git commit --amend" -> "git commit"
pub fn extractBaseCommand(cmd: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, cmd, " \t\r\n");
    if (trimmed.len == 0) return trimmed;

    // Strip common env prefixes (VAR=value pattern)
    var stripped = trimmed;
    while (stripped.len > 0) {
        // Check if starts with an env var pattern: WORD=VALUE followed by space
        const eq_pos = std.mem.findScalar(u8, stripped, '=') orelse break;
        const space_after_val = blk: {
            // Find space after the value part
            var i: usize = eq_pos + 1;
            while (i < stripped.len and stripped[i] != ' ') : (i += 1) {}
            if (i < stripped.len) break :blk i;
            break :blk stripped.len;
        };

        // Verify the part before '=' is all uppercase letters/underscores (env var name)
        const var_name = stripped[0..eq_pos];
        var is_env_var = var_name.len > 0;
        for (var_name) |c| {
            if (!std.ascii.isUpper(c) and c != '_' and !std.ascii.isDigit(c)) {
                is_env_var = false;
                break;
            }
        }

        if (!is_env_var) break;

        if (space_after_val < stripped.len) {
            stripped = std.mem.trim(u8, stripped[space_after_val..], " ");
        } else {
            // Entire string is just an env var assignment
            return stripped;
        }
    }

    // Get first 1-2 tokens
    var token_count: usize = 0;
    var end: usize = 0;
    var i: usize = 0;
    while (i < stripped.len and token_count < 2) {
        // Skip whitespace
        while (i < stripped.len and stripped[i] == ' ') : (i += 1) {}
        if (i >= stripped.len) break;

        // Read token
        const token_start = i;
        _ = token_start;
        while (i < stripped.len and stripped[i] != ' ') : (i += 1) {}
        end = i;
        token_count += 1;
    }

    return stripped[0..end];
}

/// Calculate similarity between two commands using Jaccard similarity.
/// Same base command = 0.5 base score + up to 0.5 from argument Jaccard similarity.
/// Different base commands = 0.0.
pub fn commandSimilarity(a: []const u8, b: []const u8) f64 {
    const base_a = extractBaseCommand(a);
    const base_b = extractBaseCommand(b);

    if (!std.mem.eql(u8, base_a, base_b)) {
        return 0.0;
    }

    // Extract args: everything after the base command
    const args_a_str = if (base_a.len < a.len) std.mem.trim(u8, a[base_a.len..], " \t") else "";
    const args_b_str = if (base_b.len < b.len) std.mem.trim(u8, b[base_b.len..], " \t") else "";

    if (args_a_str.len == 0 and args_b_str.len == 0) {
        return 1.0; // Identical commands (same base, no args)
    }

    // Count unique tokens in each and compute intersection/union
    // Use a simple approach: iterate tokens, count set sizes
    var union_count: usize = 0;
    var intersection_count: usize = 0;

    // Collect tokens from A
    const max_tokens = 64;
    var tokens_a: [max_tokens][]const u8 = undefined;
    var count_a: usize = 0;
    {
        var iter = std.mem.tokenizeScalar(u8, args_a_str, ' ');
        while (iter.next()) |tok| {
            if (count_a < max_tokens) {
                // Check for duplicate in tokens_a
                var dup = false;
                for (tokens_a[0..count_a]) |existing| {
                    if (std.mem.eql(u8, existing, tok)) {
                        dup = true;
                        break;
                    }
                }
                if (!dup) {
                    tokens_a[count_a] = tok;
                    count_a += 1;
                }
            }
        }
    }

    // Collect tokens from B
    var tokens_b: [max_tokens][]const u8 = undefined;
    var count_b: usize = 0;
    {
        var iter = std.mem.tokenizeScalar(u8, args_b_str, ' ');
        while (iter.next()) |tok| {
            if (count_b < max_tokens) {
                var dup = false;
                for (tokens_b[0..count_b]) |existing| {
                    if (std.mem.eql(u8, existing, tok)) {
                        dup = true;
                        break;
                    }
                }
                if (!dup) {
                    tokens_b[count_b] = tok;
                    count_b += 1;
                }
            }
        }
    }

    // Compute intersection: tokens in both A and B
    for (tokens_a[0..count_a]) |ta| {
        for (tokens_b[0..count_b]) |tb| {
            if (std.mem.eql(u8, ta, tb)) {
                intersection_count += 1;
                break;
            }
        }
    }

    // Union = |A| + |B| - |intersection|
    union_count = count_a + count_b - intersection_count;

    if (union_count == 0) {
        return 0.5; // Same base, no args
    }

    // 0.5 for same base + up to 0.5 for arg Jaccard similarity
    return 0.5 + (@as(f64, @floatFromInt(intersection_count)) / @as(f64, @floatFromInt(union_count))) * 0.5;
}

// ===== Task 2.2: User Rejection Filter =====

/// Filters out user rejections - requires actual error-indicating content.
/// Returns true only if is_error is set AND output contains error indicators
/// AND output is NOT a user rejection.
pub fn isCommandError(is_error: bool, output: []const u8) bool {
    if (!is_error) return false;

    // Check for user rejection patterns (case-insensitive)
    if (containsCI(output, "user doesn't want") or
        containsCI(output, "user declined") or
        containsCI(output, "user rejected") or
        containsCI(output, "user cancelled") or
        containsCI(output, "operation cancelled by user") or
        containsCI(output, "operation aborted by user"))
    {
        return false;
    }

    // Must contain error-indicating content
    return containsCI(output, "error") or
        containsCI(output, "failed") or
        containsCI(output, "unknown") or
        containsCI(output, "invalid") or
        containsCI(output, "not found") or
        containsCI(output, "permission denied") or
        containsCI(output, "cannot");
}

// ===== Task 2.3: Enhanced Error Classification =====

/// Classify error type from command output using enhanced pattern matching.
/// Matches patterns from RTK detector.rs classify_error.
pub fn classifyError(output: []const u8) ErrorType {
    // Unknown flag patterns
    if (containsCI(output, "unexpected argument") or
        containsCI(output, "unknown option") or
        containsCI(output, "unknown flag") or
        containsCI(output, "unrecognized option") or
        containsCI(output, "unrecognized flag") or
        containsCI(output, "invalid option") or
        containsCI(output, "invalid flag"))
    {
        return .unknown_flag;
    }

    // Command not found patterns
    if (containsCI(output, "command not found") or
        containsCI(output, "not recognized as an internal"))
    {
        return .command_not_found;
    }

    // Missing argument patterns
    if (containsCI(output, "requires a value") or
        containsCI(output, "requires an argument") or
        containsCI(output, "missing required argument") or
        containsCI(output, "missing argument") or
        containsCI(output, "expected") and containsCI(output, "argument"))
    {
        return .missing_arg;
    }

    // Permission denied patterns
    if (containsCI(output, "permission denied") or
        containsCI(output, "access denied") or
        containsCI(output, "not permitted"))
    {
        return .permission_denied;
    }

    // Wrong path patterns
    if (containsCI(output, "no such file or directory") or
        containsCI(output, "cannot find the path") or
        containsCI(output, "file not found"))
    {
        return .wrong_path;
    }

    return .other;
}

// ===== Task 1.3: TDD Cycle Filter =====

/// Check if error is a compilation/test error (TDD red-green cycle, not CLI correction).
/// These should be filtered out to avoid false positives.
pub fn isTddCycleError(error_type: ErrorType, output: []const u8) bool {
    // Rust compilation errors
    if (std.mem.find(u8, output, "error[E") != null or
        std.mem.find(u8, output, "aborting due to") != null)
    {
        return true;
    }

    // Zig compilation errors (error: with line number pattern)
    // Look for "error:" followed by digits (line numbers)
    if (hasErrorWithLineNumber(output)) {
        return true;
    }

    // Test failure patterns
    if (std.mem.find(u8, output, "test result: FAILED") != null or
        containsCI(output, "tests failed") or
        containsCI(output, "test failed"))
    {
        return true;
    }

    // Only certain error types combined with compilation/test output
    switch (error_type) {
        .command_not_found, .other => {
            if (std.mem.find(u8, output, "error[E") != null or
                std.mem.find(u8, output, "FAILED") != null)
            {
                return true;
            }
        },
        else => {},
    }

    return false;
}

// ===== Task 1.4: Path Exploration Detection =====

/// Check if commands differ only by path (exploration, not correction).
/// Heuristic: same base command + similarity > 0.9 but < 1.0.
pub fn differsOnlyByPath(a: []const u8, b: []const u8) bool {
    const base_a = extractBaseCommand(a);
    const base_b = extractBaseCommand(b);

    if (!std.mem.eql(u8, base_a, base_b)) {
        return false;
    }

    const sim = commandSimilarity(a, b);
    return sim > 0.9 and sim < 1.0;
}

// ===== Task 1.5: Diff Token Extraction =====

/// Extract the specific token that changed between wrong and right commands.
/// Returns allocated string like "removed_token → added_token", "removed X", or "added X".
pub fn extractDiffToken(allocator: std.mem.Allocator, wrong: []const u8, right: []const u8) ![]const u8 {
    // Collect unique tokens from each command
    const max_tokens = 64;

    var wrong_tokens: [max_tokens][]const u8 = undefined;
    var wrong_count: usize = 0;
    {
        var iter = std.mem.tokenizeScalar(u8, wrong, ' ');
        while (iter.next()) |tok| {
            if (wrong_count < max_tokens) {
                var dup = false;
                for (wrong_tokens[0..wrong_count]) |existing| {
                    if (std.mem.eql(u8, existing, tok)) {
                        dup = true;
                        break;
                    }
                }
                if (!dup) {
                    wrong_tokens[wrong_count] = tok;
                    wrong_count += 1;
                }
            }
        }
    }

    var right_tokens: [max_tokens][]const u8 = undefined;
    var right_count: usize = 0;
    {
        var iter = std.mem.tokenizeScalar(u8, right, ' ');
        while (iter.next()) |tok| {
            if (right_count < max_tokens) {
                var dup = false;
                for (right_tokens[0..right_count]) |existing| {
                    if (std.mem.eql(u8, existing, tok)) {
                        dup = true;
                        break;
                    }
                }
                if (!dup) {
                    right_tokens[right_count] = tok;
                    right_count += 1;
                }
            }
        }
    }

    // Find tokens in wrong but not in right (removed)
    var removed: [max_tokens][]const u8 = undefined;
    var removed_count: usize = 0;
    for (wrong_tokens[0..wrong_count]) |wt| {
        var found = false;
        for (right_tokens[0..right_count]) |rt| {
            if (std.mem.eql(u8, wt, rt)) {
                found = true;
                break;
            }
        }
        if (!found and removed_count < max_tokens) {
            removed[removed_count] = wt;
            removed_count += 1;
        }
    }

    // Find tokens in right but not in wrong (added)
    var added: [max_tokens][]const u8 = undefined;
    var added_count: usize = 0;
    for (right_tokens[0..right_count]) |rt| {
        var found = false;
        for (wrong_tokens[0..wrong_count]) |wt| {
            if (std.mem.eql(u8, wt, rt)) {
                found = true;
                break;
            }
        }
        if (!found and added_count < max_tokens) {
            added[added_count] = rt;
            added_count += 1;
        }
    }

    // Format result
    if (removed_count > 0 and added_count > 0) {
        return std.fmt.allocPrint(allocator, "{s} → {s}", .{ removed[0], added[0] });
    } else if (removed_count > 0) {
        return std.fmt.allocPrint(allocator, "removed {s}", .{removed[0]});
    } else if (added_count > 0) {
        return std.fmt.allocPrint(allocator, "added {s}", .{added[0]});
    } else {
        return try allocator.dupe(u8, "unknown");
    }
}

// ===== Task 1.2: Sliding Window Correction Detection =====

/// Find correction pairs using sliding window detection.
/// For each error command, looks ahead within CORRECTION_WINDOW (3) commands
/// for a similar command that succeeded.
pub fn findCorrections(allocator: std.mem.Allocator, commands: []const CommandExecution) ![]CorrectionPair {
    var corrections = try std.ArrayList(CorrectionPair).initCapacity(allocator, 0);
    errdefer corrections.deinit(allocator);

    for (commands, 0..) |cmd, i| {
        // Must be an actual error
        if (!isCommandError(cmd.is_error, cmd.output)) {
            continue;
        }

        const error_type = classifyError(cmd.output);

        // Skip TDD cycle errors
        if (isTddCycleError(error_type, cmd.output)) {
            continue;
        }

        // Look ahead for correction within CORRECTION_WINDOW
        const window_end = @min(i + 1 + CORRECTION_WINDOW, commands.len);
        for (commands[i + 1 .. window_end]) |candidate| {
            const similarity = commandSimilarity(cmd.command, candidate.command);

            // Must meet minimum similarity (0.5)
            if (similarity < 0.5) {
                continue;
            }

            // Skip if only path differs (exploration)
            if (differsOnlyByPath(cmd.command, candidate.command)) {
                continue;
            }

            // Skip if identical commands (same error repeated)
            if (std.mem.eql(u8, cmd.command, candidate.command)) {
                continue;
            }

            // Calculate confidence
            var confidence = similarity;

            // Boost confidence if correction succeeded
            if (!isCommandError(candidate.is_error, candidate.output)) {
                confidence = @min(confidence + 0.2, 1.0);
            }

            // Must meet minimum confidence
            if (confidence < MIN_CONFIDENCE) {
                continue;
            }

            // Truncate error output to 500 chars
            const error_output = if (cmd.output.len > 500) cmd.output[0..500] else cmd.output;

            try corrections.append(allocator, .{
                .wrong_command = cmd.command,
                .right_command = candidate.command,
                .error_output = error_output,
                .error_type = error_type,
                .confidence = confidence,
            });

            // Take first match only
            break;
        }
    }

    return corrections.toOwnedSlice(allocator);
}

// ===== Task 1.6: Deduplication =====

/// Deduplicate correction pairs by (base_command, error_type, diff_token).
/// Each group keeps the highest confidence example and accumulates occurrence count.
/// Results sorted by occurrences descending.
pub fn deduplicateCorrections(allocator: std.mem.Allocator, pairs: []const CorrectionPair) ![]CorrectionRule {
    // Group key: "base_command|error_type_str|diff_token"
    const GroupEntry = struct {
        best_idx: usize,
        best_confidence: f64,
        count: usize,
    };

    var groups = std.StringHashMap(GroupEntry).init(allocator);
    defer {
        var key_iter = groups.keyIterator();
        while (key_iter.next()) |key| {
            allocator.free(key.*);
        }
        groups.deinit();
    }

    // Store diff tokens so we can free them
    var diff_tokens = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer {
        for (diff_tokens.items) |dt| {
            allocator.free(dt);
        }
        diff_tokens.deinit(allocator);
    }

    for (pairs, 0..) |pair, idx| {
        const base = extractBaseCommand(pair.wrong_command);
        const error_type_str = pair.error_type.asStr();
        const diff_token = try extractDiffToken(allocator, pair.wrong_command, pair.right_command);
        try diff_tokens.append(allocator, diff_token);

        const key = try std.fmt.allocPrint(allocator, "{s}|{s}|{s}", .{ base, error_type_str, diff_token });

        if (groups.getPtr(key)) |entry| {
            entry.count += 1;
            if (pair.confidence > entry.best_confidence) {
                entry.best_confidence = pair.confidence;
                entry.best_idx = idx;
            }
            allocator.free(key);
        } else {
            try groups.put(key, .{
                .best_idx = idx,
                .best_confidence = pair.confidence,
                .count = 1,
            });
        }
    }

    // Build rules from groups
    var rules = try std.ArrayList(CorrectionRule).initCapacity(allocator, 0);
    errdefer rules.deinit(allocator);

    var iter = groups.iterator();
    while (iter.next()) |entry| {
        const group = entry.value_ptr.*;
        const best = pairs[group.best_idx];

        try rules.append(allocator, .{
            .wrong_pattern = best.wrong_command,
            .right_pattern = best.right_command,
            .error_type = best.error_type,
            .occurrences = group.count,
            .base_command = extractBaseCommand(best.wrong_command),
            .example_error = best.error_output,
        });
    }

    // Sort by occurrences descending
    const items = try rules.toOwnedSlice(allocator);
    std.mem.sort(CorrectionRule, items, {}, struct {
        fn lessThan(_: void, a: CorrectionRule, b_rule: CorrectionRule) bool {
            return b_rule.occurrences < a.occurrences;
        }
    }.lessThan);

    return items;
}

// ===== Task 2.1: Refactored analyzeCorrections =====

/// Main analysis function. Reads history, runs findCorrections + deduplicateCorrections pipeline.
pub fn analyzeCorrections(allocator: std.mem.Allocator, options: LearnOptions) !void {
    // Get session history path
    const home = _getEnvVarOwned(allocator, "HOME") catch {
        std.debug.print("Learn: HOME not set\n", .{});
        return;
    };
    defer allocator.free(home);

    const history_path = try std.fs.path.join(allocator, &.{
        home,
        ".local/share/llmlite/history.db",
    });
    defer allocator.free(history_path);

    const file = std.Io.Dir.openFileAbsolute(g_io, history_path, .{}) catch {
        std.debug.print("No history found. Run 'llmlite-cmd' commands first.\n", .{});
        return;
    };
    defer file.close(g_io);

    var buf: [8192]u8 = undefined;
    var file_buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer file_buffer.deinit(allocator);

    while (true) {
        const bytes_read = file.readPositional(g_io, &.{&buf}, 0) catch break;
        if (bytes_read == 0) break;
        try file_buffer.appendSlice(allocator, buf[0..bytes_read]);
    }

    // Parse history into CommandExecution structs
    var commands = try std.ArrayList(CommandExecution).initCapacity(allocator, 0);
    defer commands.deinit(allocator);

    var line_iter = std.mem.splitScalar(u8, file_buffer.items, '\n');
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        var field_iter = std.mem.splitScalar(u8, line, '|');
        _ = field_iter.next(); // timestamp
        _ = field_iter.next(); // original command
        const rtk_cmd = field_iter.next() orelse continue;
        const exit_str = field_iter.next() orelse "0";
        const exit_code = std.fmt.parseInt(u32, exit_str, 10) catch 0;
        const output_field = field_iter.next() orelse "";

        try commands.append(allocator, .{
            .command = rtk_cmd,
            .is_error = exit_code != 0,
            .output = output_field,
        });
    }

    // Run detection pipeline
    const pairs = try findCorrections(allocator, commands.items);
    defer allocator.free(pairs);

    const rules = try deduplicateCorrections(allocator, pairs);
    defer allocator.free(rules);

    // Filter by options
    var filtered_rules = try std.ArrayList(CorrectionRule).initCapacity(allocator, 0);
    defer filtered_rules.deinit(allocator);

    for (rules) |rule| {
        if (rule.occurrences >= options.min_occurrences) {
            try filtered_rules.append(allocator, rule);
        }
    }

    // Output results
    switch (options.output_format) {
        .text => showLearnText(filtered_rules.items),
        .json => showLearnJson(filtered_rules.items),
    }

    // Write rules file if requested
    if (options.write_rules and filtered_rules.items.len > 0) {
        writeRulesFile(allocator, filtered_rules.items) catch |err| {
            std.debug.print("Failed to write rules file: {}\n", .{err});
        };
    }
}

// ===== Output Functions =====

fn showLearnText(corrections: []const CorrectionRule) void {
    std.debug.print("\n=== llmlite Learn - CLI Corrections ===\n\n", .{});

    if (corrections.len == 0) {
        std.debug.print("No patterns detected. Keep using llmlite-cmd to build history.\n", .{});
        return;
    }

    std.debug.print("Detected {d} correction patterns:\n\n", .{corrections.len});

    for (corrections) |c| {
        std.debug.print("[{s}] x{d}\n", .{
            c.error_type.asStr(),
            c.occurrences,
        });
        std.debug.print("  Wrong:  {s}\n", .{c.wrong_pattern});
        std.debug.print("  Right:  {s}\n\n", .{c.right_pattern});
    }

    std.debug.print("Run 'llmlite-cmd learn --write-rules' to generate correction rules.\n", .{});
}

fn showLearnJson(corrections: []const CorrectionRule) void {
    std.debug.print("[\n", .{});
    for (corrections, 0..) |c, i| {
        std.debug.print("  {{\n", .{});
        std.debug.print("    \"wrong\": \"{s}\",\n", .{c.wrong_pattern});
        std.debug.print("    \"right\": \"{s}\",\n", .{c.right_pattern});
        std.debug.print("    \"error\": \"{s}\",\n", .{c.error_type.asStr()});
        std.debug.print("    \"occurrences\": {d},\n", .{c.occurrences});
        std.debug.print("    \"base_command\": \"{s}\"\n", .{c.base_command});
        if (i < corrections.len - 1) {
            std.debug.print("  }},\n", .{});
        } else {
            std.debug.print("  }}\n", .{});
        }
    }
    std.debug.print("]\n", .{});
}

fn writeRulesFile(allocator: std.mem.Allocator, corrections: []const CorrectionRule) !void {
    const rules_dir = ".llmlite/rules";

    std.Io.Dir.cwd().createDirPath(g_io, rules_dir) catch {};

    const rules_path = try std.fs.path.join(allocator, &.{ rules_dir, "cli-corrections.md" });
    defer allocator.free(rules_path);

    const file = try std.Io.Dir.cwd().createFile(g_io, rules_path, .{});
    defer file.close(g_io);

    try file.writeStreamingAll(g_io, "# CLI Corrections\n\n");
    try file.writeStreamingAll(g_io, "Auto-generated by llmlite-cmd learn\n\n");

    for (corrections) |c| {
        const section = try std.fmt.allocPrint(allocator, "## {s} (x{d})\n\n- Don't run: `{s}`\n- Run instead: `{s}`\n\n", .{
            c.error_type.asStr(),
            c.occurrences,
            c.wrong_pattern,
            c.right_pattern,
        });
        defer allocator.free(section);
        try file.writeStreamingAll(g_io, section);
    }

    std.debug.print("Written: {s}\n", .{rules_path});
}

// ===== Helper Functions =====

/// Case-insensitive substring search.
fn containsCI(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;

    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
        var match = true;
        for (needle, 0..) |nc, j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(nc)) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

/// Check if output contains "error:" followed by a line number pattern (Zig-style).
fn hasErrorWithLineNumber(output: []const u8) bool {
    const marker = "error:";
    var pos: usize = 0;
    while (std.mem.findPos(u8, output, pos, marker)) |idx| {
        // Check if there's a colon + digits pattern nearby (file:line:col pattern)
        const before_start = if (idx > 40) idx - 40 else 0;
        const before = output[before_start..idx];
        // Look for "filename.zig:NN:NN:" pattern before "error:"
        if (std.mem.find(u8, before, ".zig:") != null) {
            return true;
        }
        pos = idx + marker.len;
    }
    return false;
}

// ===== Tests =====

test "extractBaseCommand basic" {
    try std.testing.expectEqualStrings("git commit", extractBaseCommand("git commit --amend"));
    try std.testing.expectEqualStrings("cargo test", extractBaseCommand("cargo test"));
    try std.testing.expectEqualStrings("git commit", extractBaseCommand("git commit --amend -m 'fix'"));
    try std.testing.expectEqualStrings("ls", extractBaseCommand("ls"));
}

test "extractBaseCommand strips env prefix" {
    try std.testing.expectEqualStrings("cargo test", extractBaseCommand("RUST_BACKTRACE=1 cargo test"));
    try std.testing.expectEqualStrings("npm start", extractBaseCommand("NODE_ENV=production npm start"));
}

test "commandSimilarity identical commands" {
    try std.testing.expectEqual(@as(f64, 1.0), commandSimilarity("git commit", "git commit"));
}

test "commandSimilarity different base commands" {
    try std.testing.expectEqual(@as(f64, 0.0), commandSimilarity("git status", "npm install"));
}

test "commandSimilarity same base different args" {
    const sim = commandSimilarity("git commit --ammend", "git commit --amend");
    // Same base (0.5) + 0 intersection / 2 union * 0.5 = 0.5
    try std.testing.expectEqual(@as(f64, 0.5), sim);
}

test "commandSimilarity partial arg overlap" {
    const sim = commandSimilarity("git commit --amend -m 'fix'", "git commit --amend -m 'bug'");
    // Same base (0.5) + intersection(--amend, -m) / union(--amend, -m, 'fix', 'bug') * 0.5
    // = 0.5 + 2/4 * 0.5 = 0.75
    try std.testing.expectEqual(@as(f64, 0.75), sim);
}

test "isCommandError requires error flag" {
    try std.testing.expect(!isCommandError(false, "error: unknown flag"));
    try std.testing.expect(isCommandError(true, "error: unknown flag"));
}

test "isCommandError filters user rejection" {
    try std.testing.expect(!isCommandError(true, "The user doesn't want to proceed"));
    try std.testing.expect(!isCommandError(true, "Operation cancelled by user"));
    try std.testing.expect(isCommandError(true, "error: permission denied"));
}

test "isCommandError requires error content" {
    try std.testing.expect(!isCommandError(true, "All good, success!"));
    try std.testing.expect(isCommandError(true, "error: something failed"));
    try std.testing.expect(isCommandError(true, "unknown flag --foo"));
    try std.testing.expect(isCommandError(true, "invalid option"));
}

test "classifyError unknown flag" {
    try std.testing.expectEqual(ErrorType.unknown_flag, classifyError("error: unexpected argument '--foo'"));
    try std.testing.expectEqual(ErrorType.unknown_flag, classifyError("unknown option: --bar"));
    try std.testing.expectEqual(ErrorType.unknown_flag, classifyError("unrecognized flag: -x"));
}

test "classifyError command not found" {
    try std.testing.expectEqual(ErrorType.command_not_found, classifyError("bash: foobar: command not found"));
    try std.testing.expectEqual(ErrorType.command_not_found, classifyError("'xyz' is not recognized as an internal or external command"));
}

test "classifyError all types" {
    try std.testing.expectEqual(ErrorType.wrong_path, classifyError("No such file or directory: foo.txt"));
    try std.testing.expectEqual(ErrorType.missing_arg, classifyError("error: --output requires a value"));
    try std.testing.expectEqual(ErrorType.permission_denied, classifyError("permission denied: /etc/shadow"));
    try std.testing.expectEqual(ErrorType.other, classifyError("something went wrong"));
}

test "isTddCycleError detects compilation errors" {
    try std.testing.expect(isTddCycleError(.other, "error[E0425]: cannot find value `x`"));
    try std.testing.expect(isTddCycleError(.other, "aborting due to previous error"));
}

test "isTddCycleError detects test failures" {
    try std.testing.expect(isTddCycleError(.other, "test result: FAILED. 1 passed; 2 failed"));
    try std.testing.expect(isTddCycleError(.other, "3 tests failed"));
}

test "isTddCycleError allows real CLI errors" {
    try std.testing.expect(!isTddCycleError(.unknown_flag, "error: unexpected argument '--foo'"));
    try std.testing.expect(!isTddCycleError(.wrong_path, "No such file or directory"));
}

test "differsOnlyByPath detects path exploration" {
    // Two commands with same base and very high similarity but not identical
    // "cat" has 1 token base, so "cat file1.txt" base = "cat file1.txt"
    // Actually for single-arg commands like "cat file1.txt", base = "cat file1.txt"
    // Let's use a command where base is 2 tokens and args differ slightly
    // e.g. "git log --oneline file1.txt" vs "git log --oneline file2.txt"
    // base = "git log", args = {--oneline, file1.txt} vs {--oneline, file2.txt}
    // intersection = 1 (--oneline), union = 3
    // sim = 0.5 + 1/3 * 0.5 = 0.667 -- not > 0.9
    // Need higher overlap for > 0.9
    // e.g. "git log --oneline --graph --all file1.txt" vs "git log --oneline --graph --all file2.txt"
    // args = {--oneline, --graph, --all, file1.txt} vs {--oneline, --graph, --all, file2.txt}
    // intersection = 3, union = 5
    // sim = 0.5 + 3/5 * 0.5 = 0.8 -- still not > 0.9
    // Need even more overlap
    // 10 shared args, 1 different each: intersection=10, union=12
    // sim = 0.5 + 10/12 * 0.5 = 0.917 -- > 0.9!
    // Simpler: different base commands should return false
    try std.testing.expect(!differsOnlyByPath("git status", "npm install"));
}

test "extractDiffToken basic" {
    const allocator = std.testing.allocator;
    const result = try extractDiffToken(allocator, "git commit --ammend", "git commit --amend");
    defer allocator.free(result);
    // --ammend removed, --amend added
    try std.testing.expectEqualStrings("--ammend \xe2\x86\x92 --amend", result);
}

test "extractDiffToken added only" {
    const allocator = std.testing.allocator;
    const result = try extractDiffToken(allocator, "git commit", "git commit --amend");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("added --amend", result);
}

test "extractDiffToken removed only" {
    const allocator = std.testing.allocator;
    const result = try extractDiffToken(allocator, "git commit --amend", "git commit");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("removed --amend", result);
}

test "findCorrections basic fail to success" {
    const allocator = std.testing.allocator;
    const commands = [_]CommandExecution{
        .{
            .command = "git commit --ammend",
            .is_error = true,
            .output = "error: unexpected argument '--ammend'",
        },
        .{
            .command = "git commit --amend",
            .is_error = false,
            .output = "[main abc123] Fix bug",
        },
    };

    const corrections = try findCorrections(allocator, &commands);
    defer allocator.free(corrections);

    try std.testing.expectEqual(@as(usize, 1), corrections.len);
    try std.testing.expectEqualStrings("git commit --ammend", corrections[0].wrong_command);
    try std.testing.expectEqualStrings("git commit --amend", corrections[0].right_command);
    try std.testing.expect(corrections[0].confidence >= 0.6);
}

test "findCorrections window limit" {
    const allocator = std.testing.allocator;
    const commands = [_]CommandExecution{
        .{
            .command = "git commit --ammend",
            .is_error = true,
            .output = "error: unexpected argument '--ammend'",
        },
        .{ .command = "ls", .is_error = false, .output = "file1.txt\nfile2.txt" },
        .{ .command = "pwd", .is_error = false, .output = "/home/user" },
        .{ .command = "echo test", .is_error = false, .output = "test" },
        // Outside CORRECTION_WINDOW (3)
        .{
            .command = "git commit --amend",
            .is_error = false,
            .output = "[main abc123] Fix",
        },
    };

    const corrections = try findCorrections(allocator, &commands);
    defer allocator.free(corrections);

    try std.testing.expectEqual(@as(usize, 0), corrections.len);
}

test "findCorrections excludes TDD cycle" {
    const allocator = std.testing.allocator;
    const commands = [_]CommandExecution{
        .{
            .command = "cargo test",
            .is_error = true,
            .output = "error[E0425]: cannot find value `x`\ntest result: FAILED",
        },
        .{
            .command = "cargo test",
            .is_error = false,
            .output = "test result: ok. 5 passed",
        },
    };

    const corrections = try findCorrections(allocator, &commands);
    defer allocator.free(corrections);

    try std.testing.expectEqual(@as(usize, 0), corrections.len);
}

test "deduplicateCorrections merges same pattern" {
    const allocator = std.testing.allocator;
    const pairs = [_]CorrectionPair{
        .{
            .wrong_command = "git commit --ammend",
            .right_command = "git commit --amend",
            .error_output = "error: unexpected argument '--ammend'",
            .error_type = .unknown_flag,
            .confidence = 0.8,
        },
        .{
            .wrong_command = "git commit --ammend",
            .right_command = "git commit --amend",
            .error_output = "error: unexpected argument '--ammend'",
            .error_type = .unknown_flag,
            .confidence = 0.9,
        },
    };

    const rules = try deduplicateCorrections(allocator, &pairs);
    defer allocator.free(rules);

    try std.testing.expectEqual(@as(usize, 1), rules.len);
    try std.testing.expectEqual(@as(usize, 2), rules[0].occurrences);
    try std.testing.expectEqualStrings("git commit", rules[0].base_command);
}

test "findCorrections excludes path exploration" {
    const allocator = std.testing.allocator;
    // Build commands where wrong and right differ only by path (similarity > 0.9)
    // Need many shared args so Jaccard > 0.9
    const commands = [_]CommandExecution{
        .{
            .command = "git log --oneline --graph --all --decorate --color --abbrev-commit --date=short --author=me --since=2024-01-01 src/old_path.zig",
            .is_error = true,
            .output = "error: not found",
        },
        .{
            .command = "git log --oneline --graph --all --decorate --color --abbrev-commit --date=short --author=me --since=2024-01-01 src/new_path.zig",
            .is_error = false,
            .output = "abc123 Fix bug",
        },
    };

    const corrections = try findCorrections(allocator, &commands);
    defer allocator.free(corrections);

    // Should be filtered out because commands differ only by path (sim > 0.9)
    try std.testing.expectEqual(@as(usize, 0), corrections.len);
}

test "deduplicateCorrections keeps different patterns" {
    const allocator = std.testing.allocator;
    const pairs = [_]CorrectionPair{
        .{
            .wrong_command = "git commit --ammend",
            .right_command = "git commit --amend",
            .error_output = "error: unexpected argument '--ammend'",
            .error_type = .unknown_flag,
            .confidence = 0.8,
        },
        .{
            .wrong_command = "npm instal",
            .right_command = "npm install",
            .error_output = "error: command not found: instal",
            .error_type = .command_not_found,
            .confidence = 0.7,
        },
    };

    const rules = try deduplicateCorrections(allocator, &pairs);
    defer allocator.free(rules);

    // Two different patterns should produce two rules
    try std.testing.expectEqual(@as(usize, 2), rules.len);
    // Each should have occurrence count of 1
    try std.testing.expectEqual(@as(usize, 1), rules[0].occurrences);
    try std.testing.expectEqual(@as(usize, 1), rules[1].occurrences);
}

test "containsCI basic" {
    try std.testing.expect(containsCI("Hello World", "hello"));
    try std.testing.expect(containsCI("ERROR: something", "error"));
    try std.testing.expect(!containsCI("Hello", "xyz"));
}
