//! TOML Filter System - RTK-style declarative filtering
//!
//! Supports 8-stage filter pipeline:
//!   1. strip_ansi        - Remove ANSI escape codes
//!   2. replace           - Regex substitutions (line-by-line)
//!   3. match_output      - Short-circuit rules
//!   4. strip/keep_lines - Filter lines by regex
//!   5. truncate_lines_at - Truncate each line to N chars
//!   6. head/tail_lines  - Keep first/last N lines
//!   7. max_lines         - Absolute line cap
//!   8. on_empty          - Message if result is empty
//!
//! Filter lookup priority:
//!   1. Project-local: .llmlite/filters.toml
//!   2. User-global:   ~/.config/llmlite/filters.toml
//!   3. Built-in:      src/cmd/core/filters/*.toml

const std = @import("std");

pub const FilterRule = struct {
    name: []const u8,
    description: ?[]const u8,
    match_command: []const u8,
    strip_ansi: bool = false,
    strip_lines_matching: []const []const u8 = &.{},
    keep_lines_matching: []const []const u8 = &.{},
    truncate_lines_at: ?usize = null,
    head_lines: ?usize = null,
    tail_lines: ?usize = null,
    max_lines: ?usize = null,
    on_empty: ?[]const u8 = null,
    match_output: []const MatchOutputRule = &.{},
    replace: []const ReplaceRule = &.{},
};

pub const MatchOutputRule = struct {
    pattern: []const u8,
    message: []const u8,
    unless: ?[]const u8 = null,
};

pub const ReplaceRule = struct {
    pattern: []const u8,
    replacement: []const u8,
};

pub const FilterTest = struct {
    name: []const u8,
    input: []const u8,
    expected: []const u8,
};

pub const FilterWithTests = struct {
    rule: FilterRule,
    tests: []const FilterTest,
};

/// Result of applying a filter
pub const FilterResult = struct {
    output: []u8,
    matched: bool,
};

/// Load all available filters
pub fn loadAllFilters(allocator: std.mem.Allocator) ![]const FilterWithTests {
    _ = allocator;
    // Return built-in filters
    return &builtin_filters.filters;
}

/// Find a matching filter for the given command
pub fn findMatchingFilter(filters: []const FilterWithTests, command: []const u8) ?*const FilterWithTests {
    for (filters) |*f| {
        if (matchCommand(command, f.rule.match_command)) {
            return f;
        }
    }
    return null;
}

/// Check if command matches a pattern
fn matchCommand(command: []const u8, pattern: []const u8) bool {
    // Simple regex-like matching for common patterns
    // Supports: ^, $, \b, \s, \d, \s+, \d+, +, *, etc.
    var i: usize = 0;
    var pi: usize = 0;

    const is_anchored_start = pattern.len > 0 and pattern[0] == '^';

    if (is_anchored_start) {
        pi = 1;
    }

    while (i < command.len and pi < pattern.len) {
        const p = pattern[pi];

        if (p == '\\') {
            pi += 1;
            if (pi >= pattern.len) break;
            const e = pattern[pi];
            switch (e) {
                'b' => {
                    // Word boundary - match if at start/end of word or before non-alphanumeric
                    if (i > 0 and std.ascii.isAlphanumeric(command[i - 1])) {
                        return false;
                    }
                    if (i < command.len and std.ascii.isAlphanumeric(command[i])) {
                        return false;
                    }
                    pi += 1;
                    continue;
                },
                's' => {
                    // Whitespace (optionally followed by +)
                    if (i >= command.len or !std.ascii.isWhitespace(command[i])) {
                        return false;
                    }
                    while (i < command.len and std.ascii.isWhitespace(command[i])) {
                        i += 1;
                    }
                    pi += 1;
                    // Handle + after \s (one or more)
                    if (pi < pattern.len and pattern[pi] == '+') {
                        pi += 1;
                    }
                    continue;
                },
                'd' => {
                    // Digit (optionally followed by +)
                    if (i >= command.len or !std.ascii.isDigit(command[i])) {
                        return false;
                    }
                    while (i < command.len and std.ascii.isDigit(command[i])) {
                        i += 1;
                    }
                    pi += 1;
                    // Handle + after \d (one or more)
                    if (pi < pattern.len and pattern[pi] == '+') {
                        pi += 1;
                    }
                    continue;
                },
                else => {
                    if (i >= command.len or command[i] != e) {
                        return false;
                    }
                    i += 1;
                    pi += 1;
                },
            }
        } else if (p == '+') {
            // + means one or more of previous element - but we need previous element
            // This simplified version just matches + literally
            if (i >= command.len or command[i] != '+') {
                return false;
            }
            i += 1;
            pi += 1;
        } else if (p == '*') {
            // * means zero or more of previous element - simplified: just skip
            pi += 1;
        } else if (p == '.') {
            // Any character
            i += 1;
            pi += 1;
        } else if (p == '*') {
            // Any sequence (greedy)
            pi += 1;
            if (pi >= pattern.len) {
                return true; // Match rest
            }
            const next = pattern[pi];
            while (i < command.len and command[i] != next) {
                i += 1;
            }
            continue;
        } else if (p == '^') {
            // Start anchor (already handled)
            pi += 1;
        } else if (p == '$') {
            // End anchor
            pi += 1;
            while (i < command.len and std.ascii.isWhitespace(command[i])) {
                i += 1;
            }
            return i == command.len;
        } else {
            // Literal match
            if (i >= command.len or command[i] != p) {
                return false;
            }
            i += 1;
            pi += 1;
        }
    }

    // Handle trailing wildcard
    if (pi < pattern.len and pattern[pi] == '*') {
        return true;
    }

    // If pattern exhausted, command should too (unless pattern ends with *)
    if (is_anchored_start) {
        return i == command.len;
    }

    return true;
}

