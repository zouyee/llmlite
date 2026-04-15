//! Hook System - Command Processing
//!
//! Processes incoming hook calls from AI agents and rewrites commands on the fly.
//! Handles VS Code Copilot Chat, Copilot CLI, and Gemini CLI formats.

const std = @import("std");
const hook = @import("cmd_core_hook");

// ============================================================================
// Constants
// ============================================================================

const PRE_TOOL_USE_KEY = "PreToolUse";

// ============================================================================
// Hook Format Detection
// ============================================================================

/// Format detected from the preToolUse JSON input.
pub const HookFormat = enum {
    /// VS Code Copilot Chat / Claude Code: snake_case keys, supports `updatedInput`.
    vscode,
    /// GitHub Copilot CLI: camelCase keys, toolArgs is a JSON-encoded string.
    copilot_cli,
    /// Non-bash tool, already uses llmlite, or unknown format — pass through silently.
    passthrough,
};

/// Detect the hook format from JSON input.
pub fn detectFormat(input: []const u8) HookFormat {
    // VS Code Copilot Chat / Claude Code: snake_case keys
    if (parseJsonField(input, "tool_name")) |tool_name| {
        if (std.mem.eql(u8, tool_name, "runTerminalCommand") or
            std.mem.eql(u8, tool_name, "Bash") or
            std.mem.eql(u8, tool_name, "bash"))
        {
            if (parseJsonNestedField(input, "tool_input", "command")) |cmd| {
                if (cmd.len > 0) {
                    return .vscode;
                }
            }
        }
        return .passthrough;
    }

    // Copilot CLI: camelCase keys, toolArgs is a JSON-encoded string
    if (parseJsonField(input, "toolName")) |tool_name| {
        if (std.mem.eql(u8, tool_name, "bash")) {
            if (parseJsonField(input, "toolArgs")) |tool_args_str| {
                // toolArgs is a JSON string like {"command":"git status"}
                // We need to extract "command" from it directly
                if (extractCommandFromToolArgs(tool_args_str)) |cmd| {
                    if (cmd.len > 0) {
                        return .copilot_cli;
                    }
                }
            }
        }
        return .passthrough;
    }

    return .passthrough;
}

/// Extract command from VS Code format input.
pub fn extractVsCodeCommand(input: []const u8) ?[]const u8 {
    return parseJsonNestedField(input, "tool_input", "command");
}

/// Extract command from Copilot CLI format input.
pub fn extractCopilotCliCommand(input: []const u8) ?[]const u8 {
    if (parseJsonField(input, "toolArgs")) |tool_args_str| {
        return extractCommandFromToolArgs(tool_args_str);
    }
    return null;
}

/// Get the rewritten command if it should be rewritten.
/// Returns null if no rewrite is needed (heredoc present, already rewritten, etc.).
pub fn getRewritten(cmd: []const u8) ?[]const u8 {
    // Don't rewrite heredocs
    if (std.mem.indexOf(u8, cmd, "<<") != null) {
        return null;
    }

    // Check if command should be rewritten
    if (!hook.shouldRewrite(cmd)) {
        return null;
    }

    // Get the rewritten command
    const rewritten = hook.rewrite(cmd) orelse return null;

    // If unchanged, return null
    if (std.mem.eql(u8, rewritten, cmd)) {
        return null;
    }

    return rewritten;
}

/// Build VS Code Copilot JSON output for hookSpecificOutput.
pub fn buildVsCodeOutput(rewritten: []const u8, decision: []const u8) []const u8 {
    const allocator = std.heap.page_allocator;
    return std.fmt.allocPrint(allocator, "{{\"hookSpecificOutput\":{{\"hookEventName\":\"{s}\",\"permissionDecision\":\"{s}\",\"permissionDecisionReason\":\"llmlite auto-rewrite\",\"updatedInput\":{{\"command\":\"{s}\"}}}}}}", .{ PRE_TOOL_USE_KEY, decision, rewritten }) catch return "";
}

/// Build Copilot CLI JSON output.
pub fn buildCopilotCliOutput(rewritten: []const u8) []const u8 {
    const allocator = std.heap.page_allocator;
    return std.fmt.allocPrint(allocator, "{{\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Token savings: use `{s}` instead (llmlite saves 60-90% tokens)\"}}", .{rewritten}) catch return "";
}

/// Build Gemini CLI allow output.
pub fn buildGeminiAllowOutput() []const u8 {
    return "{\"decision\":\"allow\"}";
}

/// Build Gemini CLI rewrite output.
pub fn buildGeminiRewriteOutput(rewritten: []const u8) []const u8 {
    const allocator = std.heap.page_allocator;
    return std.fmt.allocPrint(allocator, "{{\"decision\":\"allow\",\"hookSpecificOutput\":{{\"tool_input\":{{\"command\":\"{s}\"}}}}}}", .{rewritten}) catch return "";
}

/// Build Gemini CLI deny output.
pub fn buildGeminiDenyOutput() []const u8 {
    return "{\"decision\":\"deny\",\"reason\":\"Blocked by llmlite permission rule\"}";
}

// ============================================================================
// JSON Parsing Helpers
// ============================================================================

