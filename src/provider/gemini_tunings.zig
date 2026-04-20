//! Tunings API - Google Gemini Model Tuning
//!
//! Reference: https://ai.google.dev/gemini-api/docs/model-tuning
//!
//! Tuning allows you to customize Gemini models for specific tasks
//! by training on your own data.

const std = @import("std");
const http = @import("http");

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

    /// Create a new tuning job
    /// POST /v1beta/tunedModels
    pub fn create(self: *Service, params: CreateTuningParams) !TuningTask {
        const json_str = try self.serializeCreateParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/tunedModels", json_str);
        defer self.allocator.free(response);

        return try self.parseTuningTask(response);
    }

    /// Get a tuning job by name
    /// GET /v1beta/{name}
    pub fn get(self: *Service, name: []const u8) !TuningTask {
        const path = try std.fmt.allocPrint(self.allocator, "/tunedModels/{s}", .{name});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseTuningTask(response);
    }

    /// List all tuning jobs
    /// GET /v1beta/tunedModels
    pub fn list(self: *Service, params: ?ListTuningParams) !ListTuningResponse {
        var path = std.array_list.Managed(u8).init(self.allocator);
        defer path.deinit();

        try path.appendSlice("/tunedModels");

        if (params) |p| {
            var first = true;
            if (p.page_size) |size| {
                try path.appendSlice(if (first) "?" else "&");
                try path.writer().print("pageSize={d}", .{size});
                first = false;
            }
            if (p.page_token) |token| {
                try path.appendSlice(if (first) "?" else "&");
                try path.appendSlice("pageToken=");
                try path.appendSlice(token);
            }
            if (p.filter) |filter| {
                try path.appendSlice(if (first) "?" else "&");
                try path.appendSlice("filter=");
                try path.appendSlice(filter);
            }
        }

        const response = try self.http_client.get(try path.toOwnedSlice());
        defer self.allocator.free(response);

        return try self.parseListResponse(response);
    }

    /// Delete a tuning job
    /// DELETE /v1beta/{name}
    pub fn delete(self: *Service, name: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/tunedModels/{s}", .{name});
        defer self.allocator.free(path);

        const response = try self.http_client.delete(path);
        defer self.allocator.free(response);
    }

    /// Cancel a tuning job
    /// POST /v1beta/{name}:cancel
    pub fn cancel(self: *Service, name: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/tunedModels/{s}:cancel", .{name});
        defer self.allocator.free(path);

        const response = try self.http_client.post(path, "{}");
        defer self.allocator.free(response);
    }

    /// Get operation status (for async operations)
    /// GET /v1beta/{name}
    pub fn getOperation(self: *Service, name: []const u8) !Operation {
        const path = try std.fmt.allocPrint(self.allocator, "/{s}", .{name});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseOperation(response);
    }

    // ============================================================================
    // Serialization
    // ============================================================================

    fn serializeCreateParams(self: *Service, params: CreateTuningParams) ![]u8 {
        var parts = std.ArrayListUnmanaged(u8){};
        defer parts.deinit(self.allocator);

        // Base model
        try parts.appendSlice(self.allocator, "{\"baseModel\":\"");
        try parts.appendSlice(self.allocator, params.base_model);
        try parts.appendSlice(self.allocator, "\",");

        // Tuning spec
        try parts.appendSlice(self.allocator, "\"tuningDataStats\":{\"tuningDatasetUri\":\"");
        try parts.appendSlice(self.allocator, params.training_data_uri);
        try parts.appendSlice(self.allocator, "\",\"tuningExamplesCount\":");
        try parts.writer(self.allocator).print("{d}", .{params.training_examples_count});
        try parts.appendSlice(self.allocator, "},");

        // Display name
        if (params.display_name) |name| {
            try parts.appendSlice(self.allocator, "\"displayName\":\"");
            try parts.appendSlice(self.allocator, name);
            try parts.appendSlice(self.allocator, "\",");
        }

        // Description
        if (params.description) |desc| {
            try parts.appendSlice(self.allocator, "\"description\":\"");
            try parts.appendSlice(self.allocator, desc);
            try parts.appendSlice(self.allocator, "\",");
        }

        // Epoch count
        if (params.epoch_count) |epochs| {
            try parts.appendSlice(self.allocator, "\"epochCount\":");
            try parts.writer(self.allocator).print("{d}", .{epochs});
            try parts.appendSlice(self.allocator, ",");
        }

        // Batch size
        if (params.batch_size) |batch| {
            try parts.appendSlice(self.allocator, "\"batchSize\":");
            try parts.writer(self.allocator).print("{d}", .{batch});
            try parts.appendSlice(self.allocator, ",");
        }

        // Learning rate
        if (params.learning_rate) |lr| {
            try parts.appendSlice(self.allocator, "\"learningRate\":");
            try parts.writer(self.allocator).print("{}", .{lr});
            try parts.appendSlice(self.allocator, ",");
        }

        // Remove trailing comma
        if (parts.items.len > 0 and parts.items[parts.items.len - 1] == ',') {
            parts.items.len -= 1;
        }

        try parts.appendSlice(self.allocator, "}");
        return try parts.toOwnedSlice(self.allocator);
    }

    // ============================================================================
    // Parsing
    // ============================================================================

    fn parseTuningTask(self: *Service, response: []const u8) !TuningTask {
        const name = self.parseField(response, "name") orelse return error.ParseError;
        const model = self.parseField(response, "baseModel") orelse self.parseField(response, "model") orelse return error.ParseError;
        const display_name = self.parseField(response, "displayName");
        const description = self.parseField(response, "description");

        // Parse state
        const state_str = self.parseField(response, "state") orelse "STATE_UNSPECIFIED";
        const state = self.parseTuningState(state_str);

        // Parse create/update times
        const create_time = self.parseField(response, "createTime");
        const update_time = self.parseField(response, "updateTime");

        // Parse error
        var error_msg: ?[]const u8 = null;
        if (self.parseField(response, "error")) |err_str| {
            error_msg = self.parseField(err_str, "message");
        }

        return TuningTask{
            .name = try self.allocator.dupe(u8, name),
            .base_model = try self.allocator.dupe(u8, model),
            .display_name = if (display_name) |d| try self.allocator.dupe(u8, d) else null,
            .description = if (description) |d| try self.allocator.dupe(u8, d) else null,
            .state = state,
            .create_time = if (create_time) |t| try self.allocator.dupe(u8, t) else null,
            .update_time = if (update_time) |t| try self.allocator.dupe(u8, t) else null,
            .error_message = if (error_msg) |e| try self.allocator.dupe(u8, e) else null,
        };
    }

    fn parseTuningState(state_str: []const u8) TuningState {
        if (std.mem.indexOf(u8, state_str, "CREATING")) |_| return .creating;
        if (std.mem.indexOf(u8, state_str, "ACTIVE")) |_| return .active;
        if (std.mem.indexOf(u8, state_str, "FAILED")) |_| return .failed;
        if (std.mem.indexOf(u8, state_str, "DELETING")) |_| return .deleting;
        if (std.mem.indexOf(u8, state_str, "PAUSED")) |_| return .paused;
        return .unspecified;
    }

    fn parseOperation(self: *Service, response: []const u8) !Operation {
        const done_str = self.parseField(response, "done") orelse "false";
        const done = std.mem.eql(u8, done_str, "true");

        var result: ?TuningTask = null;
        if (self.parseField(response, "response")) |resp_str| {
            result = self.parseTuningTask(resp_str) catch null;
        }

        var error_msg: ?[]const u8 = null;
        if (self.parseField(response, "error")) |err_str| {
            error_msg = self.parseField(err_str, "message");
        }

        return Operation{
            .done = done,
            .result = result,
            .error_message = if (error_msg) |e| try self.allocator.dupe(u8, e) else null,
        };
    }

    fn parseListResponse(self: *Service, response: []const u8) !ListTuningResponse {
        const data_str = self.parseField(response, "tunedModels") orelse self.parseField(response, "models") orelse return error.ParseError;
        const next_page_token = self.parseField(response, "nextPageToken");

        var items = std.ArrayListUnmanaged(TuningTask){};
        errdefer {
            for (items.items) |item| self.freeTuningTask(item);
            items.deinit(self.allocator);
        }

        // Parse array
        var search_idx: usize = 0;
        while (search_idx < data_str.len) {
            const obj_start = std.mem.indexOf(u8, data_str[search_idx..], "{") orelse break;
            const obj_end = findMatchingBrace(data_str[search_idx + obj_start ..]) orelse break;
            const obj_json = data_str[search_idx + obj_start .. search_idx + obj_start + obj_end + 1];

            const item = self.parseTuningTask(obj_json) catch continue;
            try items.append(self.allocator, item);

            search_idx += obj_start + obj_end + 1;
        }

        return ListTuningResponse{
            .tuned_models = try items.toOwnedSlice(self.allocator),
            .next_page_token = if (next_page_token) |t| try self.allocator.dupe(u8, t) else null,
        };
    }

    fn freeTuningTask(self: *Service, task: TuningTask) void {
        self.allocator.free(task.name);
        self.allocator.free(task.base_model);
        if (task.display_name) |d| self.allocator.free(d);
        if (task.description) |d| self.allocator.free(d);
        if (task.create_time) |t| self.allocator.free(t);
        if (task.update_time) |t| self.allocator.free(t);
        if (task.error_message) |e| self.allocator.free(e);
    }

    fn parseField(self: *Service, json_str: []const u8, field_name: []const u8) ?[]const u8 {
        _ = self;
        const search_pattern = "\"" ++ field_name ++ "\":";
        const start_idx = std.mem.indexOf(u8, json_str, search_pattern) orelse return null;
        const value_start = start_idx + search_pattern.len;

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
        } else if (json_str[i] == '{' or json_str[i] == '[') {
            var depth: u32 = 1;
            i += 1;
            while (i < json_str.len and depth > 0) {
                if (json_str[i] == '{' or json_str[i] == '[') depth += 1;
                if (json_str[i] == '}' or json_str[i] == ']') depth -= 1;
                i += 1;
            }
            return json_str[value_start..i];
        } else {
            const num_start = i;
            while (i < json_str.len and (std.ascii.isDigit(json_str[i]) or json_str[i] == '.' or json_str[i] == '-' or json_str[i] == 'e' or json_str[i] == 'E' or json_str[i] == 'n' or json_str[i] == 'u' or json_str[i] == 'l')) {
                i += 1;
            }
            return json_str[num_start..i];
        }
    }
};

