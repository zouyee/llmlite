//! Persistence Layer for llmlite Proxy
//!
//! SQLite-based persistence for keys, teams, projects, and spend entries.
//! Replaces the previous JSON file-based implementation.

const std = @import("std");
const sqlite = @import("sqlite");
const virtual_key = @import("virtual_key");
const team = @import("team");
const cost = @import("cost");
const time_compat = @import("time_compat");

pub const ProxyDbError = error{
    OpenFailed,
    MigrationFailed,
    SqlError,
    ForeignKeyViolation,
    SerializationError,
    NotFound,
};

// =========================================================================
// ProxyDb - Core SQLite database
// =========================================================================

pub const ProxyDb = struct {
    db: sqlite.Database,
    allocator: std.mem.Allocator,
    io: std.Io,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, db_path: []const u8) !ProxyDb {
        const dir = std.fs.path.dirname(db_path) orelse ".";
        try std.Io.Dir.cwd().createDirPath(io, dir);

        const path_z = try allocator.dupeZ(u8, db_path);
        defer allocator.free(path_z);

        const db = sqlite.Database.open(.{
            .path = path_z.ptr,
            .mode = .ReadWrite,
            .create = true,
        }) catch |err| {
            std.log.err("Failed to open database at {s}: {s}", .{ db_path, @errorName(err) });
            return ProxyDbError.OpenFailed;
        };
        errdefer db.close();

        db.exec("PRAGMA journal_mode=WAL", .{}) catch |err| {
            std.log.warn("Failed to enable WAL mode: {s}", .{@errorName(err)});
        };

        db.exec("PRAGMA foreign_keys=ON", .{}) catch |err| {
            std.log.warn("Failed to enable foreign keys: {s}", .{@errorName(err)});
        };

        var self = ProxyDb{
            .db = db,
            .allocator = allocator,
            .io = io,
        };

        try self.runMigrations();

        const current_version = try self.getCurrentVersion();
        std.log.info("ProxyDb initialized at {s}, schema version {d}", .{ db_path, current_version });

        return self;
    }

    pub fn deinit(self: *ProxyDb) void {
        sqlite.Database.close(self.db);
    }

    // =========================================================================
    // Schema Management
    // =========================================================================

    fn runMigrations(self: *ProxyDb) !void {
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
    }

    fn getCurrentVersion(self: *ProxyDb) !u32 {
        const stmt = self.db.prepare(struct {}, struct { version: u32 },
            "SELECT version FROM schema_versions ORDER BY version DESC LIMIT 1") catch return 0;
        defer stmt.finalize();
        if (stmt.step() catch return 0) |row| return row.version;
        return 0;
    }

    fn recordMigration(self: *ProxyDb, version: u32) !void {
        try self.db.exec(
            "INSERT INTO schema_versions (version, applied_at) VALUES (:version, :applied_at)",
            .{ .version = version, .applied_at = time_compat.timestamp(self.io) },
        );
    }

    fn migration001(self: *ProxyDb) !void {
        try self.db.exec(
            \\CREATE TABLE IF NOT EXISTS virtual_keys (
            \\  id TEXT PRIMARY KEY,
            \\  key_hash TEXT NOT NULL,
            \\  user_id TEXT,
            \\  team_id TEXT,
            \\  rate_limit INTEGER,
            \\  allowed_models TEXT,
            \\  allowed_providers TEXT,
            \\  created_at INTEGER NOT NULL,
            \\  expires_at INTEGER,
            \\  spend REAL DEFAULT 0,
            \\  request_count INTEGER DEFAULT 0,
            \\  last_used INTEGER,
            \\  active INTEGER DEFAULT 1
            \\)
        , .{});
        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_vk_user_id ON virtual_keys(user_id)", .{});
        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_vk_team_id ON virtual_keys(team_id)", .{});
        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_vk_active ON virtual_keys(active)", .{});

        try self.db.exec(
            \\CREATE TABLE IF NOT EXISTS teams (
            \\  id TEXT PRIMARY KEY,
            \\  name TEXT NOT NULL,
            \\  created_at INTEGER NOT NULL,
            \\  budget_limit REAL,
            \\  budget_spent REAL DEFAULT 0,
            \\  max_keys INTEGER,
            \\  max_requests_per_minute INTEGER
            \\)
        , .{});

        try self.db.exec(
            \\CREATE TABLE IF NOT EXISTS projects (
            \\  id TEXT PRIMARY KEY,
            \\  team_id TEXT NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
            \\  name TEXT NOT NULL,
            \\  created_at INTEGER NOT NULL,
            \\  budget_limit REAL,
            \\  budget_spent REAL DEFAULT 0,
            \\  allowed_models TEXT,
            \\  allowed_providers TEXT
            \\)
        , .{});
        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_proj_team_id ON projects(team_id)", .{});

        try self.db.exec(
            \\CREATE TABLE IF NOT EXISTS spend_entries (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  timestamp INTEGER NOT NULL,
            \\  key_id TEXT NOT NULL,
            \\  team_id TEXT,
            \\  project_id TEXT,
            \\  provider TEXT NOT NULL,
            \\  model TEXT NOT NULL,
            \\  prompt_tokens INTEGER NOT NULL,
            \\  completion_tokens INTEGER NOT NULL,
            \\  cost REAL NOT NULL
            \\)
        , .{});
        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_spend_timestamp ON spend_entries(timestamp)", .{});
        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_spend_key_id ON spend_entries(key_id)", .{});
        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_spend_team_id ON spend_entries(team_id)", .{});
        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_spend_project_id ON spend_entries(project_id)", .{});
    }

    // =========================================================================
    // JSON Serialization Helpers
    // =========================================================================

    fn stringSliceToJson(self: *ProxyDb, items: ?[][]const u8) ![]const u8 {
        const slice = items orelse return try self.allocator.dupe(u8, "null");
        if (slice.len == 0) return try self.allocator.dupe(u8, "[]");

        var result = std.ArrayList(u8).empty;
        defer result.deinit(self.allocator);

        try result.appendSlice(self.allocator, "[");
        for (slice, 0..) |item, i| {
            if (i > 0) try result.appendSlice(self.allocator, ",");
            try result.appendSlice(self.allocator, "\"");
            for (item) |c| {
                if (c == '"') {
                    try result.appendSlice(self.allocator, "\\\"");
                } else if (c == '\\') {
                    try result.appendSlice(self.allocator, "\\\\");
                } else {
                    try result.append(self.allocator, c);
                }
            }
            try result.appendSlice(self.allocator, "\"");
        }
        try result.appendSlice(self.allocator, "]");

        return try result.toOwnedSlice(self.allocator);
    }

    fn jsonToStringSlice(self: *ProxyDb, json_text: ?[]const u8) !?[][]const u8 {
        const text = json_text orelse return null;
        if (std.mem.eql(u8, text, "null")) return null;

        const trimmed = std.mem.trim(u8, text, " \t\n");
        if (trimmed.len < 2 or trimmed[0] != '[' or trimmed[trimmed.len - 1] != ']') {
            return null;
        }

        const content = trimmed[1 .. trimmed.len - 1];
        if (content.len == 0) return try self.allocator.alloc([]const u8, 0);

        var result = std.ArrayList([]const u8).empty;
        errdefer {
            for (result.items) |s| self.allocator.free(s);
            result.deinit(self.allocator);
        }

        var i: usize = 0;
        while (i < content.len) {
            while (i < content.len and (content[i] == ' ' or content[i] == '\t' or content[i] == ',')) : (i += 1) {}
            if (i >= content.len) break;

            if (content[i] != '"') {
                var end = i;
                while (end < content.len and content[end] != ',') : (end += 1) {}
                const val = std.mem.trim(u8, content[i..end], " \t");
                try result.append(self.allocator, try self.allocator.dupe(u8, val));
                i = end;
            } else {
                i += 1;
                const start = i;
                var escaped = false;
                while (i < content.len) : (i += 1) {
                    if (escaped) {
                        escaped = false;
                    } else if (content[i] == '\\') {
                        escaped = true;
                    } else if (content[i] == '"') {
                        break;
                    }
                }
                const raw = content[start..i];
                var unescaped = std.ArrayList(u8).empty;
                defer unescaped.deinit(self.allocator);
                var j: usize = 0;
                while (j < raw.len) : (j += 1) {
                    if (raw[j] == '\\' and j + 1 < raw.len) {
                        j += 1;
                        switch (raw[j]) {
                            '"' => try unescaped.append(self.allocator, '"'),
                            '\\' => try unescaped.append(self.allocator, '\\'),
                            'n' => try unescaped.append(self.allocator, '\n'),
                            't' => try unescaped.append(self.allocator, '\t'),
                            else => try unescaped.append(self.allocator, raw[j]),
                        }
                    } else {
                        try unescaped.append(self.allocator, raw[j]);
                    }
                }
                try result.append(self.allocator, try unescaped.toOwnedSlice(self.allocator));
                if (i < content.len and content[i] == '"') i += 1;
            }
        }

        return try result.toOwnedSlice(self.allocator);
    }

    // =========================================================================
    // Virtual Keys CRUD
    // =========================================================================

    pub fn insertVirtualKey(self: *ProxyDb, vk: virtual_key.VirtualKey) !void {
        const allowed_models_json = try self.stringSliceToJson(vk.allowed_models);
        defer self.allocator.free(allowed_models_json);

        try self.db.exec(
            \\INSERT INTO virtual_keys
            \\(id, key_hash, user_id, team_id, rate_limit, allowed_models, allowed_providers,
            \\ created_at, expires_at, spend, request_count, last_used, active)
            \\VALUES (:id, :key_hash, :user_id, :team_id, :rate_limit, :allowed_models,
            \\ :allowed_providers, :created_at, :expires_at, :spend, :request_count,
            \\ :last_used, :active)
        , .{
            .id = sqlite.text(vk.id),
            .key_hash = sqlite.text(vk.key_hash),
            .user_id = if (vk.user_id) |v| sqlite.text(v) else null,
            .team_id = if (vk.team_id) |v| sqlite.text(v) else null,
            .rate_limit = vk.rate_limit,
            .allowed_models = sqlite.text(allowed_models_json),
            .allowed_providers = if (vk.allowed_providers) |v| sqlite.text(v) else null,
            .created_at = vk.created_at,
            .expires_at = vk.expires_at,
            .spend = vk.spend,
            .request_count = vk.request_count,
            .last_used = vk.last_used,
            .active = if (vk.active) @as(i64, 1) else @as(i64, 0),
        });
    }

    pub fn getVirtualKey(self: *ProxyDb, id: []const u8) !?virtual_key.VirtualKey {
        const RowType = struct {
            id: sqlite.Text,
            key_hash: sqlite.Text,
            user_id: ?sqlite.Text,
            team_id: ?sqlite.Text,
            rate_limit: ?u32,
            allowed_models: ?sqlite.Text,
            allowed_providers: ?sqlite.Text,
            created_at: i64,
            expires_at: ?i64,
            spend: f64,
            request_count: u64,
            last_used: ?i64,
            active: i64,
        };

        const stmt = self.db.prepare(struct { id: sqlite.Text }, RowType,
            "SELECT * FROM virtual_keys WHERE id = :id") catch return null;
        defer stmt.finalize();
        try stmt.bind(.{ .id = sqlite.text(id) });

        if (try stmt.step()) |row| {
            return try self.rowToVirtualKey(row);
        }
        return null;
    }

    fn rowToVirtualKey(self: *ProxyDb, row: anytype) !virtual_key.VirtualKey {
        const allowed_models = try self.jsonToStringSlice(if (row.allowed_models) |m| m.data else null);
        errdefer if (allowed_models) |m| {
            for (m) |s| self.allocator.free(s);
            self.allocator.free(m);
        };

        return virtual_key.VirtualKey{
            .id = try self.allocator.dupe(u8, row.id.data),
            .key_hash = try self.allocator.dupe(u8, row.key_hash.data),
            .user_id = if (row.user_id) |v| try self.allocator.dupe(u8, v.data) else null,
            .team_id = if (row.team_id) |v| try self.allocator.dupe(u8, v.data) else null,
            .rate_limit = row.rate_limit,
            .allowed_models = allowed_models,
            .allowed_providers = if (row.allowed_providers) |v| try self.allocator.dupe(u8, v.data) else null,
            .created_at = row.created_at,
            .expires_at = row.expires_at,
            .spend = row.spend,
            .request_count = row.request_count,
            .last_used = row.last_used,
            .active = row.active != 0,
        };
    }

    pub fn updateVirtualKeySpend(self: *ProxyDb, id: []const u8, spend_delta: f64) !void {
        try self.db.exec(
            "UPDATE virtual_keys SET spend = spend + :delta, request_count = request_count + 1, last_used = :now WHERE id = :id",
            .{ .delta = spend_delta, .now = time_compat.timestamp(self.io), .id = sqlite.text(id) },
        );
    }

    pub fn deleteVirtualKey(self: *ProxyDb, id: []const u8) !void {
        try self.db.exec("DELETE FROM virtual_keys WHERE id = :id", .{ .id = sqlite.text(id) });
    }

    pub fn loadAllVirtualKeys(self: *ProxyDb) ![]virtual_key.VirtualKey {
        const RowType = struct {
            id: sqlite.Text,
            key_hash: sqlite.Text,
            user_id: ?sqlite.Text,
            team_id: ?sqlite.Text,
            rate_limit: ?u32,
            allowed_models: ?sqlite.Text,
            allowed_providers: ?sqlite.Text,
            created_at: i64,
            expires_at: ?i64,
            spend: f64,
            request_count: u64,
            last_used: ?i64,
            active: i64,
        };

        const stmt = self.db.prepare(struct {}, RowType, "SELECT * FROM virtual_keys") catch return &[_]virtual_key.VirtualKey{};
        defer stmt.finalize();

        var result = std.ArrayList(virtual_key.VirtualKey).empty;
        errdefer {
            for (result.items) |*vk| self.freeVirtualKey(vk);
            result.deinit(self.allocator);
        }

        while (true) {
            const maybe_row = stmt.step() catch break;
            if (maybe_row) |row| {
                const vk = try self.rowToVirtualKey(row);
                try result.append(self.allocator, vk);
            } else break;
        }

        return try result.toOwnedSlice(self.allocator);
    }

    fn freeVirtualKey(self: *ProxyDb, vk: *virtual_key.VirtualKey) void {
        self.allocator.free(vk.id);
        self.allocator.free(vk.key_hash);
        if (vk.user_id) |v| self.allocator.free(v);
        if (vk.team_id) |v| self.allocator.free(v);
        if (vk.allowed_models) |m| {
            for (m) |s| self.allocator.free(s);
            self.allocator.free(m);
        }
        if (vk.allowed_providers) |v| self.allocator.free(v);
    }

    // =========================================================================
    // Teams CRUD
    // =========================================================================

    pub fn insertTeam(self: *ProxyDb, t: team.Team) !void {
        try self.db.exec(
            \\INSERT INTO teams (id, name, created_at, budget_limit, budget_spent, max_keys, max_requests_per_minute)
            \\VALUES (:id, :name, :created_at, :budget_limit, :budget_spent, :max_keys, :max_requests_per_minute)
        , .{
            .id = sqlite.text(t.id),
            .name = sqlite.text(t.name),
            .created_at = t.created_at,
            .budget_limit = t.budget_limit,
            .budget_spent = t.budget_spent,
            .max_keys = t.max_keys,
            .max_requests_per_minute = t.max_requests_per_minute,
        });
    }

    pub fn getTeam(self: *ProxyDb, id: []const u8) !?team.Team {
        const RowType = struct {
            id: sqlite.Text,
            name: sqlite.Text,
            created_at: i64,
            budget_limit: ?f64,
            budget_spent: f64,
            max_keys: ?u32,
            max_requests_per_minute: ?u32,
        };

        const stmt = self.db.prepare(struct { id: sqlite.Text }, RowType,
            "SELECT * FROM teams WHERE id = :id") catch return null;
        defer stmt.finalize();
        try stmt.bind(.{ .id = sqlite.text(id) });

        if (try stmt.step()) |row| {
            return team.Team{
                .id = try self.allocator.dupe(u8, row.id.data),
                .name = try self.allocator.dupe(u8, row.name.data),
                .created_at = row.created_at,
                .budget_limit = row.budget_limit,
                .budget_spent = row.budget_spent,
                .max_keys = row.max_keys,
                .max_requests_per_minute = row.max_requests_per_minute,
                .metadata = null,
            };
        }
        return null;
    }

    pub fn deleteTeam(self: *ProxyDb, id: []const u8) !void {
        try self.db.exec("DELETE FROM teams WHERE id = :id", .{ .id = sqlite.text(id) });
    }

    pub fn updateTeamSpend(self: *ProxyDb, id: []const u8, amount: f64) !void {
        try self.db.exec(
            "UPDATE teams SET budget_spent = budget_spent + :amount WHERE id = :id",
            .{ .amount = amount, .id = sqlite.text(id) },
        );
    }

    pub fn loadAllTeams(self: *ProxyDb) ![]team.Team {
        const RowType = struct {
            id: sqlite.Text,
            name: sqlite.Text,
            created_at: i64,
            budget_limit: ?f64,
            budget_spent: f64,
            max_keys: ?u32,
            max_requests_per_minute: ?u32,
        };

        const stmt = self.db.prepare(struct {}, RowType, "SELECT * FROM teams") catch return &[_]team.Team{};
        defer stmt.finalize();

        var result = std.ArrayList(team.Team).empty;
        errdefer {
            for (result.items) |*t| self.freeTeam(t);
            result.deinit(self.allocator);
        }

        while (true) {
            const maybe_row = stmt.step() catch break;
            if (maybe_row) |row| {
                const t = team.Team{
                    .id = try self.allocator.dupe(u8, row.id.data),
                    .name = try self.allocator.dupe(u8, row.name.data),
                    .created_at = row.created_at,
                    .budget_limit = row.budget_limit,
                    .budget_spent = row.budget_spent,
                    .max_keys = row.max_keys,
                    .max_requests_per_minute = row.max_requests_per_minute,
                    .metadata = null,
                };
                try result.append(self.allocator, t);
            } else break;
        }

        return try result.toOwnedSlice(self.allocator);
    }

    fn freeTeam(self: *ProxyDb, t: *const team.Team) void {
        self.allocator.free(t.id);
        self.allocator.free(t.name);
        if (t.metadata) |md| {
            for (md) |m| self.allocator.free(m);
            self.allocator.free(md);
        }
    }

    // =========================================================================
    // Projects CRUD
    // =========================================================================

    pub fn insertProject(self: *ProxyDb, p: team.Project) !void {
        const allowed_models_json = try self.stringSliceToJson(p.allowed_models);
        defer self.allocator.free(allowed_models_json);

        try self.db.exec(
            \\INSERT INTO projects (id, team_id, name, created_at, budget_limit, budget_spent, allowed_models, allowed_providers)
            \\VALUES (:id, :team_id, :name, :created_at, :budget_limit, :budget_spent, :allowed_models, :allowed_providers)
        , .{
            .id = sqlite.text(p.id),
            .team_id = sqlite.text(p.team_id),
            .name = sqlite.text(p.name),
            .created_at = p.created_at,
            .budget_limit = p.budget_limit,
            .budget_spent = p.budget_spent,
            .allowed_models = sqlite.text(allowed_models_json),
            .allowed_providers = if (p.allowed_providers) |v| sqlite.text(v) else null,
        });
    }

    pub fn getProject(self: *ProxyDb, id: []const u8) !?team.Project {
        const RowType = struct {
            id: sqlite.Text,
            team_id: sqlite.Text,
            name: sqlite.Text,
            created_at: i64,
            budget_limit: ?f64,
            budget_spent: f64,
            allowed_models: ?sqlite.Text,
            allowed_providers: ?sqlite.Text,
        };

        const stmt = self.db.prepare(struct { id: sqlite.Text }, RowType,
            "SELECT * FROM projects WHERE id = :id") catch return null;
        defer stmt.finalize();
        try stmt.bind(.{ .id = sqlite.text(id) });

        if (try stmt.step()) |row| {
            const allowed_models = try self.jsonToStringSlice(if (row.allowed_models) |m| m.data else null);
            errdefer if (allowed_models) |m| {
                for (m) |s| self.allocator.free(s);
                self.allocator.free(m);
            };

            return team.Project{
                .id = try self.allocator.dupe(u8, row.id.data),
                .team_id = try self.allocator.dupe(u8, row.team_id.data),
                .name = try self.allocator.dupe(u8, row.name.data),
                .created_at = row.created_at,
                .budget_limit = row.budget_limit,
                .budget_spent = row.budget_spent,
                .allowed_models = allowed_models,
                .allowed_providers = if (row.allowed_providers) |v| try self.allocator.dupe(u8, v.data) else null,
                .metadata = null,
            };
        }
        return null;
    }

    pub fn deleteProject(self: *ProxyDb, id: []const u8) !void {
        try self.db.exec("DELETE FROM projects WHERE id = :id", .{ .id = sqlite.text(id) });
    }

    pub fn updateProjectSpend(self: *ProxyDb, id: []const u8, amount: f64) !void {
        const TeamIdRow = struct { team_id: sqlite.Text };
        const stmt = self.db.prepare(struct { id: sqlite.Text }, TeamIdRow,
            "SELECT team_id FROM projects WHERE id = :id") catch return;
        defer stmt.finalize();
        try stmt.bind(.{ .id = sqlite.text(id) });

        if (try stmt.step()) |row| {
            const team_id = row.team_id.data;
            try self.db.exec(
                "UPDATE projects SET budget_spent = budget_spent + :amount WHERE id = :id",
                .{ .amount = amount, .id = sqlite.text(id) },
            );
            try self.db.exec(
                "UPDATE teams SET budget_spent = budget_spent + :amount WHERE id = :team_id",
                .{ .amount = amount, .team_id = sqlite.text(team_id) },
            );
        }
    }

    pub fn loadAllProjects(self: *ProxyDb) ![]team.Project {
        const RowType = struct {
            id: sqlite.Text,
            team_id: sqlite.Text,
            name: sqlite.Text,
            created_at: i64,
            budget_limit: ?f64,
            budget_spent: f64,
            allowed_models: ?sqlite.Text,
            allowed_providers: ?sqlite.Text,
        };

        const stmt = self.db.prepare(struct {}, RowType, "SELECT * FROM projects") catch return &[_]team.Project{};
        defer stmt.finalize();

        var result = std.ArrayList(team.Project).empty;
        errdefer {
            for (result.items) |*p| self.freeProject(p);
            result.deinit(self.allocator);
        }

        while (true) {
            const maybe_row = stmt.step() catch break;
            if (maybe_row) |row| {
                const allowed_models = try self.jsonToStringSlice(if (row.allowed_models) |m| m.data else null);
                errdefer if (allowed_models) |m| {
                    for (m) |s| self.allocator.free(s);
                    self.allocator.free(m);
                };

                const p = team.Project{
                    .id = try self.allocator.dupe(u8, row.id.data),
                    .team_id = try self.allocator.dupe(u8, row.team_id.data),
                    .name = try self.allocator.dupe(u8, row.name.data),
                    .created_at = row.created_at,
                    .budget_limit = row.budget_limit,
                    .budget_spent = row.budget_spent,
                    .allowed_models = allowed_models,
                    .allowed_providers = if (row.allowed_providers) |v| try self.allocator.dupe(u8, v.data) else null,
                    .metadata = null,
                };
                try result.append(self.allocator, p);
            } else break;
        }

        return try result.toOwnedSlice(self.allocator);
    }

    fn freeProject(self: *ProxyDb, p: *const team.Project) void {
        self.allocator.free(p.id);
        self.allocator.free(p.team_id);
        self.allocator.free(p.name);
        if (p.allowed_models) |m| {
            for (m) |s| self.allocator.free(s);
            self.allocator.free(m);
        }
        if (p.allowed_providers) |v| self.allocator.free(v);
        if (p.metadata) |md| {
            for (md) |m| self.allocator.free(m);
            self.allocator.free(md);
        }
    }

    // =========================================================================
    // Spend Entries CRUD
    // =========================================================================

    pub fn insertSpendEntry(self: *ProxyDb, entry: cost.SpendEntry) !void {
        try self.db.exec(
            \\INSERT INTO spend_entries
            \\(timestamp, key_id, team_id, project_id, provider, model, prompt_tokens, completion_tokens, cost)
            \\VALUES (:timestamp, :key_id, :team_id, :project_id, :provider, :model, :prompt_tokens, :completion_tokens, :cost)
        , .{
            .timestamp = entry.timestamp,
            .key_id = sqlite.text(entry.key_id),
            .team_id = if (entry.team_id) |v| sqlite.text(v) else null,
            .project_id = if (entry.project_id) |v| sqlite.text(v) else null,
            .provider = sqlite.text(entry.provider),
            .model = sqlite.text(entry.model),
            .prompt_tokens = entry.prompt_tokens,
            .completion_tokens = entry.completion_tokens,
            .cost = entry.cost,
        });
    }

    pub fn getSpendEntriesByKey(self: *ProxyDb, key_id: []const u8, start: i64, end: i64) ![]cost.SpendEntry {
        const RowType = struct {
            id: u64,
            timestamp: i64,
            key_id: sqlite.Text,
            team_id: ?sqlite.Text,
            project_id: ?sqlite.Text,
            provider: sqlite.Text,
            model: sqlite.Text,
            prompt_tokens: u32,
            completion_tokens: u32,
            cost: f64,
        };

        const stmt = self.db.prepare(struct { key_id: sqlite.Text, start: i64, end: i64 }, RowType,
            "SELECT * FROM spend_entries WHERE key_id = :key_id AND timestamp >= :start AND timestamp <= :end ORDER BY timestamp") catch return &[_]cost.SpendEntry{};
        defer stmt.finalize();
        try stmt.bind(.{ .key_id = sqlite.text(key_id), .start = start, .end = end });

        var result = std.ArrayList(cost.SpendEntry).empty;
        errdefer {
            for (result.items) |*e| self.freeSpendEntry(e);
            result.deinit(self.allocator);
        }

        while (true) {
            const maybe_row = stmt.step() catch break;
            if (maybe_row) |row| {
                const e = cost.SpendEntry{
                    .timestamp = row.timestamp,
                    .key_id = try self.allocator.dupe(u8, row.key_id.data),
                    .team_id = if (row.team_id) |v| try self.allocator.dupe(u8, v.data) else null,
                    .project_id = if (row.project_id) |v| try self.allocator.dupe(u8, v.data) else null,
                    .provider = try self.allocator.dupe(u8, row.provider.data),
                    .model = try self.allocator.dupe(u8, row.model.data),
                    .prompt_tokens = row.prompt_tokens,
                    .completion_tokens = row.completion_tokens,
                    .cost = row.cost,
                };
                try result.append(self.allocator, e);
            } else break;
        }

        return try result.toOwnedSlice(self.allocator);
    }

    pub fn getTotalSpendForTeam(self: *ProxyDb, team_id: []const u8) !f64 {
        const RowType = struct { total: ?f64 };
        const stmt = self.db.prepare(struct { team_id: sqlite.Text }, RowType,
            "SELECT SUM(cost) as total FROM spend_entries WHERE team_id = :team_id") catch return 0.0;
        defer stmt.finalize();
        try stmt.bind(.{ .team_id = sqlite.text(team_id) });

        if (try stmt.step()) |row| {
            return row.total orelse 0.0;
        }
        return 0.0;
    }

    pub fn getTotalSpendForKey(self: *ProxyDb, key_id: []const u8) !f64 {
        const RowType = struct { total: ?f64 };
        const stmt = self.db.prepare(struct { key_id: sqlite.Text }, RowType,
            "SELECT SUM(cost) as total FROM spend_entries WHERE key_id = :key_id") catch return 0.0;
        defer stmt.finalize();
        try stmt.bind(.{ .key_id = sqlite.text(key_id) });

        if (try stmt.step()) |row| {
            return row.total orelse 0.0;
        }
        return 0.0;
    }

    pub fn loadAllSpendEntries(self: *ProxyDb) ![]cost.SpendEntry {
        const RowType = struct {
            id: u64,
            timestamp: i64,
            key_id: sqlite.Text,
            team_id: ?sqlite.Text,
            project_id: ?sqlite.Text,
            provider: sqlite.Text,
            model: sqlite.Text,
            prompt_tokens: u32,
            completion_tokens: u32,
            cost: f64,
        };

        const stmt = self.db.prepare(struct {}, RowType, "SELECT * FROM spend_entries") catch return &[_]cost.SpendEntry{};
        defer stmt.finalize();

        var result = std.ArrayList(cost.SpendEntry).empty;
        errdefer {
            for (result.items) |*e| self.freeSpendEntry(e);
            result.deinit(self.allocator);
        }

        while (true) {
            const maybe_row = stmt.step() catch break;
            if (maybe_row) |row| {
                const e = cost.SpendEntry{
                    .timestamp = row.timestamp,
                    .key_id = try self.allocator.dupe(u8, row.key_id.data),
                    .team_id = if (row.team_id) |v| try self.allocator.dupe(u8, v.data) else null,
                    .project_id = if (row.project_id) |v| try self.allocator.dupe(u8, v.data) else null,
                    .provider = try self.allocator.dupe(u8, row.provider.data),
                    .model = try self.allocator.dupe(u8, row.model.data),
                    .prompt_tokens = row.prompt_tokens,
                    .completion_tokens = row.completion_tokens,
                    .cost = row.cost,
                };
                try result.append(self.allocator, e);
            } else break;
        }

        return try result.toOwnedSlice(self.allocator);
    }

    fn freeSpendEntry(self: *ProxyDb, e: *cost.SpendEntry) void {
        self.allocator.free(e.key_id);
        if (e.team_id) |v| self.allocator.free(v);
        if (e.project_id) |v| self.allocator.free(v);
        self.allocator.free(e.provider);
        self.allocator.free(e.model);
    }
};

