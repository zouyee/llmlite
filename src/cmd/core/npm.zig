//! NPM - Node Package Manager
//!
//! Filters npm output with support for scripts, install, list, etc.
//! Inspired by RTK's npm_cmd.rs.
//!
//! ## Features
//!
//! - Auto-detects "npm run" vs direct subcommands
//! - Strips npm lifecycle scripts
//! - Filters progress bars and noise
//! - Shows script output cleanly
//!
//! ## Token Savings
//!
//! npm run build: ~200 lines → ~30 lines (85% reduction)

const std = @import("std");
const json = @import("cmd_core_json");

/// Known npm subcommands (no "run" injection needed)
const NPM_SUBCOMMANDS = &[_][]const u8{
    "install",   "i",        "ci",       "uninstall", "remove",  "rm",      "update",  "up",
    "list",      "ls",       "outdated", "init",      "create",  "publish", "pack",    "link",
    "audit",     "fund",     "exec",     "explain",   "why",     "search",  "view",    "info",
    "show",      "config",   "set",      "get",       "cache",   "prune",   "dedupe",  "doctor",
    "help",      "version",  "prefix",   "root",      "bin",     "bugs",    "docs",    "home",
    "repo",      "ping",     "whoami",   "token",     "profile", "team",    "access",  "owner",
    "deprecate", "dist-tag", "star",     "stars",     "login",   "logout",  "adduser", "unpublish",
    "pkg",       "diff",     "rebuild",  "test",      "t",       "start",   "stop",    "restart",
};

/// Filter npm output
pub fn filterNpm(output: []const u8, subcommand: []const u8) []const u8 {
    if (std.mem.eql(u8, subcommand, "list")) {
        return filterNpmList(output);
    }
    return filterNpmGeneric(output);
}

/// Filter npm list --json output
fn filterNpmList(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Try JSON parsing
    if (output.len > 0 and output[0] == '{') {
        const parsed = json.parse(std.heap.page_allocator, output) catch {
            return filterNpmGeneric(output);
        };
        defer parsed.deinit(std.heap.page_allocator);

        if (parsed == .object) {
            // Extract dependencies
            return extractNpmListSummary(&parsed.object);
        }
    }

    return filterNpmGeneric(output);
}

/// Extract summary from npm list JSON
fn extractNpmListSummary(obj: *std.json.ObjectMap) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Get dependencies count
    if (obj.get("dependencies")) |deps| {
        if (deps == .object) {
            const count = deps.object.count();
            result.print( "npm: {d} dependencies", .{count}) catch return "";
            return result.toOwnedSlice() catch "";
        }
    }

    // Check for extraneous
    if (obj.get("extraneous")) |_| {
        result.print( "npm: extraneous packages found", .{}) catch return "";
        return result.toOwnedSlice() catch "";
    }

    return "npm: ok";
}

/// Filter generic npm output (npm run, npm install, etc.)
fn filterNpmGeneric(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var shown_count: usize = 0;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Skip npm lifecycle scripts (lines starting with ">")
        if (trimmed.len > 0 and trimmed[0] == '>') {
            continue;
        }

        // Skip npm WARN
        if (std.mem.containsAtLeast(u8, trimmed, 1, "npm WARN")) {
            continue;
        }

        // Skip npm notice
        if (std.mem.containsAtLeast(u8, trimmed, 1, "npm notice")) {
            continue;
        }

        // Skip progress indicators
        if (std.mem.containsAtLeast(u8, trimmed, 1, "⸩") or
            std.mem.containsAtLeast(u8, trimmed, 1, "⸨") or
            std.mem.containsAtLeast(u8, trimmed, 1, "..."))
        {
            continue;
        }

        // Skip empty lines
        if (trimmed.len == 0) {
            continue;
        }

        // Skip lines that are just decoration
        if (std.mem.containsAtLeast(u8, trimmed, 1, "added") and std.mem.containsAtLeast(u8, trimmed, 1, "packages")) {
            continue;
        }

        result.appendSlice(trimmed) catch {};
        result.append('\n') catch {};
        shown_count += 1;

        if (shown_count >= 20) {
            result.appendSlice("... (truncated)") catch {};
            break;
        }
    }

    if (result.items.len == 0) {
        return "npm: ok";
    }

    return result.toOwnedSlice() catch "";
}

/// Run npm with filtering
pub fn runNpm(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    // Determine if this is "npm run <script>" or direct subcommand
    var effective_args = args;
    var needs_run = true;

    if (args.len > 0) {
        const first = args[0];
        if (std.mem.eql(u8, first, "run")) {
            needs_run = false;
            effective_args = args[1..];
        } else {
            // Check if it's a known subcommand
            for (NPM_SUBCOMMANDS) |sub| {
                if (std.mem.eql(u8, first, sub)) {
                    needs_run = false;
                    break;
                }
            }
        }
    }

    // Build command
    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("npm");

    if (needs_run) {
        try cmd_args.append("run");
    }

    for (effective_args) |arg| {
        try cmd_args.append(arg);
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    // Determine subcommand for filtering
    const subcommand = if (args.len > 0) args[0] else "";

    return runner.runFiltered(allocator, cmd_args.items, "npm", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
        .filter_fn = struct {
            fn filter(s: []const u8) []const u8 {
                return filterNpm(s, subcommand);
            }
        }.filter,
    });
}

test "npm filter - generic" {
    const output = "> building...\n> script output\nnpm WARN deprecated\nok";
    const result = filterNpmGeneric(output);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "script output"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "npm WARN"));
}
