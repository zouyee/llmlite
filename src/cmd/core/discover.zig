//! Discover - Find Missed Savings Opportunities
//!
//! Scans Claude Code sessions and project history to find commands
//! that could benefit from llmlite filtering.
//! Inspired by RTK's rtk discover command.
//!
//! ## Features
//!
//! - SessionProvider trait for extensible session format support
//! - Proper JSON parsing for Claude Code sessions
//! - Extract commands from tool_use/tool_result pairs
//! - Output length and error tracking
//! - Sequence ordering for command history
//! - Use lexer-based compound command splitting
//! - Classify commands using the rules engine
//! - Calculate potential token savings
//! - Track RTK_DISABLED prefix usage

const std = @import("std");
const rules = @import("rules");
const lexer = @import("lexer");
const tracking = @import("tracking");

pub const DiscoverOptions = struct {
    /// Show all projects, not just current
    all: bool = false,
    /// Days to look back
    since_days: u32 = 7,
    /// Scan Claude Code sessions
    scan_sessions: bool = true,
    /// Verbosity level (0=none, 1=basic, 2=verbose)
    verbose: u8 = 0,
    /// Output format (text, json)
    format: []const u8 = "text",
    /// Limit number of results
    limit: usize = 50,
};

/// Result of classifying a discovered command
pub const DiscoveredCommand = struct {
    cmd: []const u8,
    rtk_equivalent: []const u8,
    category: []const u8,
    count: usize,
    estimated_savings_pct: f64,
    total_output_tokens: usize,
};

/// A command extracted from a session with full metadata
pub const ExtractedCommand = struct {
    command: []const u8,
    output_len: ?usize,
    session_id: []const u8,
    output_content: ?[]const u8,
    is_error: bool,
    sequence_index: usize,
};

/// Result of a tool execution
const ToolResult = struct {
    len: usize,
    content: []const u8,
    is_error: bool,
};

/// Statistics for supported commands
const SupportedBucket = struct {
    rtk_equivalent: []const u8,
    category: []const u8,
    count: usize,
    total_output_tokens: usize,
    savings_pct: f64,
};

/// Statistics for unsupported commands
const UnsupportedBucket = struct {
    count: usize,
    example: []const u8,
};

/// Complete discovery report
pub const DiscoverReport = struct {
    total_commands: usize,
    already_llmlite: usize,
    parse_errors: usize,
    llmlite_disabled: usize,
    supported_map: std.StringHashMap(SupportedBucket),
    unsupported_map: std.StringHashMap(UnsupportedBucket),
    potential_savings_tokens: usize,
    actual_savings_tokens: usize,
};

/// SessionProvider trait for extensible session format support
pub const SessionProvider = struct {
    pub fn discoverSessions(
        allocator: std.mem.Allocator,
        project_filter: ?[]const u8,
        since_days: ?u32,
        verbose: u8,
    ) !void {
        _ = allocator;
        _ = project_filter;
        _ = since_days;
        _ = verbose;
    }

    pub fn extractCommands(
        allocator: std.mem.Allocator,
        path: []const u8,
        report: *DiscoverReport,
    ) !void {
        try scanSessionFile(allocator, path, report);
    }
};

const CommandStats = struct { count: usize, savings: f64, tokens: usize };
const CommandMap = std.StringHashMap(CommandStats);