// =========================================================================
// Persistence - High-level interface
// =========================================================================

pub const Persistence = struct {
    allocator: std.mem.Allocator,
    proxy_db: ProxyDb,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, db_path: []const u8) !Persistence {
        const proxy_db = try ProxyDb.init(allocator, io, db_path);
        return .{
            .allocator = allocator,
            .proxy_db = proxy_db,
        };
    }

    pub fn deinit(self: *Persistence) void {
        self.proxy_db.deinit();
    }

    pub fn loadKeys(self: *Persistence, key_store: *virtual_key.VirtualKeyStore) !void {
        const keys = try self.proxy_db.loadAllVirtualKeys();
        for (keys) |vk| {
            const config = virtual_key.VirtualKeyConfig{
                .user_id = vk.user_id,
                .team_id = vk.team_id,
                .rate_limit = vk.rate_limit,
                .allowed_models = vk.allowed_models,
                .allowed_providers = vk.allowed_providers,
                .expires_at = vk.expires_at,
            };
            try key_store.add(vk.id, config);
            if (key_store.keys.getPtr(vk.id)) |stored| {
                stored.spend = vk.spend;
                stored.request_count = vk.request_count;
                stored.last_used = vk.last_used;
                stored.active = vk.active;
            }
            self.allocator.free(vk.id);
            self.allocator.free(vk.key_hash);
            if (vk.user_id) |v| self.allocator.free(v);
            if (vk.team_id) |v| self.allocator.free(v);
            if (vk.allowed_models) |m| {
                for (m) |s| self.allocator.free(s);
                self.allocator.free(m);
            }
            if (vk.allowed_providers) |v| self.allocator.free(v);
        }
        self.allocator.free(keys);
    }

    pub fn saveKeys(self: *Persistence, key_store: *virtual_key.VirtualKeyStore) !void {
        try self.proxy_db.db.exec("DELETE FROM virtual_keys", .{});

        var it = key_store.keys.iterator();
        while (it.next()) |entry| {
            try self.proxy_db.insertVirtualKey(entry.value_ptr.*);
        }
    }

    pub fn loadTeams(self: *Persistence, team_store: *team.TeamStore) !void {
        const teams = try self.proxy_db.loadAllTeams();
        for (teams) |t| {
            const team_copy = team.Team{
                .id = try team_store.allocator.dupe(u8, t.id),
                .name = try team_store.allocator.dupe(u8, t.name),
                .created_at = t.created_at,
                .budget_limit = t.budget_limit,
                .budget_spent = t.budget_spent,
                .max_keys = t.max_keys,
                .max_requests_per_minute = t.max_requests_per_minute,
                .metadata = null,
            };
            try team_store.teams.put(team_copy.id, team_copy);
            self.allocator.free(t.id);
            self.allocator.free(t.name);
        }
        self.allocator.free(teams);
    }

    pub fn saveTeams(self: *Persistence, team_store: *team.TeamStore) !void {
        try self.proxy_db.db.exec("DELETE FROM teams", .{});

        var it = team_store.teams.iterator();
        while (it.next()) |entry| {
            try self.proxy_db.insertTeam(entry.value_ptr.*);
        }
    }

    pub fn loadProjects(self: *Persistence, team_store: *team.TeamStore) !void {
        const projects = try self.proxy_db.loadAllProjects();
        for (projects) |p| {
            const proj_copy = team.Project{
                .id = try team_store.allocator.dupe(u8, p.id),
                .team_id = try team_store.allocator.dupe(u8, p.team_id),
                .name = try team_store.allocator.dupe(u8, p.name),
                .created_at = p.created_at,
                .budget_limit = p.budget_limit,
                .budget_spent = p.budget_spent,
                .allowed_models = if (p.allowed_models) |models| blk: {
                    const copy = try team_store.allocator.alloc([]const u8, models.len);
                    for (models, 0..) |m, i| copy[i] = try team_store.allocator.dupe(u8, m);
                    break :blk copy;
                } else null,
                .allowed_providers = if (p.allowed_providers) |v| try team_store.allocator.dupe(u8, v) else null,
                .metadata = null,
            };
            try team_store.projects.put(proj_copy.id, proj_copy);
            self.allocator.free(p.id);
            self.allocator.free(p.team_id);
            self.allocator.free(p.name);
            if (p.allowed_models) |m| {
                for (m) |s| self.allocator.free(s);
                self.allocator.free(m);
            }
            if (p.allowed_providers) |v| self.allocator.free(v);
        }
        self.allocator.free(projects);
    }

    pub fn saveProjects(self: *Persistence, team_store: *team.TeamStore) !void {
        try self.proxy_db.db.exec("DELETE FROM projects", .{});

        var it = team_store.projects.iterator();
        while (it.next()) |entry| {
            try self.proxy_db.insertProject(entry.value_ptr.*);
        }
    }

    pub fn loadSpendEntries(self: *Persistence, spend_tracker: *cost.SpendTracker) !void {
        const entries = try self.proxy_db.loadAllSpendEntries();
        for (entries) |e| {
            try spend_tracker.record(e);
            self.allocator.free(e.key_id);
            if (e.team_id) |v| self.allocator.free(v);
            if (e.project_id) |v| self.allocator.free(v);
            self.allocator.free(e.provider);
            self.allocator.free(e.model);
        }
        self.allocator.free(entries);
    }

    pub fn saveSpendEntries(self: *Persistence, spend_tracker: *cost.SpendTracker) !void {
        try self.proxy_db.db.exec("DELETE FROM spend_entries", .{});

        for (spend_tracker.entries.items) |entry| {
            try self.proxy_db.insertSpendEntry(entry);
        }
    }
};

