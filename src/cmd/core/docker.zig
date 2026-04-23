//! Docker - Container Management
//!
//! Filters docker command outputs for compact representation.
//! Inspired by RTK's docker.rs.
//!
//! ## Supported Commands
//!
//! - docker ps - Container list
//! - docker images - Image list
//! - docker logs - Log output
//! - docker compose ps - Compose services
//!
//! ## Token Savings
//!
//! docker ps: ~50 lines → ~15 lines (70% reduction)

const std = @import("std");
const json = @import("cmd_core_json");

/// Filter docker output
pub fn filterDocker(output: []const u8, subcommand: []const u8) []const u8 {
    if (std.mem.containsAtLeast(u8, subcommand, 1, "ps")) {
        return filterDockerPs(output);
    }
    if (std.mem.containsAtLeast(u8, subcommand, 1, "images")) {
        return filterDockerImages(output);
    }
    if (std.mem.containsAtLeast(u8, subcommand, 1, "logs")) {
        return filterDockerLogs(output);
    }
    if (std.mem.containsAtLeast(u8, subcommand, 1, "compose")) {
        return filterDockerCompose(output);
    }

    return filterDockerGeneric(output);
}

/// Filter docker ps output
fn filterDockerPs(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;
    var headers: ?[]const u8 = null;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // First line is usually headers
        if (headers == null) {
            headers = trimmed;
            continue;
        }

        if (count >= 10) {
            result.print( "\n... +{d} more containers", .{count - 10}) catch return "";
            break;
        }

        // Parse space-separated columns
        var cols = std.mem.splitScalar(u8, trimmed, ' ');
        var col_count: usize = 0;
        var cols_array: [4][]const u8 = .{ "", "", "", "" };

        while (cols.next()) |col| {
            const trimmed_col = std.mem.trim(u8, col, " \t");
            if (trimmed_col.len == 0) continue;
            if (col_count < 4) {
                cols_array[col_count] = trimmed_col;
                col_count += 1;
            }
        }

        // Show: CONTAINER ID, IMAGE, STATUS, NAMES
        if (col_count >= 4) {
            result.print( "{s} {s} {s} {s}\n", .{
                cols_array[0][0..@min(12, cols_array[0].len)],
                cols_array[1][0..@min(20, cols_array[1].len)],
                cols_array[2][0..@min(15, cols_array[2].len)],
                cols_array[3][0..@min(20, cols_array[3].len)],
            }) catch return "";
        } else if (col_count > 0) {
            result.appendSlice(trimmed[0..@min(80, trimmed.len)]) catch {};
            result.append('\n') catch {};
        }

        count += 1;
    }

    if (result.items.len == 0) {
        return "docker ps: No containers";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter docker images output
fn filterDockerImages(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;
    var headers: ?[]const u8 = null;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        if (headers == null) {
            headers = trimmed;
            continue;
        }

        if (count >= 10) {
            result.print( "\n... +{d} more images", .{count - 10}) catch return "";
            break;
        }

        // Parse space-separated columns
        var cols = std.mem.splitScalar(u8, trimmed, ' ');
        var col_count: usize = 0;
        var cols_array: [4][]const u8 = .{ "", "", "", "" };

        while (cols.next()) |col| {
            const trimmed_col = std.mem.trim(u8, col, " \t");
            if (trimmed_col.len == 0) continue;
            if (col_count < 4) {
                cols_array[col_count] = trimmed_col;
                col_count += 1;
            }
        }

        // Show: REPOSITORY, TAG, SIZE, IMAGE ID
        if (col_count >= 3) {
            result.print( "{s} {s} {s}", .{
                cols_array[0][0..@min(25, cols_array[0].len)],
                cols_array[1][0..@min(15, cols_array[1].len)],
                cols_array[2][0..@min(15, cols_array[2].len)],
            }) catch return "";
            if (col_count >= 4) {
                result.print( " {s}", .{cols_array[3][0..@min(12, cols_array[3].len)]}) catch return "";
            }
            result.append('\n') catch {};
        }

        count += 1;
    }

    if (result.items.len == 0) {
        return "docker images: No images";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter docker logs output
fn filterDockerLogs(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;
    var last_line: []const u8 = "";
    var repeat_count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 50) {
            result.print( "\n... +{d} more lines", .{(std.mem.count(u8, output, &.{'\n'}) - 50)}) catch return "";
            break;
        }

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Deduplicate repeated lines
        if (std.mem.eql(u8, trimmed, last_line)) {
            repeat_count += 1;
            continue;
        }

        if (repeat_count > 1) {
            result.print( "... repeated {d} times\n", .{repeat_count}) catch return "";
        }

        result.appendSlice(trimmed) catch {};
        result.append('\n') catch {};
        last_line = trimmed;
        repeat_count = 1;
        count += 1;
    }

    if (repeat_count > 1) {
        result.print( "... repeated {d} times\n", .{repeat_count}) catch return "";
    }

    if (result.items.len == 0) {
        return "docker logs: No logs";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter docker compose ps output
fn filterDockerCompose(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        if (count >= 15) break;

        // Skip separator lines
        if (std.mem.containsAtLeast(u8, trimmed, 1, "─") or
            std.mem.containsAtLeast(u8, trimmed, 1, "═"))
        {
            continue;
        }

        result.appendSlice(trimmed[0..@min(100, trimmed.len)]) catch {};
        result.append('\n') catch {};
        count += 1;
    }

    if (result.items.len == 0) {
        return "docker compose: No services";
    }

    return result.toOwnedSlice() catch "";
}

/// Generic docker filter
fn filterDockerGeneric(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 30) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        result.appendSlice(trimmed[0..@min(120, trimmed.len)]) catch {};
        result.append('\n') catch {};
        count += 1;
    }

    if (result.items.len == 0) {
        return "docker: No output";
    }

    return result.toOwnedSlice() catch "";
}

