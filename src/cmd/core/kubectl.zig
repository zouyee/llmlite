//! Kubectl - Kubernetes CLI
//!
//! Filters kubectl command outputs for compact representation.
//! Inspired by RTK's container.rs.
//!
//! ## Supported Commands
//!
//! - kubectl get pods - Pod list
//! - kubectl get svc - Service list
//! - kubectl get deployments - Deployment list
//! - kubectl logs - Log output
//! - kubectl describe - Resource details
//!
//! ## Token Savings
//!
//! kubectl get pods: ~100 lines → ~20 lines (80% reduction)

const std = @import("std");
const json = @import("cmd_core_json");

/// Filter kubectl output
pub fn filterKubectl(output: []const u8, subcommand: []const u8) []const u8 {
    if (std.mem.containsAtLeast(u8, subcommand, 1, "get")) {
        if (std.mem.containsAtLeast(u8, subcommand, 1, "pod")) {
            return filterKubectlPods(output);
        }
        if (std.mem.containsAtLeast(u8, subcommand, 1, "svc")) {
            return filterKubectlSvc(output);
        }
        if (std.mem.containsAtLeast(u8, subcommand, 1, "deploy")) {
            return filterKubectlDeployments(output);
        }
        return filterKubectlGet(output);
    }
    if (std.mem.containsAtLeast(u8, subcommand, 1, "logs")) {
        return filterKubectlLogs(output);
    }
    if (std.mem.containsAtLeast(u8, subcommand, 1, "describe")) {
        return filterKubectlDescribe(output);
    }

    return filterKubectlGeneric(output);
}