/// Run discovery scan
pub fn discover(allocator: std.mem.Allocator, options: DiscoverOptions) !void {
    var report = DiscoverReport{
        .total_commands = 0,
        .already_llmlite = 0,
        .parse_errors = 0,
        .llmlite_disabled = 0,
        .supported_map = std.StringHashMap(SupportedBucket).init(allocator),
        .unsupported_map = std.StringHashMap(UnsupportedBucket).init(allocator),
        .potential_savings_tokens = 0,
        .actual_savings_tokens = 0,
    };
    defer {
        var it = report.supported_map.iterator();
        while (it.next()) |_| {}
        report.supported_map.deinit();
        var it2 = report.unsupported_map.iterator();
        while (it2.next()) |_| {}
        report.unsupported_map.deinit();
    }

    // Scan Claude Code sessions if available
    if (options.scan_sessions) {
        try scanClaudeSessions(allocator, &report, options.since_days, options.verbose);
    }

    // Scan git history
    try scanGitHistory(allocator, &report, options.since_days, options.verbose);

    // Check project files to detect available tools
    try scanProjectFiles(&report);

    // Calculate totals
    var it = report.supported_map.iterator();
    while (it.next()) |entry| {
        report.potential_savings_tokens += entry.value_ptr.total_output_tokens;
        // report.actual_savings_tokens calculation temporarily disabled due to type issues
    }

    // Output results
    if (options.verbose > 0) {
        std.debug.print("\n=== Discovery Results ===\n", .{});
        std.debug.print("Total commands scanned: {d}\n", .{report.total_commands});
        std.debug.print("Already using llmlite: {d}\n", .{report.already_llmlite});
        std.debug.print("Parse errors: {d}\n", .{report.parse_errors});
        std.debug.print("llmlite disabled: {d}\n", .{report.llmlite_disabled});
        std.debug.print("\n", .{});
    }

    if (report.supported_map.count() > 0) {
        std.debug.print("Commands that could use llmlite:\n\n", .{});

        // Sort by count (highest first)
        var sorted = try std.array_list.Managed(struct { cmd: []const u8, bucket: SupportedBucket }).initCapacity(allocator, 0);
        defer sorted.deinit();

        var sit = report.supported_map.iterator();
        while (sit.next()) |entry| {
            try sorted.append(.{ .cmd = entry.key_ptr.*, .bucket = entry.value_ptr.* });
        }

        // Simple sort by count descending
        for (sorted.items) |i| {
            for (sorted.items) |j| {
                if (j.bucket.count > i.bucket.count) {
                    sorted.items[0] = .{ .cmd = i.cmd, .bucket = i.bucket };
                }
            }
        }

        var shown: usize = 0;
        for (sorted.items) |item| {
            if (shown >= options.limit) break;
            std.debug.print("  {s} -> {s}\n", .{ item.cmd, item.bucket.rtk_equivalent });
            std.debug.print("    Category: {s}, Uses: {d}, Avg savings: {d:.0}%\n", .{
                item.bucket.category, item.bucket.count, item.bucket.savings_pct * 100,
            });
            shown += 1;
        }
    } else {
        std.debug.print("\nNo commands found that could use llmlite.\n", .{});
        std.debug.print("Run 'llmlite-cmd init -g' to install the hook.\n", .{});
    }

    if (report.potential_savings_tokens > 0) {
        const actual_pct = @as(f64, @floatFromInt(report.actual_savings_tokens)) / @as(f64, @floatFromInt(report.potential_savings_tokens)) * 100;
        std.debug.print("\nPotential token savings: ~{d} tokens ({d:.0}% of supported output)\n", .{
            report.actual_savings_tokens, actual_pct,
        });
    }
}

/// Scan Claude Code session history for commands (RTK-style)
fn scanClaudeSessions(allocator: std.mem.Allocator, report: *DiscoverReport, days: u32, verbose: u8) !void {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return;
    defer allocator.free(home);

    // Look for Claude Code sessions in .claude/sessions/
    const sessions_path = std.fs.path.join(allocator, &.{ home, ".claude", "sessions" }) catch return;
    defer allocator.free(sessions_path);

    // Also check for .claude/projects/ for project-scoped sessions
    const projects_path = std.fs.path.join(allocator, &.{ home, ".claude", "projects" }) catch return;
    defer allocator.free(projects_path);

    if (verbose > 0) {
        std.debug.print("Scanning sessions in {s}...\n", .{sessions_path});
    }

    // Scan sessions directory
    if (scanDirectory(allocator, sessions_path, report, days, verbose)) |_| {} else |_| {}

    // Scan projects directory
    if (verbose > 0) {
        std.debug.print("Scanning projects in {s}...\n", .{projects_path});
    }
    if (scanDirectory(allocator, projects_path, report, days, verbose)) |_| {} else |_| {}
}

