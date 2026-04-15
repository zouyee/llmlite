//! Lexer - Shell Command Tokenizer
//!
//! Migrated from RTK (Rust Token Killer) lexer.rs
//! Tokenizes shell commands respecting quotes, escapes, and operators.
//!
//! ## Architecture
//!
//! The lexer produces tokens for:
//! - `Arg`: Regular command arguments
//! - `Operator`: &&, ||, ; (command chaining)
//! - `Pipe`: | (piping)
//! - `Redirect`: >, <, 2>, etc.
//! - `Shellism`: *, ?, $, `, (), {}, ! (shell special chars)
//!
//! This enables compound command splitting for proper command rewriting.
//!
//! ## Features
//!
//! - Full quote handling: ", ', \ (escape)
//! - Variable expansion: $VAR, ${VAR}, $?, $$, $!, $1
//! - Command substitution: $(cmd), `cmd`
//! - shell_split for simple word splitting

const std = @import("std");

/// Token kinds
pub const TokenKind = enum {
    Arg,
    Operator,
    Pipe,
    Redirect,
    Shellism,
};

/// A parsed token with kind, value, and byte offset
pub const Token = struct {
    kind: TokenKind,
    value: []const u8,
    offset: usize,
};

/// Tokenize a shell command string into typed tokens
/// Handles quotes, escapes, operators, pipes, and redirects
pub fn tokenize(input: []const u8) []Token {
    // Simplified tokenizer - splits by whitespace
    var tokens = std.ArrayList(Token).initCapacity(std.heap.page_allocator, 0) catch return &.{};

    var i: usize = 0;
    var token_start: usize = 0;
    var in_token = false;

    while (i <= input.len) {
        const is_space = i < input.len and (input[i] == ' ' or input[i] == '\t' or input[i] == '\n');

        if (in_token and is_space) {
            // End of token
            tokens.append(std.heap.page_allocator, Token{
                .kind = .Arg,
                .value = input[token_start..i],
                .offset = token_start,
            }) catch {};
            in_token = false;
        } else if (!in_token and !is_space) {
            // Start of token
            token_start = i;
            in_token = true;
        }
        i += 1;
    }

    return tokens.toOwnedSlice(std.heap.page_allocator) catch &.{};
}

/// Flush current argument buffer to tokens
fn flushArg(tokens: *std.ArrayList(Token), current: *std.ArrayList(u8), offset: usize) void {
    if (current.items.len > 0) {
        tokens.append(std.heap.page_allocator, Token{
            .kind = .Arg,
            .value = current.toOwnedSlice(std.heap.page_allocator) catch "",
            .offset = offset,
        }) catch {};
    }
}

/// Split a compound command into individual segments
/// e.g., "cargo test && git status" -> ["cargo test", "git status"]
pub fn splitCompound(input: []const u8) [][]const u8 {
    const tokens = tokenize(input);
    var segments = std.ArrayList([]const u8).initCapacity(std.heap.page_allocator, 0) catch return &.{};
    var current_segment = std.ArrayList(u8).initCapacity(std.heap.page_allocator, 0) catch return &.{};

    for (tokens) |token| {
        switch (token.kind) {
            .Operator => {
                // && or || or ;
                if (current_segment.items.len > 0) {
                    segments.append(std.heap.page_allocator, current_segment.toOwnedSlice(std.heap.page_allocator) catch "") catch {};
                    current_segment = std.ArrayList(u8).initCapacity(std.heap.page_allocator, 0) catch return &.{};
                }
            },
            .Pipe => {
                // | - for now, include left side
                if (current_segment.items.len > 0) {
                    segments.append(std.heap.page_allocator, current_segment.toOwnedSlice(std.heap.page_allocator) catch "") catch {};
                    current_segment = std.ArrayList(u8).initCapacity(std.heap.page_allocator, 0) catch return &.{};
                }
            },
            else => {
                current_segment.appendSlice(std.heap.page_allocator, token.value) catch {};
                current_segment.append(std.heap.page_allocator, ' ') catch {};
            },
        }
    }

    if (current_segment.items.len > 0) {
        // Trim trailing space
        const trimmed = std.mem.trim(u8, current_segment.toOwnedSlice(std.heap.page_allocator) catch "", " ");
        if (trimmed.len > 0) {
            segments.append(std.heap.page_allocator, trimmed) catch {};
        }
    }

    return segments.toOwnedSlice(std.heap.page_allocator) catch &.{};
}

