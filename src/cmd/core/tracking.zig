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
        const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch {
            return Tracker{
                .allocator = allocator,
                .db_path = try std.fmt.allocPrint(allocator, "/tmp/llmlite_history.db", .{}),
            };
        };
        defer allocator.free(home_dir);

        const data_dir = try std.fmt.allocPrint(allocator, "{s}/.local/share/llmlite", .{home_dir});
        defer allocator.free(data_dir);

        std.fs.makeDirAbsolute(data_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

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
        const input_tokens = estimateTokens(record.raw_output);
        const output_tokens = estimateTokens(record.filtered_output);
        const saved_tokens = if (input_tokens > output_tokens) input_tokens - output_tokens else 0;
        const savings_pct = if (input_tokens > 0)
            @as(f64, @floatFromInt(saved_tokens)) / @as(f64, @floatFromInt(input_tokens)) * 100.0
        else
            0.0;

        const entry = try std.fmt.allocPrint(self.allocator, "{d}|{s}|{s}|{d}|{d}|{d}|{d:.2}|{d}\n", .{
            std.time.timestamp(),
            record.original_cmd,
            record.rtk_cmd,
            input_tokens,
            output_tokens,
            saved_tokens,
            savings_pct,
            record.exit_code,
        });
        defer self.allocator.free(entry);

        // Open existing file or create new one
        var file = std.fs.openFileAbsolute(self.db_path, .{ .mode = .write_only }) catch |err| {
            if (err == error.FileNotFound) {
                const new_file = try std.fs.createFileAbsolute(self.db_path, .{});
                defer new_file.close();
                try new_file.writeAll(entry);
                return;
            }
            return err;
        };
        defer file.close();
        try file.seekFromEnd(0);
        try file.writeAll(entry);
    }

    pub fn getStats(self: *Tracker) !TokenStats {
        var stats = TokenStats{
            .total_commands = 0,
            .total_input_tokens = 0,
            .total_output_tokens = 0,
            .total_saved_tokens = 0,
            .avg_savings_pct = 0.0,
        };

        const file = std.fs.openFileAbsolute(self.db_path, .{ .mode = .read_only }) catch |err| {
            if (err == error.FileNotFound) return stats;
            return err;
        };
        defer file.close();

        try file.seekTo(0);

        var buf: [4096]u8 = undefined;
        var file_buffer = std.array_list.Managed(u8).init(self.allocator);
        defer file_buffer.deinit();

        while (true) {
            const bytes_read = try file.read(&buf);
            if (bytes_read == 0) break;
            try file_buffer.appendSlice(buf[0..bytes_read]);
        }

        var line_iter = std.mem.splitScalar(u8, file_buffer.items, '\n');
        while (line_iter.next()) |line| {
            if (line.len == 0) continue;

            var field_iter = std.mem.splitScalar(u8, line, '|');
            _ = field_iter.next();
            _ = field_iter.next();
            _ = field_iter.next();

            const input_toks = std.fmt.parseInt(usize, field_iter.next() orelse continue, 10) catch continue;
            const output_toks = std.fmt.parseInt(usize, field_iter.next() orelse continue, 10) catch continue;
            const saved_toks = std.fmt.parseInt(usize, field_iter.next() orelse continue, 10) catch continue;
            const savings_pct = std.fmt.parseFloat(f64, field_iter.next() orelse continue, 10) catch continue;

            stats.total_commands += 1;
            stats.total_input_tokens += input_toks;
            stats.total_output_tokens += output_toks;
            stats.total_saved_tokens += saved_toks;
            stats.avg_savings_pct += savings_pct;
        }

        if (stats.total_commands > 0) {
            stats.avg_savings_pct /= @as(f64, @floatFromInt(stats.total_commands));
        }

        return stats;
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
