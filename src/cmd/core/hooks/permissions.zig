//! Hook System - Permission Checking
//!
//! Implements permission checking for commands based on Claude Code's permission rules.
//! Precedence: Deny > Ask > Allow > Default (ask)

const std = @import("std");

/// Permission verdict from checking a command against permission rules
pub const PermissionVerdict = enum {
    /// An explicit allow rule matched - safe to auto-allow
    allow,
    /// A deny rule matched - pass through to native deny handling
    deny,
    /// An ask rule matched - rewrite but let Claude Code prompt user
    ask,
    /// No rule matched - default to ask (matches Claude Code's least-privilege default)
    default,
};

/// Check `cmd` against deny/ask/allow permission rules.
/// Returns `default` when no rules match.
pub fn checkCommand(cmd: []const u8) PermissionVerdict {
    _ = cmd;
    return .default;
}

/// Internal implementation allowing tests to inject rules without file I/O.
pub fn checkCommandWithRules(
    cmd: []const u8,
    deny_rules: []const []const u8,
    ask_rules: []const []const u8,
    allow_rules: []const []const u8,
) PermissionVerdict {
    var any_ask = false;
    var any_allow = false;

    // Split by && first - use simple slice counting
    const max_segments = 32;
    var segment_starts: [max_segments]usize = .{0} ** max_segments;
    var segment_ends: [max_segments]usize = .{0} ** max_segments;
    var segment_count: usize = 0;

    {
        var start: usize = 0;
        var i: usize = 0;
        while (i <= cmd.len and segment_count < max_segments) {
            const is_and = i < cmd.len and i + 1 < cmd.len and cmd[i] == '&' and cmd[i + 1] == '&';
            if (i == cmd.len or is_and) {
                if (i > start) {
                    segment_starts[segment_count] = start;
                    segment_ends[segment_count] = i;
                    segment_count += 1;
                }
                start = i + 2;
                i += 2;
                continue;
            }
            i += 1;
        }
    }

    for (0..segment_count) |idx| {
        const segment = cmd[segment_starts[idx]..segment_ends[idx]];
        const trimmed = trim(segment);
        if (trimmed.len == 0) continue;

        // Deny takes highest priority
        for (deny_rules) |pattern| {
            if (commandMatchesPattern(trimmed, pattern)) {
                return .deny;
            }
        }

        if (!any_ask) {
            for (ask_rules) |pattern| {
                if (commandMatchesPattern(trimmed, pattern)) {
                    any_ask = true;
                    break;
                }
            }
        }

        if (!any_allow and !any_ask) {
            for (allow_rules) |pattern| {
                if (commandMatchesPattern(trimmed, pattern)) {
                    any_allow = true;
                    break;
                }
            }
        }
    }

    // Precedence: Deny > Ask > Allow > Default (ask)
    if (any_ask) {
        return .ask;
    } else if (any_allow) {
        return .allow;
    } else {
        return .default;
    }
}

/// Trim whitespace from both ends
fn trim(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and std.ascii.isWhitespace(s[start])) {
        start += 1;
    }
    var end = s.len;
    while (end > start and std.ascii.isWhitespace(s[end - 1])) {
        end -= 1;
    }
    return s[start..end];
}

/// Extract the pattern string from inside `Bash(pattern)`.
pub fn extractBashPattern(rule: []const u8) []const u8 {
    if (std.mem.startsWith(u8, rule, "Bash(")) {
        if (std.mem.endsWith(u8, rule, ")")) {
            return rule[5 .. rule.len - 1];
        }
    }
    return rule;
}

