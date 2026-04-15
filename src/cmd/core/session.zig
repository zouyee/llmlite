//! Session Analysis - Claude Code Session Tracking
//!
//! Scans Claude Code sessions to calculate RTK/llmlite adoption rate
//! and find missed savings opportunities.
//! Inspired by RTK's session_cmd.rs and discover modules.
//!
//! ## Features
//!
//! - Discover Claude Code session files from ~/.claude/projects/
//! - Parse JSONL format to extract Bash tool calls
//! - Match tool_use with tool_result for output length
//! - Classify commands using rules engine
//! - Calculate llmlite adoption rate
//! - Find unsupported commands that could benefit
//! - Detect LLMLITE_DISABLED/RTK_DISABLED bypasses

const std = @import("std");
const rules = @import("rules");
const lexer = @import("lexer");
const fs = std.fs;

pub const SessionOptions = struct {
    /// Show all projects, not just current
    all: bool = false,
    /// Days to look back
    since_days: u32 = 30,
    /// Output format (text, json)
    format: []const u8 = "text",
    /// Verbosity level
    verbose: u8 = 0,
};

/// A summarized session for display
pub const SessionSummary = struct {
    id: []const u8,
    date: []const u8,
    total_cmds: usize,
    llmlite_cmds: usize,
    output_tokens: usize,
};

/// A command extracted from a session file
pub const ExtractedCommand = struct {
    command: []const u8,
    output_len: ?usize,
    session_id: []const u8,
    output_content: ?[]const u8,
    is_error: bool,
    sequence_index: usize,
};

/// Progress bar for display
fn progressBar(pct: f64, width: usize) []const u8 {
    const filled: usize = @intFromFloat((pct / 100.0) * @as(f64, @floatFromInt(width)));
    const empty = width -| filled;

    var result: [20]u8 = undefined;
    var i: usize = 0;
    while (i < filled and i < result.len) : (i += 1) {
        result[i] = '@';
    }
    while (i < filled + empty and i < result.len) : (i += 1) {
        result[i] = '.';
    }
    return result[0..i];
}

/// Format token count for display
fn formatTokens(tokens: usize) []const u8 {
    if (tokens < 1000) {
        return std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{tokens}) catch return "";
    } else if (tokens < 1000000) {
        return std.fmt.allocPrint(std.heap.page_allocator, "{d}K", .{tokens / 1000}) catch return "";
    } else {
        return std.fmt.allocPrint(std.heap.page_allocator, "{d}M", .{tokens / 1000000}) catch return "";
    }
}

/// Count llmlite-covered commands from extracted commands.
/// A command is "covered" if it either:
/// - starts with "llmlite-cmd " or "llmlite " (explicit invocation)
/// - starts with "rtk " (RTK compatibility)
/// - would be rewritten by the hook (classify returns Supported)
fn countLlmliteCommands(cmds: []const ExtractedCommand, allocator: std.mem.Allocator) struct { total: usize, llmlite: usize, output: usize } {
    _ = allocator;
    var total: usize = 0;
    var llmlite: usize = 0;
    var output: usize = 0;

    for (cmds) |c| {
        const parts = lexer.splitCompound(c.command);
        for (parts) |part| {
            total += 1;

            const trimmed = std.mem.trim(u8, part, " \t");
            if (trimmed.len == 0) continue;

            // Explicit llmlite or rtk invocation
            if (std.mem.startsWith(u8, trimmed, "llmlite-cmd ") or
                std.mem.startsWith(u8, trimmed, "llmlite ") or
                std.mem.startsWith(u8, trimmed, "rtk "))
            {
                llmlite += 1;
            } else {
                // Check if hook would rewrite it
                const cls = rules.classify(trimmed);
                if (cls.matched) {
                    llmlite += 1;
                }
            }
        }

        if (c.output_len) |len| {
            output += len / 4; // Estimate tokens
        }
    }

    return .{ .total = total, .llmlite = llmlite, .output = output };
}