/// Apply a filter to input text
pub fn applyFilter(
    allocator: std.mem.Allocator,
    rule: FilterRule,
    input: []const u8,
) !FilterResult {
    var lines = std.mem.splitScalar(u8, input, '\n');

    // Stage 1: strip_ansi
    var processed = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    errdefer processed.deinit(allocator);
    while (lines.next()) |line| {
        if (rule.strip_ansi) {
            const stripped = stripAnsi(line, allocator);
            try processed.append(allocator, stripped);
        } else {
            try processed.append(allocator, try allocator.dupe(u8, line));
        }
    }

    // Stage 2: replace (regex substitutions, line-by-line)
    if (rule.replace.len > 0) {
        for (processed.items) |*line| {
            for (rule.replace) |r| {
                line.* = replaceAll(line.*, r.pattern, r.replacement, allocator);
            }
        }
    }

    // Stage 3: match_output (short-circuit rules)
    if (rule.match_output.len > 0) {
        const blob = std.mem.join(allocator, "\n", processed.items) catch |e| {
            return FilterResult{
                .output = try allocator.dupe(u8, @errorName(e)),
                .matched = true,
            };
        };
        defer allocator.free(blob);

        for (rule.match_output) |mo| {
            if (matchPattern(blob, mo.pattern)) {
                // Check unless
                if (mo.unless) |unless_pat| {
                    if (matchPattern(blob, unless_pat)) {
                        continue; // Skip this rule
                    }
                }
                return FilterResult{
                    .output = try allocator.dupe(u8, mo.message),
                    .matched = true,
                };
            }
        }
    }

    // Stage 4: strip OR keep lines
    if (rule.strip_lines_matching.len > 0) {
        var filtered = try std.ArrayList([]const u8).initCapacity(allocator, 0);
        errdefer filtered.deinit(allocator);
        for (processed.items) |line| {
            var should_keep = true;
            for (rule.strip_lines_matching) |pattern| {
                if (matchPattern(line, pattern)) {
                    should_keep = false;
                    break;
                }
            }
            if (should_keep) {
                try filtered.append(allocator, line);
            } else {
                allocator.free(line);
            }
        }
        processed.deinit(allocator);
        processed = filtered;
    } else if (rule.keep_lines_matching.len > 0) {
        var filtered = try std.ArrayList([]const u8).initCapacity(allocator, 0);
        errdefer filtered.deinit(allocator);
        for (processed.items) |line| {
            var should_keep = false;
            for (rule.keep_lines_matching) |pattern| {
                if (matchPattern(line, pattern)) {
                    should_keep = true;
                    break;
                }
            }
            if (should_keep) {
                try filtered.append(allocator, line);
            } else {
                allocator.free(line);
            }
        }
        processed.deinit(allocator);
        processed = filtered;
    }

    // Stage 5: truncate_lines_at
    if (rule.truncate_lines_at) |max_chars| {
        for (processed.items) |*line| {
            if (line.len > max_chars) {
                line.* = truncateWithEllipsis(line.*, max_chars, allocator);
            }
        }
    }

    // Stage 6: head + tail lines
    const total = processed.items.len;
    if (rule.head_lines) |head| {
        if (rule.tail_lines) |tail| {
            if (total > head + tail) {
                var result = try std.ArrayList([]const u8).initCapacity(allocator, 0);
                errdefer result.deinit(allocator);
                for (processed.items[0..head]) |line| {
                    try result.append(allocator, line);
                }
                try result.append(allocator, try std.fmt.allocPrint(allocator, "... ({d} lines omitted)", .{total - head - tail}));
                for (processed.items[total - tail ..]) |line| {
                    try result.append(allocator, line);
                }
                // Free the truncated items
                for (processed.items[head .. total - tail]) |line| {
                    allocator.free(line);
                }
                processed.deinit(allocator);
                processed = result;
            }
        } else if (total > head) {
            // Truncate head
            for (processed.items[head..]) |line| {
                allocator.free(line);
            }
            processed.items.len = head;
            try processed.append(allocator, try std.fmt.allocPrint(allocator, "... ({d} lines omitted)", .{total - head}));
        }
    } else if (rule.tail_lines) |tail| {
        if (total > tail) {
            const omit_count = total - tail;
            for (processed.items[0..omit_count]) |line| {
                allocator.free(line);
            }
            // Shift elements - copy slice pointers
            const keep_count = total - omit_count;
            for (0..keep_count) |i| {
                processed.items[i] = processed.items[omit_count + i];
            }
            processed.items.len = keep_count;
            try processed.insert(allocator, 0, try std.fmt.allocPrint(allocator, "... ({d} lines omitted)", .{omit_count}));
        }
    }

    // Stage 7: max_lines
    if (rule.max_lines) |max| {
        if (processed.items.len > max) {
            const truncate_count = processed.items.len - max;
            for (processed.items[max..]) |line| {
                allocator.free(line);
            }
            processed.items.len = max;
            try processed.append(allocator, try std.fmt.allocPrint(allocator, "... ({d} lines truncated)", .{truncate_count}));
        }
    }

    // Stage 8: on_empty
    const result = try std.mem.join(allocator, "\n", processed.items);
    errdefer allocator.free(result);

    if (result.len == 0 or std.mem.trim(u8, result, " \t\r").len == 0) {
        if (rule.on_empty) |msg| {
            allocator.free(result);
            return FilterResult{
                .output = try allocator.dupe(u8, msg),
                .matched = true,
            };
        }
    }

    return FilterResult{
        .output = result,
        .matched = true,
    };
}

// ============================================================================
// Helper functions (public for testing)
// ============================================================================