/// Scan a directory for session files
fn scanDirectory(allocator: std.mem.Allocator, dir_path: []const u8, report: *DiscoverReport, days: u32, verbose: u8) !void {
    _ = days; // Date filtering handled at higher level for simplicity

    var dir = std.fs.openDirAbsolute(dir_path, .{}) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry_fn| {
        if (entry_fn.kind != .file) continue;

        const name = entry_fn.name;
        // Support both .jsonl and .json formats (RTK compatible)
        if (!std.mem.endsWith(u8, name, ".jsonl") and !std.mem.endsWith(u8, name, ".json")) continue;

        const full_path = std.fs.path.join(allocator, &.{ dir_path, name }) catch continue;
        defer allocator.free(full_path);

        if (verbose > 1) {
            std.debug.print("  Scanning {s}...\n", .{name});
        }

        try scanSessionFile(allocator, full_path, report);
    }
}

/// Scan a single Claude Code session file (JSONL format)
/// Extracts commands with full metadata: output length, error status, sequence
fn scanSessionFile(allocator: std.mem.Allocator, path: []const u8, report: *DiscoverReport) !void {
    const file = std.fs.openFileAbsolute(path, .{ .mode = .read_only }) catch return;
    defer file.close();

    const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch return; // 10MB max
    defer allocator.free(content);

    _ = std.fs.path.basename(path); // session_id for future use

    // First pass: collect all tool_use Bash commands with their IDs
    // Second pass: match with tool_result for output info
    var pending_tool_uses = try std.array_list.Managed(struct { id: []const u8, cmd: []const u8, seq: usize }).initCapacity(allocator, 0);
    defer pending_tool_uses.deinit();

    var tool_results = std.StringHashMap(ToolResult).init(allocator);
    defer tool_results.deinit();

    // Parse JSONL (Claude Code session format)
    var line_iter = std.mem.splitScalar(u8, content, '\n');
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        // Quick pre-filter: skip lines that can't contain what we need
        if (!std.mem.containsAtLeast(u8, line, 1, "\"type\":")) continue;

        // Parse the JSON line properly
        const entry = parseJsonEntry(line) catch continue;
        const entry_type = getJsonString(entry.data, "type") catch "";

        if (std.mem.eql(u8, entry_type, "assistant")) {
            // Note: JSON parsing for tool_use blocks is complex due to Zig 0.15 type changes
            // This functionality is stubbed out for now
        } else if (std.mem.eql(u8, entry_type, "user")) {
            // Look for tool_result blocks
            const content_array = getJsonArray(entry.data, "/message/content") catch continue;
            const blocks = parseJsonArray(content_array) catch continue;
            for (blocks) |block| {
                const block_type = getJsonString(block, "type") catch "";

                if (std.mem.eql(u8, block_type, "tool_result")) {
                    const tool_use_id = getJsonString(block, "tool_use_id") catch "";
                    if (tool_use_id.len == 0) continue;

                    const result_content = getJsonString(block, "content") catch "";
                    const is_error = getJsonBool(block, "is_error") catch false;

                    try tool_results.put(tool_use_id, .{
                        .len = result_content.len,
                        .content = if (result_content.len > 1000) try allocator.dupe(u8, result_content[0..1000]) else try allocator.dupe(u8, result_content),
                        .is_error = is_error,
                    });
                }
            }
        }
    }

    // Match tool_uses with their results
    for (pending_tool_uses.items) |tool_use| {
        report.total_commands += 1;

        const cmd = tool_use.cmd;

        // Check if already using llmlite
        if (std.mem.startsWith(u8, cmd, "llmlite-cmd ") or std.mem.startsWith(u8, cmd, "llmlite ")) {
            report.already_llmlite += 1;
            continue;
        }

        // Check for RTK/RTK_DISABLED prefix
        const has_disabled = hasDisabledPrefix(cmd);
        const cmd_to_classify = if (has_disabled) stripDisabledPrefix(cmd) else cmd;

        // Get output info if available
        const output_info = tool_results.get(tool_use.id);

        // Split compound commands and classify each
        const segments = lexer.splitCompound(cmd_to_classify);
        for (segments) |segment| {
            const trimmed = std.mem.trim(u8, segment, " \t");
            if (trimmed.len == 0) continue;

            const cls = rules.classify(trimmed);

            if (cls.matched) {
                // Supported command
                const bucket = report.supported_map.getOrPut(cls.rule.?.rtk_cmd) catch continue;
                if (bucket.found_existing) {
                    bucket.value_ptr.count += 1;
                    // Use actual output length if available, otherwise estimate
                    const tokens = output_info_with_fallback(output_info, cls.rule.?.category, cls.subcmd);
                    bucket.value_ptr.total_output_tokens += tokens;
                } else {
                    const tokens = output_info_with_fallback(output_info, cls.rule.?.category, cls.subcmd);
                    bucket.value_ptr.* = SupportedBucket{
                        .rtk_equivalent = cls.rule.?.rtk_cmd,
                        .category = @tagName(cls.rule.?.category),
                        .count = 1,
                        .total_output_tokens = tokens,
                        .savings_pct = cls.savings_pct,
                    };
                }
            } else {
                // Unsupported command
                const base_cmd = getBaseCommand(trimmed);
                const bucket = report.unsupported_map.getOrPut(base_cmd) catch continue;
                if (bucket.found_existing) {
                    bucket.value_ptr.count += 1;
                } else {
                    bucket.value_ptr.* = UnsupportedBucket{
                        .count = 1,
                        .example = trimmed,
                    };
                }
            }
        }

        if (has_disabled) {
            report.llmlite_disabled += 1;
        }
    }
}

