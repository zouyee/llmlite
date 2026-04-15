//! PNPM - Performant NPM
//!
//! Filters pnpm output with support for list, install, outdated, etc.
//! Inspired by RTK's pnpm_cmd.rs.
//!
//! ## Features
//!
//! - pnpm list --json - Dependency tree
//! - pnpm outdated - Outdated packages
//! - pnpm install - Install logs
//!
//! ## Token Savings
//!
//! pnpm list: ~500 lines → ~20 lines (96% reduction)

const std = @import("std");
const json = @import("cmd_core_json");

/// Filter pnpm output
pub fn filterPnpm(output: []const u8, subcommand: []const u8) []const u8 {
    if (std.mem.eql(u8, subcommand, "list")) {
        return filterPnpmList(output);
    }
    if (std.mem.eql(u8, subcommand, "outdated")) {
        return filterPnpmOutdated(output);
    }
    return filterPnpmGeneric(output);
}

/// Filter pnpm list --json output
fn filterPnpmList(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Try JSON parsing
    if (output.len > 0 and output[0] == '{') {
        const parsed = json.parse(std.heap.page_allocator, output) catch {
            return filterPnpmGeneric(output);
        };
        defer parsed.deinit(std.heap.page_allocator);

        if (parsed == .object) {
            return extractPnpmListSummary(&parsed.object);
        }
    }

    return filterPnpmGeneric(output);
}

/// Extract summary from pnpm list JSON
fn extractPnpmListSummary(obj: *std.json.ObjectMap) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Count packages at root
    var package_count: usize = 0;
    var dep_count: usize = 0;
    var dev_count: usize = 0;

    var it = obj.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (std.mem.eql(u8, key, "dependencies")) {
            if (entry.value_ptr.* == .object) {
                dep_count = entry.value_ptr.*.object.count();
                package_count += dep_count;
            }
        } else if (std.mem.eql(u8, key, "devDependencies")) {
            if (entry.value_ptr.* == .object) {
                dev_count = entry.value_ptr.*.object.count();
                package_count += dev_count;
            }
        }
    }

    if (package_count > 0) {
        std.fmt.format(result.writer(), "pnpm: {d} packages", .{package_count}) catch return "";
        if (dep_count > 0) {
            std.fmt.format(result.writer(), " ({d} prod, {d} dev)", .{ dep_count, dev_count }) catch return "";
        }
        return result.toOwnedSlice() catch "";
    }

    return "pnpm: ok";
}

/// Filter pnpm outdated output
fn filterPnpmOutdated(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Try JSON parsing
    if (output.len > 0 and output[0] == '[') {
        const parsed = json.parse(std.heap.page_allocator, output) catch {
            return filterPnpmGeneric(output);
        };
        defer parsed.deinit(std.heap.page_allocator);

        if (parsed == .array) {
            return extractPnpmOutdatedSummary(parsed.array);
        }
    }

    return filterPnpmGeneric(output);
}

/// Extract summary from pnpm outdated JSON
fn extractPnpmOutdatedSummary(arr: []json.JsonValue) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    const count = arr.len;
    if (count == 0) {
        return "pnpm: all packages up to date";
    }

    std.fmt.format(result.writer(), "pnpm: {d} outdated packages\n", .{count}) catch return "";
    std.fmt.format(result.writer(), "═══════════════════════════════════════\n", .{}) catch return "";

    // Show first 5
    const show = @min(5, count);
    for (arr[0..show]) |item| {
        if (item == .object) {
            const name = json.getString(&item.object, "package") orelse "unknown";
            const current = json.getString(&item.object, "current") orelse "?";
            const latest = json.getString(&item.object, "latest") orelse "?";
            std.fmt.format(result.writer(), "  {s}: {s} → {s}\n", .{ name, current, latest }) catch return "";
        }
    }

    if (count > 5) {
        std.fmt.format(result.writer(), "  ... +{d} more", .{count - 5}) catch return "";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter generic pnpm output
fn filterPnpmGeneric(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var shown_count: usize = 0;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Skip empty lines
        if (trimmed.len == 0) continue;

        // Skip pnpm lifecycle scripts
        if (trimmed.len > 0 and trimmed[0] == '>') continue;

        // Skip deprecation warnings
        if (std.mem.containsAtLeast(u8, trimmed, 1, "deprecated")) continue;

        // Skip progress bars
        if (std.mem.containsAtLeast(u8, trimmed, 1, "▓") or
            std.mem.containsAtLeast(u8, trimmed, 1, "░"))
        {
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
        return "pnpm: ok";
    }

    return result.toOwnedSlice() catch "";
}

/// Run pnpm with filtering
pub fn runPnpm(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.ArrayList([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("pnpm");

    for (args) |arg| {
        try cmd_args.append(arg);
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    const subcommand = if (args.len > 0) args[0] else "";

    return runner.runFiltered(allocator, cmd_args.items, "pnpm", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
        .filter_fn = struct {
            fn filter(s: []const u8) []const u8 {
                return filterPnpm(s, subcommand);
            }
        }.filter,
    });
}

test "pnpm filter - generic" {
    const output = "Packages: 150\nDone in 2.5s";
    const result = filterPnpmGeneric(output);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "150"));
}
