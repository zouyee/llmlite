//! Tracking Handler for llmlite Proxy
//!
//! Handles /tracking/* API endpoints for syncing cmd tracking data

const std = @import("std");
const analytics_types = @import("types");

pub const SyncRequest = analytics_types.SyncRequest;

pub const TrackingHandler = struct {
    allocator: std.mem.Allocator,
    store: *TrackingStore,

    pub fn init(allocator: std.mem.Allocator, store: *TrackingStore) TrackingHandler {
        return .{
            .allocator = allocator,
            .store = store,
        };
    }

    /// Handle tracking request
    pub fn handle(self: *TrackingHandler, request: *std.http.Server.Request) !void {
        const path = request.path();

        if (std.mem.startsWith(u8, path, "POST /tracking/sync")) {
            try self.handleSync(request);
        } else if (std.mem.startsWith(u8, path, "GET /analytics/gain")) {
            try self.handleGain(request);
        } else if (std.mem.startsWith(u8, path, "GET /analytics/team")) {
            try self.handleTeam(request);
        } else if (std.mem.startsWith(u8, path, "GET /analytics/sessions")) {
            try self.handleSessions(request);
        } else {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Not Found\",\"type\":\"invalid_request_error\"}}",
            });
        }
    }

    /// POST /tracking/sync - Receive tracking records from cmd
    fn handleSync(self: *TrackingHandler, request: *std.http.Server.Request) !void {
        const body = try request.reader().readAllAlloc(self.allocator, 10_000_000);
        defer self.allocator.free(body);

        // Parse the sync request
        const parsed = std.json.parseFromSlice(
            analytics_types.SyncRequest,
            self.allocator,
            body,
            .{},
        ) catch {
            try request.respond(.{
                .status = .bad_request,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Invalid request body\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };
        defer parsed.deinit();

        var synced: usize = 0;
        var errors: usize = 0;

        // Store each record
        for (parsed.value.records) |record| {
            self.store.addRecord(record) catch {
                errors += 1;
                continue;
            };
            synced += 1;
        }

        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .synced = synced,
            .errors = errors,
        }, .{});
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    /// GET /analytics/gain - Get token savings statistics
    fn handleGain(self: *TrackingHandler, request: *std.http.Server.Request) !void {
        // Parse query parameters
        const query = try self.parseAnalyticsQuery(request);

        // Get statistics from store
        const stats = self.store.getGainStats(query);

        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .total_saved_tokens = stats.total_saved_tokens,
            .total_requests = stats.total_requests,
            .avg_savings_pct = stats.avg_savings_pct,
            .breakdown = stats.breakdown,
        }, .{});
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    /// GET /analytics/team - Get team-level statistics
    fn handleTeam(self: *TrackingHandler, request: *std.http.Server.Request) !void {
        const query = try self.parseAnalyticsQuery(request);

        const stats = self.store.getTeamStats(query);

        const adoption_rate: f64 = if (stats.total_requests > 0)
            @as(f64, @floatFromInt(stats.total_llmlite_requests)) / @as(f64, @floatFromInt(stats.total_requests)) * 100.0
        else
            0.0;

        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .team_id = query.team_id,
            .total_saved_tokens = stats.total_saved_tokens,
            .total_requests = stats.total_requests,
            .avg_savings_pct = stats.avg_savings_pct,
            .adoption_rate = adoption_rate,
            .users = stats.by_user,
            .daily = stats.by_day,
        }, .{});
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    /// GET /analytics/sessions - Get session overview
    fn handleSessions(self: *TrackingHandler, request: *std.http.Server.Request) !void {
        const query = try self.parseAnalyticsQuery(request);

        const sessions = self.store.getSessionOverview(query);

        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .sessions_scanned = sessions.len,
            .total_commands = self.countTotalCommands(sessions),
            .llmlite_commands = self.countLlmliteCommands(sessions),
            .adoption_rate = self.calculateAdoptionRate(sessions),
            .sessions = sessions,
        }, .{});
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    fn parseAnalyticsQuery(_: *TrackingHandler, _: *std.http.Server.Request) !analytics_types.AnalyticsQuery {
        // For now, return default query
        // TODO: Parse query string parameters
        return analytics_types.AnalyticsQuery{};
    }

    fn countTotalCommands(self: *TrackingHandler, sessions: []analytics_types.SessionSummary) usize {
        _ = self;
        var total: usize = 0;
        for (sessions) |s| total += s.total_cmds;
        return total;
    }

    fn countLlmliteCommands(self: *TrackingHandler, sessions: []analytics_types.SessionSummary) usize {
        _ = self;
        var total: usize = 0;
        for (sessions) |s| total += s.llmlite_cmds;
        return total;
    }

    fn calculateAdoptionRate(self: *TrackingHandler, sessions: []analytics_types.SessionSummary) f64 {
        const total = self.countTotalCommands(sessions);
        if (total == 0) return 0.0;
        const llmlite = self.countLlmliteCommands(sessions);
        return @as(f64, @floatFromInt(llmlite)) / @as(f64, @floatFromInt(total)) * 100.0;
    }
};