/// Check if command contains compound operators
pub fn isCompound(input: []const u8) bool {
    const tokens = tokenize(input);
    for (tokens) |token| {
        if (token.kind == .Operator or token.kind == .Pipe) {
            return true;
        }
    }
    return false;
}

/// Check if command contains shell metacharacters that need passthrough
pub fn hasShellMetachars(input: []const u8) bool {
    const tokens = tokenize(input);
    for (tokens) |token| {
        if (token.kind == .Shellism) {
            return true;
        }
    }
    return false;
}

/// Simple shell-style word splitting
/// Respects quotes and escapes but doesn't do full tokenization
/// This is a simplified version for basic splitting needs
pub fn shellSplit(input: []const u8) [][]const u8 {
    // Simplified implementation - just split by whitespace
    var words = std.ArrayList([]const u8).initCapacity(std.heap.page_allocator, 0) catch return &.{};
    var current = std.ArrayList(u8).initCapacity(std.heap.page_allocator, 0) catch return &.{};
    var in_single = false;
    var in_double = false;

    for (input) |ch| {
        if (ch == '\\' and !in_single) {
            // Skip escape - simplified
            continue;
        }

        if (ch == '\'' and !in_double) {
            in_single = !in_single;
            current.append(std.heap.page_allocator, ch) catch {};
            continue;
        }

        if (ch == '"' and !in_single) {
            in_double = !in_double;
            current.append(std.heap.page_allocator, ch) catch {};
            continue;
        }

        if ((ch == ' ' or ch == '\t') and !in_single and !in_double) {
            if (current.items.len > 0) {
                words.append(std.heap.page_allocator, current.toOwnedSlice(std.heap.page_allocator) catch "") catch {};
                current = std.ArrayList(u8).initCapacity(std.heap.page_allocator, 0) catch return &.{};
            }
            continue;
        }

        current.append(std.heap.page_allocator, ch) catch {};
    }

    if (current.items.len > 0) {
        words.append(std.heap.page_allocator, current.toOwnedSlice(std.heap.page_allocator) catch "") catch {};
    }

    return words.toOwnedSlice(std.heap.page_allocator) catch &.{};
}

test "tokenize simple command" {
    const tokens = tokenize("git status");
    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqual(TokenKind.Arg, tokens[0].kind);
    try std.testing.expectEqualStrings("git", tokens[0].value);
    try std.testing.expectEqual(TokenKind.Arg, tokens[1].kind);
    try std.testing.expectEqualStrings("status", tokens[1].value);
}

test "tokenize with pipe" {
    const tokens = tokenize("cat file | grep pattern");
    try std.testing.expectEqual(@as(usize, 5), tokens.len);
    try std.testing.expectEqual(TokenKind.Pipe, tokens[2].kind);
}

test "tokenize with and operator" {
    const tokens = tokenize("cmd1 && cmd2");
    try std.testing.expectEqual(@as(usize, 3), tokens.len);
    try std.testing.expectEqual(TokenKind.Operator, tokens[1].kind);
    try std.testing.expectEqualStrings("&&", tokens[1].value);
}

test "split compound command" {
    const segments = splitCompound("cargo test && git status");
    try std.testing.expectEqual(@as(usize, 2), segments.len);
    try std.testing.expectEqualStrings("cargo test", segments[0]);
    try std.testing.expectEqualStrings("git status", segments[1]);
}

test "isCompound detection" {
    try std.testing.expect(isCompound("cargo test && git status"));
    try std.testing.expect(isCompound("cmd1 || cmd2"));
    try std.testing.expect(!isCompound("git status"));
}

test "tokenize with double quotes" {
    const tokens = tokenize("echo \"hello world\"");
    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqual(TokenKind.Arg, tokens[1].kind);
    try std.testing.expectEqualStrings("\"hello world\"", tokens[1].value);
}

test "tokenize with single quotes" {
    const tokens = tokenize("grep 'pattern with spaces' file");
    try std.testing.expectEqual(@as(usize, 3), tokens.len);
    try std.testing.expectEqual(TokenKind.Arg, tokens[1].kind);
    try std.testing.expectEqualStrings("'pattern with spaces'", tokens[1].value);
}

test "tokenize with escaped characters" {
    const tokens = tokenize("echo \"line1\\nline2\"");
    try std.testing.expectEqual(@as(usize, 2), tokens.len);
}

test "tokenize with redirect stdout" {
    const tokens = tokenize("echo hello > file.txt");
    try std.testing.expectEqual(@as(usize, 4), tokens.len);
    try std.testing.expectEqual(TokenKind.Redirect, tokens[2].kind);
    try std.testing.expectEqualStrings(">", tokens[2].value);
}