// =========================================================================
// Tests
// =========================================================================

test "ProxyDb init and schema" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const test_path = "/tmp/llmlite_proxy_test.db";

    std.Io.Dir.deleteFileAbsolute(io, test_path) catch {};

    var db = try ProxyDb.init(allocator, io, test_path);
    defer {
        db.deinit();
        std.Io.Dir.deleteFileAbsolute(io, test_path) catch {};
    }

    const version = try db.getCurrentVersion();
    try std.testing.expectEqual(@as(u32, 1), version);
}

test "VirtualKey round-trip" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const test_path = "/tmp/llmlite_proxy_vk_test.db";
    std.Io.Dir.deleteFileAbsolute(io, test_path) catch {};

    var db = try ProxyDb.init(allocator, io, test_path);
    defer {
        db.deinit();
        std.Io.Dir.deleteFileAbsolute(io, test_path) catch {};
    }

    const models = try allocator.alloc([]const u8, 2);
    models[0] = try allocator.dupe(u8, "gpt-4o");
    models[1] = try allocator.dupe(u8, "claude-3");

    const vk = virtual_key.VirtualKey{
        .id = "sk-test123",
        .key_hash = "abc123",
        .user_id = "user1",
        .team_id = "team1",
        .rate_limit = @as(u32, 100),
        .allowed_models = models,
        .allowed_providers = "openai,anthropic",
        .created_at = 1234567890,
        .expires_at = @as(i64, 9999999999),
        .spend = 1.23,
        .request_count = @as(u64, 42),
        .last_used = @as(i64, 1234567900),
        .active = true,
    };

    try db.insertVirtualKey(vk);

    const loaded = try db.getVirtualKey("sk-test123");
    try std.testing.expect(loaded != null);
    var l = loaded.?;
    try std.testing.expectEqualStrings("sk-test123", l.id);
    try std.testing.expectEqualStrings("abc123", l.key_hash);
    try std.testing.expectEqualStrings("user1", l.user_id.?);
    try std.testing.expectEqualStrings("team1", l.team_id.?);
    try std.testing.expectEqual(@as(u32, 100), l.rate_limit.?);
    try std.testing.expectEqualStrings("gpt-4o", l.allowed_models.?[0]);
    try std.testing.expectEqualStrings("claude-3", l.allowed_models.?[1]);
    try std.testing.expectEqualStrings("openai,anthropic", l.allowed_providers.?);
    try std.testing.expectEqual(@as(i64, 1234567890), l.created_at);
    try std.testing.expectEqual(@as(i64, 9999999999), l.expires_at.?);
    try std.testing.expectEqual(@as(f64, 1.23), l.spend);
    try std.testing.expectEqual(@as(u64, 42), l.request_count);
    try std.testing.expectEqual(@as(i64, 1234567900), l.last_used.?);
    try std.testing.expect(l.active);

    db.freeVirtualKey(&l);
}

