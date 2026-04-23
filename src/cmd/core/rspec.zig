//! RSpec - Ruby Test Runner
//!
//! Filters RSpec JSON output for compact representation.
//! Inspired by RTK's rspec_cmd.rs.
//!
//! ## Token Savings
//!
//! rspec: ~500 lines → ~50 lines (90% reduction)

const std = @import("std");
const json = @import("cmd_core_json");

/// Filter RSpec output
pub fn filterRspec(output: []const u8) []const u8 {
    // Check for JSON format
    if (std.mem.containsAtLeast(u8, output, 1, "{\"examples\":")) {
        return filterRspecJson(output);
    }

    return filterRspecText(output);
}

/// Filter RSpec JSON output
fn filterRspecJson(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Extract summary counts
    const examples = json.extractInteger(output, "examples") orelse 0;
    const failures = json.extractInteger(output, "failure_count") orelse 0;
    const pending = json.extractInteger(output, "pending_count") orelse 0;

    if (failures == 0) {
        result.print( "rspec: {d} examples, {d} passed", .{ examples, examples - failures - pending }) catch return "";
        if (pending > 0) {
            result.print( ", {d} pending", .{pending}) catch return "";
        }
        return result.toOwnedSlice() catch "";
    }

    // Show failures
    result.print( "rspec: {d} examples, {d} failures\n", .{ examples, failures }) catch return "";
    result.appendSlice("═══════════════════════════════════════\n") catch return "";

    // Extract examples with failures
    var examples_start: usize = 0;
    var examples_end: usize = output.len;

    for (output, 0..) |c, i| {
        if (c == '[' and std.mem.containsAtLeast(u8, output[i..], 1, "{\"id\":")) {
            examples_start = i;
            break;
        }
    }

    var depth: usize = 0;
    for (examples_start..output.len) |i| {
        if (output[i] == '[') depth += 1 else if (output[i] == ']') {
            depth -= 1;
            if (depth == 0) {
                examples_end = i + 1;
                break;
            }
        }
    }

    var failure_count: usize = 0;
    var pos = examples_start;
    while (pos < examples_end and failure_count < 10) {
        while (pos < examples_end and output[pos] != '{') pos += 1;
        if (pos >= examples_end) break;

        var obj_depth: usize = 0;
        var obj_end = pos;
        for (pos..examples_end) |i| {
            if (output[i] == '{') obj_depth += 1 else if (output[i] == '}') {
                obj_depth -= 1;
                if (obj_depth == 0) {
                    obj_end = i + 1;
                    break;
                }
            }
        }

        const obj_text = output[pos..obj_end];
        const status = json.extractString(obj_text, "status") orelse "";

        if (std.mem.eql(u8, status, "failed")) {
            const full_description = json.extractString(obj_text, "full_description") orelse "???";
            const file_path = json.extractString(obj_text, "file_path") orelse "???";
            const line_number = json.extractInteger(obj_text, "line_number") orelse 0;

            result.print( "FAIL: {s}\n  {s}:{d}\n", .{
                full_description, file_path, line_number,
            }) catch return {};

            failure_count += 1;
        }

        pos = obj_end + 1;
    }

    if (failures > 10) {
        result.print( "... +{d} more failures\n", .{failures - 10}) catch return "";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter RSpec text output
fn filterRspecText(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 50) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Skip noise
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Fetching gem metadata")) continue;
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Installing")) continue;
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Using")) continue;

        // Show failures
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Failure/Error:") or
            std.mem.containsAtLeast(u8, trimmed, 1, "rspec ") or
            std.mem.containsAtLeast(u8, trimmed, 1, "FAILED"))
        {
            result.appendSlice(trimmed[0..@min(150, trimmed.len)]) catch {};
            result.append('\n') catch {};
            count += 1;
        }
    }

    if (result.items.len == 0) {
        return output[0..@min(output.len, 500)];
    }

    return result.toOwnedSlice() catch "";
}

/// Run RSpec with filtering
pub fn runRspec(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    // Check if bundle exec
    var use_bundle = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "bundle")) use_bundle = true;
    }

    if (use_bundle) {
        try cmd_args.append("bundle");
        try cmd_args.append("exec");
        try cmd_args.append("rspec");
    } else {
        try cmd_args.append("rspec");
    }

    // Add --format json if not present
    var has_format = false;
    for (args) |arg| {
        if (std.mem.containsAtLeast(u8, arg, 1, "--format")) has_format = true;
        if (!std.mem.eql(u8, arg, "bundle") and !std.mem.eql(u8, arg, "exec") and !std.mem.eql(u8, arg, "rspec")) {
            try cmd_args.append(arg);
        }
    }

    if (!has_format) {
        try cmd_args.append("--format=json");
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "rspec", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
        .filter_fn = filterRspec,
    });
}