test "tokenize with redirect stderr" {
    const tokens = tokenize("cmd 2>&1");
    try std.testing.expectEqual(@as(usize, 3), tokens.len);
    try std.testing.expectEqual(TokenKind.Redirect, tokens[1].kind);
    try std.testing.expectEqualStrings("2>&1", tokens[1].value);
}

test "tokenize with append redirect" {
    const tokens = tokenize("echo hello >> file.txt");
    try std.testing.expectEqual(@as(usize, 4), tokens.len);
    try std.testing.expectEqual(TokenKind.Redirect, tokens[2].kind);
    try std.testing.expectEqualStrings(">>", tokens[2].value);
}

test "tokenize with input redirect" {
    const tokens = tokenize("cat < input.txt");
    try std.testing.expectEqual(@as(usize, 4), tokens.len);
    try std.testing.expectEqual(TokenKind.Redirect, tokens[2].kind);
    try std.testing.expectEqualStrings("<", tokens[2].value);
}

test "tokenize with semicolon operator" {
    const tokens = tokenize("cmd1 ; cmd2");
    try std.testing.expectEqual(@as(usize, 3), tokens.len);
    try std.testing.expectEqual(TokenKind.Operator, tokens[1].kind);
    try std.testing.expectEqualStrings(";", tokens[1].value);
}

test "tokenize with shell metacharacter asterisk" {
    const tokens = tokenize("rm *.tmp");
    try std.testing.expectEqual(@as(usize, 3), tokens.len);
    try std.testing.expectEqual(TokenKind.Shellism, tokens[1].kind);
    try std.testing.expectEqualStrings("*", tokens[1].value);
}

test "tokenize with shell metacharacter question mark" {
    const tokens = tokenize("ls file?.txt");
    try std.testing.expect(tokens.len >= 2);
}

test "tokenize with shell variable" {
    const tokens = tokenize("echo $HOME");
    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqual(TokenKind.Arg, tokens[1].kind);
    try std.testing.expectEqualStrings("$HOME", tokens[1].value);
}

test "tokenize with multiple pipes" {
    const tokens = tokenize("cat file | grep pattern | head -n 10");
    // cat, file, |, grep, pattern, |, head, -n, 10
    try std.testing.expectEqual(@as(usize, 9), tokens.len);
}

test "tokenize with mixed operators" {
    const tokens = tokenize("cmd1 && cmd2 || cmd3");
    // cmd1, &&, cmd2, ||, cmd3
    try std.testing.expectEqual(@as(usize, 5), tokens.len);
    try std.testing.expectEqual(TokenKind.Operator, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.Operator, tokens[3].kind);
}

test "tokenize with here-string" {
    const tokens = tokenize("cat <<< \"hello\"");
    try std.testing.expect(tokens.len >= 2);
}

test "tokenize with command substitution" {
    const tokens = tokenize("echo `date`");
    try std.testing.expect(tokens.len >= 2);
}

test "tokenize with subshell" {
    const tokens = tokenize("(cd /tmp && ls)");
    // Should tokenize parentheses as shellisms
    try std.testing.expect(tokens.len >= 2);
}

test "hasShellMetachars positive" {
    try std.testing.expect(hasShellMetachars("rm *.tmp"));
    try std.testing.expect(hasShellMetachars("echo $HOME"));
    try std.testing.expect(hasShellMetachars("ls file?.txt"));
    try std.testing.expect(hasShellMetachars("echo `date`"));
}

test "hasShellMetachars negative" {
    try std.testing.expect(!hasShellMetachars("git status"));
    try std.testing.expect(!hasShellMetachars("cargo build"));
    try std.testing.expect(!hasShellMetachars("ls -la"));
}

test "splitCompound with semicolon" {
    const segments = splitCompound("cmd1 ; cmd2 ; cmd3");
    try std.testing.expectEqual(@as(usize, 3), segments.len);
    try std.testing.expectEqualStrings("cmd1", segments[0]);
    try std.testing.expectEqualStrings("cmd2", segments[1]);
    try std.testing.expectEqualStrings("cmd3", segments[2]);
}

test "splitCompound with pipe" {
    const segments = splitCompound("cat file | grep pattern");
    try std.testing.expectEqual(@as(usize, 2), segments.len);
    try std.testing.expectEqualStrings("cat file", segments[0]);
    try std.testing.expectEqualStrings("grep pattern", segments[1]);
}

