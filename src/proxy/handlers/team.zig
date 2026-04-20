//! Team Management Handler for llmlite Proxy
//!
//! Handles /team/* and /project/* API endpoints

const std = @import("std");
const team_pkg = @import("../team");

pub const TeamHandler = struct {
    allocator: std.mem.Allocator,
    team_store: *team_pkg.TeamStore,

    pub fn init(allocator: std.mem.Allocator, team_store: *team_pkg.TeamStore) TeamHandler {
        return .{
            .allocator = allocator,
            .team_store = team_store,
        };
    }

    pub fn handle(self: *TeamHandler, request: *std.http.Server.Request) !void {
        const path = request.path();

        if (std.mem.startsWith(u8, path, "POST /team")) {
            try self.handleCreateTeam(request);
        } else if (std.mem.startsWith(u8, path, "GET /team/")) {
            try self.handleGetTeam(request);
        } else if (std.mem.startsWith(u8, path, "DELETE /team/")) {
            try self.handleDeleteTeam(request);
        } else if (std.mem.startsWith(u8, path, "GET /teams")) {
            try self.handleListTeams(request);
        } else if (std.mem.startsWith(u8, path, "POST /project")) {
            try self.handleCreateProject(request);
        } else if (std.mem.startsWith(u8, path, "GET /project/")) {
            try self.handleGetProject(request);
        } else if (std.mem.startsWith(u8, path, "DELETE /project/")) {
            try self.handleDeleteProject(request);
        } else if (std.mem.startsWith(u8, path, "GET /projects")) {
            try self.handleListProjects(request);
        } else {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Not Found\",\"type\":\"invalid_request_error\"}}",
            });
        }
    }

    // ============ Team Endpoints ============

    fn handleCreateTeam(self: *TeamHandler, request: *std.http.Server.Request) !void {
        const body = try request.reader().readAllAlloc(self.allocator, 1_000_000);
        defer self.allocator.free(body);

        const create_req = std.json.parseFromSlice(
            team_pkg.CreateTeamConfig,
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
        defer create_req.deinit();

        const team_id = self.team_store.createTeam(create_req.value) catch {
            try request.respond(.{
                .status = .internal_server_error,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Failed to create team\",\"type\":\"internal_error\"}}",
            });
            return;
        };
        defer self.allocator.free(team_id);

        const team = self.team_store.getTeam(team_id).?;
        const response = try self.formatTeamInfo(team);
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .created,
            .content_type = .json,
            .body = response,
        });
    }

    fn handleGetTeam(self: *TeamHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        const team_id = path[9..]; // Skip "/team/"
        if (team_id.len == 0) {
            try request.respond(.{
                .status = .bad_request,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Team ID required\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        }

        const team = self.team_store.getTeam(team_id) orelse {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Team not found\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };

        const response = try self.formatTeamInfo(team);
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    fn handleDeleteTeam(self: *TeamHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        const team_id = path[12..]; // Skip "/team/"
        if (team_id.len == 0) {
            try request.respond(.{
                .status = .bad_request,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Team ID required\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        }

        if (self.team_store.deleteTeam(team_id)) {
            try request.respond(.{
                .status = .ok,
                .content_type = .json,
                .body = "{\"deleted\":true,\"id\":\"" ++ team_id ++ "\"}",
            });
        } else {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Team not found\",\"type\":\"invalid_request_error\"}}",
            });
        }
    }

    fn handleListTeams(self: *TeamHandler, request: *std.http.Server.Request) !void {
        var teams_array = std.array_list.Managed([]const u8).init(self.allocator);
        defer {
            for (teams_array.items) |item| self.allocator.free(item);
            teams_array.deinit();
        }

        var it = self.team_store.teams.iterator();
        while (it.next()) |entry| {
            const info = try self.formatTeamInfo(entry.value_ptr);
            try teams_array.append(info);
        }

        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .object = "list",
            .data = teams_array.items,
        }, .{});
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    fn formatTeamInfo(self: *TeamHandler, t: *const team_pkg.Team) ![]u8 {
        return std.json.Stringify.valueAlloc(self.allocator, .{
            .id = t.id,
            .name = t.name,
            .object = "team",
            .created_at = t.created_at,
            .budget_limit = t.budget_limit,
            .budget_spent = t.budget_spent,
            .max_keys = t.max_keys,
            .max_requests_per_minute = t.max_requests_per_minute,
        }, .{});
    }

    // ============ Project Endpoints ============

    fn handleCreateProject(self: *TeamHandler, request: *std.http.Server.Request) !void {
        const body = try request.reader().readAllAlloc(self.allocator, 1_000_000);
        defer self.allocator.free(body);

        const req_with_team = try std.json.parseFromSlice(
            CreateProjectRequest,
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
        defer req_with_team.deinit();

        const config = team_pkg.CreateProjectConfig{
            .name = req_with_team.value.name,
            .budget_limit = req_with_team.value.budget_limit,
            .allowed_models = req_with_team.value.allowed_models,
            .allowed_providers = req_with_team.value.allowed_providers,
        };

        const project_id = self.team_store.createProject(req_with_team.value.team_id, config) catch {
            try request.respond(.{
                .status = .internal_server_error,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Failed to create project\",\"type\":\"internal_error\"}}",
            });
            return;
        };
        defer self.allocator.free(project_id);

        const project = self.team_store.getProject(project_id).?;
        const response = try self.formatProjectInfo(project);
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .created,
            .content_type = .json,
            .body = response,
        });
    }

    fn handleGetProject(self: *TeamHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        const project_id = path[12..]; // Skip "/project/"
        if (project_id.len == 0) {
            try request.respond(.{
                .status = .bad_request,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Project ID required\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        }

        const project = self.team_store.getProject(project_id) orelse {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Project not found\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        };

        const response = try self.formatProjectInfo(project);
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    fn handleDeleteProject(self: *TeamHandler, request: *std.http.Server.Request) !void {
        const path = request.path();
        const project_id = path[14..]; // Skip "/project/"
        if (project_id.len == 0) {
            try request.respond(.{
                .status = .bad_request,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Project ID required\",\"type\":\"invalid_request_error\"}}",
            });
            return;
        }

        if (self.team_store.deleteProject(project_id)) {
            try request.respond(.{
                .status = .ok,
                .content_type = .json,
                .body = "{\"deleted\":true,\"id\":\"" ++ project_id ++ "\"}",
            });
        } else {
            try request.respond(.{
                .status = .not_found,
                .content_type = .json,
                .body = "{\"error\":{\"message\":\"Project not found\",\"type\":\"invalid_request_error\"}}",
            });
        }
    }

    fn handleListProjects(self: *TeamHandler, request: *std.http.Server.Request) !void {
        var projects_array = std.array_list.Managed([]const u8).init(self.allocator);
        defer {
            for (projects_array.items) |item| self.allocator.free(item);
            projects_array.deinit();
        }

        var it = self.team_store.projects.iterator();
        while (it.next()) |entry| {
            const info = try self.formatProjectInfo(entry.value_ptr);
            try projects_array.append(info);
        }

        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .object = "list",
            .data = projects_array.items,
        }, .{});
        defer self.allocator.free(response);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    fn formatProjectInfo(self: *TeamHandler, p: *const team_pkg.Project) ![]u8 {
        return std.json.Stringify.valueAlloc(self.allocator, .{
            .id = p.id,
            .team_id = p.team_id,
            .name = p.name,
            .object = "project",
            .created_at = p.created_at,
            .budget_limit = p.budget_limit,
            .budget_spent = p.budget_spent,
            .allowed_models = p.allowed_models,
            .allowed_providers = p.allowed_providers,
        }, .{});
    }
};

pub const CreateProjectRequest = struct {
    team_id: []const u8,
    name: []const u8,
    budget_limit: ?f64 = null,
    allowed_models: ?[][]const u8 = null,
    allowed_providers: ?[]const u8 = null,
};