/// Filter kubectl get pods output
fn filterKubectlPods(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;
    var headers_parsed = false;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Skip header line
        if (!headers_parsed) {
            headers_parsed = true;
            // Show abbreviated header
            result.appendSlice("NAME                      READY   STATUS    RESTARTS   AGE\n") catch {};
            continue;
        }

        if (count >= 15) {
            std.fmt.format(result.writer(), "\n... +{d} more pods", .{count - 15}) catch return "";
            break;
        }

        // Parse space-separated columns
        var cols = std.mem.splitScalar(u8, trimmed, ' ');
        var col_count: usize = 0;
        var cols_array: [6][]const u8 = .{ "", "", "", "", "", "" };

        while (cols.next()) |col| {
            const trimmed_col = std.mem.trim(u8, col, " \t");
            if (trimmed_col.len == 0) continue;
            if (col_count < 6) {
                cols_array[col_count] = trimmed_col;
                col_count += 1;
            }
        }

        // Show: NAME, READY, STATUS, RESTARTS, AGE
        if (col_count >= 5) {
            std.fmt.format(result.writer(), "{s} {s} {s} {s} {s}\n", .{
                cols_array[0][0..@min(24, cols_array[0].len)],
                cols_array[1][0..@min(6, cols_array[1].len)],
                cols_array[2][0..@min(12, cols_array[2].len)],
                cols_array[3][0..@min(9, cols_array[3].len)],
                cols_array[4][0..@min(8, cols_array[4].len)],
            }) catch return "";
        } else if (col_count > 0) {
            result.appendSlice(trimmed[0..@min(80, trimmed.len)]) catch {};
            result.append('\n') catch {};
        }

        count += 1;
    }

    if (result.items.len == 0) {
        return "kubectl: No pods found";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter kubectl get svc output
fn filterKubectlSvc(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;
    var headers_parsed = false;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        if (!headers_parsed) {
            headers_parsed = true;
            result.appendSlice("NAME             TYPE           CLUSTER-IP      PORT(S)        AGE\n") catch {};
            continue;
        }

        if (count >= 15) break;

        var cols = std.mem.splitScalar(u8, trimmed, ' ');
        var col_count: usize = 0;
        var cols_array: [5][]const u8 = .{ "", "", "", "", "" };

        while (cols.next()) |col| {
            const trimmed_col = std.mem.trim(u8, col, " \t");
            if (trimmed_col.len == 0) continue;
            if (col_count < 5) {
                cols_array[col_count] = trimmed_col;
                col_count += 1;
            }
        }

        if (col_count >= 4) {
            std.fmt.format(result.writer(), "{s} {s} {s} {s}\n", .{
                cols_array[0][0..@min(16, cols_array[0].len)],
                cols_array[1][0..@min(14, cols_array[1].len)],
                cols_array[2][0..@min(14, cols_array[2].len)],
                cols_array[3][0..@min(18, cols_array[3].len)],
            }) catch return "";
        }

        count += 1;
    }

    if (result.items.len == 0) {
        return "kubectl: No services found";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter kubectl get deployments output
fn filterKubectlDeployments(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;
    var headers_parsed = false;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        if (!headers_parsed) {
            headers_parsed = true;
            result.appendSlice("NAME                    READY   UP-TO-DATE   AVAILABLE   AGE\n") catch {};
            continue;
        }

        if (count >= 15) break;

        var cols = std.mem.splitScalar(u8, trimmed, ' ');
        var col_count: usize = 0;
        var cols_array: [5][]const u8 = .{ "", "", "", "", "" };

        while (cols.next()) |col| {
            const trimmed_col = std.mem.trim(u8, col, " \t");
            if (trimmed_col.len == 0) continue;
            if (col_count < 5) {
                cols_array[col_count] = trimmed_col;
                col_count += 1;
            }
        }

        if (col_count >= 4) {
            std.fmt.format(result.writer(), "{s} {s} {s} {s} {s}\n", .{
                cols_array[0][0..@min(20, cols_array[0].len)],
                cols_array[1][0..@min(6, cols_array[1].len)],
                cols_array[2][0..@min(12, cols_array[2].len)],
                cols_array[3][0..@min(11, cols_array[3].len)],
                cols_array[4][0..@min(6, cols_array[4].len)],
            }) catch return "";
        }

        count += 1;
    }

    if (result.items.len == 0) {
        return "kubectl: No deployments found";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter kubectl get output (generic)
fn filterKubectlGet(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 20) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        result.appendSlice(trimmed[0..@min(100, trimmed.len)]) catch {};
        result.append('\n') catch {};
        count += 1;
    }

    if (result.items.len == 0) {
        return "kubectl: No resources found";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter kubectl logs output
fn filterKubectlLogs(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;
    var last_line: []const u8 = "";
    var repeat_count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 50) {
            std.fmt.format(result.writer(), "\n... +{d} more lines", .{(std.mem.count(u8, output, &.{'\n'}) - 50)}) catch return "";
            break;
        }

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Deduplicate
        if (std.mem.eql(u8, trimmed, last_line)) {
            repeat_count += 1;
            continue;
        }

        if (repeat_count > 1) {
            std.fmt.format(result.writer(), "... repeated {d} times\n", .{repeat_count}) catch return "";
        }

        result.appendSlice(trimmed[0..@min(150, trimmed.len)]) catch {};
        result.append('\n') catch {};
        last_line = trimmed;
        repeat_count = 1;
        count += 1;
    }

    if (repeat_count > 1) {
        std.fmt.format(result.writer(), "... repeated {d} times\n", .{repeat_count}) catch return "";
    }

    if (result.items.len == 0) {
        return "kubectl logs: No logs";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter kubectl describe output
fn filterKubectlDescribe(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    // Key fields to show from describe
    const key_fields = &.{
        "Name:",     "Namespace:", "Labels:",     "Status:",
        "Type:",     "Port:",      "TargetPort:", "Replicas:",
        "Strategy:", "Events:",
    };

    while (lines.next()) |line| {
        if (count >= 40) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Show key lines
        for (key_fields) |key| {
            if (std.mem.startsWith(u8, trimmed, key)) {
                result.appendSlice(trimmed[0..@min(120, trimmed.len)]) catch {};
                result.append('\n') catch {};
                count += 1;
                break;
            }
        }
    }

    if (result.items.len == 0) {
        return output[0..@min(output.len, 500)];
    }

    return result.toOwnedSlice() catch "";
}

/// Generic kubectl filter
fn filterKubectlGeneric(output: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
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
        return "kubectl: No output";
    }

    return result.toOwnedSlice() catch "";
}

/// Run kubectl with filtering
pub fn runKubectl(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.ArrayList([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("kubectl");

    for (args) |arg| {
        try cmd_args.append(arg);
    }

    // Detect subcommand
    var subcommand: []const u8 = "";
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "get") or
            std.mem.eql(u8, arg, "logs") or
            std.mem.eql(u8, arg, "describe") or
            std.mem.eql(u8, arg, "pods") or
            std.mem.eql(u8, arg, "svc") or
            std.mem.eql(u8, arg, "services") or
            std.mem.eql(u8, arg, "deployments") or
            std.mem.eql(u8, arg, "deploy"))
        {
            subcommand = arg;
        }
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "kubectl", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
    });
}