/// Encode a filesystem path to Claude Code's directory name format.
/// `/Users/foo/bar` → `-Users-foo-bar`
pub fn encodeProjectPath(path: []const u8) []const u8 {
    var result = std.ArrayList(u8).initCapacity(std.heap.page_allocator, path.len) catch return "";
    defer result.deinit(std.heap.page_allocator);

    for (path) |c| {
        if (c == '/') {
            result.append(std.heap.page_allocator, '-') catch {};
        } else {
            result.append(std.heap.page_allocator, c) catch {};
        }
    }

    return result.toOwnedSlice(std.heap.page_allocator) catch "";
}

/// Get the Claude Code projects directory
fn getProjectsDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    return std.fmt.allocPrint(allocator, "{s}/.claude/projects", .{home});
}

/// Discover session files from Claude Code projects
fn discoverSessions(allocator: std.mem.Allocator, project_filter: ?[]const u8, since_days: u32) ![][]const u8 {
    var sessions = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    errdefer {
        for (sessions.items) |p| allocator.free(p);
        sessions.deinit(allocator);
    }

    const projects_dir = try getProjectsDir(allocator);
    defer allocator.free(projects_dir);

    // Check if projects directory exists
    var dir = fs.openDirAbsolute(projects_dir, .{}) catch return sessions.toOwnedSlice(allocator);
    defer dir.close();

    // Calculate cutoff time
    const cutoff = std.time.timestamp() - (@as(i64, since_days) * 86400);

    var iter = dir.iterate();
    while (try iter.next()) |entry_fn| {
        if (entry_fn.kind != .directory) continue;

        const dir_name = entry_fn.name;

        // Apply project filter if specified
        if (project_filter) |filter| {
            if (!std.mem.containsAtLeast(u8, dir_name, 1, filter)) {
                continue;
            }
        }

        // Look for sessions subdirectory
        const sessions_path = try std.fs.path.join(allocator, &.{ projects_dir, dir_name, "sessions" });
        defer allocator.free(sessions_path);

        var sessions_dir = fs.openDirAbsolute(sessions_path, .{}) catch continue;
        defer sessions_dir.close();

        var session_iter = sessions_dir.iterate();
        while (try session_iter.next()) |session_entry_fn| {
            if (session_entry_fn.kind != .file) continue;

            const filename = session_entry_fn.name;
            if (!std.mem.endsWith(u8, filename, ".jsonl")) continue;

            const full_path = try std.fs.path.join(allocator, &.{ sessions_path, filename });
            errdefer allocator.free(full_path);

            // Check mtime
            const file = fs.openFileAbsolute(full_path, .{}) catch continue;
            defer file.close();

            const stat = file.stat() catch continue;
            const mtime = stat.mtime;
            if (mtime != 0) {
                const mtime_secs = @divTrunc(mtime, std.time.ns_per_s);
                if (mtime_secs < cutoff) continue;
            }

            try sessions.append(allocator, try allocator.dupe(u8, full_path));
        }
    }

    return sessions.toOwnedSlice(allocator);
}

