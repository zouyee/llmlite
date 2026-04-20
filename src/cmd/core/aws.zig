//! AWS CLI - Amazon Web Services
//!
//! Filters AWS CLI output for compact representation.
//! Inspired by RTK's aws_cmd.rs.
//!
//! ## Token Savings
//!
//! aws cli: ~500 lines → ~50 lines (90% reduction)

const std = @import("std");
const json = @import("cmd_core_json");

/// Filter AWS CLI output
pub fn filterAws(output: []const u8, subcommand: []const u8) []const u8 {
    if (std.mem.containsAtLeast(u8, subcommand, 1, "ec2")) {
        return filterAwsEc2(output);
    }
    if (std.mem.containsAtLeast(u8, subcommand, 1, "lambda")) {
        return filterAwsLambda(output);
    }
    if (std.mem.containsAtLeast(u8, subcommand, 1, "s3")) {
        return filterAwsS3(output);
    }
    if (std.mem.containsAtLeast(u8, subcommand, 1, "sts")) {
        return filterAwsSts(output);
    }
    if (std.mem.containsAtLeast(u8, subcommand, 1, "logs")) {
        return filterAwsLogs(output);
    }

    return filterAwsGeneric(output);
}

/// Filter AWS STS output (usually short)
fn filterAwsSts(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 10) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        result.appendSlice(trimmed[0..@min(100, trimmed.len)]) catch {};
        result.append('\n') catch {};
        count += 1;
    }

    if (result.items.len == 0) {
        return "aws sts: No output";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter AWS EC2 output
fn filterAwsEc2(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Check for JSON output
    if (output.len > 0 and output[0] == '{') {
        return filterAwsEc2Json(output);
    }

    // Text format
    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 30) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Skip separators
        if (std.mem.containsAtLeast(u8, trimmed, 1, "---")) continue;

        result.appendSlice(trimmed[0..@min(120, trimmed.len)]) catch {};
        result.append('\n') catch {};
        count += 1;
    }

    if (result.items.len == 0) {
        return "aws ec2: No instances";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter AWS EC2 JSON output
fn filterAwsEc2Json(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Try to extract reservations
    const reservations = json.extractJsonObject(output, "Reservations");
    if (reservations == null) {
        return "aws ec2: No reservations";
    }

    var instance_count: usize = 0;

    // Simplified: just count and show first few
    var pos: usize = 0;
    while (pos < reservations.?.len) {
        const search = "\"InstanceId\":\"";
        const idx = std.mem.indexOf(u8, reservations.?[pos..], search);
        if (idx == null) break;

        pos += idx.? + search.len;
        const end = std.mem.indexOf(u8, reservations.?[pos..], "\"") orelse break;
        const instance_id = reservations.?[pos .. pos + end];

        if (instance_count < 10) {
            std.fmt.format(result.writer(), "{s}\n", .{instance_id}) catch return "";
        }
        instance_count += 1;
        pos += end;
    }

    if (instance_count == 0) {
        return "aws ec2: No instances";
    }

    if (instance_count > 10) {
        std.fmt.format(result.writer(), "... +{d} more instances\n", .{instance_count - 10}) catch return "";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter AWS Lambda output
fn filterAwsLambda(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    // Check for JSON
    if (output.len > 0 and output[0] == '{') {
        // Try to extract function names
        var pos: usize = 0;
        var count: usize = 0;

        while (pos < output.len and count < 20) {
            const search = "\"FunctionName\":\"";
            const idx = std.mem.indexOf(u8, output[pos..], search);
            if (idx == null) break;

            pos += idx.? + search.len;
            const end = std.mem.indexOf(u8, output[pos..], "\"") orelse break;
            const func_name = output[pos .. pos + end];

            std.fmt.format(result.writer(), "{s}\n", .{func_name}) catch return "";
            count += 1;
            pos += end;
        }

        if (count == 0) {
            return "aws lambda: No functions";
        }

        return result.toOwnedSlice() catch "";
    }

    // Text format
    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 30) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        result.appendSlice(trimmed[0..@min(100, trimmed.len)]) catch {};
        result.append('\n') catch {};
        count += 1;
    }

    if (result.items.len == 0) {
        return "aws lambda: No functions";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter AWS S3 output
fn filterAwsS3(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 30) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        result.appendSlice(trimmed[0..@min(100, trimmed.len)]) catch {};
        result.append('\n') catch {};
        count += 1;
    }

    if (result.items.len == 0) {
        return "aws s3: No output";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter AWS CloudWatch Logs output
fn filterAwsLogs(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
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
        return "aws logs: No logs";
    }

    return result.toOwnedSlice() catch "";
}

/// Generic AWS filter
fn filterAwsGeneric(output: []const u8) []const u8 {
    if (output.len == 0) {
        return "aws: No output";
    }
    return output[0..@min(output.len, 500)];
}

/// Run AWS CLI with filtering
pub fn runAws(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("aws");

    for (args) |arg| {
        try cmd_args.append(arg);
    }

    // Detect service subcommand
    var subcommand: []const u8 = "";
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "ec2") or
            std.mem.eql(u8, arg, "s3") or
            std.mem.eql(u8, arg, "lambda") or
            std.mem.eql(u8, arg, "sts") or
            std.mem.eql(u8, arg, "logs") or
            std.mem.eql(u8, arg, "iam") or
            std.mem.eql(u8, arg, "dynamodb"))
        {
            subcommand = arg;
        }
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "aws", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
    });
}