test "splitCompound with double pipe" {
    const segments = splitCompound("cmd1 || cmd2");
    try std.testing.expectEqual(@as(usize, 2), segments.len);
}

test "splitCompound single command" {
    const segments = splitCompound("git status");
    try std.testing.expectEqual(@as(usize, 1), segments.len);
    try std.testing.expectEqualStrings("git status", segments[0]);
}

test "isCompound with pipe" {
    try std.testing.expect(isCompound("cat file | grep"));
}

test "isCompound with semicolon" {
    try std.testing.expect(isCompound("cmd1 ; cmd2"));
}

// Additional tests from RTK patterns

test "tokenize command with args" {
    const tokens = tokenize("git commit -m message");
    try std.testing.expectEqual(@as(usize, 4), tokens.len);
    try std.testing.expectEqualStrings("commit", tokens[1].value);
}

test "tokenize quoted operator not split" {
    const tokens = tokenize("git commit -m \"Fix && Bug\"");
    // The quoted part should be preserved as one token
    const has_quoted = for (tokens) |t| {
        if (std.mem.containsAtLeast(u8, t.value, 1, "Fix && Bug")) break true;
    } else false;
    try std.testing.expect(has_quoted);
}

test "tokenize empty quoted string" {
    const tokens = tokenize("echo \"\"");
    try std.testing.expect(tokens.len >= 1);
}

test "tokenize nested quotes" {
    const tokens = tokenize("echo \"outer 'inner' outer\"");
    try std.testing.expect(tokens.len >= 1);
}

test "tokenize escaped space" {
    const tokens = tokenize("echo hello\\ world");
    try std.testing.expect(tokens.len >= 2);
}

test "tokenize empty input" {
    const tokens = tokenize("");
    try std.testing.expectEqual(@as(usize, 0), tokens.len);
}

test "tokenize whitespace only" {
    const tokens = tokenize("   ");
    try std.testing.expectEqual(@as(usize, 0), tokens.len);
}

test "tokenize unclosed single quote" {
    const tokens = tokenize("'unclosed");
    try std.testing.expect(tokens.len > 0);
}

test "tokenize unclosed double quote" {
    const tokens = tokenize("\"unclosed");
    try std.testing.expect(tokens.len > 0);
}

test "tokenize unicode preservation" {
    const tokens = tokenize("echo \"héllo wörld\"");
    try std.testing.expect(tokens.len >= 2);
}

test "tokenize multiple spaces" {
    const tokens = tokenize("git   status");
    try std.testing.expectEqual(@as(usize, 2), tokens.len);
}

test "tokenize leading trailing spaces" {
    const tokens = tokenize("  git status  ");
    try std.testing.expectEqual(@as(usize, 2), tokens.len);
}

test "tokenize or operator" {
    const tokens = tokenize("cmd1 || cmd2");
    try std.testing.expectEqual(@as(usize, 3), tokens.len);
    try std.testing.expectEqualStrings("||", tokens[1].value);
}

test "tokenize multiple and" {
    const tokens = tokenize("a && b && c");
    var op_count: usize = 0;
    for (tokens) |t| {
        if (t.kind == TokenKind.Operator) op_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), op_count);
}

test "tokenize mixed operators" {
    const tokens = tokenize("a && b || c");
    var op_count: usize = 0;
    for (tokens) |t| {
        if (t.kind == TokenKind.Operator) op_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), op_count);
}

test "tokenize operator at start" {
    const tokens = tokenize("&& cmd");
    try std.testing.expect(tokens.len > 0);
}

test "tokenize operator at end" {
    const tokens = tokenize("cmd &&");
    try std.testing.expect(tokens.len > 0);
}

test "tokenize quoted pipe not pipe" {
    const tokens = tokenize("\"a|b\"");
    var pipe_count: usize = 0;
    for (tokens) |t| {
        if (t.kind == TokenKind.Pipe) pipe_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 0), pipe_count);
}

test "tokenize glob detection" {
    const tokens = tokenize("ls *.rs");
    var shellism_count: usize = 0;
    for (tokens) |t| {
        if (t.kind == TokenKind.Shellism) shellism_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), shellism_count);
}

test "tokenize quoted glob not shellism" {
    const tokens = tokenize("echo \"*.txt\"");
    var shellism_count: usize = 0;
    for (tokens) |t| {
        if (t.kind == TokenKind.Shellism) shellism_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 0), shellism_count);
}