/// Extract Bash commands from a Claude Code session file (JSONL format)
pub fn extractCommands(allocator: std.mem.Allocator, path: []const u8) ![]ExtractedCommand {
    var commands = try std.ArrayList(ExtractedCommand).initCapacity(allocator, 256);
    errdefer commands.deinit(allocator);

    const file = fs.openFileAbsolute(path, .{}) catch return commands.toOwnedSlice(allocator);
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(content);

    // Get session ID from filename
    const session_id = std.fs.path.basename(path);

    // First pass: collect all tool_use Bash commands with their IDs
    var pending_tool_uses = try std.ArrayList(struct { id: []const u8, cmd: []const u8, seq: usize }).initCapacity(allocator, 256);
    defer pending_tool_uses.deinit(allocator);

    // Second pass: collect tool_results
    var tool_results = std.StringHashMap(struct { len: usize, content: []const u8, is_error: bool }).init(allocator);
    defer tool_results.deinit();

    var sequence_counter: usize = 0;

    var line_iter = std.mem.splitScalar(u8, content, '\n');
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        // Pre-filter: skip lines that can't contain what we need
        if (!std.mem.containsAtLeast(u8, line, 1, "\"type\":") and
            !std.mem.containsAtLeast(u8, line, 1, "\"Bash\""))
        {
            continue;
        }

        // Parse the JSON line
        const entry = parseJsonEntry(line) catch continue;
        const entry_type = getJsonString(entry.data, "type") catch continue;

        if (std.mem.eql(u8, entry_type, "assistant")) {
            // Look for tool_use blocks in message.content
            const content_array = getJsonArray(entry.data, "/message/content") catch continue;
            const blocks = parseJsonArray(content_array) catch continue;

            for (blocks) |block| {
                const block_type = getJsonString(block, "type") catch continue;
                const tool_name = getJsonString(block, "name") catch continue;

                // Only handle Bash tool
                if (std.mem.eql(u8, block_type, "tool_use") and std.mem.eql(u8, tool_name, "Bash")) {
                    const tool_id = getJsonString(block, "id") catch "";
                    const cmd_input = getJsonString(block, "/input/command") catch "";

                    if (tool_id.len > 0 and cmd_input.len > 0) {
                        try pending_tool_uses.append(allocator, .{
                            .id = try allocator.dupe(u8, tool_id),
                            .cmd = try allocator.dupe(u8, cmd_input),
                            .seq = sequence_counter,
                        });
                        sequence_counter += 1;
                    }
                }
            }
        } else if (std.mem.eql(u8, entry_type, "user")) {
            // Look for tool_result blocks
            const content_array = getJsonArray(entry.data, "/message/content") catch continue;
            const blocks = parseJsonArray(content_array) catch continue;

            for (blocks) |block| {
                const block_type = getJsonString(block, "type") catch continue;

                if (std.mem.eql(u8, block_type, "tool_result")) {
                    const tool_use_id = getJsonString(block, "tool_use_id") catch "";
                    if (tool_use_id.len == 0) continue;

                    const result_content = getJsonString(block, "content") catch "";
                    const is_error = getJsonBool(block, "is_error") catch false;

                    // Store first 1000 chars of content
                    const content_preview = if (result_content.len > 1000)
                        try allocator.dupe(u8, result_content[0..1000])
                    else
                        try allocator.dupe(u8, result_content);

                    try tool_results.put(tool_use_id, .{
                        .len = result_content.len,
                        .content = content_preview,
                        .is_error = is_error,
                    });
                }
            }
        }
    }

    // Match tool_uses with their results
    for (pending_tool_uses.items) |tool_use| {
        const result = tool_results.get(tool_use.id);

        const output_len = if (result) |r| r.len else null;
        const output_content = if (result) |r| r.content else null;
        const is_error = if (result) |r| r.is_error else false;

        try commands.append(allocator, .{
            .command = tool_use.cmd,
            .output_len = output_len,
            .session_id = try allocator.dupe(u8, session_id),
            .output_content = output_content,
            .is_error = is_error,
            .sequence_index = tool_use.seq,
        });
    }

    return commands.toOwnedSlice(allocator);
}

// ============================================================================
// JSON Parsing Helpers (simplified, no external dependencies)
// ============================================================================

/// Simplified JSON value representation
const JsonValue = struct {
    data: []const u8,
};

/// Parse a JSON object from a line
fn parseJsonEntry(line: []const u8) !JsonValue {
    return JsonValue{ .data = line };
}