// ============================================================================
// In-Memory Tracking Store
// ============================================================================

pub const CommandStats = struct { count: usize, saved: usize };

pub const TrackingStore = struct {
    allocator: std.mem.Allocator,
    records: std.ArrayList(analytics_types.TrackingRecord),
    by_hostname: std.StringArrayHashMap(std.ArrayList(*const analytics_types.TrackingRecord)),
    by_user: std.StringArrayHashMap(std.ArrayList(*const analytics_types.TrackingRecord)),
    by_command: std.StringArrayHashMap(CommandStats),

    pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!TrackingStore {
        return .{
            .allocator = allocator,
            .records = try std.ArrayList(analytics_types.TrackingRecord).initCapacity(allocator, 0),
            .by_hostname = std.StringArrayHashMap(std.ArrayList(*const analytics_types.TrackingRecord)).init(allocator),
            .by_user = std.StringArrayHashMap(std.ArrayList(*const analytics_types.TrackingRecord)).init(allocator),
            .by_command = std.StringArrayHashMap(CommandStats).init(allocator),
        };
    }

    pub fn deinit(self: *TrackingStore) void {
        for (self.records.items) |*record| {
            self.allocator.free(record.original_cmd);
            self.allocator.free(record.rtk_cmd);
            self.allocator.free(record.hostname);
            if (record.user_id) |uid| self.allocator.free(uid);
            if (record.team_id) |tid| self.allocator.free(tid);
        }
        self.records.deinit(self.allocator);

        {
            var it = self.by_hostname.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            self.by_hostname.deinit();
        }

        {
            var it = self.by_user.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            self.by_user.deinit();
        }

        self.by_command.deinit();
    }

    pub fn addRecord(self: *TrackingStore, record: analytics_types.TrackingRecord) !void {
        // Make a copy of the record with owned strings
        const owned = analytics_types.TrackingRecord{
            .timestamp = record.timestamp,
            .original_cmd = try self.allocator.dupe(u8, record.original_cmd),
            .rtk_cmd = try self.allocator.dupe(u8, record.rtk_cmd),
            .raw_output_len = record.raw_output_len,
            .filtered_output_len = record.filtered_output_len,
            .exit_code = record.exit_code,
            .hostname = try self.allocator.dupe(u8, record.hostname),
            .user_id = if (record.user_id) |uid| try self.allocator.dupe(u8, uid) else null,
            .team_id = if (record.team_id) |tid| try self.allocator.dupe(u8, tid) else null,
        };

        try self.records.append(self.allocator, owned);
        const rec_ptr = &self.records.items[self.records.items.len - 1];

        // Index by hostname
        if (self.by_hostname.getPtr(owned.hostname)) |list| {
            try list.append(self.allocator, rec_ptr);
        } else {
            var list = try std.ArrayList(*const analytics_types.TrackingRecord).initCapacity(self.allocator, 0);
            try list.append(self.allocator, rec_ptr);
            try self.by_hostname.put(try self.allocator.dupe(u8, owned.hostname), list);
        }

        // Index by user
        if (owned.user_id) |uid| {
            if (self.by_user.getPtr(uid)) |list| {
                try list.append(self.allocator, rec_ptr);
            } else {
                var list = try std.ArrayList(*const analytics_types.TrackingRecord).initCapacity(self.allocator, 0);
                try list.append(self.allocator, rec_ptr);
                try self.by_user.put(try self.allocator.dupe(u8, uid), list);
            }
        }

        // Index by command (extract base command)
        const base_cmd = extractBaseCommand(owned.original_cmd);
        if (self.by_command.getPtr(base_cmd)) |entry| {
            entry.count += 1;
            const saved = if (owned.raw_output_len > owned.filtered_output_len)
                owned.raw_output_len - owned.filtered_output_len
            else
                0;
            entry.saved += saved;
        } else {
            const saved = if (owned.raw_output_len > owned.filtered_output_len)
                owned.raw_output_len - owned.filtered_output_len
            else
                0;
            try self.by_command.put(try self.allocator.dupe(u8, base_cmd), .{
                .count = 1,
                .saved = saved,
            });
        }
    }

    pub fn getGainStats(self: *TrackingStore, query: analytics_types.AnalyticsQuery) !struct {
        total_saved_tokens: usize,
        total_requests: usize,
        avg_savings_pct: f64,
        breakdown: []analytics_types.CommandStats,
    } {
        _ = query;
        var total_saved: usize = 0;
        var total_raw: usize = 0;
        var total_filtered: usize = 0;

        for (self.records.items) |record| {
            total_raw += record.raw_output_len;
            total_filtered += record.filtered_output_len;
        }

        total_saved = if (total_raw > total_filtered) total_raw - total_filtered else 0;
        const avg_pct: f64 = if (total_raw > 0)
            @as(f64, @floatFromInt(total_saved)) / @as(f64, @floatFromInt(total_raw)) * 100.0
        else
            0.0;

        // Build breakdown by command
        var breakdown = try std.ArrayList(analytics_types.CommandStats).initCapacity(self.allocator, 0);
        var it = self.by_command.iterator();
        while (it.next()) |entry| {
            const avg_cmd_pct: f64 = if (entry.value_ptr.count > 0)
                @as(f64, @floatFromInt(entry.value_ptr.saved)) / @as(f64, @floatFromInt(entry.value_ptr.count * 1000)) * 100.0
            else
                0.0;
            try breakdown.append(self.allocator, .{
                .command = entry.key_ptr.*,
                .count = entry.value_ptr.count,
                .total_saved_tokens = entry.value_ptr.saved,
                .avg_savings_pct = avg_cmd_pct,
            });
        }

        return .{
            .total_saved_tokens = total_saved,
            .total_requests = self.records.items.len,
            .avg_savings_pct = avg_pct,
            .breakdown = try breakdown.toOwnedSlice(self.allocator),
        };
    }

    pub fn getTeamStats(self: *TrackingStore, query: analytics_types.AnalyticsQuery) !struct {
        total_saved_tokens: usize,
        total_requests: usize,
        avg_savings_pct: f64,
        total_llmlite_requests: usize,
        by_user: []analytics_types.UserStats,
        by_day: []analytics_types.DailyStats,
    } {
        _ = query;
        // Calculate totals
        var total_raw: usize = 0;
        var total_filtered: usize = 0;
        var llmlite_count: usize = 0;

        for (self.records.items) |record| {
            total_raw += record.raw_output_len;
            total_filtered += record.filtered_output_len;
            // Simple heuristic: if cmd starts with llmlite, it's llmlite commands
            if (std.mem.startsWith(u8, record.rtk_cmd, "llmlite")) {
                llmlite_count += 1;
            }
        }

        const total_saved = if (total_raw > total_filtered) total_raw - total_filtered else 0;
        const avg_pct: f64 = if (total_raw > 0)
            @as(f64, @floatFromInt(total_saved)) / @as(f64, @floatFromInt(total_raw)) * 100.0
        else
            0.0;

        // Aggregate by user
        var user_map = std.StringArrayHashMap(struct {
            total: usize = 0,
            llmlite: usize = 0,
            saved: usize = 0,
        }).init(self.allocator);
        defer {
            var it = user_map.iterator();
            while (it.next()) |_| {}
            user_map.deinit();
        }

        for (self.records.items) |record| {
            const user_key = record.user_id orelse record.hostname;
            if (user_map.getPtr(user_key)) |entry| {
                entry.total += 1;
                if (std.mem.startsWith(u8, record.rtk_cmd, "llmlite")) entry.llmlite += 1;
                const saved = if (record.raw_output_len > record.filtered_output_len)
                    record.raw_output_len - record.filtered_output_len
                else
                    0;
                entry.saved += saved;
            } else {
                const saved = if (record.raw_output_len > record.filtered_output_len)
                    record.raw_output_len - record.filtered_output_len
                else
                    0;
                try user_map.put(try self.allocator.dupe(u8, user_key), .{
                    .total = 1,
                    .llmlite = if (std.mem.startsWith(u8, record.rtk_cmd, "llmlite")) 1 else 0,
                    .saved = saved,
                });
            }
        }

        var by_user = try std.ArrayList(analytics_types.UserStats).initCapacity(self.allocator, 0);
        var it = user_map.iterator();
        while (it.next()) |entry| {
            const avg_u: f64 = if (entry.value_ptr.total > 0)
                @as(f64, @floatFromInt(entry.value_ptr.saved)) / @as(f64, @floatFromInt(entry.value_ptr.total * 1000)) * 100.0
            else
                0.0;
            try by_user.append(self.allocator, .{
                .user_id = entry.key_ptr.*,
                .hostname = entry.key_ptr.*,
                .total_commands = entry.value_ptr.total,
                .llmlite_commands = entry.value_ptr.llmlite,
                .total_saved_tokens = entry.value_ptr.saved,
                .avg_savings_pct = avg_u,
            });
        }

        return .{
            .total_saved_tokens = total_saved,
            .total_requests = self.records.items.len,
            .avg_savings_pct = avg_pct,
            .total_llmlite_requests = llmlite_count,
            .by_user = try by_user.toOwnedSlice(self.allocator),
            .by_day = &.{},
        };
    }

    pub fn getSessionOverview(self: *TrackingStore, query: analytics_types.AnalyticsQuery) ![]analytics_types.SessionSummary {
        _ = query;
        // Group by hostname and date
        var sessions_map = std.StringArrayHashMap(struct {
            cmds: usize = 0,
            llmlite: usize = 0,
            tokens: usize = 0,
        }).init(self.allocator);
        defer {
            var it = sessions_map.iterator();
            while (it.next()) |_| {}
            sessions_map.deinit();
        }

        for (self.records.items) |record| {
            const date = formatTimestamp(record.timestamp, self.allocator) catch "1970-01-01";
            defer self.allocator.free(date);
            const key = try std.fmt.allocPrint(self.allocator, "{s}_{s}", .{ record.hostname, date });
            defer self.allocator.free(key);

            if (sessions_map.getPtr(key)) |entry| {
                entry.cmds += 1;
                if (std.mem.startsWith(u8, record.rtk_cmd, "llmlite")) entry.llmlite += 1;
                entry.tokens += record.filtered_output_len / 4; // Estimate tokens
            } else {
                try sessions_map.put(key, .{
                    .cmds = 1,
                    .llmlite = if (std.mem.startsWith(u8, record.rtk_cmd, "llmlite")) 1 else 0,
                    .tokens = record.filtered_output_len / 4,
                });
            }
        }

        var sessions = try std.ArrayList(analytics_types.SessionSummary).initCapacity(self.allocator, 0);
        var it = sessions_map.iterator();
        while (it.next()) |entry| {
            // Parse hostname from key (format: hostname_date)
            const last_underscore = std.mem.lastIndexOfScalar(u8, entry.key_ptr.*, '_');
            const hostname = if (last_underscore) |idx| entry.key_ptr.*[0..idx] else entry.key_ptr.*;
            const date = if (last_underscore) |idx| entry.key_ptr.*[idx + 1 ..] else "unknown";

            try sessions.append(self.allocator, .{
                .id = try self.allocator.dupe(u8, entry.key_ptr.*),
                .date = try self.allocator.dupe(u8, date),
                .hostname = try self.allocator.dupe(u8, hostname),
                .total_cmds = entry.value_ptr.cmds,
                .llmlite_cmds = entry.value_ptr.llmlite,
                .output_tokens = entry.value_ptr.tokens,
            });
        }

        return try sessions.toOwnedSlice(self.allocator);
    }
};