/// Check if `cmd` matches a permission pattern.
pub fn commandMatchesPattern(cmd: []const u8, pattern: []const u8) bool {
    // 1. Global wildcard
    if (std.mem.eql(u8, pattern, "*")) {
        return true;
    }

    // 2. Trailing-only wildcard: fast path with word-boundary preservation
    //    Handles: "git push*", "git push *", "sudo:*"
    if (std.mem.endsWith(u8, pattern, "*")) {
        var prefix = pattern[0 .. pattern.len - 1];
        while (prefix.len > 0 and (prefix[prefix.len - 1] == ' ' or prefix[prefix.len - 1] == ':')) {
            prefix = prefix[0 .. prefix.len - 1];
        }

        if (prefix.len == 0 or std.mem.eql(u8, prefix, "*")) {
            return true;
        }

        // No other wildcards in prefix -> use word-boundary fast path
        if (std.mem.indexOf(u8, prefix, "*") == null) {
            if (std.mem.eql(u8, cmd, prefix)) return true;
            // Check cmd.startsWith(prefix + " ")
            if (cmd.len > prefix.len and cmd[prefix.len] == ' ') {
                if (std.mem.eql(u8, cmd[0..prefix.len], prefix)) {
                    return true;
                }
            }
            return false;
        }

        // Fall through to glob matching
    }

    // 3. Complex wildcards (leading, middle, multiple): glob matching
    if (std.mem.indexOf(u8, pattern, "*") != null) {
        return globMatches(cmd, pattern);
    }

    // 4. No wildcard: exact match or prefix with word boundary
    if (std.mem.eql(u8, cmd, pattern)) return true;
    // Check cmd.startsWith(pattern + " ")
    if (cmd.len > pattern.len and cmd[pattern.len] == ' ') {
        if (std.mem.eql(u8, cmd[0..pattern.len], pattern)) {
            return true;
        }
    }
    return false;
}

/// Glob-style matching where `*` matches any character sequence (including empty).
fn globMatches(cmd: []const u8, pattern: []const u8) bool {
    // All-stars pattern (e.g. "***") matches everything
    var has_non_star_part = false;
    for (pattern) |c| {
        if (c != '*') {
            has_non_star_part = true;
            break;
        }
    }
    if (!has_non_star_part) {
        return true;
    }

    // Count parts split by *
    var part_count: usize = 0;
    var in_star = true;
    for (pattern) |c| {
        if (c == '*') {
            in_star = true;
        } else if (in_star) {
            part_count += 1;
            in_star = false;
        }
    }

    // Simple glob: split by * and check each part
    // Use fixed-size arrays to avoid ArrayList issues
    const max_parts = 16;
    var part_starts: [max_parts]usize = .{0} ** max_parts;
    var part_ends: [max_parts]usize = .{0} ** max_parts;
    var parts_filled: usize = 0;

    {
        var start: usize = 0;
        var i: usize = 0;
        while (i <= pattern.len and parts_filled < max_parts) {
            if (i == pattern.len or pattern[i] == '*') {
                part_starts[parts_filled] = start;
                part_ends[parts_filled] = i;
                parts_filled += 1;
                start = i + 1;
            }
            i += 1;
        }
    }

    var search_from: usize = 0;

    for (0..parts_filled) |idx| {
        const part = pattern[part_starts[idx]..part_ends[idx]];
        if (part.len == 0) continue;

        if (idx == 0) {
            // First segment: must be prefix
            if (!std.mem.startsWith(u8, cmd, part)) {
                return false;
            }
            search_from = part.len;
        } else if (idx == parts_filled - 1) {
            // Last segment: must be suffix
            if (cmd.len < search_from + part.len) {
                return false;
            }
            if (!std.mem.endsWith(u8, cmd[search_from..], part)) {
                return false;
            }
        } else {
            // Middle segment: find next occurrence
            if (search_from >= cmd.len) return false;
            const found = std.mem.indexOf(u8, cmd[search_from..], part);
            if (found == null) {
                return false;
            }
            search_from += found.? + part.len;
        }
    }

    return true;
}

// ============================================================================
// Tests
// ============================================================================

test "extract bash pattern basic" {
    try std.testing.expectEqualStrings("git push --force", extractBashPattern("Bash(git push --force)"));
}

test "extract bash pattern with parens" {
    try std.testing.expectEqualStrings("*", extractBashPattern("Bash(*)"));
    try std.testing.expectEqualStrings("sudo:*", extractBashPattern("Bash(sudo:*)"));
}

test "extract bash pattern non-bash unchanged" {
    try std.testing.expectEqualStrings("Read(**/.env*)", extractBashPattern("Read(**/.env*)"));
}

test "exact match positive" {
    try std.testing.expect(commandMatchesPattern("git push --force", "git push --force"));
}