/// Get a string field from a JSON object by field name
fn getJsonString(data: []const u8, field: []const u8) ![]const u8 {
    var pos: usize = 0;

    // Skip to opening brace
    while (pos < data.len and data[pos] != '{') pos += 1;
    if (pos >= data.len) return error.NotAnObject;
    pos += 1;

    while (pos < data.len) {
        // Skip whitespace
        while (pos < data.len and (data[pos] == ' ' or data[pos] == '\t' or data[pos] == '\n' or data[pos] == '\r')) pos += 1;
        if (pos >= data.len) break;

        // Check if we found the field we want
        const key_start = pos;
        while (pos < data.len and data[pos] != ':') pos += 1;
        if (pos >= data.len) return error.InvalidJson;

        const key = std.mem.trim(u8, data[key_start..pos], " \t\"");
        pos += 1; // skip :

        if (std.mem.eql(u8, key, field)) {
            // Skip whitespace
            while (pos < data.len and (data[pos] == ' ' or data[pos] == '\t')) pos += 1;

            if (pos >= data.len) return error.InvalidJson;

            if (data[pos] == '"') {
                // String value
                pos += 1; // skip opening quote
                const value_start = pos;
                while (pos < data.len and data[pos] != '"') {
                    if (data[pos] == '\\') pos += 2 else pos += 1;
                }
                const result = data[value_start..pos];
                pos += 1; // skip closing quote
                return result;
            } else {
                // Other value (number, boolean, null)
                const value_start = pos;
                while (pos < data.len and data[pos] != ',' and data[pos] != '}') pos += 1;
                return std.mem.trim(u8, data[value_start..pos], " \t");
            }
        }

        // Skip this value
        if (pos < data.len and data[pos] == '"') {
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

/// Get an array field from a JSON object
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

// ============================================================================
// Main Session Analysis
// ============================================================================

/// Run session analysis
pub fn runSessionAnalysis(allocator: std.mem.Allocator, options: SessionOptions) !void {
    // Discover session files
    const project_filter: ?[]const u8 = if (options.all) null else blk: {
        const cwd_str = try std.process.getCwdAlloc(allocator);
        defer allocator.free(cwd_str);
        break :blk encodeProjectPath(cwd_str);
    };

    const sessions = discoverSessions(allocator, project_filter, options.since_days) catch &.{};
    defer {
        for (sessions) |p| allocator.free(p);
        allocator.free(sessions);
    }

    if (options.verbose > 0) {
        std.debug.print("Found {d} session files...\n", .{sessions.len});
    }

    if (sessions.len == 0) {
        if (options.verbose > 0) {
            std.debug.print("No Claude Code sessions found. Make sure Claude Code has been used.\n", .{});
        }
        return;
    }

    // Collect session summaries
    var summaries = try std.ArrayList(SessionSummary).initCapacity(allocator, 256);
    defer summaries.deinit(allocator);

    var total_cmds: usize = 0;
    var total_llmlite: usize = 0;

    for (sessions) |session_path| {
        const cmds = extractCommands(allocator, session_path) catch continue;
        defer {
            for (cmds) |c| {
                allocator.free(c.command);
                allocator.free(c.session_id);
                if (c.output_content) |oc| allocator.free(oc);
            }
            allocator.free(cmds);
        }

        if (cmds.len == 0) continue;

        const counts = countLlmliteCommands(cmds, allocator);

        total_cmds += counts.total;
        total_llmlite += counts.llmlite;

        // Extract session ID from filename
        const session_id = std.fs.path.basename(session_path);
        const short_id = if (session_id.len > 8) session_id[0..8] else session_id;

        // Get date from mtime
        const file = fs.openFileAbsolute(session_path, .{}) catch continue;
        defer file.close();
        const stat = file.stat() catch continue;

        const mtime = stat.mtime;
        const mtime_secs = @divTrunc(mtime, std.time.ns_per_s);
        const now = std.time.timestamp();
        const days = @divTrunc((now - mtime_secs), 86400);
        const date_str = if (days == 0) "Today" else if (days == 1) "Yesterday" else (std.fmt.allocPrint(allocator, "{d}d ago", .{days}) catch "?");

        try summaries.append(allocator, .{
            .id = try allocator.dupe(u8, short_id),
            .date = date_str,
            .total_cmds = counts.total,
            .llmlite_cmds = counts.llmlite,
            .output_tokens = counts.output,
        });
    }

    // Display results
    if (std.mem.eql(u8, options.format, "json")) {
        try printJsonReport(summaries.items, total_cmds, total_llmlite);
    } else {
        try printTextReport(summaries.items, total_cmds, total_llmlite, options.verbose);
    }
}

/// Print text report
fn printTextReport(summaries: []const SessionSummary, total_cmds: usize, total_llmlite: usize, verbose: u8) !void {
    _ = verbose;

    std.debug.print("llmlite Session Overview (last {d} sessions)\n", .{summaries.len});
    std.debug.print("======================================================================\n", .{});
    std.debug.print("{s:<12} {s:<12} {s:>5} {s:>5} {s:>9} {s:<7} {s:>8}\n", .{ "Session", "Date", "Cmds", "llmlite", "Adoption", "", "Output" });
    std.debug.print("----------------------------------------------------------------------\n", .{});

    for (summaries) |s| {
        const pct: f64 = if (s.total_cmds > 0) @as(f64, @floatFromInt(s.llmlite_cmds * 100)) / @as(f64, @floatFromInt(s.total_cmds)) else 0.0;
        const bar = progressBar(pct, 5);

        std.debug.print("{s:<12} {s:<12} {d:>5} {d:>5} {d:>8.0}% {s:<7} {s:>8}\n", .{
            s.id, s.date, s.total_cmds, s.llmlite_cmds, pct, bar, formatTokens(s.output_tokens),
        });
    }

    std.debug.print("----------------------------------------------------------------------\n", .{});

    const avg_adoption: f64 = if (total_cmds > 0) @as(f64, @floatFromInt(total_llmlite * 100)) / @as(f64, @floatFromInt(total_cmds)) else 0.0;
    std.debug.print("Average adoption: {:.0}%\n", .{avg_adoption});
    std.debug.print("Tip: Run `llmlite discover` to find missed llmlite opportunities\n", .{});
}

/// Print JSON report
fn printJsonReport(summaries: []const SessionSummary, total_cmds: usize, total_llmlite: usize) !void {
    const avg_adoption: f64 = if (total_cmds > 0) @as(f64, @floatFromInt(total_llmlite * 100)) / @as(f64, @floatFromInt(total_cmds)) else 0.0;

    std.debug.print("{{\n", .{});
    std.debug.print("  \"sessions_scanned\": {d},\n", .{summaries.len});
    std.debug.print("  \"total_commands\": {d},\n", .{total_cmds});
    std.debug.print("  \"llmlite_commands\": {d},\n", .{total_llmlite});
    std.debug.print("  \"adoption_rate\": {:.1},\n", .{avg_adoption});
    std.debug.print("  \"sessions\": [\n", .{});

    for (summaries, 0..) |s, i| {
        const pct: f64 = if (s.total_cmds > 0) @as(f64, @floatFromInt(s.llmlite_cmds * 100)) / @as(f64, @floatFromInt(s.total_cmds)) else 0.0;
        std.debug.print("    {{\n", .{});
        std.debug.print("      \"id\": \"{s}\",\n", .{s.id});
        std.debug.print("      \"date\": \"{s}\",\n", .{s.date});
        std.debug.print("      \"total_commands\": {d},\n", .{s.total_cmds});
        std.debug.print("      \"llmlite_commands\": {d},\n", .{s.llmlite_cmds});
        std.debug.print("      \"adoption_rate\": {:.1},\n", .{pct});
        std.debug.print("      \"output_tokens\": {d}\n", .{s.output_tokens});
        std.debug.print("    }}", .{});
        if (i < summaries.len - 1) std.debug.print(",", .{});
        std.debug.print("\n", .{});
    }

    std.debug.print("  ]\n", .{});
    std.debug.print("}}\n", .{});
}

test "session analysis tests" {
    // Test encode project path
    const encoded = encodeProjectPath("/Users/foo/bar");
    defer std.heap.page_allocator.free(encoded);
    try std.testing.expect(std.mem.eql(u8, encoded, "-Users-foo-bar"));
}

test "progress bar" {
    const bar = progressBar(50.0, 5);
    try std.testing.expect(bar.len == 5);
}

test "progress bar boundaries" {
    const empty = progressBar(0.0, 5);
    try std.testing.expectEqualStrings(".....", empty);

    const full = progressBar(100.0, 5);
    try std.testing.expectEqualStrings("@@@@@", full);

    const half = progressBar(50.0, 5);
    try std.testing.expectEqualStrings("@@@..", half);
}

test "encode project path" {
    const encoded = encodeProjectPath("/Users/test/project");
    defer std.heap.page_allocator.free(encoded);
    try std.testing.expect(std.mem.containsAtLeast(u8, encoded, 1, "-"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, encoded, 1, "/"));
}

test "encode project path simple" {
    const encoded = encodeProjectPath("foo/bar");
    defer std.heap.page_allocator.free(encoded);
    try std.testing.expectEqualStrings("-foo-bar", encoded);
}