test "Team round-trip and cascade delete" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const test_path = "/tmp/llmlite_proxy_team_test.db";
    std.Io.Dir.deleteFileAbsolute(io, test_path) catch {};

    var db = try ProxyDb.init(allocator, io, test_path);
    defer {
        db.deinit();
        std.Io.Dir.deleteFileAbsolute(io, test_path) catch {};
    }

    const t = team.Team{
        .id = "team_abc",
        .name = "Test Team",
        .created_at = 1234567890,
        .budget_limit = @as(f64, 1000.0),
        .budget_spent = @as(f64, 50.0),
        .max_keys = @as(u32, 10),
        .max_requests_per_minute = @as(u32, 100),
        .metadata = null,
    };

    try db.insertTeam(t);

    const loaded = try db.getTeam("team_abc");
    try std.testing.expect(loaded != null);
    var l = loaded.?;
    try std.testing.expectEqualStrings("team_abc", l.id);
    try std.testing.expectEqualStrings("Test Team", l.name);
    try std.testing.expectEqual(@as(f64, 1000.0), l.budget_limit.?);
    try std.testing.expectEqual(@as(f64, 50.0), l.budget_spent);
    try std.testing.expectEqual(@as(u32, 10), l.max_keys.?);
    try std.testing.expectEqual(@as(u32, 100), l.max_requests_per_minute.?);

    db.freeTeam(&l);

    const proj_models = try allocator.alloc([]const u8, 1);
    proj_models[0] = try allocator.dupe(u8, "gpt-4o");

    const p = team.Project{
        .id = "proj_123",
        .team_id = "team_abc",
        .name = "Test Project",
        .created_at = 1234567890,
        .budget_limit = @as(f64, 500.0),
        .budget_spent = @as(f64, 25.0),
        .allowed_models = proj_models,
        .allowed_providers = "openai",
        .metadata = null,
    };
    try db.insertProject(p);

    const proj_loaded = try db.getProject("proj_123");
    try std.testing.expect(proj_loaded != null);
    if (proj_loaded) |pl| {
        db.freeProject(&pl);
    }

    try db.deleteTeam("team_abc");
    const proj_after = try db.getProject("proj_123");
    try std.testing.expect(proj_after == null);
}

