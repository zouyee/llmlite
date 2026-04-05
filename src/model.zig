//! Models API

const std = @import("std");
const http = @import("http");

// ============================================================================
// Service
// ============================================================================

pub const Service = struct {
    allocator: std.mem.Allocator,
    http_client: *http.HttpClient,

    pub fn init(allocator: std.mem.Allocator, http_client: *http.HttpClient) Service {
        return .{
            .allocator = allocator,
            .http_client = http_client,
        };
    }

    pub fn deinit(self: *Service) void {
        _ = self;
    }

    /// Lists the currently available models.
    pub fn listModels(self: *Service) !ModelList {
        const response = try self.http_client.get("/models");
        defer self.allocator.free(response);
        return try self.parseModelsResponse(response);
    }

    /// Retrieves a model instance.
    pub fn getModel(self: *Service, model_id: []const u8) !Model {
        const path = try std.fmt.allocPrint(self.allocator, "/models/{s}", .{model_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseModelResponse(response);
    }

    fn parseJsonField(json_str: []const u8, field_name: []const u8) ?[]const u8 {
        const search_pattern_len = field_name.len + 3;
        var search_pattern_buf: [128]u8 = undefined;
        if (search_pattern_len >= search_pattern_buf.len) return null;

        var buf = search_pattern_buf[0..search_pattern_len];
        buf[0] = '"';
        @memcpy(buf[1..][0..field_name.len], field_name);
        buf[field_name.len + 1] = '"';
        buf[field_name.len + 2] = ':';

        const start_idx = std.mem.indexOf(u8, json_str, buf) orelse return null;
        const value_start = start_idx + search_pattern_len;

        var i = value_start;
        while (i < json_str.len and (json_str[i] == ' ' or json_str[i] == '\n' or json_str[i] == '\t')) {
            i += 1;
        }

        if (i >= json_str.len) return null;

        if (json_str[i] == '"') {
            i += 1;
            const str_start = i;
            while (i < json_str.len and json_str[i] != '"') {
                i += 1;
            }
            return json_str[str_start..i];
        } else {
            const num_start = i;
            while (i < json_str.len and (std.ascii.isDigit(json_str[i]) or json_str[i] == '.' or json_str[i] == '-' or json_str[i] == 'e' or json_str[i] == 'E')) {
                i += 1;
            }
            return json_str[num_start..i];
        }
    }

    fn parseModelsResponse(self: *Service, response: []const u8) !ModelList {
        const data_str = parseJsonField(response, "data") orelse return error.ParseError;

        var model_count: usize = 0;
        var search_pos: usize = 0;
        while (std.mem.indexOfPos(u8, data_str, search_pos, "\"id\":")) |idx| {
            _ = idx;
            model_count += 1;
            search_pos += 1;
        }

        var models = try self.allocator.alloc(Model, model_count);
        errdefer self.allocator.free(models);

        if (model_count > 0) {
            const first_id = parseJsonField(data_str, "id") orelse "unknown";
            const first_created = parseJsonField(data_str, "created") orelse "0";
            const first_owned_by = parseJsonField(data_str, "owned_by") orelse "unknown";

            models[0] = Model{
                .id = try self.allocator.dupe(u8, first_id),
                .created = std.fmt.parseInt(u64, first_created, 10) catch 0,
                .owned_by = try self.allocator.dupe(u8, first_owned_by),
            };
        }

        return ModelList{
            .data = models,
        };
    }

    fn parseModelResponse(self: *Service, response: []const u8) !Model {
        const id = parseJsonField(response, "id") orelse return error.ParseError;
        const created_str = parseJsonField(response, "created") orelse "0";
        const owned_by = parseJsonField(response, "owned_by") orelse "unknown";

        return Model{
            .id = try self.allocator.dupe(u8, id),
            .created = std.fmt.parseInt(u64, created_str, 10) catch 0,
            .owned_by = try self.allocator.dupe(u8, owned_by),
        };
    }
};

// ============================================================================
// Response Types
// ============================================================================

pub const ModelList = struct {
    object: []const u8 = "list",
    data: []Model,
};

pub const Model = struct {
    id: []const u8,
    object: []const u8 = "model",
    created: u64,
    owned_by: []const u8,
    permission: ?[]ModelPermission = null,
    root: ?[]const u8 = null,
    parent: ?[]const u8 = null,
};

pub const ModelPermission = struct {
    id: []const u8,
    object: []const u8 = "model_permission",
    created: u64,
    allow_create_engine: bool,
    allow_sampling: bool,
    allow_logprobs: bool,
    allow_search_indices: bool,
    allow_view: bool,
    allow_fine_tuning: bool,
    organization: []const u8,
    group: ?[]const u8 = null,
    is_blocking: bool,
};

// ============================================================================
// Model Constants
// ============================================================================

pub const ChatModel = enum {
    GPT4O,
    GPT4OMini,
    GPT4Turbo,
    GPT35Turbo,
    GPT35Turbo16K,

    pub fn toString(self: ChatModel) []const u8 {
        return switch (self) {
            .GPT4O => "gpt-4o",
            .GPT4OMini => "gpt-4o-mini",
            .GPT4Turbo => "gpt-4-turbo",
            .GPT35Turbo => "gpt-3.5-turbo",
            .GPT35Turbo16K => "gpt-3.5-turbo-16k",
        };
    }
};