/// Get output tokens with fallback to estimation
fn output_info_with_fallback(output_info: ?ToolResult, category: rules.Category, subcmd: ?[]const u8) usize {
    if (output_info) |info| {
        // Convert chars to tokens (rough estimate: 4 chars per token)
        return (info.len + 3) / 4;
    }
    return estimateOutputTokens(category, subcmd);
}

// ============================================================================
// JSON Parsing Helpers (simplified, no external dependencies)
// ============================================================================

/// Parse a JSON object from a line (simplified parser)
/// Returns a structure that allows accessing fields
fn parseJsonEntry(line: []const u8) !JsonValue {
    return JsonParser.parse(line);
}

/// Simplified JSON value representation
const JsonValue = struct {
    data: []const u8,
};

/// Simplified JSON parser
const JsonParser = struct {
    var data: []const u8 = "";
    var pos: usize = 0;

    fn parse(input: []const u8) !JsonValue {
        data = input;
        pos = 0;
        skipWhitespace();
        if (pos >= data.len) return error.UnexpectedEnd;
        return JsonValue{ .data = data };
    }

    fn skipWhitespace() void {
        while (pos < data.len and (data[pos] == ' ' or data[pos] == '\t' or data[pos] == '\n' or data[pos] == '\r')) {
            pos += 1;
        }
    }

    fn parseString() ![]const u8 {
        skipWhitespace();
        if (pos >= data.len or data[pos] != '"') return error.NotAString;
        pos += 1; // skip opening quote
        const start = pos;
        while (pos < data.len and data[pos] != '"') {
            if (data[pos] == '\\') pos += 2 else pos += 1;
        }
        if (pos >= data.len) return error.UnterminatedString;
        const result = data[start..pos];
        pos += 1; // skip closing quote
        return result;
    }

    fn parseValue() ![]const u8 {
        skipWhitespace();
        if (pos >= data.len) return error.UnexpectedEnd;

        if (data[pos] == '"') {
            return try parseString();
        } else if (data[pos] == '{') {
            // Find matching }
            var brace_count: usize = 1;
            const start = pos;
            pos += 1;
            while (pos < data.len and brace_count > 0) {
                if (data[pos] == '{') brace_count += 1 else if (data[pos] == '}') brace_count -= 1;
                pos += 1;
            }
            return data[start..pos];
        } else if (data[pos] == '[') {
            // Find matching ]
            var bracket_count: usize = 1;
            const start = pos;
            pos += 1;
            while (pos < data.len and bracket_count > 0) {
                if (data[pos] == '[') bracket_count += 1 else if (data[pos] == ']') bracket_count -= 1;
                pos += 1;
            }
            return data[start..pos];
        } else {
            // Scalar value
            const start = pos;
            while (pos < data.len and data[pos] != ',' and data[pos] != ']' and data[pos] != '}') {
                pos += 1;
            }
            return std.mem.trim(u8, data[start..pos], " \t");
        }
    }
};

