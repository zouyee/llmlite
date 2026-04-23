//! Tracking - SQLite-based Token Tracking

const std = @import("std");

var global_tracker: ?*Tracker = null;

pub const TrackingRecord = struct {
    original_cmd: []const u8,
    rtk_cmd: []const u8,
    raw_output: []const u8,
    filtered_output: []const u8,
    exit_code: i32,
};

pub const TokenStats = struct {
    total_commands: usize,
    total_input_tokens: usize,
    total_output_tokens: usize,
    total_saved_tokens: usize,
    avg_savings_pct: f64,
};

pub fn init(allocator: std.mem.Allocator) !void {
    if (global_tracker != null) return;
    const tracker = try allocator.create(Tracker);
    errdefer allocator.destroy(tracker);
    tracker.* = try Tracker.init(allocator);
    global_tracker = tracker;
}

pub fn deinit() void {
    if (global_tracker) |tracker| {
        tracker.deinit();
        tracker.allocator.destroy(tracker);
        global_tracker = null;
    }
}

pub const Tracker = struct {
    allocator: std.mem.Allocator,
    db_path: []const u8,

    pub fn init(allocator: std.mem.Allocator) !Tracker {
        const home_ptr = std.c.getenv("HOME");
        if (home_ptr == null) {
            return Tracker{
                .allocator = allocator,
                .db_path = try allocator.dupe(u8, "/tmp/llmlite_history.db"),
            };
        }
        const home_dir = std.mem.sliceTo(home_ptr.?, 0);

        const data_dir = try std.fmt.allocPrint(allocator, "{s}/.local/share/llmlite", .{home_dir});
        defer allocator.free(data_dir);

        // Use C mkdir to create directory (no io needed)
        const data_dir_z = try allocator.dupeZ(u8, data_dir);
        defer allocator.free(data_dir_z);
        _ = std.c.mkdir(data_dir_z, 0o755);

        const db_path = try std.fmt.allocPrint(allocator, "{s}/history.db", .{data_dir});

        return Tracker{
            .allocator = allocator,
            .db_path = db_path,
        };
    }

    pub fn deinit(self: *Tracker) void {
        self.allocator.free(self.db_path);
    }

    pub fn track(self: *Tracker, record: TrackingRecord) !void {
        _ = self;
        _ = record;
        // Tracking write is a no-op in 0.16.0 migration
        // Full implementation requires io parameter which is not available in this module
    }

    pub fn getStats(self: *Tracker) !TokenStats {
        _ = self;
        return TokenStats{
            .total_commands = 0,
            .total_input_tokens = 0,
            .total_output_tokens = 0,
            .total_saved_tokens = 0,
            .avg_savings_pct = 0.0,
        };
    }
};

pub fn estimateTokens(text: []const u8) usize {
    if (text.len == 0) return 0;
    return @intFromFloat(@ceil(@as(f64, @floatFromInt(text.len)) / 4.0));
}

pub fn track(_: std.mem.Allocator, record: TrackingRecord) !void {
    if (global_tracker) |tracker| {
        try tracker.track(record);
    }
    // Also log for visibility
    const input_tokens = estimateTokens(record.raw_output);
    const output_tokens = estimateTokens(record.filtered_output);
    const saved_tokens = if (input_tokens > output_tokens) input_tokens - output_tokens else 0;
    const savings_pct = if (input_tokens > 0)
        @as(f64, @floatFromInt(saved_tokens)) / @as(f64, @floatFromInt(input_tokens)) * 100.0
    else
        0.0;

    std.log.info("tracked: {s} - {d} tokens in, {d} tokens out, {d:.1}% saved", .{
        record.original_cmd,
        input_tokens,
        output_tokens,
        savings_pct,
    });
}
