//! Session management - boundary detection and summaries

const std = @import("std");
const sqlite = @import("sqlite");
const types = @import("types.zig");
const db = @import("db.zig");
const utils = @import("utils.zig");

pub const SessionManager = struct {
    allocator: std.mem.Allocator,
    memory_db: *db.MemoryDb,
    idle_threshold_secs: i64,
    privacy_mode: types.PrivacyMode = .normal,

    pub fn init(allocator: std.mem.Allocator, memory_db: *db.MemoryDb) SessionManager {
        return SessionManager{
            .allocator = allocator,
            .memory_db = memory_db,
            .idle_threshold_secs = 1800, // 30 minutes
            .privacy_mode = .normal,
        };
    }

    pub fn initWithPrivacy(allocator: std.mem.Allocator, memory_db: *db.MemoryDb, privacy_mode: types.PrivacyMode) SessionManager {
        return SessionManager{
            .allocator = allocator,
            .memory_db = memory_db,
            .idle_threshold_secs = 1800, // 30 minutes
            .privacy_mode = privacy_mode,
        };
    }

    pub fn deinit(self: *SessionManager) void {
        _ = self;
    }

    /// Get or create a session ID (persisted across CLI invocations)
    /// In private mode, skips writing to session.json
    pub fn getSessionId(self: *SessionManager) ![]const u8 {
        // In privacy mode, return an in-memory session without persisting
        if (self.privacy_mode == .private) {
            return try self.allocator.dupe(u8, "private-session");
        }

        const state = readSessionFile(self.allocator) catch null;
        defer if (state) |s| {
            self.allocator.free(s.session_id);
            self.allocator.free(s.project);
        };

        const now = std.time.timestamp();

        if (state) |s| {
            if (now - s.last_activity < self.idle_threshold_secs) {
                // Update last_activity and return existing ID
                try writeSessionFile(self.allocator, .{
                    .session_id = s.session_id,
                    .last_activity = now,
                    .project = s.project,
                });
                return try self.allocator.dupe(u8, s.session_id);
            }
        }

        // Create new session
        const project = try utils.detectProject(self.allocator);
        defer self.allocator.free(project);

        const new_id = try utils.generateSessionId(self.allocator);
        errdefer self.allocator.free(new_id);

        try writeSessionFile(self.allocator, .{
            .session_id = new_id,
            .last_activity = now,
            .project = project,
        });

        return new_id;
    }

    /// Start an explicit session
    /// In private mode, skips writing to session.json
    pub fn startSession(self: *SessionManager) ![]const u8 {
        const now = std.time.timestamp();
        const project = try utils.detectProject(self.allocator);
        defer self.allocator.free(project);

        const new_id = try utils.generateSessionId(self.allocator);
        errdefer self.allocator.free(new_id);

        if (self.privacy_mode == .normal) {
            try writeSessionFile(self.allocator, .{
                .session_id = new_id,
                .last_activity = now,
                .project = project,
            });
        }

        return new_id;
    }

    /// End current session and generate summary
    pub fn endSession(self: *SessionManager) !?types.SessionSummary {
        const state = readSessionFile(self.allocator) catch null;
        defer if (state) |s| {
            self.allocator.free(s.session_id);
            self.allocator.free(s.project);
        };

        const session_id = if (state) |s| s.session_id else return null;

        // Generate summary
        const summary = try self.generateSummary(session_id);

        // Delete session file
        const path = try getSessionStatePath(self.allocator);
        defer self.allocator.free(path);
        std.fs.deleteFileAbsolute(path) catch {};

        return summary;
    }

    /// Get current session status
    pub fn getStatus(self: *SessionManager) SessionStatus {
        const state = readSessionFile(self.allocator) catch return .{
            .active = false,
            .session_id = "",
            .idle_secs = 0,
            .expires_in_secs = 0,
        };
        defer if (state) |s| {
            // Don't free session_id - it's referenced by the returned SessionStatus
            self.allocator.free(s.project);
        };

        if (state) |s| {
            const now = std.time.timestamp();
            const idle = now - s.last_activity;
            return SessionStatus{
                .active = idle < self.idle_threshold_secs,
                .session_id = s.session_id,
                .idle_secs = idle,
                .expires_in_secs = @max(0, self.idle_threshold_secs - idle),
            };
        }

        return .{
            .active = false,
            .session_id = "",
            .idle_secs = 0,
            .expires_in_secs = 0,
        };
    }

    fn generateSummary(self: *SessionManager, session_id: []const u8) !?types.SessionSummary {
        const rows = try self.memory_db.getSessionMemories(session_id);
        defer {
            for (rows) |r| {
                self.allocator.free(r.commands);
                self.allocator.free(r.category);
            }
            self.allocator.free(rows);
        }

        if (rows.len == 0) return null;

        // Simple array-based counting for base commands (sessions are small)
        var base_cmds = std.ArrayList([]const u8).empty;
        defer {
            for (base_cmds.items) |c| self.allocator.free(c);
            base_cmds.deinit(self.allocator);
        }
        var base_cmd_counts = std.ArrayList(u32).empty;
        defer base_cmd_counts.deinit(self.allocator);

        // Collect unique categories
        var unique_cats = std.ArrayList([]const u8).empty;
        defer {
            for (unique_cats.items) |c| self.allocator.free(c);
            unique_cats.deinit(self.allocator);
        }

        var success_count: u32 = 0;
        var failure_count: u32 = 0;

        for (rows) |row| {
            // Parse base command from commands JSON ["cmd"]
            const base_cmd = try extractBaseFromCommandsJson(self.allocator, row.commands);
            defer self.allocator.free(base_cmd);

            // Find existing base command
            var found = false;
            for (base_cmds.items, 0..) |cmd, i| {
                if (std.mem.eql(u8, cmd, base_cmd)) {
                    base_cmd_counts.items[i] += 1;
                    found = true;
                    break;
                }
            }
            if (!found) {
                try base_cmds.append(self.allocator, try self.allocator.dupe(u8, base_cmd));
                try base_cmd_counts.append(self.allocator, 1);
            }

            // Track unique categories
            var cat_found = false;
            for (unique_cats.items) |cat| {
                if (std.mem.eql(u8, cat, row.category)) {
                    cat_found = true;
                    break;
                }
            }
            if (!cat_found) {
                try unique_cats.append(self.allocator, try self.allocator.dupe(u8, row.category));
            }

            // Count success/failure
            if (row.exit_code == 0) {
                success_count += 1;
            } else {
                failure_count += 1;
            }
        }

        // Find most common base command
        var task: []const u8 = "mixed";
        var max_count: u32 = 0;
        for (base_cmds.items, 0..) |cmd, i| {
            if (base_cmd_counts.items[i] > max_count) {
                task = cmd;
                max_count = base_cmd_counts.items[i];
            }
        }

        // Build learned string (comma-separated categories)
        var learned_buf = std.ArrayList(u8).empty;
        defer learned_buf.deinit(self.allocator);
        for (unique_cats.items, 0..) |cat, i| {
            if (i > 0) try learned_buf.appendSlice(self.allocator, ", ");
            try learned_buf.appendSlice(self.allocator, cat);
        }

        // Get project
        const project_name = try utils.detectProject(self.allocator);
        defer self.allocator.free(project_name);

        const learned = try learned_buf.toOwnedSlice(self.allocator);
        defer self.allocator.free(learned);

        const completed = try std.fmt.allocPrint(self.allocator, "成功: {d}, 失败: {d}", .{ success_count, failure_count });
        defer self.allocator.free(completed);

        const summary = types.SessionSummary{
            .id = 0,
            .session_id = try self.allocator.dupe(u8, session_id),
            .project = try self.allocator.dupe(u8, project_name),
            .task = try self.allocator.dupe(u8, task),
            .learned = try self.allocator.dupe(u8, learned),
            .completed = try self.allocator.dupe(u8, completed),
            .followups = "",
            .notes = "",
            .command_count = @intCast(rows.len),
            .created_at = std.time.timestamp(),
        };

        // Save to database
        _ = self.memory_db.insertSessionSummary(summary) catch |err| {
            std.debug.print("failed to save session summary: {}\n", .{err});
        };

        return summary;
    }
};

