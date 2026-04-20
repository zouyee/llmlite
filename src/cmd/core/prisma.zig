//! Prisma - Database ORM
//!
//! Filters prisma output for compact representation.
//! Inspired by RTK's prisma_cmd.rs.
//!
//! ## Token Savings
//!
//! prisma generate: ~100 lines → ~20 lines (80% reduction)

const std = @import("std");

/// Filter prisma output
pub fn filterPrisma(output: []const u8, subcommand: []const u8) []const u8 {
    if (std.mem.containsAtLeast(u8, subcommand, 1, "generate")) {
        return filterPrismaGenerate(output);
    }
    if (std.mem.containsAtLeast(u8, subcommand, 1, "migrate")) {
        return filterPrismaMigrate(output);
    }
    if (std.mem.containsAtLeast(u8, subcommand, 1, "studio")) {
        return "prisma studio: Opening Prisma Studio";
    }

    return filterPrismaGeneric(output);
}

/// Filter prisma generate output
fn filterPrismaGenerate(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 20) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Skip noise
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Prisma Studio")) continue;
        if (std.mem.containsAtLeast(u8, trimmed, 1, "created")) continue;

        // Show important lines
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Generated") or
            std.mem.containsAtLeast(u8, trimmed, 1, "Query engine") or
            std.mem.containsAtLeast(u8, trimmed, 1, "error") or
            std.mem.containsAtLeast(u8, trimmed, 1, "Error") or
            std.mem.containsAtLeast(u8, trimmed, 1, "warning"))
        {
            result.appendSlice(trimmed[0..@min(120, trimmed.len)]) catch {};
            result.append('\n') catch {};
            count += 1;
        }
    }

    if (result.items.len == 0) {
        return "prisma generate: Completed";
    }

    return result.toOwnedSlice() catch "";
}

/// Filter prisma migrate output
fn filterPrismaMigrate(output: []const u8) []const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= 20) break;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Show important lines
        if (std.mem.containsAtLeast(u8, trimmed, 1, "Migration") or
            std.mem.containsAtLeast(u8, trimmed, 1, "applied") or
            std.mem.containsAtLeast(u8, trimmed, 1, "error") or
            std.mem.containsAtLeast(u8, trimmed, 1, "Error"))
        {
            result.appendSlice(trimmed[0..@min(120, trimmed.len)]) catch {};
            result.append('\n') catch {};
            count += 1;
        }
    }

    if (result.items.len == 0) {
        return "prisma migrate: Completed";
    }

    return result.toOwnedSlice() catch "";
}

/// Generic prisma filter
fn filterPrismaGeneric(output: []const u8) []const u8 {
    if (output.len == 0) {
        return "prisma: No output";
    }
    return output[0..@min(output.len, 500)];
}

/// Run prisma with filtering
pub fn runPrisma(allocator: std.mem.Allocator, args: []const []const u8, verbose: u8) !i32 {
    const runner = @import("cmd_core_runner");

    var cmd_args = std.array_list.Managed([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("prisma");

    for (args) |arg| {
        try cmd_args.append(arg);
    }

    // Detect subcommand
    var subcommand: []const u8 = "";
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "generate") or
            std.mem.eql(u8, arg, "migrate") or
            std.mem.eql(u8, arg, "studio") or
            std.mem.eql(u8, arg, "db"))
        {
            subcommand = arg;
        }
    }

    if (verbose > 0) {
        std.debug.print("Running: {s}\n", .{std.mem.join(u8, &cmd_args.items, " ")});
    }

    return runner.runFiltered(allocator, cmd_args.items, "prisma", std.mem.join(u8, args, " "), .{
        .verbose = verbose,
        .strategy = .state_machine,
    });
}