fn parseJsonField(json: []const u8, field: []const u8) ?[]const u8 {
    const search = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":", .{field}) catch return null;
    defer std.heap.page_allocator.free(search);

    const start = std.mem.indexOf(u8, json, search) orelse return null;
    const value_start = start + search.len;

    // Skip whitespace
    var i = value_start;
    while (i < json.len and (json[i] == ' ' or json[i] == '\t')) i += 1;

    if (i >= json.len) return null;
    if (json[i] != '"') return null;

    // Find closing quote (skip escaped quotes)
    i += 1;
    const value_start_idx = i;
    while (i < json.len) {
        if (json[i] == '\\' and i + 1 < json.len) {
            // Skip escaped character
            i += 2;
            continue;
        }
        if (json[i] == '"') break;
        i += 1;
    }

    if (i >= json.len) return null;
    return json[value_start_idx..i];
}

fn parseJsonNestedField(json: []const u8, parent: []const u8, field: []const u8) ?[]const u8 {
    const parent_search = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":{{", .{parent}) catch return null;
    defer std.heap.page_allocator.free(parent_search);

    const parent_start = std.mem.indexOf(u8, json, parent_search) orelse return null;
    const obj_start = parent_start + parent_search.len - 1;

    // Find matching closing brace
    var depth: u32 = 1;
    var i = obj_start + 1;
    while (i < json.len and depth > 0) {
        if (json[i] == '{') depth += 1 else if (json[i] == '}') depth -= 1;
        i += 1;
    }

    if (depth != 0) return null;

    const obj_end = i - 1;
    const obj_content = json[obj_start..obj_end];

    return parseJsonField(obj_content, field);
}

/// Extract command from Copilot CLI's toolArgs JSON string.
/// toolArgs is a JSON string like {"command":"git status"} that has already
/// been extracted as a string value from the parent JSON.
/// Note: The quotes inside toolArgs are escaped as \"
fn extractCommandFromToolArgs(tool_args_str: []const u8) ?[]const u8 {
    // The tool_args_str is like {"command":"git status"} (JSON object as string)
    // But quotes are escaped: {\"command\":\"git status\"}
    // We need to find the \"command\":\" pattern and extract the value
    const search = "\\\"command\\\":\\\"";
    const start = std.mem.indexOf(u8, tool_args_str, search) orelse return null;
    const value_start = start + search.len;

    // Find the closing escaped quote
    var i = value_start;
    while (i < tool_args_str.len - 1) {
        if (tool_args_str[i] == '\\' and tool_args_str[i + 1] == '"') break;
        i += 1;
    }

    if (i >= tool_args_str.len - 1) return null;
    return tool_args_str[value_start..i];
}

// ============================================================================
// Tests
// ============================================================================

test "detect VS Code bash format" {
    const input = "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git status\"}}";
    try std.testing.expectEqual(HookFormat.vscode, detectFormat(input));
}

test "detect VS Code runTerminalCommand format" {
    const input = "{\"tool_name\":\"runTerminalCommand\",\"tool_input\":{\"command\":\"cargo test\"}}";
    try std.testing.expectEqual(HookFormat.vscode, detectFormat(input));
}

test "detect Copilot CLI format" {
    const input = "{\"toolName\":\"bash\",\"toolArgs\":\"{\\\"command\\\":\\\"git status\\\"}\"}";
    try std.testing.expectEqual(HookFormat.copilot_cli, detectFormat(input));
}

test "detect non-bash is passthrough" {
    const input = "{\"tool_name\":\"editFiles\",\"tool_input\":{}}";
    try std.testing.expectEqual(HookFormat.passthrough, detectFormat(input));
}

test "detect unknown is passthrough" {
    try std.testing.expectEqual(HookFormat.passthrough, detectFormat("{}"));
    try std.testing.expectEqual(HookFormat.passthrough, detectFormat(""));
}

test "extract VS Code command" {
    const input = "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cargo test\"}}";
    const cmd = extractVsCodeCommand(input);
    try std.testing.expect(cmd != null);
    try std.testing.expectEqualStrings("cargo test", cmd.?);
}

test "extract Copilot CLI command" {
    const input = "{\"toolName\":\"bash\",\"toolArgs\":\"{\\\"command\\\":\\\"git status\\\"}\"}";
    const cmd = extractCopilotCliCommand(input);
    try std.testing.expect(cmd != null);
    try std.testing.expectEqualStrings("git status", cmd.?);
}

test "vscode output format" {
    const output = buildVsCodeOutput("llmlite-cmd git status", "ask");
    try std.testing.expect(std.mem.indexOf(u8, output, "llmlite-cmd git status") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "PreToolUse") != null);
}

test "copilot cli output format" {
    const output = buildCopilotCliOutput("llmlite-cmd git status");
    try std.testing.expect(std.mem.indexOf(u8, output, "llmlite-cmd git status") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "deny") != null);
}

test "gemini allow output format" {
    const output = buildGeminiAllowOutput();
    try std.testing.expectEqualStrings("{\"decision\":\"allow\"}", output);
}

test "gemini deny output format" {
    const output = buildGeminiDenyOutput();
    try std.testing.expect(std.mem.indexOf(u8, output, "deny") != null);
}