/// Strip ANSI escape codes from a string
pub fn stripAnsi(input: []const u8, allocator: std.mem.Allocator) []const u8 {
    var result = std.ArrayList(u8).initCapacity(allocator, input.len) catch return input;
    var i: usize = 0;

    while (i < input.len) {
        if (input[i] == '\x1b' and i + 1 < input.len and input[i + 1] == '[') {
            // ANSI escape sequence
            i += 2;
            while (i < input.len) {
                if (input[i] == 'm' or input[i] == 'H' or input[i] == 'J') {
                    i += 1;
                    break;
                }
                i += 1;
            }
        } else {
            result.append(allocator, input[i]) catch {};
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator) catch input;
}

/// Match a pattern against text (simple regex)
pub fn matchPattern(text: []const u8, pattern: []const u8) bool {
    // Very simple pattern matching - supports basic regex
    if (pattern.len == 0) return true;

    var ti: usize = 0;
    var pi: usize = 0;

    while (pi < pattern.len and ti < text.len) {
        const p = pattern[pi];

        if (p == '\\') {
            pi += 1;
            if (pi >= pattern.len) break;
            const e = pattern[pi];
            switch (e) {
                'd' => {
                    if (!std.ascii.isDigit(text[ti])) return false;
                    while (ti < text.len and std.ascii.isDigit(text[ti])) ti += 1;
                },
                's' => {
                    if (!std.ascii.isWhitespace(text[ti])) return false;
                    while (ti < text.len and std.ascii.isWhitespace(text[ti])) ti += 1;
                },
                'b' => {
                    // Word boundary - for simplicity, just skip
                },
                else => {
                    if (text[ti] != e) return false;
                    ti += 1;
                },
            }
            pi += 1;
        } else if (p == '.') {
            ti += 1;
            pi += 1;
        } else if (p == '*') {
            pi += 1;
            if (pi >= pattern.len) return true;
            const next = pattern[pi];
            while (ti < text.len and text[ti] != next) ti += 1;
            if (ti >= text.len) return false;
            continue;
        } else if (p == '^') {
            pi += 1;
            if (ti != 0) return false;
        } else if (p == '$') {
            pi += 1;
            while (ti < text.len and std.ascii.isWhitespace(text[ti])) ti += 1;
            return ti == text.len;
        } else {
            if (text[ti] != p) return false;
            ti += 1;
            pi += 1;
        }
    }

    if (pi < pattern.len) {
        if (pattern[pi] == '$') return true;
        if (pattern[pi] == '*') return true;
        return false;
    }

    return true;
}

/// Replace all occurrences of pattern with replacement
fn replaceAll(text: []const u8, pattern: []const u8, replacement: []const u8, allocator: std.mem.Allocator) []const u8 {
    var result = std.ArrayList(u8).initCapacity(allocator, text.len) catch return text;
    var i: usize = 0;

    while (i < text.len) {
        // Check for match at current position
        var matched = true;
        var match_len: usize = 0;

        if (pattern.len > 0 and i + pattern.len <= text.len) {
            matched = matchAt(text[i..], pattern, &match_len);
        }

        if (matched and match_len > 0) {
            result.appendSlice(allocator, replacement) catch {};
            i += match_len;
        } else {
            result.append(allocator, text[i]) catch {};
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator) catch text;
}

/// Check if pattern matches at start of text, return match length
fn matchAt(text: []const u8, pattern: []const u8, match_len: *usize) bool {
    var ti: usize = 0;
    var pi: usize = 0;

    while (pi < pattern.len and ti < text.len) {
        const p = pattern[pi];

        if (p == '\\') {
            pi += 1;
            if (pi >= pattern.len) break;
            const e = pattern[pi];
            switch (e) {
                'd' => {
                    if (!std.ascii.isDigit(text[ti])) {
                        match_len.* = 0;
                        return false;
                    }
                    var end = ti;
                    while (end < text.len and std.ascii.isDigit(text[end])) end += 1;
                    ti = end;
                },
                's' => {
                    if (!std.ascii.isWhitespace(text[ti])) {
                        match_len.* = 0;
                        return false;
                    }
                    var end = ti;
                    while (end < text.len and std.ascii.isWhitespace(text[end])) end += 1;
                    ti = end;
                },
                else => {
                    if (text[ti] != e) {
                        match_len.* = 0;
                        return false;
                    }
                    ti += 1;
                },
            }
            pi += 1;
        } else if (p == '.') {
            ti += 1;
            pi += 1;
        } else if (p == '*') {
            // Greedy - find longest match
            pi += 1;
            if (pi >= pattern.len) {
                match_len.* = text.len;
                return true;
            }
            const next = pattern[pi];
            var end = ti;
            while (end < text.len and text[end] != next) end += 1;
            match_len.* = end;
            return true;
        } else if (p == '^') {
            pi += 1;
            if (ti != 0) {
                match_len.* = 0;
                return false;
            }
        } else {
            if (text[ti] != p) {
                match_len.* = 0;
                return false;
            }
            ti += 1;
            pi += 1;
        }
    }

    match_len.* = ti;
    return pi == pattern.len;
}

/// Truncate string with ellipsis
pub fn truncateWithEllipsis(text: []const u8, max_chars: usize, allocator: std.mem.Allocator) []const u8 {
    if (text.len <= max_chars) {
        return text;
    }

    const ellipsis_len = 3;

    if (max_chars < ellipsis_len) {
        return text[0..max_chars];
    }

    const usable = max_chars - ellipsis_len;
    return std.fmt.allocPrint(allocator, "{s}...", .{text[0..usable]}) catch text;
}

// ============================================================================
// Built-in filters
// ============================================================================

const builtin_filters = struct {
    pub const filters = [35]FilterWithTests{
        .{
            .rule = .{
                .name = "make",
                .description = "Compact make output",
                .match_command = "^make\\b",
                .strip_ansi = true,
                .strip_lines_matching = &.{
                    "^make\\[\\d+\\]+: Entering directory",
                    "^make\\[\\d+\\]+: Leaving directory",
                    "^\\s*$",
                },
                .max_lines = 50,
                .on_empty = "make: ok",
            },
            .tests = &.{
                .{
                    .name = "strips entering/leaving lines",
                    .input = "make[1]: Entering directory '/home/user/project'\ngcc -O2 -Wall -c foo.c -o foo.o\nmake[1]: Leaving directory '/home/user/project'",
                    .expected = "gcc -O2 -Wall -c foo.c -o foo.o",
                },
            },
        },
        .{
            .rule = .{
                .name = "terraform-plan",
                .description = "Compact Terraform plan output",
                .match_command = "^terraform\\s+plan",
                .strip_ansi = true,
                .strip_lines_matching = &.{
                    "^Refreshing state",
                    "^\\s*#.*unchanged",
                    "^\\s*$",
                    "^Acquiring state lock",
                    "^Releasing state lock",
                },
                .max_lines = 80,
                .on_empty = "terraform plan: no changes detected",
            },
            .tests = &.{
                .{
                    .name = "strips Refreshing state lines",
                    .input = "Acquiring state lock. This may take a few moments...\nRefreshing state... [id=vpc-abc]\nReleasing state lock.\n\nTerraform will perform the following actions:\n\n  # aws_instance.web will be created\n  + resource \"aws_instance\" \"web\" {}\n\nPlan: 1 to add, 0 to change, 0 to destroy.",
                    .expected = "Terraform will perform the following actions:\n\n  # aws_instance.web will be created\n  + resource \"aws_instance\" \"web\" {}\n\nPlan: 1 to add, 0 to change, 0 to destroy.",
                },
            },
        },
        .{
            .rule = .{
                .name = "biome",
                .description = "Compact Biome lint/format output",
                .match_command = "^biome\\b",
                .strip_ansi = true,
                .strip_lines_matching = &.{
                    "^\\s*$",
                    "^Checked \\d+ file",
                    "^Fixed \\d+ file",
                },
                .max_lines = 50,
                .on_empty = "biome: ok",
            },
            .tests = &.{
                .{
                    .name = "lint strips noise",
                    .input = "Checked 42 files in 0.5s\n\nsrc/app.tsx:5:3 lint/suspicious/noExplicitAny\n  × Unexpected any.\n\nFound 2 errors.",
                    .expected = "src/app.tsx:5:3 lint/suspicious/noExplicitAny\n  × Unexpected any.\n\nFound 2 errors.",
                },
            },
        },
        .{
            .rule = .{
                .name = "pre-commit",
                .description = "Compact pre-commit output",
                .match_command = "^pre-commit\\b",
                .strip_ansi = true,
                .strip_lines_matching = &.{
                    "^\\[INFO\\] Installing environment",
                    "^\\[INFO\\] Once installed",
                    "^\\[INFO\\] This may take",
                    "^\\s*$",
                },
                .max_lines = 40,
            },
            .tests = &.{
                .{
                    .name = "strips INFO noise",
                    .input = "[INFO] Installing environment...\n[INFO] Once installed...\nTrim Trailing Whitespace.................................................Passed\nCheck Yaml...............................................................Failed",
                    .expected = "Trim Trailing Whitespace.................................................Passed\nCheck Yaml...............................................................Failed",
                },
            },
        },
        .{
            .rule = .{
                .name = "mix-compile",
                .description = "Compact mix compile output",
                .match_command = "^mix\\s+compile(\\s|$)",
                .strip_ansi = true,
                .strip_lines_matching = &.{
                    "^Compiling \\d+ file",
                    "^\\s*$",
                    "^Generated\\s",
                },
                .max_lines = 40,
                .on_empty = "mix compile: ok",
            },
            .tests = &.{
                .{
                    .name = "strips compile noise",
                    .input = "Compiling 12 files (.ex)\nGenerated my_app app\n\nwarning: variable \"conn\" is unused",
                    .expected = "warning: variable \"conn\" is unused",
                },
            },
        },
        .{
            .rule = .{
                .name = "mix-format",
                .description = "Compact mix format output",
                .match_command = "^mix\\s+format",
                .strip_ansi = true,
                .strip_lines_matching = &.{"^\\s*$"},
                .max_lines = 40,
                .on_empty = "mix format: ok",
            },
            .tests = &.{
                .{
                    .name = "format success strips whitespace",
                    .input = "\n\n  \n  \nFormatted lib/foo.ex\nFormatted lib/bar.ex\n\n",
                    .expected = "Formatted lib/foo.ex\nFormatted lib/bar.ex",
                },
                .{
                    .name = "format all formatted",
                    .input = "All source files are formatted correctly",
                    .expected = "All source files are formatted correctly",
                },
            },
        },
        .{
            .rule = .{
                .name = "docker-ps",
                .description = "Compact docker ps output",
                .match_command = "^docker\\s+ps",
                .strip_ansi = true,
                .strip_lines_matching = &.{"^\\s*$"},
                .max_lines = 30,
            },
            .tests = &.{
                .{
                    .name = "ps shows running containers",
                    .input = "CONTAINER ID   IMAGE       COMMAND                  CREATED        STATUS        PORTS                    NAMES\nabc123def456   nginx       \"/docker-entrypoint…\"   2 hours ago   Up 2 hours    0.0.0.0:80->80/tcp   web\ndef456abc789   postgres    \"docker-entrypoint…\"    3 days ago    Up 3 days     5432/tcp               db",
                    .expected = "CONTAINER ID   IMAGE       COMMAND                  CREATED        STATUS        PORTS                    NAMES\nabc123def456   nginx       \"/docker-entrypoint…\"   2 hours ago   Up 2 hours    0.0.0.0:80->80/tcp   web\ndef456abc789   postgres    \"docker-entrypoint…\"    3 days ago    Up 3 days     5432/tcp               db",
                },
            },
        },
        .{
            .rule = .{
                .name = "docker-logs",
                .description = "Compact docker logs output",
                .match_command = "^docker\\s+logs",
                .strip_ansi = true,
                .strip_lines_matching = &.{"^\\s*$"},
                .max_lines = 100,
            },
            .tests = &.{
                .{
                    .name = "logs shows application output",
                    .input = "2024-01-01 12:00:00 Starting server on port 8080\n2024-01-01 12:00:01 Server started successfully\n2024-01-01 12:00:02 Received request: GET /health",
                    .expected = "2024-01-01 12:00:00 Starting server on port 8080\n2024-01-01 12:00:01 Server started successfully\n2024-01-01 12:00:02 Received request: GET /health",
                },
            },
        },
        .{
            .rule = .{
                .name = "ps",
                .description = "Compact ps output",
                .match_command = "^ps\\b",
                .strip_ansi = true,
                .strip_lines_matching = &.{"^\\s*$"},
                .max_lines = 50,
            },
            .tests = &.{
                .{
                    .name = "ps shows processes",
                    .input = "  PID TTY          TIME CMD\n    1 pts/0    00:00:00 bash\n 1234 pts/0    00:00:00 ps\n 5678 pts/0    00:00:01 vim",
                    .expected = "  PID TTY          TIME CMD\n    1 pts/0    00:00:00 bash\n 1234 pts/0    00:00:00 ps\n 5678 pts/0    00:00:01 vim",
                },
            },
        },
        .{
            .rule = .{
                .name = "df",
                .description = "Compact df output",
                .match_command = "^df\\b",
                .strip_ansi = true,
                .strip_lines_matching = &.{"^\\s*$"},
                .max_lines = 20,
            },
            .tests = &.{
                .{
                    .name = "df shows filesystem usage",
                    .input = "Filesystem      Size  Used Avail Use% Mounted on\n/dev/sda1       100G   50G   50G  50% /\ntmpfs           16G   10M   16G   1% /dev/shm",
                    .expected = "Filesystem      Size  Used Avail Use% Mounted on\n/dev/sda1       100G   50G   50G  50% /\ntmpfs           16G   10M   16G   1% /dev/shm",
                },
            },
        },
        .{
            .rule = .{
                .name = "du",
                .description = "Compact du output",
                .match_command = "^du\\b",
                .strip_ansi = true,
                .strip_lines_matching = &.{"^\\s*$"},
                .max_lines = 30,
            },
            .tests = &.{
                .{
                    .name = "du shows disk usage",
                    .input = "4       ./src\n8       ./lib\n12      .",
                    .expected = "4       ./src\n8       ./lib\n12      .",
                },
            },
        },
        .{
            .rule = .{
                .name = "systemctl-status",
                .description = "Compact systemctl status output",
                .match_command = "^systemctl\\s+status",
                .strip_ansi = true,
                .strip_lines_matching = &.{
                    "^\\s*$",
                    "^\\s*Loaded:.*$",
                },
                .max_lines = 30,
            },
            .tests = &.{
                .{
                    .name = "status shows service info",
                    .input = "  Loaded: loaded (/lib/systemd/system/nginx.service; enabled; vendor preset: enabled)\n  Active: active (running) since Mon 2024-01-01 12:00:00 UTC; 1 day ago\nMain PID: 1234 (nginx)\n  CGroup: /system.slice/nginx.service\n          └─1234 nginx: worker process",
                    .expected = "  Active: active (running) since Mon 2024-01-01 12:00:00 UTC; 1 day ago\nMain PID: 1234 (nginx)\n  CGroup: /system.slice/nginx.service\n          └─1234 nginx: worker process",
                },
            },
        },
        .{
            .rule = .{
                .name = "shellcheck",
                .description = "Compact shellcheck output",
                .match_command = "^shellcheck\\b",
                .strip_ansi = true,
                .strip_lines_matching = &.{"^\\s*$"},
                .max_lines = 50,
            },
            .tests = &.{
                .{
                    .name = "shellcheck with issues",
                    .input = "In script.sh line 5:\nrm -rf /\n     ^-- SC2115: Use ... instead of / in rm -rf /",
                    .expected = "In script.sh line 5:\nrm -rf /\n     ^-- SC2115: Use ... instead of / in rm -rf /",
                },
            },
        },
        .{
            .rule = .{
                .name = "yamllint",
                .description = "Compact yamllint output",
                .match_command = "^yamllint\\b",
                .strip_ansi = true,
                .strip_lines_matching = &.{"^\\s*$"},
                .max_lines = 50,
            },
            .tests = &.{
                .{
                    .name = "yamllint with errors",
                    .input = "config.yaml\n  1:1       error    missing document start \"---\" (document-start)\n  5:10      warning  trailing spaces (trailing-spaces)",
                    .expected = "config.yaml\n  1:1       error    missing document start \"---\" (document-start)\n  5:10      warning  trailing spaces (trailing-spaces)",
                },
            },
        },
        .{
            .rule = .{
                .name = "hadolint",
                .description = "Compact hadolint output",
                .match_command = "^hadolint\\b",
                .strip_ansi = true,
                .strip_lines_matching = &.{"^\\s*$"},
                .max_lines = 50,
            },
            .tests = &.{
                .{
                    .name = "hadolint with issues",
                    .input = "Dockerfile:5:3 warning: Use absolute COPY dest (DL3020)\nDockerfile:10:1 error: EXPORT not combined with single RUN (DL3059)",
                    .expected = "Dockerfile:5:3 warning: Use absolute COPY dest (DL3020)\nDockerfile:10:1 error: EXPORT not combined with single RUN (DL3059)",
                },
            },
        },
        .{
            .rule = .{
                .name = "rsync",
                .description = "Compact rsync output",
                .match_command = "^rsync\\b",
                .strip_ansi = true,
                .strip_lines_matching = &.{"^\\s*$"},
                .match_output = &.{
                    .{
                        .pattern = "total size is",
                        .message = "rsync: ok (synced)",
                        .unless = "error|failed",
                    },
                },
                .max_lines = 50,
            },
            .tests = &.{
                .{
                    .name = "rsync success shows sync message",
                    .input = "total size is 1024\nspeedup is 1.23",
                    .expected = "rsync: ok (synced)",
                },
            },
        },
        .{
            .rule = .{
                .name = "helm",
                .description = "Compact helm output",
                .match_command = "^helm\\b",
                .strip_ansi = true,
                .strip_lines_matching = &.{"^\\s*$"},
                .max_lines = 50,
            },
            .tests = &.{
                .{
                    .name = "helm list shows releases",
                    .input = "NAME            NAMESPACE   REVISION    UPDATED                             STATUS      CHART\nnginx           default     1           2024-01-01 12:00:00 UTC    deployed    nginx-1.0.0",
                    .expected = "NAME            NAMESPACE   REVISION    UPDATED                             STATUS      CHART\nnginx           default     1           2024-01-01 12:00:00 UTC    deployed    nginx-1.0.0",
                },
            },
        },
        .{
            .rule = .{
                .name = "ssh",
                .description = "Compact ssh output",
                .match_command = "^ssh\\b",
                .strip_ansi = true,
                .strip_lines_matching = &.{
                    "^Warning:.*$",
                    "^\\s*$",
                },
                .max_lines = 10,
                .on_empty = "ssh: connected",
            },
            .tests = &.{
                .{
                    .name = "ssh strips warnings",
                    .input = "Warning: Permanently added 'server' to the list of known hosts.\nConnected to server\nLast login: Mon Jan  1 12:00:00 2024",
                    .expected = "Connected to server\nLast login: Mon Jan  1 12:00:00 2024",
                },
            },
        },
        .{
            .rule = .{
                .name = "uv-sync",
                .description = "Compact uv sync output",
                .match_command = "^uv\\s+sync",
                .strip_ansi = true,
                .strip_lines_matching = &.{
                    "^\\s*$",
                    "^Using\\s",
                    "^Resolved\\s",
                    "^Downloading\\s",
                    "^Installed\\s",
                },
                .max_lines = 40,
                .on_empty = "uv sync: ok",
            },
            .tests = &.{
                .{
                    .name = "uv sync shows resolutions",
                    .input = "Using Python 3.12\nResolved at 1.0ms\nDownloading packages...\nInstalled 5 packages in 2.3s",
                    .expected = "Installed 5 packages in 2.3s",
                },
            },
        },
        .{
            .rule = .{
                .name = "pip-install",
                .description = "Compact pip install output",
                .match_command = "^pip\\s+install",
                .strip_ansi = true,
                .strip_lines_matching = &.{
                    "^\\s*$",
                    "^Collecting\\s",
                    "^Using\\s",
                    "^Installing\\s",
                    "^Successfully installed\\s",
                },
                .max_lines = 50,
                .on_empty = "pip install: ok",
            },
            .tests = &.{
                .{
                    .name = "pip install shows packages",
                    .input = "Collecting requests\nUsing cached requests-2.31.0-py3.py3-none-any.whl\nInstalling collected packages: requests, urllib3\nSuccessfully installed requests-2.31.0",
                    .expected = "Successfully installed requests-2.31.0",
                },
            },
        },
        .{
            .rule = .{
                .name = "mvn-build",
                .description = "Compact Maven build output",
                .match_command = "^mvn\\s+(compile|package|install|deploy)",
                .strip_ansi = true,
                .strip_lines_matching = &.{
                    "^\\[INFO\\] Building\\s",
                    "^\\[INFO\\] ---\\s",
                    "^\\[INFO\\] Downloaded from\\s",
                    "^\\s*$",
                },
                .max_lines = 60,
                .on_empty = "mvn: ok",
            },
            .tests = &.{
                .{
                    .name = "mvn build shows errors",
                    .input = "[INFO] Building my-project 1.0.0\n[INFO] ---\n[INFO] Compiling...\n[ERROR] src/main/java/App.java:10: error: cannot find symbol\nimport missing.Dependency;\n^\n[INFO] Downloaded from central: https://repo.maven.apache.org",
                    .expected = "[ERROR] src/main/java/App.java:10: error: cannot find symbol\nimport missing.Dependency;\n^",
                },
            },
        },
        .{
            .rule = .{
                .name = "gradle",
                .description = "Compact Gradle build output",
                .match_command = "^gradle\\b|^./gradlew",
                .strip_ansi = true,
                .strip_lines_matching = &.{
                    "^\\s*$",
                    "^BUILD SUCCESSFUL\\s",
                    "^\\d+ tasks? executed\\s",
                },
                .max_lines = 60,
                .on_empty = "gradle: ok",
            },
            .tests = &.{
                .{
                    .name = "gradle shows tasks",
                    .input = "BUILD SUCCESSFUL\n12 tasks executed\n:compileJava\n:processResources\n:classes",
                    .expected = ":compileJava\n:processResources\n:classes",
                },
            },
        },
        .{
            .rule = .{
                .name = "composer-install",
                .description = "Compact composer install output",
                .match_command = "^composer\\s+install",
                .strip_ansi = true,
                .strip_lines_matching = &.{
                    "^\\s*$",
                    "^Loading composer repositories\\s",
                    "^Installing dependencies from lock file\\s",
                    "^Lock file operations:\\s",
                },
                .max_lines = 50,
                .on_empty = "composer install: ok",
            },
            .tests = &.{
                .{
                    .name = "composer install shows package errors",
                    .input = "Loading composer repositories with package information\nInstalling dependencies from lock file\nLock file operations: 1 install, 0 updates\nWriting lock file\nInstalling dependencies from cache\nPackage guzzlehttp/guzzle is abandoned\n",
                    .expected = "Installing dependencies from cache\nPackage guzzlehttp/guzzle is abandoned",
                },
            },
        },
        .{
            .rule = .{
                .name = "brew-install",
                .description = "Compact brew install output",
                .match_command = "^brew\\s+install",
                .strip_ansi = true,
                .strip_lines_matching = &.{
                    "^\\s*$",
                    "^==> Downloading\\s",
                    "^==> Installing\\s",
                    "^🍺\\s",
                },
                .max_lines = 30,
                .on_empty = "brew install: ok",
            },
            .tests = &.{
                .{
                    .name = "brew install with caveats",
                    .input = "==> Downloading https://example.com/package.tar.gz\n==> Installing from local directory\n==> Pouring package-1.0.0.arm64_monterey.bottle.tar.gz\n🍺  /opt/homebrew/Cellar/package/1.0.0: 12 files, 45KB",
                    .expected = "brew install: ok",
                },
            },
        },
        .{
            .rule = .{
                .name = "bundle-install",
                .description = "Compact bundle install output",
                .match_command = "^bundle\\s+install",
                .strip_ansi = true,
                .strip_lines_matching = &.{
                    "^\\s*$",
                    "^Fetching\\s",
                    "^Resolving\\s",
                    "^Installing\\s",
                },
                .max_lines = 40,
                .on_empty = "bundle install: ok",
            },
            .tests = &.{
                .{
                    .name = "bundle install shows warnings",
                    .input = "Fetching gem metadata from https://rubygems.org/\nResolving dependencies...\nInstalling rake 13.0.0\nBundle complete! 2 Gemfile dependencies, 3 gems.\nWarning: the gems don't have executables",
                    .expected = "Bundle complete! 2 Gemfile dependencies, 3 gems.\nWarning: the gems don't have executables",
                },
            },
        },
        .{
            .rule = .{
                .name = "gcloud",
                .description = "Compact gcloud output",
                .match_command = "^gcloud\\b",
                .strip_ansi = true,
                .strip_lines_matching = &.{"^\\s*$"},
                .max_lines = 50,
            },
            .tests = &.{
                .{
                    .name = "gcloud compute instances",
                    .input = "NAME              ZONE           MACHINE_TYPE   PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP    STATUS\nweb-server        us-central1-a   n1-standard-1               10.0.0.1      34.56.78.90   RUNNING",
                    .expected = "NAME              ZONE           MACHINE_TYPE   PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP    STATUS\nweb-server        us-central1-a   n1-standard-1               10.0.0.1      34.56.78.90   RUNNING",
                },
            },
        },
        .{
            .rule = .{
                .name = "tofu-plan",
                .description = "Compact OpenTofu plan output",
                .match_command = "^tofu\\s+plan",
                .strip_ansi = true,
                .strip_lines_matching = &.{
                    "^Refreshing state",
                    "^\\s*#.*unchanged",
                    "^\\s*$",
                    "^Acquiring state lock",
                    "^Releasing state lock",
                },
                .max_lines = 80,
                .on_empty = "tofu plan: no changes detected",
            },
            .tests = &.{
                .{
                    .name = "tofu plan shows changes",
                    .input = "Acquiring state lock. This may take a few moments...\nRefreshing state... [id=vpc-abc]\nReleasing state lock.\n\nOpenTofu will perform the following actions:\n\n  # aws_instance.web will be created\n  + resource \"aws_instance\" \"web\" {}\n\nPlan: 1 to add, 0 to change, 0 to destroy.",
                    .expected = "OpenTofu will perform the following actions:\n\n  # aws_instance.web will be created\n  + resource \"aws_instance\" \"web\" {}\n\nPlan: 1 to add, 0 to change, 0 to destroy.",
                },
            },
        },
        .{
            .rule = .{
                .name = "tofu-init",
                .description = "Compact OpenTofu init output",
                .match_command = "^tofu\\s+init",
                .strip_ansi = true,
                .strip_lines_matching = &.{
                    "^\\s*$",
                    "^Initializing the backend...\\s",
                    "^Initializing provider plugins...\\s",
                },
                .max_lines = 40,
                .on_empty = "tofu init: ok",
            },
            .tests = &.{
                .{
                    .name = "tofu init shows provider",
                    .input = "Initializing the backend...\nInitializing provider plugins...\n- Finding hashicorp/aws versions matching \"~> 5.0\"...\nTerraform has been successfully initialized!",
                    .expected = "- Finding hashicorp/aws versions matching \"~> 5.0\"...\nTerraform has been successfully initialized!",
                },
            },
        },
        .{
            .rule = .{
                .name = "tofu-fmt",
                .description = "Compact OpenTofu fmt output",
                .match_command = "^tofu\\s+fmt",
                .strip_ansi = true,
                .strip_lines_matching = &.{"^\\s*$"},
                .max_lines = 30,
                .on_empty = "tofu fmt: no changes",
            },
            .tests = &.{
                .{
                    .name = "tofu fmt shows formatted files",
                    .input = "main.tf\nvariables.tf\nOutputs.tf",
                    .expected = "main.tf\nvariables.tf\nOutputs.tf",
                },
            },
        },
        .{
            .rule = .{
                .name = "tofu-validate",
                .description = "Compact OpenTofu validate output",
                .match_command = "^tofu\\s+validate",
                .strip_ansi = true,
                .strip_lines_matching = &.{"^\\s*$"},
                .max_lines = 30,
                .on_empty = "tofu validate: valid",
            },
            .tests = &.{
                .{
                    .name = "tofu validate success",
                    .input = "Success! The configuration is valid.",
                    .expected = "Success! The configuration is valid.",
                },
            },
        },
        .{
            .rule = .{
                .name = "markdownlint",
                .description = "Compact markdownlint output",
                .match_command = "^markdownlint\\b",
                .strip_ansi = true,
                .strip_lines_matching = &.{"^\\s*$"},
                .max_lines = 50,
            },
            .tests = &.{
                .{
                    .name = "markdownlint with issues",
                    .input = "README.md:1:1 MD041/first-line-heading First line in a file should be a heading\nREADME.md:10:20 MD013/line-length Line length exceeds 80 characters",
                    .expected = "README.md:1:1 MD041/first-line-heading First line in a file should be a heading\nREADME.md:10:20 MD013/line-length Line length exceeds 80 characters",
                },
            },
        },
        .{
            .rule = .{
                .name = "just",
                .description = "Compact just output",
                .match_command = "^just\\b",
                .strip_ansi = true,
                .strip_lines_matching = &.{"^\\s*$"},
                .max_lines = 30,
            },
            .tests = &.{
                .{
                    .name = "just shows recipe output",
                    .input = "build\ntest\ndeploy",
                    .expected = "build\ntest\ndeploy",
                },
            },
        },
        .{
            .rule = .{
                .name = "mise",
                .description = "Compact mise output",
                .match_command = "^mise\\b",
                .strip_ansi = true,
                .strip_lines_matching = &.{"^\\s*$"},
                .max_lines = 30,
            },
            .tests = &.{
                .{
                    .name = "mise shows installed versions",
                    .input = "node    20.11.0\npython  3.12.1\nzig     0.13.0",
                    .expected = "node    20.11.0\npython  3.12.1\nzig     0.13.0",
                },
            },
        },
        .{
            .rule = .{
                .name = "ping",
                .description = "Compact ping output",
                .match_command = "^ping\\b",
                .strip_ansi = true,
                .strip_lines_matching = &.{"^\\s*$"},
                .match_output = &.{
                    .{
                        .pattern = "^\\d+ packets transmitted",
                        .message = "ping: ok",
                        .unless = "100% packet loss",
                    },
                },
                .max_lines = 20,
            },
            .tests = &.{
                .{
                    .name = "ping success",
                    .input = "PING 8.8.8.8 (8.8.8.8): 56 data bytes\n64 bytes from 8.8.8.8: time=10.5 ms\n\n--- 8.8.8.8 ping statistics ---\n10 packets transmitted, 10 packets received, 0.0% packet loss\nround-trip min/avg/max = 9.2/11.3/15.4 ms",
                    .expected = "ping: ok",
                },
            },
        },
        .{
            .rule = .{
                .name = "poetry-install",
                .description = "Compact poetry install output",
                .match_command = "^poetry\\s+install",
                .strip_ansi = true,
                .strip_lines_matching = &.{
                    "^\\s*$",
                    "^Updating\\s",
                    "^Resolving\\s",
                    "^Installing\\s",
                },
                .max_lines = 40,
                .on_empty = "poetry install: ok",
            },
            .tests = &.{
                .{
                    .name = "poetry install shows errors",
                    .input = "Updating dependencies\nResolving dependencies...\nInstalling the updated packages\n\n  SolverProblemError\n\n  Because project depends on missing-package",
                    .expected = "  SolverProblemError\n\n  Because project depends on missing-package",
                },
            },
        },
    };
};

test "matchPattern simple match" {
    try std.testing.expect(matchPattern("hello world", "hello"));
    try std.testing.expect(!matchPattern("hello world", "goodbye"));
}

test "matchPattern with wildcard" {
    try std.testing.expect(matchPattern("hello world", "hello*"));
    try std.testing.expect(matchPattern("hello world", "*world"));
}

test "matchPattern anchored" {
    try std.testing.expect(matchPattern("hello", "^hello$"));
    try std.testing.expect(!matchPattern("hello world", "^hello$"));
}

test "truncateWithEllipsis short string unchanged" {
    const allocator = std.heap.page_allocator;
    const input = "hi";
    const result = truncateWithEllipsis(input, 10, allocator);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hi", result);
}

test "truncateWithEllipsis long string truncated" {
    const allocator = std.heap.page_allocator;
    const input = "hello world this is long";
    const result = truncateWithEllipsis(input, 10, allocator);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello...", result);
}

test "applyFilter strip_ansi" {
    const allocator = std.heap.page_allocator;
    const rule = FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .strip_ansi = true,
    };
    const input = "\x1b[31mError\x1b[0m\nnormal";
    const result = try applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    try std.testing.expectEqualStrings("Error\nnormal", result.output);
}

test "applyFilter strip_lines_matching" {
    const allocator = std.heap.page_allocator;
    const rule = FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .strip_lines_matching = &.{"^noise"},
    };
    const input = "noise line\nkeep this\nnoise stuff";
    const result = try applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    try std.testing.expectEqualStrings("keep this", result.output);
}