fn findMatchingBrace(data: []const u8) ?usize {
    if (data.len == 0 or data[0] != '{') return null;
    var depth: u32 = 1;
    var i: usize = 1;
    while (i < data.len and depth > 0) {
        if (data[i] == '{' or data[i] == '[') depth += 1;
        if (data[i] == '}' or data[i] == ']') depth -= 1;
        i += 1;
    }
    if (depth == 0) return i - 1;
    return null;
}

// ============================================================================
// Request Types
// ============================================================================

pub const CreateTuningParams = struct {
    base_model: []const u8,
    training_data_uri: []const u8,
    training_examples_count: i32,
    display_name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    epoch_count: ?i32 = null,
    batch_size: ?i32 = null,
    learning_rate: ?f32 = null,
};

pub const ListTuningParams = struct {
    page_size: ?i32 = null,
    page_token: ?[]const u8 = null,
    filter: ?[]const u8 = null,
};

// ============================================================================
// Tuning State
// ============================================================================

pub const TuningState = enum {
    unspecified,
    creating,
    active,
    failed,
    deleting,
    paused,

    pub fn toString(self: TuningState) []const u8 {
        return switch (self) {
            .unspecified => "STATE_UNSPECIFIED",
            .creating => "CREATING",
            .active => "ACTIVE",
            .failed => "FAILED",
            .deleting => "DELETING",
            .paused => "PAUSED",
        };
    }
};

// ============================================================================
// Response Types
// ============================================================================

pub const TuningTask = struct {
    name: []const u8,
    base_model: []const u8,
    display_name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    state: TuningState = .unspecified,
    create_time: ?[]const u8 = null,
    update_time: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
};

pub const Operation = struct {
    done: bool,
    result: ?TuningTask,
    error_message: ?[]const u8 = null,
};

pub const ListTuningResponse = struct {
    tuned_models: []TuningTask,
    next_page_token: ?[]const u8 = null,
};

// ============================================================================
// Endpoint Helpers
// ============================================================================

pub const getTunedModelsListEndpoint = "/tunedModels";