fn extractBaseFromCommandsJson(allocator: std.mem.Allocator, json: []const u8) ![]const u8 {
    const parsed = std.json.parseFromSlice([][]const u8, allocator, json, .{}) catch {
        return try allocator.dupe(u8, "unknown");
    };
    defer parsed.deinit();

    if (parsed.value.len == 0) return try allocator.dupe(u8, "unknown");

    const cmd = parsed.value[0];
    var i: usize = 0;
    while (i < cmd.len and cmd[i] != ' ') : (i += 1) {}
    return try allocator.dupe(u8, cmd[0..i]);
}

pub const SessionStatus = struct {
    active: bool,
    session_id: []const u8,
    idle_secs: i64,
    expires_in_secs: i64,
};

// =========================================================================
// Session State File I/O
// =========================================================================

const SessionState = struct {
    session_id: []const u8,
    last_activity: i64,
    project: []const u8,
};

fn getSessionStatePath(allocator: std.mem.Allocator) ![]const u8 {
    const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch {
        return try std.fmt.allocPrint(allocator, "/tmp/llmlite_session.json", .{});
    };
    defer allocator.free(home_dir);

    const data_dir = try std.fmt.allocPrint(allocator, "{s}/.local/share/llmlite", .{home_dir});
    defer allocator.free(data_dir);

    std.fs.makeDirAbsolute(data_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    return try std.fmt.allocPrint(allocator, "{s}/session.json", .{data_dir});
}

fn readSessionFile(allocator: std.mem.Allocator) !?SessionState {
    const path = try getSessionStatePath(allocator);
    defer allocator.free(path);

    const file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();

    const content = file.readToEndAlloc(allocator, 4096) catch return null;
    defer allocator.free(content);

    const Parsed = struct {
        session_id: []const u8,
        last_activity: i64,
        project: []const u8,
    };

    const parsed = std.json.parseFromSlice(Parsed, allocator, content, .{
        .ignore_unknown_fields = true,
    }) catch return null;
    defer parsed.deinit();

    return SessionState{
        .session_id = try allocator.dupe(u8, parsed.value.session_id),
        .last_activity = parsed.value.last_activity,
        .project = try allocator.dupe(u8, parsed.value.project),
    };
}

fn writeSessionFile(allocator: std.mem.Allocator, state: SessionState) !void {
    const path = try getSessionStatePath(allocator);
    defer allocator.free(path);

    const JsonState = struct {
        session_id: []const u8,
        last_activity: i64,
        project: []const u8,
    };

    const json_bytes = try std.json.Stringify.valueAlloc(allocator, JsonState{
        .session_id = state.session_id,
        .last_activity = state.last_activity,
        .project = state.project,
    }, .{});
    defer allocator.free(json_bytes);

    const file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();
    try file.writeAll(json_bytes);
}