fn formatTimestamp(timestamp: i64, allocator: std.mem.Allocator) ![]u8 {
    // Convert Unix timestamp to date string (YYYY-MM-DD)
    // Using simple calendar algorithm
    const days_since_epoch = @divFloor(timestamp, 86400);

    // Calculate year using Zeller-like approximation
    var year: i64 = 1970;
    var remaining_days = days_since_epoch;

    while (remaining_days >= 365) {
        const is_leap = (@mod(year, 4) == 0 and @mod(year, 100) != 0) or (@mod(year, 400) == 0);
        const days_in_year: i64 = if (is_leap) 366 else 365;
        if (remaining_days < days_in_year) break;
        remaining_days -= days_in_year;
        year += 1;
    }

    // Days in each month
    const days_per_month_normal = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    const days_per_month_leap = [_]i64{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

    const is_leap = (@mod(year, 4) == 0 and @mod(year, 100) != 0) or (@mod(year, 400) == 0);
    const days_per_month = if (is_leap) days_per_month_leap else days_per_month_normal;

    var month: i64 = 1;
    for (days_per_month, 0..) |days_in_month, i| {
        if (remaining_days < days_in_month) break;
        remaining_days -= days_in_month;
        month = @intCast(i + 1);
    }

    const day = remaining_days + 1;

    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{ year, month, day });
}

fn extractBaseCommand(cmd: []const u8) []const u8 {
    // Extract the base command (first word) from a command string
    for (cmd, 0..) |c, i| {
        if (c == ' ' or c == '\t') {
            return cmd[0..i];
        }
    }
    return cmd;
}