test "SpendEntry round-trip and aggregation" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const test_path = "/tmp/llmlite_proxy_spend_test.db";
    std.Io.Dir.deleteFileAbsolute(io, test_path) catch {};

    var db = try ProxyDb.init(allocator, io, test_path);
    defer {
        db.deinit();
        std.Io.Dir.deleteFileAbsolute(io, test_path) catch {};
    }

    const entries = [_]cost.SpendEntry{
        .{
            .timestamp = 1000,
            .key_id = "key1",
            .team_id = "team1",
            .project_id = null,
            .provider = "openai",
            .model = "gpt-4o",
            .prompt_tokens = 100,
            .completion_tokens = 50,
            .cost = 0.5,
        },
        .{
            .timestamp = 2000,
            .key_id = "key1",
            .team_id = "team1",
            .project_id = null,
            .provider = "openai",
            .model = "gpt-4o",
            .prompt_tokens = 200,
            .completion_tokens = 100,
            .cost = 1.0,
        },
        .{
            .timestamp = 3000,
            .key_id = "key2",
            .team_id = "team2",
            .project_id = null,
            .provider = "anthropic",
            .model = "claude-3",
            .prompt_tokens = 150,
            .completion_tokens = 75,
            .cost = 0.75,
        },
    };

    for (&entries) |e| {
        try db.insertSpendEntry(e);
    }

    const key1_entries = try db.getSpendEntriesByKey("key1", 500, 2500);
    defer {
        for (key1_entries) |*e| db.freeSpendEntry(e);
        allocator.free(key1_entries);
    }
    try std.testing.expectEqual(@as(usize, 2), key1_entries.len);

    const team1_total = try db.getTotalSpendForTeam("team1");
    try std.testing.expectEqual(@as(f64, 1.5), team1_total);

    const key1_total = try db.getTotalSpendForKey("key1");
    try std.testing.expectEqual(@as(f64, 1.5), key1_total);
}

