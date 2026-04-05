//! Beta Thread API - Deprecated Assistants API threads
//!
//! DEPRECATED: The Assistants API is deprecated in favor of the Responses API.
//! This module is provided for backward compatibility.
//!
//! Reference: https://platform.openai.com/docs/api-reference/threads

const std = @import("std");
const json = std.json;
const http = @import("http");

// ============================================================================
// Beta Thread Service
// ============================================================================

pub const Service = struct {
    allocator: std.mem.Allocator,
    http_client: *http.HttpClient,
    runs: RunService,
    messages: MessageService,

    pub fn init(allocator: std.mem.Allocator, http_client: *http.HttpClient) Service {
        return .{
            .allocator = allocator,
            .http_client = http_client,
            .runs = RunService.init(allocator, http_client),
            .messages = MessageService.init(allocator, http_client),
        };
    }

    pub fn deinit(self: *Service) void {
        _ = self;
    }

    /// Create a new thread
    pub fn create(self: *Service, params: CreateThreadParams) !Thread {
        const json_str = try self.serializeParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/threads", json_str);
        defer self.allocator.free(response);

        return try self.parseThreadResponse(response);
    }

    /// Get a thread by ID
    pub fn get(self: *Service, thread_id: []const u8) !Thread {
        const path = try std.fmt.allocPrint(self.allocator, "/threads/{s}", .{thread_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseThreadResponse(response);
    }

    /// Update a thread
    pub fn update(self: *Service, thread_id: []const u8, params: UpdateThreadParams) !Thread {
        const path = try std.fmt.allocPrint(self.allocator, "/threads/{s}", .{thread_id});
        defer self.allocator.free(path);

        const json_str = try self.serializeUpdateParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post(path, json_str);
        defer self.allocator.free(response);

        return try self.parseThreadResponse(response);
    }

    /// Delete a thread
    pub fn delete(self: *Service, thread_id: []const u8) !DeletedThread {
        const path = try std.fmt.allocPrint(self.allocator, "/threads/{s}", .{thread_id});
        defer self.allocator.free(path);

        const response = try self.http_client.delete(path);
        defer self.allocator.free(response);

        return try self.parseDeleteResponse(response);
    }

    /// Create a thread and run it in one request
    pub fn createAndRun(self: *Service, params: CreateAndRunParams) !Run {
        const json_str = try self.serializeCreateAndRunParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/threads/runs", json_str);
        defer self.allocator.free(response);

        return try self.parseRunResponse(response);
    }

    fn serializeParams(self: *Service, params: CreateThreadParams) ![]u8 {
        var parts = std.ArrayList(u8).init(self.allocator);
        errdefer parts.deinit();

        if (params.messages) |messages| {
            try parts.appendSlice("{\"messages\":[");
            for (messages, 0..) |msg, i| {
                if (i > 0) try parts.appendSlice(",");
                try std.json.stringify(.{
                    .role = msg.role,
                    .content = msg.content,
                }, .{}, parts.writer());
            }
            try parts.appendSlice("]");
        } else {
            try parts.appendSlice("{}");
        }

        return parts.toOwnedSlice();
    }

    fn serializeUpdateParams(self: *Service, params: UpdateThreadParams) ![]u8 {
        var parts = std.ArrayList(u8).init(self.allocator);
        errdefer parts.deinit();

        try std.json.stringify(params, .{}, parts.writer());
        return parts.toOwnedSlice();
    }

    fn serializeCreateAndRunParams(self: *Service, params: CreateAndRunParams) ![]u8 {
        _ = self;
        var parts = std.ArrayList(u8).init(self.allocator);
        errdefer parts.deinit();

        try std.json.stringify(.{
            .assistant_id = params.assistant_id,
            .model = params.model,
            .instructions = params.instructions,
        }, .{}, parts.writer());

        return parts.toOwnedSlice();
    }

    fn parseThreadResponse(self: *Service, response: []const u8) !Thread {
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        return Thread{
            .id = try self.allocator.dupe(u8, (root.get("id") orelse return error.ParseError).string),
            .object = try self.allocator.dupe(u8, (root.get("object") orelse return error.ParseError).string),
            .created_at = @intCast((root.get("created_at") orelse return error.ParseError).integer),
        };
    }

    fn parseDeleteResponse(self: *Service, response: []const u8) !DeletedThread {
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        return DeletedThread{
            .id = try self.allocator.dupe(u8, (root.get("id") orelse return error.ParseError).string),
            .object = try self.allocator.dupe(u8, (root.get("object") orelse return error.ParseError).string),
            .deleted = (root.get("deleted") orelse return error.ParseError).bool,
        };
    }

    fn parseRunResponse(self: *Service, response: []const u8) !Run {
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        return Run{
            .id = try self.allocator.dupe(u8, (root.get("id") orelse return error.ParseError).string),
            .object = try self.allocator.dupe(u8, (root.get("object") orelse return error.ParseError).string),
            .created_at = @intCast((root.get("created_at") orelse return error.ParseError).integer),
            .status = try self.allocator.dupe(u8, (root.get("status") orelse return error.ParseError).string),
            .assistant_id = try self.allocator.dupe(u8, (root.get("assistant_id") orelse return error.ParseError).string),
            .thread_id = try self.allocator.dupe(u8, (root.get("thread_id") orelse return error.ParseError).string),
        };
    }
};

// ============================================================================
// Run Service (Beta Thread Runs)
// ============================================================================

pub const RunService = struct {
    allocator: std.mem.Allocator,
    http_client: *http.HttpClient,

    pub fn init(allocator: std.mem.Allocator, http_client: *http.HttpClient) RunService {
        return .{
            .allocator = allocator,
            .http_client = http_client,
        };
    }

    /// Get a run
    pub fn get(self: *RunService, thread_id: []const u8, run_id: []const u8) !Run {
        const path = try std.fmt.allocPrint(self.allocator, "/threads/{s}/runs/{s}", .{ thread_id, run_id });
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseRunResponse(response);
    }

    /// List runs for a thread
    pub fn list(self: *RunService, thread_id: []const u8) !RunListResponse {
        const path = try std.fmt.allocPrint(self.allocator, "/threads/{s}/runs", .{thread_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseRunListResponse(response);
    }

    /// Submit tool outputs for a run
    pub fn submitToolOutputs(self: *RunService, thread_id: []const u8, run_id: []const u8, outputs: []const []const u8) !Run {
        const path = try std.fmt.allocPrint(self.allocator, "/threads/{s}/runs/{s}/submit_tool_outputs", .{ thread_id, run_id });
        defer self.allocator.free(path);

        const json_str = try std.fmt.allocPrint(self.allocator, "{{\"tool_outputs\":{s}}}", .{
            try std.json.stringify(outputs, .{}),
        });
        defer self.allocator.free(json_str);

        const response = try self.http_client.post(path, json_str);
        defer self.allocator.free(response);

        return try self.parseRunResponse(response);
    }

    fn parseRunResponse(self: *RunService, response: []const u8) !Run {
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        return Run{
            .id = try self.allocator.dupe(u8, (root.get("id") orelse return error.ParseError).string),
            .object = try self.allocator.dupe(u8, (root.get("object") orelse return error.ParseError).string),
            .created_at = @intCast((root.get("created_at") orelse return error.ParseError).integer),
            .status = try self.allocator.dupe(u8, (root.get("status") orelse return error.ParseError).string),
            .assistant_id = try self.allocator.dupe(u8, (root.get("assistant_id") orelse return error.ParseError).string),
            .thread_id = try self.allocator.dupe(u8, (root.get("thread_id") orelse return error.ParseError).string),
        };
    }

    fn parseRunListResponse(self: *RunService, response: []const u8) !RunListResponse {
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        const data_array = (root.get("data") orelse return error.ParseError).array;
        var runs = try self.allocator.alloc(Run, data_array.len);

        for (data_array, 0..) |item, i| {
            const obj = item.object orelse return error.ParseError;
            runs[i] = .{
                .id = try self.allocator.dupe(u8, (obj.get("id") orelse return error.ParseError).string),
                .object = try self.allocator.dupe(u8, (obj.get("object") orelse return error.ParseError).string),
                .created_at = @intCast((obj.get("created_at") orelse return error.ParseError).integer),
                .status = try self.allocator.dupe(u8, (obj.get("status") orelse return error.ParseError).string),
                .assistant_id = try self.allocator.dupe(u8, (obj.get("assistant_id") orelse return error.ParseError).string),
                .thread_id = try self.allocator.dupe(u8, (obj.get("thread_id") orelse return error.ParseError).string),
            };
        }

        return RunListResponse{
            .data = runs,
            .has_more = root.get("has_more").?.bool,
        };
    }
};

// ============================================================================
// Message Service (Beta Thread Messages)
// ============================================================================

pub const MessageService = struct {
    allocator: std.mem.Allocator,
    http_client: *http.HttpClient,

    pub fn init(allocator: std.mem.Allocator, http_client: *http.HttpClient) MessageService {
        return .{
            .allocator = allocator,
            .http_client = http_client,
        };
    }

    /// Create a message
    pub fn create(self: *MessageService, thread_id: []const u8, params: CreateMessageParams) !ThreadMessage {
        const path = try std.fmt.allocPrint(self.allocator, "/threads/{s}/messages", .{thread_id});
        defer self.allocator.free(path);

        const json_str = try self.serializeParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post(path, json_str);
        defer self.allocator.free(response);

        return try self.parseMessageResponse(response);
    }

    /// Get a message
    pub fn get(self: *MessageService, thread_id: []const u8, message_id: []const u8) !ThreadMessage {
        const path = try std.fmt.allocPrint(self.allocator, "/threads/{s}/messages/{s}", .{ thread_id, message_id });
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseMessageResponse(response);
    }

    /// List messages in a thread
    pub fn list(self: *MessageService, thread_id: []const u8) !MessageListResponse {
        const path = try std.fmt.allocPrint(self.allocator, "/threads/{s}/messages", .{thread_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseMessageListResponse(response);
    }

    fn serializeParams(self: *MessageService, params: CreateMessageParams) ![]u8 {
        _ = self;
        var parts = std.ArrayList(u8).init(self.allocator);
        errdefer parts.deinit();

        try std.json.stringify(.{
            .role = params.role,
            .content = params.content,
        }, .{}, parts.writer());

        return parts.toOwnedSlice();
    }

    fn parseMessageResponse(self: *MessageService, response: []const u8) !ThreadMessage {
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        return ThreadMessage{
            .id = try self.allocator.dupe(u8, (root.get("id") orelse return error.ParseError).string),
            .object = try self.allocator.dupe(u8, (root.get("object") orelse return error.ParseError).string),
            .created_at = @intCast((root.get("created_at") orelse return error.ParseError).integer),
            .role = try self.allocator.dupe(u8, (root.get("role") orelse return error.ParseError).string),
            .content = try self.allocator.dupe(u8, (root.get("content") orelse return error.ParseError).string),
        };
    }

    fn parseMessageListResponse(self: *MessageService, response: []const u8) !MessageListResponse {
        var parser = json.Parser.init(self.allocator, .{});
        defer parser.deinit();

        const tree = try parser.parse(response);
        const root = tree.root.object orelse return error.ParseError;

        const data_array = (root.get("data") orelse return error.ParseError).array;
        var messages = try self.allocator.alloc(ThreadMessage, data_array.len);

        for (data_array, 0..) |item, i| {
            const obj = item.object orelse return error.ParseError;
            messages[i] = .{
                .id = try self.allocator.dupe(u8, (obj.get("id") orelse return error.ParseError).string),
                .object = try self.allocator.dupe(u8, (obj.get("object") orelse return error.ParseError).string),
                .created_at = @intCast((obj.get("created_at") orelse return error.ParseError).integer),
                .role = try self.allocator.dupe(u8, (obj.get("role") orelse return error.ParseError).string),
                .content = try self.allocator.dupe(u8, (obj.get("content") orelse return error.ParseError).string),
            };
        }

        return MessageListResponse{
            .data = messages,
            .has_more = root.get("has_more").?.bool,
        };
    }
};

// ============================================================================
// Types
// ============================================================================

/// Thread object
pub const Thread = struct {
    id: []const u8,
    object: []const u8,
    created_at: i64,
};

/// Deleted thread object
pub const DeletedThread = struct {
    id: []const u8,
    object: []const u8,
    deleted: bool,
};

/// Run object
pub const Run = struct {
    id: []const u8,
    object: []const u8,
    created_at: i64,
    status: []const u8,
    assistant_id: []const u8,
    thread_id: []const u8,
};

/// Run list response
pub const RunListResponse = struct {
    data: []Run,
    has_more: bool,
};

/// Thread message object
pub const ThreadMessage = struct {
    id: []const u8,
    object: []const u8,
    created_at: i64,
    role: []const u8,
    content: []const u8,
};

/// Message list response
pub const MessageListResponse = struct {
    data: []ThreadMessage,
    has_more: bool,
};

// ============================================================================
// Parameters
// ============================================================================

/// Parameters for creating a thread
pub const CreateThreadParams = struct {
    messages: ?[]ThreadMessageParams = null,
};

/// Thread message parameters
pub const ThreadMessageParams = struct {
    role: []const u8,
    content: []const u8,
};

/// Parameters for updating a thread
pub const UpdateThreadParams = struct {
    metadata: ?std.json.Value = null,
};

/// Parameters for creating a message
pub const CreateMessageParams = struct {
    role: []const u8,
    content: []const u8,
};

/// Parameters for creating a thread and run
pub const CreateAndRunParams = struct {
    assistant_id: []const u8,
    model: ?[]const u8 = null,
    instructions: ?[]const u8 = null,
};
