//! Curl - HTTP Client
//!
//! Filters curl output for compact representation.
//! Inspired by RTK's curl_cmd.rs.
//!
//! ## Token Savings
//!
//! curl: ~500 lines → ~50 lines (90% reduction)

const std = @import("std");
const json = @import("cmd_core_json");

/// Filter curl output
pub fn filterCurl(output: []const u8, has_json_output: bool) []const u8 {
    if (has_json_output) {
        return filterCurlJson(output);
    }

    return filterCurlGeneric(output);
}

/// Filter curl JSON output
fn filterCurlJson(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Try to parse and summarize JSON
    const trimmed = std.mem.trim(u8, output, " \t\r\n");

    if (trimmed.len == 0) {
        return "curl: Empty response";
    }

    // Check if it's a JSON object or array
    if (trimmed[0] == '{') {
        // JSON object - extract keys and summarize
        var keys = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
        defer keys.deinit();

        var pos: usize = 1;
        while (pos < trimmed.len) {
            const search = "\"";
            const idx = std.mem.indexOf(u8, trimmed[pos..], search);
            if (idx == null) break;

            pos += idx.? + 1;
            if (pos >= trimmed.len) break;

            // Check for : after key
            const colon_idx = std.mem.indexOf(u8, trimmed[pos..], ":\"");
            const comma_idx = std.mem.indexOf(u8, trimmed[pos..], ",\"");

            if (colon_idx == null and comma_idx == null) break;

            const after_quote = trimmed[pos..];
            const next_colon = std.mem.indexOf(u8, after_quote, ":");
            const next_comma = std.mem.indexOf(u8, after_quote, ",");

            if (next_colon == null) break;

            const key_end = if (next_comma != null and next_comma.? < next_colon.?)
                next_comma.?
            else
                next_colon.?;

            const key = after_quote[0..key_end];
            if (key.len > 0 and key.len < 50) {
                keys.append(key) catch {};
            }

            pos += key_end + 1;
            if (pos >= trimmed.len) break;
        }

        std.fmt.format(result.writer(), "curl: JSON response with {d} fields\n", .{keys.items.len}) catch return "";
        result.appendSlice("═══════════════════════════════════════\n") catch return "";

        const show_count = @min(10, keys.items.len);
        for (keys.items[0..show_count]) |key| {
            std.fmt.format(result.writer(), "  {s}\n", .{key}) catch return "";
        }

        if (keys.items.len > 10) {
            std.fmt.format(result.writer(), "  ... +{d} more\n", .{keys.items.len - 10}) catch return "";
        }

        return result.toOwnedSlice() catch "";
    } else if (trimmed[0] == '[') {
        // JSON array
        var count: usize = 0;
        var pos: usize = 1;
        while (pos < trimmed.len and count < 5) {
            while (pos < trimmed.len and trimmed[pos] != '{') pos += 1;
            if (pos >= trimmed.len) break;

            var depth: usize = 0;
            var obj_end = pos;
            for (pos..trimmed.len) |i| {
                if (trimmed[i] == '{') depth += 1 else if (trimmed[i] == '}') {
                    depth -= 1;
                    if (depth == 0) {
                        obj_end = i + 1;
                        break;
                    }
                }
            }

            const obj_text = trimmed[pos..obj_end];
            const first_key = json.extractString(obj_text, "id") orelse
                json.extractString(obj_text, "name") orelse
                json.extractString(obj_text, "key") orelse "?";
            std.fmt.format(result.writer(), "  {s}\n", .{first_key}) catch return "";

            count += 1;
            pos = obj_end + 1;
        }

        // Count total items
        const total = std.mem.count(u8, trimmed, &.{'{'});

        std.fmt.format(result.writer(), "curl: JSON array with {d} items\n", .{total}) catch return "";
        if (count < total) {
            std.fmt.format(result.writer(), "  ... showing first {d}\n", .{count}) catch return "";
        }

        return result.toOwnedSlice() catch "";
    }

    // Not JSON, return truncated
    return trimmed[0..@min(trimmed.len, 200)];
}

/// Generic curl filter
fn filterCurlGeneric(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 30) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Skip HTTP headers
        if (std.mem.startsWith(u8, trimmed, "HTTP/")) continue;
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Content-Type:")) continue;
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Date:")) continue;
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Cache-Control:")) continue;

        result.appendSlice(trimmed[0..@min(200, trimmed.len)]) catch {};
        result.append('\n') catch {};
        count += 1;
    }

    if (result.items.len == 0) {
        return "curl: No content";
    }

    return result.toOwnedSlice() catch "";
}

/// Run curl with filtering
pub fn runCurl(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    // Check for -i (include headers) or -v (verbose) which we should remove
    var has_json_output = false;
    for (args) |arg| {
        if (std.mem.containsAtLeast(u8, arg, 1, "json") or
            std.mem.containsAtLeast(u8, arg, 1, "Accept:"))
        {
            has_json_output = true;
        }
    }

    for (args) |arg| {
        // Skip verbose flags
        if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose") or
            std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--include"))
        {
            continue;
        }
        try cmd_args.append(arg);
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "curl", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
    });
}