test "VirtualKey spend accumulation" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const test_path = "/tmp/llmlite_proxy_vk_spend_test.db";
    std.Io.Dir.deleteFileAbsolute(io, test_path) catch {};

    var db = try ProxyDb.init(allocator, io, test_path);
    defer {
        db.deinit();
        std.Io.Dir.deleteFileAbsolute(io, test_path) catch {};
    }

    const vk = virtual_key.VirtualKey{
        .id = "sk-accum",
        .key_hash = "hash1",
        .user_id = null,
        .team_id = null,
        .rate_limit = null,
        .allowed_models = null,
        .allowed_providers = null,
        .created_at = 0,
        .expires_at = null,
        .spend = 0,
        .request_count = 0,
        .last_used = null,
        .active = true,
    };
    try db.insertVirtualKey(vk);

    try db.updateVirtualKeySpend("sk-accum", 1.5);
    try db.updateVirtualKeySpend("sk-accum", 2.5);

    const loaded = try db.getVirtualKey("sk-accum");
    try std.testing.expect(loaded != null);
    var l = loaded.?;
    try std.testing.expectEqual(@as(f64, 4.0), l.spend);
    try std.testing.expectEqual(@as(u64, 2), l.request_count);
    try std.testing.expect(l.last_used != null);

    db.freeVirtualKey(&l);
}

