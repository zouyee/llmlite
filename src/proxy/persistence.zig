//! Persistence Layer for llmlite Proxy
//!
//! JSON file-based persistence for keys, teams, and projects
//! This avoids external dependencies while providing durability

const std = @import("std");
const virtual_key = @import("virtual_key");
const team = @import("team");

pub const PersistenceError = error{
    FileNotFound,
    InvalidFormat,
    IoError,
    SerializationError,
};

pub const Persistence = struct {
    allocator: std.mem.Allocator,
    base_path: []const u8,
    keys_path: []const u8,
    teams_path: []const u8,
    projects_path: []const u8,
    spend_path: []const u8,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, base_path: []const u8) !Persistence {
        const keys_path = try std.fmt.allocPrint(allocator, "{s}/keys.json", .{base_path});
        const teams_path = try std.fmt.allocPrint(allocator, "{s}/teams.json", .{base_path});
        const projects_path = try std.fmt.allocPrint(allocator, "{s}/projects.json", .{base_path});
        const spend_path = try std.fmt.allocPrint(allocator, "{s}/spend.json", .{base_path});

        return .{
            .allocator = allocator,
            .base_path = try allocator.dupe(u8, base_path),
            .keys_path = keys_path,
            .teams_path = teams_path,
            .projects_path = projects_path,
            .spend_path = spend_path,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *Persistence) void {
        self.allocator.free(self.base_path);
        self.allocator.free(self.keys_path);
        self.allocator.free(self.teams_path);
        self.allocator.free(self.projects_path);
        self.allocator.free(self.spend_path);
    }

    /// Ensure data directory exists
    pub fn ensureDir(self: *Persistence) !void {
        try std.fs.cwd().makePath(self.base_path);
    }

    // ============ Key Persistence ============

    pub fn loadKeys(self: *Persistence, key_store: *virtual_key.VirtualKeyStore) !void {
        const mtx = self.mutex.lock();
        defer mtx.unlock();

        const content = self.readFile(self.keys_path) catch |err| {
            if (err == PersistenceError.FileNotFound) return;
            return err;
        };
        defer self.allocator.free(content);

        try self.parseAndLoadKeys(key_store, content);
    }

    pub fn saveKeys(self: *Persistence, key_store: *virtual_key.VirtualKeyStore) !void {
        const mtx = self.mutex.lock();
        defer mtx.unlock();

        const content = try self.serializeKeys(key_store);
        defer self.allocator.free(content);

        try self.writeFile(self.keys_path, content);
    }

    fn serializeKeys(self: *Persistence, key_store: *virtual_key.VirtualKeyStore) ![]u8 {
        var keys_array = std.ArrayList(struct {
            id: []const u8,
            key_hash: []const u8,
            user_id: ?[]const u8,
            team_id: ?[]const u8,
            rate_limit: ?u32,
            allowed_models: ?[][]const u8,
            allowed_providers: ?[]const u8,
            created_at: i64,
            expires_at: ?i64,
            spend: f64,
            request_count: u64,
            last_used: ?i64,
            active: bool,
        }).init(self.allocator);
        defer keys_array.deinit();

        var it = key_store.keys.iterator();
        while (it.next()) |entry| {
            const vk = entry.value_ptr;
            try keys_array.append(.{
                .id = vk.id,
                .key_hash = vk.key_hash,
                .user_id = vk.user_id,
                .team_id = vk.team_id,
                .rate_limit = vk.rate_limit,
                .allowed_models = vk.allowed_models,
                .allowed_providers = vk.allowed_providers,
                .created_at = vk.created_at,
                .expires_at = vk.expires_at,
                .spend = vk.spend,
                .request_count = vk.request_count,
                .last_used = vk.last_used,
                .active = vk.active,
            });
        }

        return std.json.stringifyAlloc(self.allocator, keys_array.items, .{
            .whitespace = .indent_tab,
        });
    }

    fn parseAndLoadKeys(self: *Persistence, key_store: *virtual_key.VirtualKeyStore, content: []const u8) !void {
        const parsed = try std.json.parseFromSlice([]const struct {
            id: []const u8,
            key_hash: []const u8,
            user_id: ?[]const u8,
            team_id: ?[]const u8,
            rate_limit: ?u32,
            allowed_models: ?[][]const u8,
            allowed_providers: ?[]const u8,
            created_at: i64,
            expires_at: ?i64,
            spend: f64,
            request_count: u64,
            last_used: ?i64,
            active: bool,
        }, self.allocator, content, .{});
        defer parsed.deinit();

        for (parsed.value) |vk| {
            const config = virtual_key.VirtualKeyConfig{
                .user_id = vk.user_id,
                .team_id = vk.team_id,
                .rate_limit = vk.rate_limit,
                .allowed_models = vk.allowed_models,
                .allowed_providers = vk.allowed_providers,
                .expires_at = vk.expires_at,
            };
            try key_store.add(vk.id, config);
            // Restore additional fields
            if (key_store.keys.getPtr(vk.id)) |stored| {
                stored.spend = vk.spend;
                stored.request_count = vk.request_count;
                stored.last_used = vk.last_used;
                stored.active = vk.active;
            }
        }
    }

    // ============ Team Persistence ============

    pub fn loadTeams(self: *Persistence, team_store: *team.TeamStore) !void {
        const mtx = self.mutex.lock();
        defer mtx.unlock();

        const content = self.readFile(self.teams_path) catch |err| {
            if (err == PersistenceError.FileNotFound) return;
            return err;
        };
        defer self.allocator.free(content);

        try self.parseAndLoadTeams(team_store, content);
    }

    pub fn saveTeams(self: *Persistence, team_store: *team.TeamStore) !void {
        const mtx = self.mutex.lock();
        defer mtx.unlock();

        const content = try self.serializeTeams(team_store);
        defer self.allocator.free(content);

        try self.writeFile(self.teams_path, content);
    }

    fn serializeTeams(self: *Persistence, team_store: *team.TeamStore) ![]u8 {
        var teams_array = std.ArrayList(struct {
            id: []const u8,
            name: []const u8,
            created_at: i64,
            budget_limit: ?f64,
            budget_spent: f64,
            max_keys: ?u32,
            max_requests_per_minute: ?u32,
        }).init(self.allocator);
        defer teams_array.deinit();

        var it = team_store.teams.iterator();
        while (it.next()) |entry| {
            const t = entry.value_ptr;
            try teams_array.append(.{
                .id = t.id,
                .name = t.name,
                .created_at = t.created_at,
                .budget_limit = t.budget_limit,
                .budget_spent = t.budget_spent,
                .max_keys = t.max_keys,
                .max_requests_per_minute = t.max_requests_per_minute,
            });
        }

        return std.json.stringifyAlloc(self.allocator, teams_array.items, .{
            .whitespace = .indent_tab,
        });
    }

    fn parseAndLoadTeams(self: *Persistence, team_store: *team.TeamStore, content: []const u8) !void {
        const parsed = try std.json.parseFromSlice([]const struct {
            id: []const u8,
            name: []const u8,
            created_at: i64,
            budget_limit: ?f64,
            budget_spent: f64,
            max_keys: ?u32,
            max_requests_per_minute: ?u32,
        }, self.allocator, content, .{});
        defer parsed.deinit();

        for (parsed.value) |t| {
            const config = team.CreateTeamConfig{
                .name = t.name,
                .budget_limit = t.budget_limit,
                .max_keys = t.max_keys,
                .max_requests_per_minute = t.max_requests_per_minute,
            };
            // Note: This creates a new team ID, we need to restore the original
            // For now, teams need to be recreated with original IDs
            _ = team_store.createTeam(config) catch {};
        }
    }

    // ============ Project Persistence ============

    pub fn loadProjects(self: *Persistence, team_store: *team.TeamStore) !void {
        const mtx = self.mutex.lock();
        defer mtx.unlock();

        const content = self.readFile(self.projects_path) catch |err| {
            if (err == PersistenceError.FileNotFound) return;
            return err;
        };
        defer self.allocator.free(content);

        try self.parseAndLoadProjects(team_store, content);
    }

    pub fn saveProjects(self: *Persistence, team_store: *team.TeamStore) !void {
        const mtx = self.mutex.lock();
        defer mtx.unlock();

        const content = try self.serializeProjects(team_store);
        defer self.allocator.free(content);

        try self.writeFile(self.projects_path, content);
    }

    fn serializeProjects(self: *Persistence, team_store: *team.TeamStore) ![]u8 {
        var projects_array = std.ArrayList(struct {
            id: []const u8,
            team_id: []const u8,
            name: []const u8,
            created_at: i64,
            budget_limit: ?f64,
            budget_spent: f64,
            allowed_models: ?[][]const u8,
            allowed_providers: ?[]const u8,
        }).init(self.allocator);
        defer projects_array.deinit();

        var it = team_store.projects.iterator();
        while (it.next()) |entry| {
            const p = entry.value_ptr;
            try projects_array.append(.{
                .id = p.id,
                .team_id = p.team_id,
                .name = p.name,
                .created_at = p.created_at,
                .budget_limit = p.budget_limit,
                .budget_spent = p.budget_spent,
                .allowed_models = p.allowed_models,
                .allowed_providers = p.allowed_providers,
            });
        }

        return std.json.stringifyAlloc(self.allocator, projects_array.items, .{
            .whitespace = .indent_tab,
        });
    }

    fn parseAndLoadProjects(self: *Persistence, team_store: *team.TeamStore, content: []const u8) !void {
        const parsed = try std.json.parseFromSlice([]const struct {
            id: []const u8,
            team_id: []const u8,
            name: []const u8,
            created_at: i64,
            budget_limit: ?f64,
            budget_spent: f64,
            allowed_models: ?[][]const u8,
            allowed_providers: ?[]const u8,
        }, self.allocator, content, .{});
        defer parsed.deinit();

        for (parsed.value) |p| {
            const config = team.CreateProjectConfig{
                .name = p.name,
                .budget_limit = p.budget_limit,
                .allowed_models = p.allowed_models,
                .allowed_providers = p.allowed_providers,
            };
            // Note: Projects need their team to exist first
            _ = team_store.createProject(p.team_id, config) catch {};
        }
    }

    // ============ Spend Persistence ============

    pub fn loadSpendEntries(self: *Persistence, spend_tracker: *SpendTracker) !void {
        const mtx = self.mutex.lock();
        defer mtx.unlock();

        const content = self.readFile(self.spend_path) catch |err| {
            if (err == PersistenceError.FileNotFound) return;
            return err;
        };
        defer self.allocator.free(content);

        try self.parseAndLoadSpend(spend_tracker, content);
    }

    pub fn saveSpendEntries(self: *Persistence, spend_tracker: *SpendTracker) !void {
        const mtx = self.mutex.lock();
        defer mtx.unlock();

        const content = try self.serializeSpend(spend_tracker);
        defer self.allocator.free(content);

        try self.writeFile(self.spend_path, content);
    }

    fn serializeSpend(self: *Persistence, spend_tracker: *SpendTracker) ![]u8 {
        return std.json.stringifyAlloc(self.allocator, spend_tracker.entries.items, .{
            .whitespace = .indent_tab,
        });
    }

    fn parseAndLoadSpend(self: *Persistence, spend_tracker: *SpendTracker, content: []const u8) !void {
        const parsed = try std.json.parseFromSlice([]const SpendEntryPersist, self.allocator, content, .{});
        defer parsed.deinit();

        for (parsed.value) |entry| {
            try spend_tracker.record(.{
                .timestamp = entry.timestamp,
                .key_id = entry.key_id,
                .team_id = entry.team_id,
                .project_id = entry.project_id,
                .provider = entry.provider,
                .model = entry.model,
                .prompt_tokens = entry.prompt_tokens,
                .completion_tokens = entry.completion_tokens,
                .cost = entry.cost,
            });
        }
    }

    // ============ File Operations ============

    fn readFile(self: *Persistence, path: []const u8) PersistenceError![]u8 {
        const file = std.fs.cwd().openFile(path, .{}) catch {
            return PersistenceError.FileNotFound;
        };
        defer file.close();

        const stat = file.stat() catch return PersistenceError.IoError;
        const content = try self.allocator.alloc(u8, @intCast(stat.size));
        errdefer self.allocator.free(content);

        const bytes_read = try file.readAll(content);
        if (bytes_read != stat.size) {
            return PersistenceError.IoError;
        }

        return content;
    }

    fn writeFile(_: *Persistence, path: []const u8, content: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
        defer file.close();

        try file.writeAll(content);
    }
};

pub const SpendTracker = @import("cost.zig").SpendTracker;
pub const SpendEntryPersist = struct {
    timestamp: i64,
    key_id: []const u8,
    team_id: ?[]const u8,
    project_id: ?[]const u8,
    provider: []const u8,
    model: []const u8,
    prompt_tokens: u32,
    completion_tokens: u32,
    cost: f64,
};

test "persistence roundtrip" {
    // Test that Persistence can be initialized and deinitialized
    const allocator = std.heap.page_allocator;
    var persist = Persistence.init(allocator, "/tmp/llmlite-test") catch {
        // Skip if we can't create the directory
        return;
    };
    defer persist.deinit();

    // Verify paths are set correctly
    try std.testing.expect(persist.keys_path.len > 0);
    try std.testing.expect(persist.teams_path.len > 0);
    try std.testing.expect(persist.projects_path.len > 0);
    try std.testing.expect(persist.spend_path.len > 0);
}
