//! Runner - 6-Phase Execution Framework
//!
//! This module implements the core execution flow used by all command modules.
//!
//! ## Execution Phases
//!
//! ```text
//! Phase 1: EXECUTE  → std.process.Child.run()
//! Phase 2: FILTER   → filter.zig (12+ strategies)
//! Phase 3: TEE      → tee.zig (failure recovery)
//! Phase 4: PRINT    → stdout output
//! Phase 5: TRACK    → tracking.zig (file-based)
//! Phase 5.3: REPORT → savings_reporter.zig (proxy-cmd integration)
//! Phase 5.5: MEMORY → memory.zig (claude-mem migration)
//! Phase 6: EXIT     → return original exit code
//! ```

const std = @import("std");

// Zig 0.16.0 compat: replacement for removed _getEnvVarOwned
fn _getEnvVarOwned(allocator: std.mem.Allocator, key: [*:0]const u8) error{EnvironmentVariableNotFound, OutOfMemory}![]u8 {
    const ptr = std.c.getenv(key) orelse return error.EnvironmentVariableNotFound;
    const slice = std.mem.sliceTo(ptr, 0);
    return allocator.dupe(u8, slice);
}
const filter = @import("filter");
const tracking = @import("tracking");
const tee = @import("tee");
const memory = @import("memory");
const config_mod = @import("config");
const shared = @import("shared_analytics");
const savings_reporter = @import("savings_reporter");
const time_compat = @import("time_compat");

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
    /// I/O handle for process spawning (Zig 0.16.0)
    io: ?std.Io = null,
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

    const io = options.io orelse return RunError.ExecutionFailed;
    const result = std.process.run(allocator, io, .{
        .argv = argv,
    }) catch {
        if (options.verbose > 0) {
            std.log.err("command execution failed: {s}", .{cmd_name});
        }
        return RunError.ExecutionFailed;
    };

    const exit_code: i32 = switch (result.term) {
        .exited => |code| code,
        .signal => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
        .stopped => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
        .unknown => 1,
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
        const filter_result = blk: {
            break :blk filter.filter(allocator, raw_output, .{
                .strategy = options.strategy,
                .level = options.level,
            }) catch |err| {
                if (options.verbose > 0) {
                    std.log.warn("filter failed: {}, using raw output", .{err});
                }
                break :blk filter.FilterResult{
                    .filtered = raw_output,
                    .original_len = raw_output.len,
                    .filtered_len = raw_output.len,
                    .reduction_pct = 0,
                    .strategy_used = options.strategy,
                };
            };
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

    // Phase 5.3: REPORT (proxy-cmd integration)
    const report_config = blk: {
        const cfg_result = config_mod.loadConfig(allocator) catch break :blk null;
        break :blk cfg_result;
    };
    if (report_config) |c| {
        defer {
            // Config fields may contain allocated strings; free them
            // Note: Config currently lacks a deinit method, so we only free
            // the analytics_proxy.host if it was allocated
            allocator.free(c.analytics_proxy.host);
        }

        if (c.analytics.enabled) {
            const raw_tokens = shared.estimateTokens(raw_output.len);
            const filtered_tokens = shared.estimateTokens(filtered.len);
            const saved_tokens = if (raw_tokens > filtered_tokens) raw_tokens - filtered_tokens else 0;
            const savings_pct = if (raw_tokens > 0)
                @as(f64, @floatFromInt(saved_tokens)) / @as(f64, @floatFromInt(raw_tokens)) * 100.0
            else
                0.0;

            const hostname = _getEnvVarOwned(allocator, "HOSTNAME") catch
                _getEnvVarOwned(allocator, "COMPUTERNAME") catch
                allocator.dupe(u8, "unknown") catch "unknown";
            defer allocator.free(hostname);

            const report = shared.SavingsReport{
                .timestamp = time_compat.timestamp(io),
                .original_cmd = raw_args,
                .raw_output_tokens = raw_tokens,
                .filtered_output_tokens = filtered_tokens,
                .saved_tokens = saved_tokens,
                .savings_pct = savings_pct,
                .exit_code = exit_code,
                .hostname = hostname,
            };

            var reporter = savings_reporter.SavingsReporter.init(
                allocator,
                io,
                c.analytics_proxy.host,
                c.analytics_proxy.port,
            ) catch |err| blk: {
                if (options.verbose > 0) std.log.warn("savings reporter init failed: {}", .{err});
                break :blk null;
            };
            if (reporter) |*r| {
                defer r.deinit();
                r.reportAsync(report);
            }
        }
    }

    // Phase 5.5: MEMORY (claude-mem migration)
    const mem_home_dir = _getEnvVarOwned(allocator, "HOME") catch null;
    defer if (mem_home_dir) |h| allocator.free(h);

    var mem_db: ?memory.MemoryDb = if (mem_home_dir) |home_dir|
        memory.MemoryDb.init(allocator, io, home_dir) catch |err| blk: {
            if (options.verbose > 0) std.log.warn("memory init failed: {}", .{err});
            break :blk null;
        }
    else null;

    if (mem_db) |*mdb| {
        defer mdb.deinit();

        // Load config first to get privacy mode for both SessionManager and Recorder
        const recorder_config = blk: {
            if (config_mod.loadConfig(allocator)) |maybe_cfg| {
                if (maybe_cfg) |cfg| {
                    break :blk memory.Recorder.RecorderConfig{
                        .enabled = cfg.memory.enabled,
                        .auto_record = cfg.memory.auto_record,
                        .max_context_length = cfg.memory.max_context_length,
                        .dedup_window_secs = cfg.memory.dedup_window_secs,
                        .excluded_patterns = cfg.memory.privacy.excluded_patterns,
                        .privacy_mode = switch (cfg.memory.privacy.mode) {
                            .normal => .normal,
                            .private => .private,
                        },
                    };
                }
            } else |_| {}
            break :blk memory.Recorder.RecorderConfig{};
        };

        // Initialize SessionManager with privacy mode so it skips writing session.json in private mode
        var session_mgr = memory.SessionManager.initWithPrivacy(allocator, io, @constCast(mdb), mem_home_dir.?, recorder_config.privacy_mode);
        defer session_mgr.deinit();

        var session_id: []const u8 = "unknown";
        var session_id_owned = false;
        if (session_mgr.getSessionId()) |sid| {
            session_id = sid;
            session_id_owned = true;
        } else |err| {
            if (options.verbose > 0) std.log.warn("session get failed: {}", .{err});
        }
        defer if (session_id_owned) allocator.free(session_id);

        var rec = memory.Recorder.init(allocator, io, mdb, recorder_config);
        _ = rec.record(raw_args, filtered, exit_code, session_id) catch |err| {
            std.log.warn("memory record failed: {}", .{err});
        };
    }

    // Phase 6: EXIT
    return exit_code;
}

/// Passthrough - just execute and return exit code (no filtering)
pub fn runPassthrough(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    verbose: u8,
    io: ?std.Io,
) RunError!i32 {
    if (verbose > 1) {
        std.log.info("executing (passthrough)", .{});
    }

    const io_val = io orelse return RunError.ExecutionFailed;
    const result = std.process.run(allocator, io_val, .{
        .argv = argv,
    }) catch {
        return RunError.ExecutionFailed;
    };

    // Print stdout
    std.debug.print("{s}", .{result.stdout});

    return switch (result.term) {
        .exited => |code| code,
        .signal => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
        .stopped => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
        .unknown => 1,
    };
}

fn concatOutput(allocator: std.mem.Allocator, a: []const u8, b: []const u8) ![]u8 {
    var result = try allocator.alloc(u8, a.len + b.len);
    @memcpy(result[0..a.len], a);
    @memcpy(result[a.len..], b);
    return result;
}
