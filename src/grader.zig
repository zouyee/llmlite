//! Grader API - For evaluating model responses
//!
//! Reference: https://platform.openai.com/docs/api-reference/grader

const std = @import("std");
const http = @import("http");

// ============================================================================
// Grader Service
// ============================================================================

pub const Service = struct {
    allocator: std.mem.Allocator,
    http_client: *http.HttpClient,
    grader_models: GraderModelService,

    pub fn init(allocator: std.mem.Allocator, http_client: *http.HttpClient) Service {
        return .{
            .allocator = allocator,
            .http_client = http_client,
            .grader_models = GraderModelService.init(allocator, http_client),
        };
    }

    pub fn deinit(self: *Service) void {
        _ = self;
    }

    /// Run a grader evaluation
    pub fn run(self: *Service, params: GraderRunParams) !GraderRunResponse {
        const json_str = try self.serializeRunParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/fine_tuning/alpha/graders/run", json_str);
        defer self.allocator.free(response);

        return try self.parseRunResponse(response);
    }

    /// Validate grader configuration
    pub fn validate(self: *Service, params: GraderValidateParams) !GraderValidateResponse {
        const json_str = try self.serializeValidateParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/fine_tuning/alpha/graders/validate", json_str);
        defer self.allocator.free(response);

        return try self.parseValidateResponse(response);
    }

    fn serializeRunParams(self: *Service, params: GraderRunParams) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        errdefer buf.deinit();

        try buf.append('{');

        var first = true;

        if (params.grader_id) |id| {
            first = false;
            try buf.appendSlice("\"grader_id\":\"");
            try buf.appendSlice(id);
            try buf.append('"');
        }

        if (params.input_data) |data| {
            if (!first) try buf.append(',');
            first = false;
            try buf.appendSlice("\"input_data\":\"");
            try buf.appendSlice(data);
            try buf.append('"');
        }

        if (params.metadata) |meta| {
            if (!first) try buf.append(',');
            try buf.appendSlice("\"metadata\":");
            try buf.appendSlice(meta);
        }

        try buf.append('}');
        return try buf.toOwnedSlice();
    }

    fn serializeValidateParams(self: *Service, params: GraderValidateParams) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        errdefer buf.deinit();

        try buf.append('{');

        var first = true;

        if (params.grader_config) |config| {
            first = false;
            try buf.appendSlice("\"grader_config\":\"");
            try buf.appendSlice(config);
            try buf.append('"');
        }

        if (params.input_data) |data| {
            if (!first) try buf.append(',');
            try buf.appendSlice("\"input_data\":\"");
            try buf.appendSlice(data);
            try buf.append('"');
        }

        try buf.append('}');
        return try buf.toOwnedSlice();
    }

    fn parseRunResponse(self: *Service, response: []const u8) !GraderRunResponse {
        const json = std.json;
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        const status = (root.get("status") orelse return error.ParseError).string;
        const result = (root.get("result") orelse return error.ParseError).string;

        return GraderRunResponse{
            .status = try self.allocator.dupe(u8, status),
            .result = try self.allocator.dupe(u8, result),
        };
    }

    fn parseValidateResponse(self: *Service, response: []const u8) !GraderValidateResponse {
        const json = std.json;
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        const valid = (root.get("valid") orelse return error.ParseError).bool;
        const message = (root.get("message") orelse return error.ParseError).string;

        return GraderValidateResponse{
            .valid = valid,
            .message = try self.allocator.dupe(u8, message),
        };
    }
};

// ============================================================================
// Grader Model Service
// ============================================================================

pub const GraderModelService = struct {
    allocator: std.mem.Allocator,
    http_client: *http.HttpClient,

    pub fn init(allocator: std.mem.Allocator, http_client: *http.HttpClient) GraderModelService {
        return .{
            .allocator = allocator,
            .http_client = http_client,
        };
    }

    /// List available grader models
    pub fn list(self: *GraderModelService) !GraderModelListResponse {
        const response = try self.http_client.get("/grader/models");
        defer self.allocator.free(response);

        return try self.parseListResponse(response);
    }

    fn parseListResponse(self: *GraderModelService, response: []const u8) !GraderModelListResponse {
        const json = std.json;
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        const data_array = (root.get("data") orelse return error.ParseError).array;
        var models = try self.allocator.alloc(GraderModel, data_array.len);

        for (data_array, 0..) |item, i| {
            const obj = item.object orelse return error.ParseError;
            models[i] = .{
                .id = try self.allocator.dupe(u8, (obj.get("id") orelse return error.ParseError).string),
                .object = try self.allocator.dupe(u8, (obj.get("object") orelse return error.ParseError).string),
                .created = @intCast((obj.get("created") orelse return error.ParseError).integer),
            };
        }

        return GraderModelListResponse{
            .data = models,
        };
    }
};

// ============================================================================
// Types
// ============================================================================

/// Grader model object
pub const GraderModel = struct {
    id: []const u8,
    object: []const u8,
    created: i64,
};

/// Grader model list response
pub const GraderModelListResponse = struct {
    data: []GraderModel,
};

/// Parameters for running a grader evaluation
pub const GraderRunParams = struct {
    grader_id: []const u8,
    input_data: []const u8,
    metadata: ?[]const u8 = null,
};

/// Response from a grader run
pub const GraderRunResponse = struct {
    status: []const u8,
    result: []const u8,
};

/// Parameters for validating grader configuration
pub const GraderValidateParams = struct {
    grader_config: []const u8,
    input_data: ?[]const u8 = null,
};

/// Response from grader validation
pub const GraderValidateResponse = struct {
    valid: bool,
    message: []const u8,
};
