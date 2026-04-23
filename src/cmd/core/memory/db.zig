//! Memory Database - SQLite schema, migrations, and connection management

const std = @import("std");
const sqlite = @import("sqlite");
const time_compat = @import("time_compat");
const types = @import("types.zig");

pub const MemoryDb = struct {
    db: sqlite.Database,
    allocator: std.mem.Allocator,
    io: std.Io,
    home_dir: []const u8,
    has_fts5: bool,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, home_dir: []const u8) !MemoryDb {
        const path = try getMemoryDbPath(allocator, io, home_dir);
        defer allocator.free(path);

        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);

        const db = try sqlite.Database.open(.{
            .path = path_z.ptr,
            .mode = .ReadWrite,
            .create = true,
        });
        errdefer db.close();

        var self = MemoryDb{
            .db = db,
            .allocator = allocator,
            .io = io,
            .home_dir = home_dir,
            .has_fts5 = false,
        };

        try self.runMigrations();
        self.has_fts5 = try self.probeFts5();
        return self;
    }

    pub fn deinit(self: *MemoryDb) void {
        self.db.close();
    }

    pub fn getDbPath(allocator: std.mem.Allocator, io: std.Io, home_dir: []const u8) ![]const u8 {
        return getMemoryDbPath(allocator, io, home_dir);
    }

    /// Pure path construction — returns `{home_dir}/.local/share/llmlite/memory.db`.
    /// Does not perform any I/O (no directory creation).
    pub fn buildMemoryDbPath(allocator: std.mem.Allocator, home_dir: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{s}/.local/share/llmlite/memory.db", .{home_dir});
    }

    fn getMemoryDbPath(allocator: std.mem.Allocator, io: std.Io, home_dir: []const u8) ![]const u8 {
        const data_dir = try std.fmt.allocPrint(allocator, "{s}/.local/share/llmlite", .{home_dir});
        defer allocator.free(data_dir);

        std.Io.Dir.createDirAbsolute(io, data_dir, .default_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        return try std.fmt.allocPrint(allocator, "{s}/memory.db", .{data_dir});
    }

    // =========================================================================
    // Migrations
    // =========================================================================

    fn runMigrations(self: *MemoryDb) !void {
        try self.db.exec(
            \\CREATE TABLE IF NOT EXISTS schema_versions (
            \\  version INTEGER PRIMARY KEY,
            \\  applied_at INTEGER NOT NULL
            \\)
        , .{});

        const current_version = try self.getCurrentVersion();

        if (current_version < 1) {
            try self.migration001();
            try self.recordMigration(1);
        }
        if (current_version < 2) {
            try self.migration002();
            try self.recordMigration(2);
        }
    }

    fn getCurrentVersion(self: *MemoryDb) !u32 {
        const stmt = self.db.prepare(struct {}, struct { version: u32 },
            "SELECT version FROM schema_versions ORDER BY version DESC LIMIT 1") catch return 0;
        defer stmt.finalize();
        if (try stmt.step()) |row| return row.version;
        return 0;
    }

    fn recordMigration(self: *MemoryDb, version: u32) !void {
        try self.db.exec(
            "INSERT INTO schema_versions (version, applied_at) VALUES (:version, :applied_at)",
            .{ .version = version, .applied_at = time_compat.timestamp(self.io) },
        );
    }

    fn migration001(self: *MemoryDb) !void {
        try self.db.exec(
            \\CREATE TABLE IF NOT EXISTS memories (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  category TEXT NOT NULL,
            \\  summary TEXT NOT NULL,
            \\  facts TEXT,
            \\  context TEXT,
            \\  tags TEXT,
            \\  commands TEXT,
            \\  project TEXT NOT NULL,
            \\  session_id TEXT NOT NULL,
            \\  created_at INTEGER NOT NULL,
            \\  exit_code INTEGER,
            \\  content_hash TEXT UNIQUE
            \\)
        , .{});

        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_memories_category ON memories(category)", .{});
        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_memories_project ON memories(project)", .{});
        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_memories_created ON memories(created_at)", .{});
        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_memories_session ON memories(session_id)", .{});
        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_memories_hash ON memories(content_hash)", .{});

        try self.db.exec(
            \\CREATE TABLE IF NOT EXISTS session_summaries (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  session_id TEXT UNIQUE NOT NULL,
            \\  project TEXT NOT NULL,
            \\  task TEXT,
            \\  learned TEXT,
            \\  completed TEXT,
            \\  followups TEXT,
            \\  notes TEXT,
            \\  command_count INTEGER DEFAULT 0,
            \\  created_at INTEGER NOT NULL
            \\)
        , .{});

        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_summaries_session ON session_summaries(session_id)", .{});
        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_summaries_project ON session_summaries(project)", .{});
        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_summaries_created ON session_summaries(created_at)", .{});
    }

    fn migration002(self: *MemoryDb) !void {
        if (!try self.probeFts5()) return;

        try self.db.exec(
            \\CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
            \\  summary, context, tags, commands,
            \\  content='memories', content_rowid='id'
            \\)
        , .{});

        try self.db.exec(
            \\CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
            \\  INSERT INTO memories_fts(rowid, summary, context, tags, commands)
            \\  VALUES (new.id, new.summary, new.context, new.tags, new.commands);
            \\END
        , .{});

        try self.db.exec(
            \\CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
            \\  INSERT INTO memories_fts(memories_fts, rowid, summary, context, tags, commands)
            \\  VALUES('delete', old.id, old.summary, old.context, old.tags, old.commands);
            \\END
        , .{});
    }

    fn probeFts5(self: *MemoryDb) !bool {
        self.db.exec("CREATE VIRTUAL TABLE _fts5_probe USING fts5(test_column)", .{}) catch return false;
        self.db.exec("DROP TABLE _fts5_probe", .{}) catch {};
        return true;
    }

    // =========================================================================
    // CRUD Operations
    // =========================================================================

    pub fn insertMemory(self: *MemoryDb, entry: types.MemoryEntry) !u64 {
        const hash_hex = try std.fmt.allocPrint(self.allocator, "{x}", .{&entry.content_hash});
        defer self.allocator.free(hash_hex);

        const facts_json = try self.stringArrayToJson(entry.facts);
        defer self.allocator.free(facts_json);

        const tags_json = try self.stringArrayToJson(entry.tags);
        defer self.allocator.free(tags_json);

        const commands_json = try self.stringArrayToJson(entry.commands);
        defer self.allocator.free(commands_json);

        try self.db.exec(
            \\INSERT INTO memories
            \\(category, summary, facts, context, tags, commands, project, session_id, created_at, exit_code, content_hash)
            \\VALUES (:category, :summary, :facts, :context, :tags, :commands, :project, :session_id, :created_at, :exit_code, :content_hash)
        , .{
            .category = sqlite.text(entry.category.asString()),
            .summary = sqlite.text(entry.summary),
            .facts = sqlite.text(facts_json),
            .context = sqlite.text(entry.context),
            .tags = sqlite.text(tags_json),
            .commands = sqlite.text(commands_json),
            .project = sqlite.text(entry.project),
            .session_id = sqlite.text(entry.session_id),
            .created_at = entry.created_at,
            .exit_code = entry.exit_code,
            .content_hash = sqlite.text(hash_hex),
        });

        // Return last insert rowid
        const RowId = struct { id: u64 };
        const id_stmt = self.db.prepare(struct {}, RowId, "SELECT last_insert_rowid() as id") catch return error.SqlError;
        defer id_stmt.finalize();
        if (try id_stmt.step()) |row| return row.id;
        return error.SqlError;
    }

    pub fn getMemoryById(self: *MemoryDb, id: u64) !?types.MemoryEntry {
        const RowType = struct {
            id: u64,
            category: sqlite.Text,
            summary: sqlite.Text,
            facts: ?sqlite.Text,
            context: ?sqlite.Text,
            tags: ?sqlite.Text,
            commands: ?sqlite.Text,
            project: sqlite.Text,
            session_id: sqlite.Text,
            created_at: i64,
            exit_code: ?i32,
            content_hash: ?sqlite.Text,
        };

        const stmt = self.db.prepare(struct { id: u64 }, RowType, "SELECT * FROM memories WHERE id = :id") catch return null;
        defer stmt.finalize();
        try stmt.bind(.{ .id = id });

        if (try stmt.step()) |row| {
            return try self.rowToMemoryEntry(row);
        }
        return null;
    }

    pub fn findDuplicate(self: *MemoryDb, hash: [32]u8, window_secs: i64) !?u64 {
        const cutoff = time_compat.timestamp(self.io) - window_secs;
        const hash_hex = try std.fmt.allocPrint(self.allocator, "{x}", .{&hash});
        defer self.allocator.free(hash_hex);

        const RowType = struct { id: u64 };
        const stmt = self.db.prepare(struct { content_hash: sqlite.Text, created_at: i64 }, RowType,
            "SELECT id FROM memories WHERE content_hash = :content_hash AND created_at > :created_at LIMIT 1") catch return null;
        defer stmt.finalize();
        try stmt.bind(.{ .content_hash = sqlite.text(hash_hex), .created_at = cutoff });

        if (try stmt.step()) |row| return row.id;
        return null;
    }

    pub fn hasDuplicateHash(self: *MemoryDb, hash: [32]u8) !bool {
        const hash_hex = try std.fmt.allocPrint(self.allocator, "{x}", .{&hash});
        defer self.allocator.free(hash_hex);

        const RowType = struct { id: u64 };
        const stmt = self.db.prepare(struct { content_hash: sqlite.Text }, RowType,
            "SELECT id FROM memories WHERE content_hash = :content_hash LIMIT 1") catch return false;
        defer stmt.finalize();
        try stmt.bind(.{ .content_hash = sqlite.text(hash_hex) });

        return (try stmt.step()) != null;
    }

    pub fn deleteMemory(self: *MemoryDb, id: u64) !void {
        try self.db.exec("DELETE FROM memories WHERE id = :id", .{ .id = id });
    }

    pub fn pruneOldMemories(self: *MemoryDb, before_timestamp: i64) !u32 {
        const RowType = struct { count: u32 };
        const stmt = self.db.prepare(struct { created_at: i64 }, RowType,
            "DELETE FROM memories WHERE created_at < :created_at RETURNING COUNT(*) as count") catch return 0;
        defer stmt.finalize();
        try stmt.bind(.{ .created_at = before_timestamp });

        if (try stmt.step()) |row| return row.count;
        return 0;
    }

    pub fn getMemoryCount(self: *MemoryDb) !u64 {
        const RowType = struct { count: u64 };
        const stmt = self.db.prepare(struct {}, RowType, "SELECT COUNT(*) as count FROM memories") catch return 0;
        defer stmt.finalize();
        if (try stmt.step()) |row| return row.count;
        return 0;
    }

    pub fn getStatsByProject(self: *MemoryDb, project: ?[]const u8) !ProjectStats {
        const RowType = struct { category: sqlite.Text, count: u64 };

        if (project) |p| {
            const stmt = self.db.prepare(struct { project: sqlite.Text }, RowType,
                "SELECT category, COUNT(*) as count FROM memories WHERE project = :project GROUP BY category") catch return ProjectStats{};
            defer stmt.finalize();
            try stmt.bind(.{ .project = sqlite.text(p) });
            return try self.collectStats(stmt);
        } else {
            const stmt = self.db.prepare(struct {}, RowType,
                "SELECT category, COUNT(*) as count FROM memories GROUP BY category") catch return ProjectStats{};
            defer stmt.finalize();
            return try self.collectStats(stmt);
        }
    }

    fn collectStats(self: *MemoryDb, stmt: anytype) !ProjectStats {
        var stats = ProjectStats{};
        while (try stmt.step()) |row| {
            const cat = types.MemoryCategory.fromString(row.category.data);
            switch (cat) {
                .fix => stats.fix_count = row.count,
                .feat => stats.feat_count = row.count,
                .learn => stats.learn_count = row.count,
                .mistake => stats.mistake_count = row.count,
                .pattern => stats.pattern_count = row.count,
                else => {},
            }
            stats.total_count += row.count;
        }
        _ = self;
        return stats;
    }

    pub fn insertSessionSummary(self: *MemoryDb, summary: types.SessionSummary) !u64 {
        try self.db.exec(
            \\INSERT INTO session_summaries
            \\(session_id, project, task, learned, completed, followups, notes, command_count, created_at)
            \\VALUES (:session_id, :project, :task, :learned, :completed, :followups, :notes, :command_count, :created_at)
        , .{
            .session_id = sqlite.text(summary.session_id),
            .project = sqlite.text(summary.project),
            .task = sqlite.text(summary.task),
            .learned = sqlite.text(summary.learned),
            .completed = sqlite.text(summary.completed),
            .followups = sqlite.text(summary.followups),
            .notes = sqlite.text(summary.notes),
            .command_count = summary.command_count,
            .created_at = summary.created_at,
        });

        // Return last insert rowid
        const RowId = struct { id: u64 };
        const id_stmt = self.db.prepare(struct {}, RowId, "SELECT last_insert_rowid() as id") catch return error.SqlError;
        defer id_stmt.finalize();
        if (try id_stmt.step()) |row| return row.id;
        return error.SqlError;
    }

    pub fn getSessionMemories(self: *MemoryDb, session_id: []const u8) ![]SessionMemoryRow {
        const RowType = struct {
            commands: sqlite.Text,
            category: sqlite.Text,
            exit_code: i32,
        };
        const stmt = self.db.prepare(
            struct { session_id: sqlite.Text },
            RowType,
            "SELECT commands, category, exit_code FROM memories WHERE session_id = :session_id") catch return &[_]SessionMemoryRow{};
        defer stmt.finalize();
        try stmt.bind(.{ .session_id = sqlite.text(session_id) });

        var results = std.ArrayList(SessionMemoryRow).empty;
        errdefer results.deinit(self.allocator);

        while (try stmt.step()) |row| {
            try results.append(self.allocator, SessionMemoryRow{
                .commands = try self.allocator.dupe(u8, row.commands.data),
                .category = try self.allocator.dupe(u8, row.category.data),
                .exit_code = row.exit_code,
            });
        }

        return results.toOwnedSlice(self.allocator);
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    fn stringArrayToJson(self: *MemoryDb, items: [][]const u8) ![]const u8 {
        if (items.len == 0) return try self.allocator.dupe(u8, "[]");

        var result = std.ArrayList(u8).empty;
        defer result.deinit(self.allocator);

        try result.appendSlice(self.allocator, "[");
        for (items, 0..) |item, i| {
            if (i > 0) try result.appendSlice(self.allocator, ",");
            try result.appendSlice(self.allocator, "\"");
            for (item) |c| {
                if (c == '"') {
                    try result.appendSlice(self.allocator, "\\\"");
                } else {
                    try result.append(self.allocator, c);
                }
            }
            try result.appendSlice(self.allocator, "\"");
        }
        try result.appendSlice(self.allocator, "]");

        return result.toOwnedSlice(self.allocator);
    }

    fn rowToMemoryEntry(self: *MemoryDb, row: anytype) !types.MemoryEntry {
        var hash: [32]u8 = undefined;
        if (row.content_hash) |h| {
            _ = std.fmt.hexToBytes(&hash, h.data) catch {
                @memset(&hash, 0);
            };
        } else {
            @memset(&hash, 0);
        }

        return types.MemoryEntry{
            .id = row.id,
            .category = types.MemoryCategory.fromString(row.category.data),
            .summary = try self.allocator.dupe(u8, row.summary.data),
            .facts = try self.jsonToStringArray(row.facts orelse sqlite.text("[]")),
            .context = if (row.context) |c| try self.allocator.dupe(u8, c.data) else "",
            .tags = try self.jsonToStringArray(row.tags orelse sqlite.text("[]")),
            .commands = try self.jsonToStringArray(row.commands orelse sqlite.text("[]")),
            .project = try self.allocator.dupe(u8, row.project.data),
            .session_id = try self.allocator.dupe(u8, row.session_id.data),
            .created_at = row.created_at,
            .exit_code = row.exit_code orelse 0,
            .content_hash = hash,
        };
    }

    fn jsonToStringArray(self: *MemoryDb, json: sqlite.Text) ![][]const u8 {
        const data = json.data;
        var result = std.ArrayList([]const u8).empty;
        errdefer {
            for (result.items) |s| self.allocator.free(s);
            result.deinit(self.allocator);
        }

        const trimmed = std.mem.trim(u8, data, " \t\n");
        if (trimmed.len < 2 or trimmed[0] != '[' or trimmed[trimmed.len - 1] != ']') {
            return result.toOwnedSlice(self.allocator);
        }

        const content = trimmed[1 .. trimmed.len - 1];
        if (content.len == 0) return result.toOwnedSlice(self.allocator);

        var i: usize = 0;
        while (i < content.len) {
            while (i < content.len and (content[i] == ' ' or content[i] == '\t' or content[i] == ',')) : (i += 1) {}
            if (i >= content.len) break;

            if (content[i] == '"') {
                i += 1;
                const start = i;
                while (i < content.len and content[i] != '"') : (i += 1) {}
                const str = try self.allocator.dupe(u8, content[start..i]);
                try result.append(self.allocator, str);
                if (i < content.len) i += 1;
            } else {
                const start = i;
                while (i < content.len and content[i] != ',') : (i += 1) {}
                const str = try self.allocator.dupe(u8, std.mem.trim(u8, content[start..i], " \t"));
                try result.append(self.allocator, str);
            }
        }

        return result.toOwnedSlice(self.allocator);
    }
};

pub const ProjectStats = struct {
    total_count: u64 = 0,
    fix_count: u64 = 0,
    feat_count: u64 = 0,
    learn_count: u64 = 0,
    mistake_count: u64 = 0,
    pattern_count: u64 = 0,
};

pub const SessionMemoryRow = struct {
    commands: []const u8,
    category: []const u8,
    exit_code: i32,
};

// ============================================================================
// Property-Based Tests
// ============================================================================

// **Feature: zig-016-upgrade, Property 6: 路径构造正确性**
// Verify for any valid HOME path, getMemoryDbPath returns `{HOME}/.local/share/llmlite/memory.db`.
//
// **Validates: Requirements 4.1, 4.2, 4.3, 4.5, 4.6**
test "Property 6: getMemoryDbPath returns correct path for any valid HOME" {
    const allocator = std.testing.allocator;

    // Test with a variety of HOME path patterns
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
        const path = try MemoryDb.buildMemoryDbPath(allocator, home);
        defer allocator.free(path);

        const expected = try std.fmt.allocPrint(allocator, "{s}/.local/share/llmlite/memory.db", .{home});
        defer allocator.free(expected);

        try std.testing.expectEqualStrings(expected, path);
    }
}