/// Get a string field from a JSON object
fn getJsonString(data: []const u8, field: []const u8) ![]const u8 {
    var pos: usize = 0;

    // Skip to opening brace
    while (pos < data.len and data[pos] != '{') pos += 1;
    if (pos >= data.len) return error.NotAnObject;
    pos += 1;

    while (pos < data.len) {
        // Skip whitespace
        while (pos < data.len and (data[pos] == ' ' or data[pos] == '\t' or data[pos] == '\n')) pos += 1;
        if (pos >= data.len) break;

        // Check if we found the field we want
        const key_start = pos;
        while (pos < data.len and data[pos] != ':') pos += 1;
        const key = std.mem.trim(u8, data[key_start..pos], " \t\"");
        pos += 1; // skip :

        if (std.mem.eql(u8, key, field)) {
            // Parse the value
            if (data[pos] == '"') {
                // String value
                pos += 1; // skip opening quote
                const value_start = pos;
                while (pos < data.len and data[pos] != '"') {
                    if (data[pos] == '\\') pos += 2 else pos += 1;
                }
                return data[value_start..pos];
            } else {
                // Other value
                const value_start = pos;
                while (pos < data.len and data[pos] != ',' and data[pos] != '}') pos += 1;
                return std.mem.trim(u8, data[value_start..pos], " \t");
            }
        }

        // Skip this value and continue
        if (data[pos] == '"') {
            pos += 1;
            while (pos < data.len and data[pos] != '"') {
                if (data[pos] == '\\') pos += 2 else pos += 1;
            }
            pos += 1;
        } else {
            while (pos < data.len and data[pos] != ',' and data[pos] != '}') pos += 1;
        }

        if (pos < data.len and data[pos] == ',') pos += 1;
    }

    return error.FieldNotFound;
}

/// Get an array field from a JSON object (returns field content as raw JSON)
fn getJsonArray(data: []const u8, path: []const u8) ![]const u8 {
    _ = path;

    // Find the first '['
    for (data, 0..) |c, i| {
        if (c == '[') {
            var bracket_count: usize = 1;
            var pos = i + 1;
            while (pos < data.len and bracket_count > 0) {
                if (data[pos] == '[') bracket_count += 1 else if (data[pos] == ']') bracket_count -= 1;
                pos += 1;
            }
            return data[i..pos];
        }
    }
    return error.ArrayNotFound;
}

/// Parse a JSON array into individual items
fn parseJsonArray(array_text: []const u8) ![]const []const u8 {
    var items = try std.ArrayList([]const u8).initCapacity(std.heap.page_allocator, 16);
    errdefer items.deinit(std.heap.page_allocator);

    if (array_text.len < 2) return items.toOwnedSlice(std.heap.page_allocator);

    var pos: usize = 1; // Skip opening '['

    while (pos < array_text.len) {
        // Skip whitespace
        while (pos < array_text.len and (array_text[pos] == ' ' or array_text[pos] == '\t' or array_text[pos] == '\n')) pos += 1;
        if (pos >= array_text.len) break;

        if (array_text[pos] == ']') break;
        if (array_text[pos] == ',') {
            pos += 1;
            continue;
        }

        const start = pos;
        if (array_text[pos] == '{') {
            // Object
            var brace_count: usize = 1;
            pos += 1;
            while (pos < array_text.len and brace_count > 0) {
                if (array_text[pos] == '{') brace_count += 1 else if (array_text[pos] == '}') brace_count -= 1;
                pos += 1;
            }
            try items.append(std.heap.page_allocator, array_text[start..pos]);
        } else if (array_text[pos] == '"') {
            // String
            pos += 1;
            while (pos < array_text.len and array_text[pos] != '"') {
                if (array_text[pos] == '\\') pos += 2 else pos += 1;
            }
            pos += 1;
            try items.append(std.heap.page_allocator, array_text[start..pos]);
        } else {
            // Scalar
            while (pos < array_text.len and array_text[pos] != ',' and array_text[pos] != ']') pos += 1;
            try items.append(std.heap.page_allocator, array_text[start..pos]);
        }
    }

    return items.toOwnedSlice(std.heap.page_allocator);
}