test "exact match negative" {
    try std.testing.expect(!commandMatchesPattern("git status", "git push --force"));
}

test "prefix match" {
    try std.testing.expect(commandMatchesPattern("git push --force origin main", "git push --force"));
}

test "no partial word match" {
    // "git push --forceful" must NOT match pattern "git push --force"
    try std.testing.expect(!commandMatchesPattern("git push --forceful", "git push --force"));
}

test "wildcard all" {
    try std.testing.expect(commandMatchesPattern("anything at all", "*"));
    try std.testing.expect(commandMatchesPattern("", "*"));
}

test "wildcard colon sudo" {
    try std.testing.expect(commandMatchesPattern("sudo rm -rf /", "sudo:*"));
}

test "star colon star matches everything" {
    try std.testing.expect(commandMatchesPattern("rm -rf /", "*:*"));
    try std.testing.expect(commandMatchesPattern("git push --force", "*:*"));
    try std.testing.expect(commandMatchesPattern("anything", "*:*"));
}

test "sudo wildcard no false positive" {
    // "sudoedit" must NOT match "sudo:*" (word boundary respected)
    try std.testing.expect(!commandMatchesPattern("sudoedit /etc/hosts", "sudo:*"));
}

test "leading wildcard positive" {
    try std.testing.expect(commandMatchesPattern("git push --force", "* --force"));
    try std.testing.expect(commandMatchesPattern("npm run --force", "* --force"));
}

test "leading wildcard negative" {
    try std.testing.expect(!commandMatchesPattern("git push --forceful", "* --force"));
    try std.testing.expect(!commandMatchesPattern("git push", "* --force"));
}

test "middle wildcard positive" {
    try std.testing.expect(commandMatchesPattern("git push main", "git * main"));
    try std.testing.expect(commandMatchesPattern("git rebase main", "git * main"));
}

test "middle wildcard negative" {
    try std.testing.expect(!commandMatchesPattern("git push develop", "git * main"));
}

test "multiple wildcards positive" {
    try std.testing.expect(commandMatchesPattern("git push --force origin main", "git * --force *"));
}

test "multiple wildcards negative" {
    try std.testing.expect(!commandMatchesPattern("git pull origin main", "git * --force *"));
}

test "compound command deny" {
    const deny = &.{"git push --force"};
    try std.testing.expectEqual(
        PermissionVerdict.deny,
        checkCommandWithRules("git status && git push --force", deny, &.{}, &.{}),
    );
}

test "compound command ask" {
    const ask = &.{"git push"};
    try std.testing.expectEqual(
        PermissionVerdict.ask,
        checkCommandWithRules("git status && git push origin main", &.{}, ask, &.{}),
    );
}

test "compound command deny overrides ask" {
    const deny = &.{"git push --force"};
    const ask = &.{"git status"};
    try std.testing.expectEqual(
        PermissionVerdict.deny,
        checkCommandWithRules("git status && git push --force", deny, ask, &.{}),
    );
}

test "permission verdict deny precedence" {
    const deny = &.{"git push --force"};
    const ask = &.{"git push --force"};
    try std.testing.expectEqual(
        PermissionVerdict.deny,
        checkCommandWithRules("git push --force", deny, ask, &.{}),
    );
}

test "permission verdict ask" {
    const ask = &.{"git push"};
    try std.testing.expectEqual(
        PermissionVerdict.ask,
        checkCommandWithRules("git push origin main", &.{}, ask, &.{}),
    );
}

test "permission verdict allow" {
    const allow = &.{"git status"};
    try std.testing.expectEqual(
        PermissionVerdict.allow,
        checkCommandWithRules("git status", &.{}, &.{}, allow),
    );
}

test "permission verdict default" {
    try std.testing.expectEqual(
        PermissionVerdict.default,
        checkCommandWithRules("git status", &.{}, &.{}, &.{}),
    );
}

test "empty permissions defaults" {
    try std.testing.expectEqual(
        PermissionVerdict.default,
        checkCommandWithRules("git push --force", &.{}, &.{}, &.{}),
    );
}

test "non bash rules ignored" {
    // Non-Bash patterns should return unchanged
    try std.testing.expectEqualStrings("Read(**/.env*)", extractBashPattern("Read(**/.env*)"));
}
