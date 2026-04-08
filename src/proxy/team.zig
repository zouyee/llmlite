//! Team and Project Management for llmlite Proxy
//!
//! Multi-tenancy support with teams and projects

const std = @import("std");

pub const Team = struct {
    id: []const u8,
    name: []const u8,
    created_at: i64,
    budget_limit: ?f64,
    budget_spent: f64 = 0,
    max_keys: ?u32,
    max_requests_per_minute: ?u32,
    metadata: ?[][]const u8,
};

pub const Project = struct {
    id: []const u8,
    team_id: []const u8,
    name: []const u8,
    created_at: i64,
    budget_limit: ?f64,
    budget_spent: f64 = 0,
    allowed_models: ?[][]const u8,
    allowed_providers: ?[]const u8,
    metadata: ?[][]const u8,
};

pub const TeamStore = struct {
    allocator: std.mem.Allocator,
    teams: std.StringArrayHashMap(Team),
    projects: std.StringArrayHashMap(Project),
    team_members: std.StringArrayHashMap(std.ArrayList([]const u8)), // team_id -> [user_id]

    pub fn init(allocator: std.mem.Allocator) TeamStore {
        return .{
            .allocator = allocator,
            .teams = std.StringArrayHashMap(Team).init(allocator),
            .projects = std.StringArrayHashMap(Project).init(allocator),
            .team_members = std.StringArrayHashMap(std.ArrayList([]const u8)).init(allocator),
        };
    }

    pub fn deinit(self: *TeamStore) void {
        var team_it = self.teams.iterator();
        while (team_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.name);
            if (entry.value_ptr.metadata) |md| {
                for (md) |m| self.allocator.free(m);
                self.allocator.free(md);
            }
        }
        self.teams.deinit();

        var proj_it = self.projects.iterator();
        while (proj_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.name);
            if (entry.value_ptr.allowed_models) |models| {
                for (models) |m| self.allocator.free(m);
                self.allocator.free(models);
            }
            if (entry.value_ptr.metadata) |md| {
                for (md) |m| self.allocator.free(m);
                self.allocator.free(md);
            }
        }
        self.projects.deinit();

        var member_it = self.team_members.iterator();
        while (member_it.next()) |entry| {
            for (entry.value_ptr.items) |user_id| {
                self.allocator.free(user_id);
            }
            entry.value_ptr.deinit();
        }
        self.team_members.deinit();
    }

    // ============ Team Operations ============

    pub fn createTeam(self: *TeamStore, config: CreateTeamConfig) ![]const u8 {
        const team_id = try generateId(self.allocator, "team");
        errdefer self.allocator.free(team_id);

        const team = Team{
            .id = team_id,
            .name = try self.allocator.dupe(u8, config.name),
            .created_at = std.time.timestamp(),
            .budget_limit = config.budget_limit,
            .max_keys = config.max_keys,
            .max_requests_per_minute = config.max_requests_per_minute,
            .metadata = if (config.metadata) |md| blk: {
                const copy = try self.allocator.alloc([]const u8, md.len);
                for (md, 0..) |m, i| copy[i] = try self.allocator.dupe(u8, m);
                break :blk copy;
            } else null,
        };

        try self.teams.put(team_id, team);
        return team_id;
    }

    pub fn getTeam(self: *TeamStore, team_id: []const u8) ?*const Team {
        return self.teams.get(team_id);
    }

    pub fn deleteTeam(self: *TeamStore, team_id: []const u8) bool {
        // Also delete all projects under this team
        var proj_it = self.projects.iterator();
        while (proj_it.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.team_id, team_id)) {
                _ = self.deleteProject(entry.key_ptr.*);
            }
        }

        // Remove team members
        if (self.team_members.fetchRemove(team_id)) |entry| {
            for (entry.value.items) |user_id| {
                self.allocator.free(user_id);
            }
            entry.value.deinit();
        }

        if (self.teams.fetchRemove(team_id)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value.name);
            if (entry.value.metadata) |md| {
                for (md) |m| self.allocator.free(m);
                self.allocator.free(md);
            }
            return true;
        }
        return false;
    }

    pub fn updateTeamSpend(self: *TeamStore, team_id: []const u8, amount: f64) !void {
        const team = self.teams.getPtr(team_id) orelse {
            return error.TeamNotFound;
        };
        team.budget_spent += amount;
    }

    pub fn addTeamMember(self: *TeamStore, team_id: []const u8, user_id: []const u8) !void {
        const members = try self.team_members.getOrPut(team_id);
        if (!members.found_existing) {
            members.value_ptr.* = std.ArrayList([]const u8).init(self.allocator);
        }
        try members.value_ptr.append(try self.allocator.dupe(u8, user_id));
    }

    pub fn removeTeamMember(self: *TeamStore, team_id: []const u8, user_id: []const u8) void {
        if (self.team_members.get(team_id)) |members| {
            for (members.items, 0..) |uid, idx| {
                if (std.mem.eql(u8, uid, user_id)) {
                    self.allocator.free(members.orderedRemove(idx));
                    return;
                }
            }
        }
    }

    pub fn isTeamMember(self: *TeamStore, team_id: []const u8, user_id: []const u8) bool {
        if (self.team_members.get(team_id)) |members| {
            for (members.items) |uid| {
                if (std.mem.eql(u8, uid, user_id)) return true;
            }
        }
        return false;
    }

    pub fn getTeamsForUser(self: *TeamStore, user_id: []const u8) []const []const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);
        var it = self.team_members.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.items) |uid| {
                if (std.mem.eql(u8, uid, user_id)) {
                    result.append(entry.key_ptr.*) catch {};
                    break;
                }
            }
        }
        return result.toOwnedSlice();
    }

    // ============ Project Operations ============

    pub fn createProject(self: *TeamStore, team_id: []const u8, config: CreateProjectConfig) ![]const u8 {
        // Verify team exists
        if (self.teams.get(team_id) == null) {
            return error.TeamNotFound;
        }

        const project_id = try generateId(self.allocator, "proj");
        errdefer self.allocator.free(project_id);

        const project = Project{
            .id = project_id,
            .team_id = try self.allocator.dupe(u8, team_id),
            .name = try self.allocator.dupe(u8, config.name),
            .created_at = std.time.timestamp(),
            .budget_limit = config.budget_limit,
            .allowed_models = if (config.allowed_models) |models| blk: {
                const copy = try self.allocator.alloc([]const u8, models.len);
                for (models, 0..) |m, i| copy[i] = try self.allocator.dupe(u8, m);
                break :blk copy;
            } else null,
            .allowed_providers = if (config.allowed_providers) |providers|
                try self.allocator.dupe(u8, providers)
            else
                null,
        };

        try self.projects.put(project_id, project);
        return project_id;
    }

    pub fn getProject(self: *TeamStore, project_id: []const u8) ?*const Project {
        return self.projects.get(project_id);
    }

    pub fn deleteProject(self: *TeamStore, project_id: []const u8) bool {
        if (self.projects.fetchRemove(project_id)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value.team_id);
            self.allocator.free(entry.value.name);
            if (entry.value.allowed_models) |models| {
                for (models) |m| self.allocator.free(m);
                self.allocator.free(models);
            }
            if (entry.value.metadata) |md| {
                for (md) |m| self.allocator.free(m);
                self.allocator.free(md);
            }
            return true;
        }
        return false;
    }

    pub fn updateProjectSpend(self: *TeamStore, project_id: []const u8, amount: f64) !void {
        const project = self.projects.getPtr(project_id) orelse {
            return error.ProjectNotFound;
        };
        project.budget_spent += amount;

        // Also update parent team spend
        try self.updateTeamSpend(project.team_id, amount);
    }

    pub fn checkProjectAccess(self: *TeamStore, project_id: []const u8, model: []const u8, provider: []const u8) !void {
        const project = self.projects.get(project_id) orelse {
            return error.ProjectNotFound;
        };

        // Check model restriction
        if (project.allowed_models) |allowed| {
            var found = false;
            for (allowed) |m| {
                if (std.mem.eql(u8, m, model)) {
                    found = true;
                    break;
                }
            }
            if (!found) return error.ModelNotAllowed;
        }

        // Check provider restriction
        if (project.allowed_providers) |allowed| {
            var it = std.mem.splitScalar(u8, allowed, ',');
            var found = false;
            while (it.next()) |p| {
                if (std.mem.eql(u8, p, provider)) {
                    found = true;
                    break;
                }
            }
            if (!found) return error.ProviderNotAllowed;
        }
    }

    pub fn getProjectsForTeam(self: *TeamStore, team_id: []const u8) []const Project {
        var result = std.ArrayList(Project).init(self.allocator);
        var it = self.projects.iterator();
        while (it.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.team_id, team_id)) {
                result.append(entry.value_ptr.*) catch {};
            }
        }
        return result.toOwnedSlice();
    }

    // ============ Budget Checking ============

    pub fn checkTeamBudget(self: *TeamStore, team_id: []const u8, amount: f64) !void {
        const team = self.teams.get(team_id) orelse {
            return error.TeamNotFound;
        };

        if (team.budget_limit) |limit| {
            if (team.budget_spent + amount > limit) {
                return error.BudgetExceeded;
            }
        }
    }

    pub fn checkProjectBudget(self: *TeamStore, project_id: []const u8, amount: f64) !void {
        const project = self.projects.get(project_id) orelse {
            return error.ProjectNotFound;
        };

        if (project.budget_limit) |limit| {
            if (project.budget_spent + amount > limit) {
                return error.BudgetExceeded;
            }
        }
    }

    fn generateId(allocator: std.mem.Allocator, prefix: []const u8) ![]const u8 {
        const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        var id = std.ArrayList(u8).init(allocator);
        try id.appendSlice(prefix);
        try id.append('_');
        const id_len = 24;
        for (0..id_len) |_| {
            const idx = std.crypto.randomInt(u6) % chars.len;
            try id.append(chars[idx]);
        }
        return id.toOwnedSlice();
    }
};

pub const CreateTeamConfig = struct {
    name: []const u8,
    budget_limit: ?f64 = null,
    max_keys: ?u32 = null,
    max_requests_per_minute: ?u32 = null,
    metadata: ?[][]const u8 = null,
};

pub const CreateProjectConfig = struct {
    name: []const u8,
    budget_limit: ?f64 = null,
    allowed_models: ?[][]const u8 = null,
    allowed_providers: ?[]const u8 = null,
    metadata: ?[][]const u8 = null,
};

pub const TeamError = error{
    TeamNotFound,
    ProjectNotFound,
    BudgetExceeded,
    ModelNotAllowed,
    ProviderNotAllowed,
    MaxKeysExceeded,
};