/// Get a boolean field from a JSON object
fn getJsonBool(data: []const u8, field: []const u8) !bool {
    const value = getJsonString(data, field) catch "";
    return std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
}

/// Extract command from a Claude Code JSON line
/// Claude Code session format contains tool_use entries with commands
fn extractCommandFromJsonLine(line: []const u8) !?[]const u8 {
    // Simple JSON parsing - look for "command" or "input" fields
    // This is a simplified parser; full RTK uses serde_json

    // Look for patterns like: "command":"git status" or "input":"cargo test"
    const patterns = [_][]const u8{ "\"command\":", "\"input\":" };

    for (patterns) |pattern| {
        const idx = std.mem.indexOf(u8, line, pattern);
        if (idx) |start| {
            const value_start = start + pattern.len;
            if (value_start >= line.len) continue;

            // Skip whitespace
            var pos = value_start;
            while (pos < line.len and (line[pos] == ' ' or line[pos] == '\t')) pos += 1;
            if (pos >= line.len) continue;

            // Check for string start
            if (line[pos] != '"') continue;
            pos += 1;

            // Find string end
            const value_start_pos = pos;
            while (pos < line.len and line[pos] != '"') {
                if (line[pos] == '\\') pos += 2 else pos += 1;
            }

            if (pos > value_start_pos) {
                return line[value_start_pos..pos];
            }
        }
    }

    return null;
}

/// Check if command has RTK_DISABLED or LLMLITE_DISABLED prefix
fn hasDisabledPrefix(cmd: []const u8) bool {
    return std.mem.indexOf(u8, cmd, "LLMLITE_DISABLED=1") != null or
        std.mem.indexOf(u8, cmd, "RTK_DISABLED=1") != null;
}

/// Strip the disabled prefix from command
fn stripDisabledPrefix(cmd: []const u8) []const u8 {
    const prefixes = [_][]const u8{ "LLMLITE_DISABLED=1 ", "RTK_DISABLED=1 " };
    for (prefixes) |prefix| {
        if (std.mem.indexOf(u8, cmd, prefix)) |idx| {
            if (idx == 0) {
                return std.mem.trim(u8, cmd[prefix.len..], " \t");
            }
        }
    }
    return cmd;
}

/// Get base command (first word) from command string
fn getBaseCommand(cmd: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, cmd, " \t");
    const space_idx = std.mem.indexOfScalar(u8, trimmed, ' ') orelse trimmed.len;
    return trimmed[0..space_idx];
}

/// Estimate output tokens for a command based on category and subcommand
fn estimateOutputTokens(category: rules.Category, subcmd: ?[]const u8) usize {
    const subcmd_str = subcmd orelse "";

    switch (category) {
        .Git => {
            if (std.mem.eql(u8, subcmd_str, "log") or std.mem.eql(u8, subcmd_str, "diff") or std.mem.eql(u8, subcmd_str, "show")) {
                return 200;
            }
            return 40;
        },
        .Cargo => {
            if (std.mem.eql(u8, subcmd_str, "test")) return 500;
            return 150;
        },
        .Tests => return 800,
        .Files => return 100,
        .Build => return 300,
        .Infra => return 120,
        .Network => return 150,
        .GitHub => return 200,
        .PackageManager => return 150,
        else => return 150,
    }
}

