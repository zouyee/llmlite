//! Savings Store - In-memory storage for cmd-reported savings data
//!
//! Provides thread-safe append and time-range aggregation.

const std = @import("std");
const shared = @import("shared_analytics");
const time_compat = @import("time_compat");

pub const SavingsStore = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    reports: std.ArrayList(shared.SavingsReport),
    mutex: std.Io.Mutex,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) SavingsStore {
        return .{
            .allocator = allocator,
            .io = io,
            .reports = std.ArrayList(shared.SavingsReport).empty,
            .mutex = std.Io.Mutex.init,
        };
    }

    pub fn deinit(self: *SavingsStore) void {
        while (!self.mutex.tryLock()) {}
        defer self.mutex.state.store(.unlocked, .release);
        for (self.reports.items) |r| {
            self.allocator.free(r.original_cmd);
            self.allocator.free(r.hostname);
        }
        self.reports.deinit(self.allocator);
    }

    /// Add a report (deep-copies string fields)
    pub fn addReport(self: *SavingsStore, report: shared.SavingsReport) !void {
        while (!self.mutex.tryLock()) {}
        defer self.mutex.state.store(.unlocked, .release);

        const owned_cmd = try self.allocator.dupe(u8, report.original_cmd);
        errdefer self.allocator.free(owned_cmd);
        const owned_host = try self.allocator.dupe(u8, report.hostname);
        errdefer self.allocator.free(owned_host);

        try self.reports.append(self.allocator, .{
            .timestamp = report.timestamp,
            .original_cmd = owned_cmd,
            .raw_output_tokens = report.raw_output_tokens,
            .filtered_output_tokens = report.filtered_output_tokens,
            .saved_tokens = report.saved_tokens,
            .savings_pct = report.savings_pct,
            .exit_code = report.exit_code,
            .hostname = owned_host,
        });
    }

    /// Aggregate savings data with optional time filter
    pub fn aggregate(self: *SavingsStore, days: ?u32, team_id: ?[]const u8) shared.CmdSavingsSummary {
        _ = team_id; // team filtering not implemented for in-memory store

        while (!self.mutex.tryLock()) {}
        defer self.mutex.state.store(.unlocked, .release);

        const cutoff = if (days) |d|
            time_compat.timestamp(self.io) - @as(i64, @intCast(d * 86400))
        else
            std.math.minInt(i64);

        var total_commands: u64 = 0;
        var total_saved: u64 = 0;
        var total_pct: f64 = 0.0;

        for (self.reports.items) |r| {
            if (r.timestamp < cutoff) continue;
            total_commands += 1;
            total_saved += r.saved_tokens;
            total_pct += r.savings_pct;
        }

        return shared.CmdSavingsSummary{
            .total_commands = total_commands,
            .total_saved_tokens = total_saved,
            .avg_savings_pct = if (total_commands > 0) total_pct / @as(f64, @floatFromInt(total_commands)) else 0.0,
            .by_command = &.{}, // TODO: implement command breakdown allocation
        };
    }

    /// Remove reports older than retention_days
    pub fn cleanup(self: *SavingsStore, retention_days: u32) void {
        while (!self.mutex.tryLock()) {}
        defer self.mutex.state.store(.unlocked, .release);

        const cutoff = time_compat.timestamp(self.io) - @as(i64, @intCast(retention_days * 86400));
        var i: usize = 0;
        while (i < self.reports.items.len) {
            if (self.reports.items[i].timestamp < cutoff) {
                self.allocator.free(self.reports.items[i].original_cmd);
                self.allocator.free(self.reports.items[i].hostname);
                _ = self.reports.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn reportCount(self: *SavingsStore) usize {
        while (!self.mutex.tryLock()) {}
        defer self.mutex.state.store(.unlocked, .release);
        return self.reports.items.len;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "add and aggregate" {
    const allocator = std.testing.allocator;
    var store = SavingsStore.init(allocator, std.testing.io);
    defer store.deinit();

    try store.addReport(.{
        .timestamp = time_compat.timestamp(std.testing.io),
        .original_cmd = "git status",
        .raw_output_tokens = 100,
        .filtered_output_tokens = 40,
        .saved_tokens = 60,
        .savings_pct = 60.0,
        .exit_code = 0,
        .hostname = "localhost",
    });

    const summary = store.aggregate(null, null);
    try std.testing.expectEqual(@as(u64, 1), summary.total_commands);
    try std.testing.expectEqual(@as(u64, 60), summary.total_saved_tokens);
}

test "cleanup old reports" {
    const allocator = std.testing.allocator;
    var store = SavingsStore.init(allocator, std.testing.io);
    defer store.deinit();

    try store.addReport(.{
        .timestamp = time_compat.timestamp(std.testing.io) - 86400 * 10,
        .original_cmd = "old cmd",
        .raw_output_tokens = 10,
        .filtered_output_tokens = 5,
        .saved_tokens = 5,
        .savings_pct = 50.0,
        .exit_code = 0,
        .hostname = "localhost",
    });

    store.cleanup(7);
    try std.testing.expectEqual(@as(usize, 0), store.reportCount());
}
