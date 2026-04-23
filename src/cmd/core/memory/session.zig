//! Session management - boundary detection and summaries

const std = @import("std");
const sqlite = @import("sqlite");
const types = @import("types.zig");
const db = @import("db.zig");
const utils = @import("utils.zig");
const time_compat = @import("time_compat");

pub const SessionManager = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    memory_db: *db.MemoryDb,
    home_dir: []const u8,
    idle_threshold_secs: i64,
    privacy_mode: types.PrivacyMode = .normal,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, memory_db: *db.MemoryDb, home_dir: []const u8) SessionManager {
        return SessionManager{
            .allocator = allocator,
            .io = io,
            .memory_db = memory_db,
            .home_dir = home_dir,
            .idle_threshold_secs = 1800, // 30 minutes
            .privacy_mode = .normal,
        };
    }

    pub fn initWithPrivacy(allocator: std.mem.Allocator, io: std.Io, memory_db: *db.MemoryDb, home_dir: []const u8, privacy_mode: types.PrivacyMode) SessionManager {
        return SessionManager{
            .allocator = allocator,
            .io = io,
            .memory_db = memory_db,
            .home_dir = home_dir,
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

        const state = readSessionFile(self.allocator, self.io, self.home_dir) catch null;
        defer if (state) |s| {
            self.allocator.free(s.session_id);
            self.allocator.free(s.project);
        };

        const now = time_compat.timestamp(self.io);

        if (state) |s| {
            if (now - s.last_activity < self.idle_threshold_secs) {
                // Update last_activity and return existing ID
                try writeSessionFile(self.allocator, self.io, self.home_dir, .{
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

        try writeSessionFile(self.allocator, self.io, self.home_dir, .{
            .session_id = new_id,
            .last_activity = now,
            .project = project,
        });

        return new_id;
    }

    /// Start an explicit session
    /// In private mode, skips writing to session.json
    pub fn startSession(self: *SessionManager) ![]const u8 {
        const now = time_compat.timestamp(self.io);
        const project = try utils.detectProject(self.allocator);
        defer self.allocator.free(project);

        const new_id = try utils.generateSessionId(self.allocator);
        errdefer self.allocator.free(new_id);

        if (self.privacy_mode == .normal) {
            try writeSessionFile(self.allocator, self.io, self.home_dir, .{
                .session_id = new_id,
                .last_activity = now,
                .project = project,
            });
        }

        return new_id;
    }

    /// End current session and generate summary
    pub fn endSession(self: *SessionManager) !?types.SessionSummary {
        const state = readSessionFile(self.allocator, self.io, self.home_dir) catch null;
        defer if (state) |s| {
            self.allocator.free(s.session_id);
            self.allocator.free(s.project);
        };

        const session_id = if (state) |s| s.session_id else return null;

        // Generate summary
        const summary = try self.generateSummary(session_id);

        // Delete session file
        const path = try getSessionStatePath(self.allocator, self.home_dir);
        defer self.allocator.free(path);
        std.Io.Dir.deleteFileAbsolute(self.io, path) catch {};

        return summary;
    }

    /// Get current session status
    pub fn getStatus(self: *SessionManager) SessionStatus {
        const state = readSessionFile(self.allocator, self.io, self.home_dir) catch return .{
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
            const now = time_compat.timestamp(self.io);
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
            .created_at = time_compat.timestamp(self.io),
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

pub const SessionState = struct {
    session_id: []const u8,
    last_activity: i64,
    project: []const u8,
};

/// Pure path construction — returns `{home_dir}/.local/share/llmlite/session.json`.
/// Does not perform any I/O (no directory creation).
pub fn buildSessionStatePath(allocator: std.mem.Allocator, home_dir: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{s}/.local/share/llmlite/session.json", .{home_dir});
}

fn getSessionStatePath(allocator: std.mem.Allocator, home_dir: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{s}/.local/share/llmlite/session.json", .{home_dir});
}

fn ensureDataDir(allocator: std.mem.Allocator, io: std.Io, home_dir: []const u8) !void {
    const data_dir = try std.fmt.allocPrint(allocator, "{s}/.local/share/llmlite", .{home_dir});
    defer allocator.free(data_dir);

    std.Io.Dir.createDirAbsolute(io, data_dir, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

fn readSessionFile(allocator: std.mem.Allocator, io: std.Io, home_dir: []const u8) !?SessionState {
    const path = try getSessionStatePath(allocator, home_dir);
    defer allocator.free(path);

    const file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return null;
    defer file.close(io);

    var read_buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &read_buf);
    const content = file_reader.interface.allocRemaining(allocator, .limited(4096)) catch return null;
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

pub fn writeSessionFile(allocator: std.mem.Allocator, io: std.Io, home_dir: []const u8, state: SessionState) !void {
    try ensureDataDir(allocator, io, home_dir);

    const path = try getSessionStatePath(allocator, home_dir);
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

    const file = try std.Io.Dir.createFileAbsolute(io, path, .{});
    defer file.close(io);
    var write_buf: [4096]u8 = undefined;
    var writer = file.writer(io, &write_buf);
    try writer.interface.writeAll(json_bytes);
    try writer.interface.flush();
}

// ============================================================================
// Property-Based Tests
// ============================================================================

// **Feature: zig-016-upgrade, Property 3: 会话持久化往返一致性**
// Verify any valid SessionState written to session.json then read back
// produces identical deserialized values.
//
// **Validates: Requirements 2.8, 2.9, 3.7**
test "Property 3: session persistence round-trip consistency" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    // Use a deterministic PRNG
    var prng = std.Random.DefaultPrng.init(0xCAFEBABE);
    const random = prng.random();

    const iterations: usize = 100;

    // Use a temp directory as home_dir for testing
    const test_home = "/tmp/__llmlite_session_prop3_test";

    // Ensure the full data directory path exists
    const dirs = [_][]const u8{
        "/tmp/__llmlite_session_prop3_test",
        "/tmp/__llmlite_session_prop3_test/.local",
        "/tmp/__llmlite_session_prop3_test/.local/share",
        "/tmp/__llmlite_session_prop3_test/.local/share/llmlite",
    };
    for (dirs) |d| {
        std.Io.Dir.createDirAbsolute(io, d, .{}) catch {};
    }

    // Clean up session file after test
    defer {
        const path = getSessionStatePath(allocator, test_home) catch null;
        if (path) |p| {
            defer allocator.free(p);
            std.Io.Dir.deleteFileAbsolute(io, p) catch {};
        }
    }

    for (0..iterations) |iter| {
        // Generate random session_id (8-16 alphanumeric chars)
        const id_len = random.intRangeAtMost(usize, 4, 16);
        const id_buf = try allocator.alloc(u8, id_len);
        defer allocator.free(id_buf);
        for (id_buf) |*c| {
            const charset = "abcdefghijklmnopqrstuvwxyz0123456789";
            c.* = charset[random.intRangeLessThan(usize, 0, charset.len)];
        }

        // Generate random last_activity (positive timestamp)
        const last_activity: i64 = random.intRangeAtMost(i64, 1000000, 2000000000);

        // Generate random project name (4-20 alphanumeric chars)
        const proj_len = random.intRangeAtMost(usize, 4, 20);
        const proj_buf = try allocator.alloc(u8, proj_len);
        defer allocator.free(proj_buf);
        for (proj_buf) |*c| {
            const charset = "abcdefghijklmnopqrstuvwxyz0123456789-_";
            c.* = charset[random.intRangeLessThan(usize, 0, charset.len)];
        }

        const original = SessionState{
            .session_id = id_buf,
            .last_activity = last_activity,
            .project = proj_buf,
        };

        // Write
        try writeSessionFile(allocator, io, test_home, original);

        // Read back
        const read_back = try readSessionFile(allocator, io, test_home);
        try std.testing.expect(read_back != null);

        const state = read_back.?;
        defer {
            allocator.free(state.session_id);
            allocator.free(state.project);
        }

        // Verify round-trip consistency
        try std.testing.expectEqualStrings(original.session_id, state.session_id);
        try std.testing.expectEqual(original.last_activity, state.last_activity);
        try std.testing.expectEqualStrings(original.project, state.project);

        _ = iter;
    }
}

// **Feature: zig-016-upgrade, Property 6 (session): session path construction**
// Verify for any valid HOME path, buildSessionStatePath returns `{HOME}/.local/share/llmlite/session.json`.
//
// **Validates: Requirements 4.3, 4.6**
test "Property 6: buildSessionStatePath returns correct path for any valid HOME" {
    const allocator = std.testing.allocator;

    const home_paths = [_][]const u8{
        "/home/user",
        "/root",
        "/home/a",
        "/Users/developer",
        "/tmp",
        "/home/user/with/deep/nesting",
        "/opt/custom-home",
        "/var/lib/service",
    };

    for (home_paths) |home| {
        const path = try buildSessionStatePath(allocator, home);
        defer allocator.free(path);

        const expected = try std.fmt.allocPrint(allocator, "{s}/.local/share/llmlite/session.json", .{home});
        defer allocator.free(expected);

        try std.testing.expectEqualStrings(expected, path);
    }
}