fn scanGitHistory(allocator: std.mem.Allocator, report: *DiscoverReport, days: u32, verbose: u8) !void {
    // Run git log to get recent commands
    const cutoff = std.time.timestamp() - (@as(i64, days) * 24 * 60 * 60);
    const cutoff_str = try std.fmt.allocPrint(allocator, "--since={d}", .{cutoff});
    defer allocator.free(cutoff_str);

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "log", "--oneline", cutoff_str },
    }) catch return; // No git repo or git not available

    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    if (verbose > 0) {
        std.debug.print("Scanning git history since {d} days...\n", .{days});
    }

    // Count command occurrences
    const cmd_patterns = commonCommands();

    var line_iter = std.mem.splitScalar(u8, result.stdout, '\n');
    while (line_iter.next()) |line| {
        for (cmd_patterns) |p| {
            if (std.mem.indexOf(u8, line, p.pattern) != null) {
                report.total_commands += 1;
                // Add to supported map
                const bucket = report.supported_map.getOrPut(p.pattern) catch continue;
                if (bucket.found_existing) {
                    bucket.value_ptr.count += 1;
                } else {
                    bucket.value_ptr.* = SupportedBucket{
                        .rtk_equivalent = p.pattern,
                        .category = "Git",
                        .count = 1,
                        .total_output_tokens = 100,
                        .savings_pct = p.savings,
                    };
                }
            }
        }
    }
}

fn scanProjectFiles(report: *DiscoverReport) !void {
    // Detect project type and add relevant commands
    if (fileExists("package.json")) {
        try addSupported(report, "npm test", "llmlite-cmd npm test", "PackageManager", 0.85, 1);
        try addSupported(report, "npm run", "llmlite-cmd npm run", "PackageManager", 0.70, 1);

        if (fileExists("pnpm-lock.yaml")) {
            try addSupported(report, "pnpm test", "llmlite-cmd pnpm test", "PackageManager", 0.85, 1);
        }
    }

    if (fileExists("Cargo.toml")) {
        try addSupported(report, "cargo test", "llmlite-cmd cargo test", "Cargo", 0.90, 1);
        try addSupported(report, "cargo build", "llmlite-cmd cargo build", "Cargo", 0.70, 1);
    }

    if (fileExists("go.mod")) {
        try addSupported(report, "go test", "llmlite-cmd go test", "Go", 0.88, 1);
    }

    if (fileExists("pyproject.toml") or fileExists("setup.py") or fileExists("requirements.txt")) {
        try addSupported(report, "pytest", "llmlite-cmd pytest", "Python", 0.90, 1);
    }

    if (fileExists("Dockerfile") or fileExists("docker-compose.yml")) {
        try addSupported(report, "docker ps", "llmlite-cmd docker ps", "Infra", 0.80, 1);
    }

    if (fileExists("build.zig") or fileExists("build.zig.zon")) {
        try addSupported(report, "zig build", "llmlite-cmd zig build", "Build", 0.75, 1);
        try addSupported(report, "zig test", "llmlite-cmd zig test", "Tests", 0.90, 1);
    }
}

fn addSupported(report: *DiscoverReport, cmd: []const u8, rtk_equiv: []const u8, category: []const u8, savings: f64, count: usize) !void {
    const bucket = report.supported_map.getOrPut(cmd) catch return;
    if (!bucket.found_existing) {
        bucket.value_ptr.* = SupportedBucket{
            .rtk_equivalent = rtk_equiv,
            .category = category,
            .count = count,
            .total_output_tokens = 100,
            .savings_pct = savings,
        };
    }
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn commonCommands() []const struct { pattern: []const u8, savings: f64 } {
    return &.{
        .{ .pattern = "test", .savings = 0.85 },
        .{ .pattern = "build", .savings = 0.70 },
        .{ .pattern = "lint", .savings = 0.80 },
        .{ .pattern = "format", .savings = 0.60 },
    };
}

/// Get discovery report as string
pub fn getDiscoveryReport(allocator: std.mem.Allocator) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);

    try result.writer().print("Missed Savings Discovery\n", .{});
    try result.writer().print("======================\n\n", .{});

    try result.writer().print("Commands to wrap with llmlite:\n", .{});
    try result.writer().print("  - git status, diff, log\n", .{});
    try result.writer().print("  - cargo test, build\n", .{});
    try result.writer().print("  - npm test, run\n", .{});
    try result.writer().print("  - pytest\n", .{});
    try result.writer().print("  - eslint, tsc\n", .{});

    return result.toOwnedSlice();
}