test "applyFilter keep_lines_matching" {
    const allocator = std.heap.page_allocator;
    const rule = FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .keep_lines_matching = &.{ "^PASS", "^FAIL" },
    };
    const input = "PASS test_a\nsome noise\nFAIL test_b";
    const result = try applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    try std.testing.expectEqualStrings("PASS test_a\nFAIL test_b", result.output);
}

test "applyFilter max_lines" {
    const allocator = std.heap.page_allocator;
    const rule = FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .max_lines = 2,
    };
    const input = "a\nb\nc\nd\ne";
    const result = try applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    try std.testing.expect(result.output.len > 0);
    try std.testing.expect(std.mem.contains(u8, result.output, "lines truncated"));
}

test "applyFilter on_empty" {
    const allocator = std.heap.page_allocator;
    const rule = FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .strip_lines_matching = &.{".*"},
        .on_empty = "nothing left",
    };
    const input = "line1\nline2";
    const result = try applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    try std.testing.expect(result.matched);
    try std.testing.expectEqualStrings("nothing left", result.output);
}

test "applyFilter head_lines" {
    const allocator = std.heap.page_allocator;
    const rule = FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .head_lines = 2,
    };
    const input = "a\nb\nc\nd\ne";
    const result = try applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    try std.testing.expect(std.mem.contains(u8, result.output, "3 lines omitted"));
}