test "Project spend bidirectional propagation" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const test_path = "/tmp/llmlite_proxy_proj_spend_test.db";
    std.Io.Dir.deleteFileAbsolute(io, test_path) catch {};

    var db = try ProxyDb.init(allocator, io, test_path);
    defer {
        db.deinit();
        std.Io.Dir.deleteFileAbsolute(io, test_path) catch {};
    }

    const t = team.Team{
        .id = "team_bp",
        .name = "BP Team",
        .created_at = 0,
        .budget_limit = null,
        .budget_spent = @as(f64, 10.0),
        .max_keys = null,
        .max_requests_per_minute = null,
        .metadata = null,
    };
    try db.insertTeam(t);

    const p = team.Project{
        .id = "proj_bp",
        .team_id = "team_bp",
        .name = "BP Project",
        .created_at = 0,
        .budget_limit = null,
        .budget_spent = @as(f64, 5.0),
        .allowed_models = null,
        .allowed_providers = null,
        .metadata = null,
    };
    try db.insertProject(p);

    try db.updateProjectSpend("proj_bp", 3.0);

    const proj_loaded = try db.getProject("proj_bp");
    try std.testing.expect(proj_loaded != null);
    var pl = proj_loaded.?;
    try std.testing.expectEqual(@as(f64, 8.0), pl.budget_spent);
    db.freeProject(&pl);

    const team_loaded = try db.getTeam("team_bp");
    try std.testing.expect(team_loaded != null);
    var tl = team_loaded.?;
    try std.testing.expectEqual(@as(f64, 13.0), tl.budget_spent);
    db.freeTeam(&tl);
}
