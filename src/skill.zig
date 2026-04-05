//! Skill API - For managing reusable skills
//!
//! Reference: https://platform.openai.com/docs/api-reference/skills

const std = @import("std");
const json = std.json;
const http = @import("http");

// ============================================================================
// Skill Service
// ============================================================================

pub const Service = struct {
    allocator: std.mem.Allocator,
    http_client: *http.HttpClient,
    content: SkillContentService,
    versions: SkillVersionService,

    pub fn init(allocator: std.mem.Allocator, http_client: *http.HttpClient) Service {
        return .{
            .allocator = allocator,
            .http_client = http_client,
            .content = SkillContentService.init(allocator, http_client),
            .versions = SkillVersionService.init(allocator, http_client),
        };
    }

    pub fn deinit(self: *Service) void {
        _ = self;
    }

    /// Create a new skill
    pub fn create(self: *Service, params: CreateSkillParams) !Skill {
        const json_str = try self.serializeCreateParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/skills", json_str);
        defer self.allocator.free(response);

        return try self.parseSkillResponse(response);
    }

    /// Get a skill by ID
    pub fn get(self: *Service, skill_id: []const u8) !Skill {
        const path = try std.fmt.allocPrint(self.allocator, "/skills/{s}", .{skill_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseSkillResponse(response);
    }

    /// Update a skill's default version
    pub fn update(self: *Service, skill_id: []const u8, params: UpdateSkillParams) !Skill {
        const path = try std.fmt.allocPrint(self.allocator, "/skills/{s}", .{skill_id});
        defer self.allocator.free(path);

        const json_str = try self.serializeUpdateParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post(path, json_str);
        defer self.allocator.free(response);

        return try self.parseSkillResponse(response);
    }

    /// List all skills
    pub fn list(self: *Service, params: ListSkillsParams) !SkillListResponse {
        const query = try self.serializeListParams(params);
        defer self.allocator.free(query);

        const response = try self.http_client.get("/skills");
        defer self.allocator.free(response);

        return try self.parseListResponse(response);
    }

    /// Delete a skill
    pub fn delete(self: *Service, skill_id: []const u8) !DeletedSkill {
        const path = try std.fmt.allocPrint(self.allocator, "/skills/{s}", .{skill_id});
        defer self.allocator.free(path);

        const response = try self.http_client.delete(path);
        defer self.allocator.free(response);

        return try self.parseDeleteResponse(response);
    }

    fn serializeCreateParams(self: *Service, params: CreateSkillParams) ![]u8 {
        _ = self;
        _ = params;
        // TODO: Implement multipart form upload for skill files
        return try std.fmt.allocPrint(self.allocator, "{{}}", .{});
    }

    fn serializeUpdateParams(self: *Service, params: UpdateSkillParams) ![]u8 {
        _ = self;
        var parts = std.ArrayList(u8).init(self.allocator);
        errdefer parts.deinit();

        try std.json.stringify(.{ .default_version = params.default_version }, .{}, parts.writer());
        return parts.toOwnedSlice();
    }

    fn serializeListParams(self: *Service, params: ListSkillsParams) ![]u8 {
        _ = self;
        _ = params;
        return try std.fmt.allocPrint(self.allocator, "", .{});
    }

    fn parseSkillResponse(self: *Service, response: []const u8) !Skill {
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        return Skill{
            .id = try self.allocator.dupe(u8, (root.get("id") orelse return error.ParseError).string),
            .object = try self.allocator.dupe(u8, (root.get("object") orelse return error.ParseError).string),
            .created_at = @intCast((root.get("created_at") orelse return error.ParseError).integer),
            .name = try self.allocator.dupe(u8, (root.get("name") orelse return error.ParseError).string),
            .description = try self.allocator.dupe(u8, (root.get("description") orelse return error.ParseError).string),
            .default_version = try self.allocator.dupe(u8, (root.get("default_version") orelse return error.ParseError).string),
            .latest_version = try self.allocator.dupe(u8, (root.get("latest_version") orelse return error.ParseError).string),
        };
    }

    fn parseListResponse(self: *Service, response: []const u8) !SkillListResponse {
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        const data_array = (root.get("data") orelse return error.ParseError).array;
        var skills = try self.allocator.alloc(Skill, data_array.len);

        for (data_array, 0..) |item, i| {
            const obj = item.object orelse return error.ParseError;
            skills[i] = .{
                .id = try self.allocator.dupe(u8, (obj.get("id") orelse return error.ParseError).string),
                .object = try self.allocator.dupe(u8, (obj.get("object") orelse return error.ParseError).string),
                .created_at = @intCast((obj.get("created_at") orelse return error.ParseError).integer),
                .name = try self.allocator.dupe(u8, (obj.get("name") orelse return error.ParseError).string),
                .description = try self.allocator.dupe(u8, (obj.get("description") orelse return error.ParseError).string),
                .default_version = try self.allocator.dupe(u8, (obj.get("default_version") orelse return error.ParseError).string),
                .latest_version = try self.allocator.dupe(u8, (obj.get("latest_version") orelse return error.ParseError).string),
            };
        }

        return SkillListResponse{
            .data = skills,
            .has_more = root.get("has_more").?.bool,
        };
    }

    fn parseDeleteResponse(self: *Service, response: []const u8) !DeletedSkill {
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        return DeletedSkill{
            .id = try self.allocator.dupe(u8, (root.get("id") orelse return error.ParseError).string),
            .object = try self.allocator.dupe(u8, (root.get("object") orelse return error.ParseError).string),
            .deleted = (root.get("deleted") orelse return error.ParseError).bool,
        };
    }
};

// ============================================================================
// Skill Content Service
// ============================================================================

pub const SkillContentService = struct {
    allocator: std.mem.Allocator,
    http_client: *http.HttpClient,

    pub fn init(allocator: std.mem.Allocator, http_client: *http.HttpClient) SkillContentService {
        return .{
            .allocator = allocator,
            .http_client = http_client,
        };
    }

    /// Get skill content by ID
    pub fn get(self: *SkillContentService, skill_id: []const u8, version: ?[]const u8) !SkillContent {
        const path = if (version) |v|
            try std.fmt.allocPrint(self.allocator, "/skills/{s}/content?version={s}", .{ skill_id, v })
        else
            try std.fmt.allocPrint(self.allocator, "/skills/{s}/content", .{skill_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseContentResponse(response);
    }

    fn parseContentResponse(self: *SkillContentService, response: []const u8) !SkillContent {
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        return SkillContent{
            .id = try self.allocator.dupe(u8, (root.get("id") orelse return error.ParseError).string),
            .skill_id = try self.allocator.dupe(u8, (root.get("skill_id") orelse return error.ParseError).string),
            .version = try self.allocator.dupe(u8, (root.get("version") orelse return error.ParseError).string),
        };
    }
};

// ============================================================================
// Skill Version Service
// ============================================================================

pub const SkillVersionService = struct {
    allocator: std.mem.Allocator,
    http_client: *http.HttpClient,

    pub fn init(allocator: std.mem.Allocator, http_client: *http.HttpClient) SkillVersionService {
        return .{
            .allocator = allocator,
            .http_client = http_client,
        };
    }

    /// List skill versions
    pub fn list(self: *SkillVersionService, skill_id: []const u8) !SkillVersionListResponse {
        const path = try std.fmt.allocPrint(self.allocator, "/skills/{s}/versions", .{skill_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseVersionListResponse(response);
    }

    fn parseVersionListResponse(self: *SkillVersionService, response: []const u8) !SkillVersionListResponse {
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        const data_array = (root.get("data") orelse return error.ParseError).array;
        var versions = try self.allocator.alloc(SkillVersion, data_array.len);

        for (data_array, 0..) |item, i| {
            const obj = item.object orelse return error.ParseError;
            versions[i] = .{
                .version = try self.allocator.dupe(u8, (obj.get("version") orelse return error.ParseError).string),
                .created_at = @intCast((obj.get("created_at") orelse return error.ParseError).integer),
            };
        }

        return SkillVersionListResponse{
            .data = versions,
        };
    }
};

// ============================================================================
// Types
// ============================================================================

/// Skill object
pub const Skill = struct {
    id: []const u8,
    object: []const u8,
    created_at: i64,
    name: []const u8,
    description: []const u8,
    default_version: []const u8,
    latest_version: []const u8,
};

/// Deleted skill object
pub const DeletedSkill = struct {
    id: []const u8,
    object: []const u8,
    deleted: bool,
};

/// Skill content object
pub const SkillContent = struct {
    id: []const u8,
    skill_id: []const u8,
    version: []const u8,
};

/// Skill version object
pub const SkillVersion = struct {
    version: []const u8,
    created_at: i64,
};

/// Skill list response
pub const SkillListResponse = struct {
    data: []Skill,
    has_more: bool,
};

/// Skill version list response
pub const SkillVersionListResponse = struct {
    data: []SkillVersion,
};

// ============================================================================
// Parameters
// ============================================================================

/// Parameters for creating a skill
pub const CreateSkillParams = struct {
    files: ?[]const u8 = null, // TODO: File upload
};

/// Parameters for updating a skill
pub const UpdateSkillParams = struct {
    default_version: []const u8,
};

/// Parameters for listing skills
pub const ListSkillsParams = struct {
    limit: ?i32 = null,
    after: ?[]const u8 = null,
    order: ?[]const u8 = null, // "asc" or "desc"
};