/// Run docker with filtering
pub fn runDocker(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("docker");

    for (args) |arg| {
        try cmd_args.append(arg);
    }

    // Detect subcommand
    const subcommand: []const u8 = blk: {
        for (args) |arg| {
            if (std.mem.eql(u8, arg, "ps") or
                std.mem.eql(u8, arg, "images") or
                std.mem.eql(u8, arg, "logs") or
                std.mem.eql(u8, arg, "compose"))
            {
                break :blk arg;
            }
        }
        break :blk "";
    };
    _ = subcommand; // Used by filterDocker when integrated with runner

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "docker", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
    });
}

// ==================== TESTS ====================

test "docker filter - ps basic" {
    const input = "CONTAINER ID   IMAGE       STATUS      PORTS                    NAMES\nabc123def456   nginx:latest   Up 2 hours   0.0.0.0:80->80/tcp   web";
    const result = filterDocker(input, "ps");
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "nginx"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "web"));
}

test "docker filter - ps empty" {
    const input = "";
    const result = filterDocker(input, "ps");
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "No containers"));
}

test "docker filter - images basic" {
    const input = "REPOSITORY   TAG       IMAGE ID       SIZE\nnginx        latest    abc123def456  142MB";
    const result = filterDocker(input, "images");
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "nginx"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "142MB"));
}

test "docker filter - compose ps basic" {
    const input = "NAME       IMAGE       STATUS      PORTS\nweb-1      nginx:latest   Up 2 hours   0.0.0.0:80->80/tcp";
    const result = filterDocker(input, "compose");
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "web"));
}

test "docker filter - logs deduplication" {
    const input = "line1\nline1\nline1\nline2";
    const result = filterDocker(input, "logs");
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "repeated"));
}

test "docker filter - generic" {
    const input = "some docker output";
    const result = filterDocker(input, "unknown");
    try std.testing.expect(result.len > 0);
}