test "applyFilter tail_lines" {
    const allocator = std.heap.page_allocator;
    const rule = FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .tail_lines = 2,
    };
    const input = "a\nb\nc\nd\ne";
    const result = try applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    try std.testing.expect(std.mem.contains(u8, result.output, "3 lines omitted"));
}

test "applyFilter match_output success" {
    const allocator = std.heap.page_allocator;
    const rule = FilterRule{
        .name = "test",
        .description = null,
        .match_command = "test",
        .match_output = &.{
            .{
                .pattern = "total size is",
                .message = "rsync: ok",
                .unless = "error|failed",
            },
        },
    };
    const input = "total size is 1024\nspeedup is 1.23";
    const result = try applyFilter(allocator, rule, input);
    defer allocator.free(result.output);
    try std.testing.expect(result.matched);
    try std.testing.expectEqualStrings("rsync: ok", result.output);
}

test "findMatchingFilter" {
    const filters = try loadAllFilters(std.heap.page_allocator);
    const match = findMatchingFilter(filters, "make");
    try std.testing.expect(match != null);
    try std.testing.expectEqualStrings("make", match.?.rule.name);
}

test "findMatchingFilter no match" {
    const filters = try loadAllFilters(std.heap.page_allocator);
    const match = findMatchingFilter(filters, "unknown_command_xyz");
    try std.testing.expect(match == null);
}
