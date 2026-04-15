//! Runner - 6-Phase Execution Framework
//!
//! This module implements the core execution flow used by all command modules.
//!
//! ## 6-Phase Execution
//!
//! ```text
//! Phase 1: EXECUTE  → std.process.Child.run()
//! Phase 2: FILTER   → filter.zig (12+ strategies)
//! Phase 3: TEE      → tee.zig (failure recovery)
//! Phase 4: PRINT    → stdout output
//! Phase 5: TRACK    → tracking.zig (SQLite)
//! Phase 6: EXIT     → return original exit code
//! ```

const std = @import("std");
const filter = @import("filter");
const tracking = @import("tracking");
const tee = @import("tee");

pub const RunOptions = struct {
    /// Combine stdout and stderr for filtering
    combined: bool = true,
    /// Enable tee for failure recovery
    tee_label: ?[]const u8 = null,
    /// Verbosity level (-v, -vv, -vvv)
    verbose: u8 = 0,
    /// Filter strategy to use
    strategy: filter.FilterStrategy = .none,
    /// Filter level
    level: filter.FilterLevel = .standard,
};

pub const RunError = error{
    ExecutionFailed,
    FilterFailed,
    TrackingFailed,
    TeeFailed,
    OutOfMemory,
};

/// Run a filtered command using the 6-phase framework
pub fn runFiltered(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    cmd_name: []const u8,
    raw_args: []const u8,
    options: RunOptions,
) RunError!i32 {
    // Phase 1: EXECUTE
    if (options.verbose > 1) {
        std.log.info("executing: {s}", .{cmd_name});
    }

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .max_output_bytes = 10 * 1024 * 1024, // 10MB for large diffs
    }) catch {
        if (options.verbose > 0) {
            std.log.err("command execution failed: {s}", .{cmd_name});
        }
        return RunError.ExecutionFailed;
    };

    const exit_code: i32 = switch (result.term) {
        .Exited => |code| code,
        .Signal => |sig| 128 + @as(i32, @intCast(sig)),
        .Stopped => |sig| 128 + @as(i32, @intCast(sig)),
        .Unknown => 1,
    };

    // Combine stdout and stderr if needed
    const raw_output = if (options.combined)
        try concatOutput(allocator, result.stdout, result.stderr)
    else
        try allocator.dupe(u8, result.stdout);
    defer allocator.free(raw_output);

    if (options.verbose > 2) {
        std.log.info("raw output ({d} bytes):\n{s}", .{ raw_output.len, raw_output });
    }

    // Phase 2: FILTER
    var filtered: []const u8 = undefined;
    if (options.strategy == .none) {
        filtered = raw_output;
    } else {
        const filter_result = filter.filter(allocator, raw_output, .{
            .strategy = options.strategy,
            .level = options.level,
        }) catch {
            if (options.verbose > 0) {
                std.log.warn("filter failed, using raw output", .{});
            }
            filtered = raw_output;
            return RunError.FilterFailed;
        };
        filtered = filter_result.filtered;
    }

    // Phase 3: TEE (failure recovery)
    var tee_filepath: ?[]const u8 = null;
    if (options.tee_label != null and exit_code != 0) {
        tee_filepath = tee.save(options.tee_label.?, raw_args, raw_output) catch null;
        if (tee_filepath == null and options.verbose > 0) {
            std.log.warn("tee save failed", .{});
        }
    }

    // Phase 4: PRINT
    std.debug.print("{s}", .{filtered});

    // Print tee recovery path if available (RTK-style)
    if (tee_filepath) |path| {
        std.debug.print("[full output: {s}]\n", .{path});
    }

    // Phase 5: TRACK
    tracking.track(allocator, .{
        .original_cmd = raw_args,
        .rtk_cmd = cmd_name,
        .raw_output = raw_output,
        .filtered_output = filtered,
        .exit_code = exit_code,
    }) catch {
        if (options.verbose > 0) {
            std.log.warn("tracking failed", .{});
        }
    };

    // Phase 6: EXIT
    return exit_code;
}

/// Passthrough - just execute and return exit code (no filtering)
pub fn runPassthrough(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    verbose: u8,
) RunError!i32 {
    if (verbose > 1) {
        std.log.info("executing (passthrough)", .{});
    }

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .max_output_bytes = 10 * 1024 * 1024, // 10MB for large outputs
    }) catch {
        return RunError.ExecutionFailed;
    };

    // Print stdout
    std.debug.print("{s}", .{result.stdout});

    return switch (result.term) {
        .Exited => |code| code,
        .Signal => |sig| 128 + @as(i32, @intCast(sig)),
        .Stopped => |sig| 128 + @as(i32, @intCast(sig)),
        .Unknown => 1,
    };
}

fn concatOutput(allocator: std.mem.Allocator, a: []const u8, b: []const u8) ![]u8 {
    var result = try allocator.alloc(u8, a.len + b.len);
    @memcpy(result[0..a.len], a);
    @memcpy(result[a.len..], b);
    return result;
}
