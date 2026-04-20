//! Assistants API (Beta) - Build AI assistants
//!
//! Reference: https://platform.openai.com/docs/api-reference/assistants
//!
//! The Assistants API allows you to build AI assistants that can perform
//! various tasks using tools, files, and conversation management.

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

    /// Creates an assistant.
    pub fn createAssistant(self: *Service, params: AssistantCreateParams) !Assistant {
        const json_str = try self.serializeCreateParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/assistants", json_str);
        defer self.allocator.free(response);

        return try self.parseAssistant(response);
    }

    /// Retrieves an assistant.
    pub fn getAssistant(self: *Service, assistant_id: []const u8) !Assistant {
        const path = try std.fmt.allocPrint(self.allocator, "/assistants/{s}", .{assistant_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseAssistant(response);
    }

    /// Modifies an assistant.
    pub fn modifyAssistant(self: *Service, assistant_id: []const u8, params: AssistantModifyParams) !Assistant {
        const path = try std.fmt.allocPrint(self.allocator, "/assistants/{s}", .{assistant_id});
        defer self.allocator.free(path);

        const json_str = try self.serializeModifyParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post(path, json_str);
        defer self.allocator.free(response);

        return try self.parseAssistant(response);
    }

    /// Deletes an assistant.
    pub fn deleteAssistant(self: *Service, assistant_id: []const u8) !AssistantDeleted {
        const path = try std.fmt.allocPrint(self.allocator, "/assistants/{s}", .{assistant_id});
        defer self.allocator.free(path);

        const response = try self.http_client.delete(path);
        defer self.allocator.free(response);

        return try self.parseDeleteResponse(response);
    }

    /// Lists assistants.
    pub fn listAssistants(self: *Service, params: ?AssistantListParams) !AssistantListResponse {
        var path = std.array_list.Managed(u8).init(self.allocator);
        defer path.deinit();

        try path.appendSlice("/assistants");

        if (params) |p| {
            var first = true;
            if (p.limit) |limit| {
                try path.appendSlice(if (first) "?" else "&");
                try path.writer().print("limit={d}", .{limit});
                first = false;
            }
            if (p.order) |order| {
                try path.appendSlice(if (first) "?" else "&");
                try path.appendSlice("order=");
                try path.appendSlice(order);
            }
            if (p.after) |after| {
                try path.appendSlice(if (first) "?" else "&");
                try path.appendSlice("after=");
                try path.appendSlice(after);
            }
            if (p.before) |before| {
                try path.appendSlice(if (first) "?" else "&");
                try path.appendSlice("before=");
                try path.appendSlice(before);
            }
        }

        const response = try self.http_client.get(try path.toOwnedSlice());
        defer self.allocator.free(response);

        return try self.parseListResponse(response);
    }

    // ============================================================================
    // Thread Operations
    // ============================================================================

    /// Creates a thread.
    pub fn createThread(self: *Service, params: ?ThreadCreateParams) !Thread {
        const json_str = if (params) |p| try self.serializeThreadCreateParams(p) else "{}";
        defer if (params != null) self.allocator.free(json_str);

        const response = try self.http_client.post("/threads", json_str);
        defer self.allocator.free(response);

        return try self.parseThread(response);
    }

    /// Retrieves a thread.
    pub fn getThread(self: *Service, thread_id: []const u8) !Thread {
        const path = try std.fmt.allocPrint(self.allocator, "/threads/{s}", .{thread_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseThread(response);
    }

    /// Modifies a thread.
    pub fn modifyThread(self: *Service, thread_id: []const u8, params: ThreadModifyParams) !Thread {
        const path = try std.fmt.allocPrint(self.allocator, "/threads/{s}", .{thread_id});
        defer self.allocator.free(path);

        const json_str = try self.serializeThreadModifyParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post(path, json_str);
        defer self.allocator.free(response);

        return try self.parseThread(response);
    }

    /// Deletes a thread.
    pub fn deleteThread(self: *Service, thread_id: []const u8) !ThreadDeleted {
        const path = try std.fmt.allocPrint(self.allocator, "/threads/{s}", .{thread_id});
        defer self.allocator.free(path);

        const response = try self.http_client.delete(path);
        defer self.allocator.free(response);

        return try self.parseThreadDeleteResponse(response);
    }

    // ============================================================================
    // Message Operations
    // ============================================================================

    /// Creates a message in a thread.
    pub fn createMessage(self: *Service, thread_id: []const u8, params: MessageCreateParams) !Message {
        const path = try std.fmt.allocPrint(self.allocator, "/threads/{s}/messages", .{thread_id});
        defer self.allocator.free(path);

        const json_str = try self.serializeMessageCreateParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post(path, json_str);
        defer self.allocator.free(response);

        return try self.parseMessage(response);
    }

    /// Lists messages in a thread.
    pub fn listMessages(self: *Service, thread_id: []const u8, params: ?MessageListParams) !MessageListResponse {
        const path = try std.fmt.allocPrint(self.allocator, "/threads/{s}/messages", .{thread_id});
        defer self.allocator.free(path);

        var query = std.array_list.Managed(u8).init(self.allocator);
        defer query.deinit();

        if (params) |p| {
            if (p.limit) |limit| {
                try query.writer().print("limit={d}", .{limit});
            }
            if (p.order) |order| {
                if (query.items.len > 0) try query.appendSlice("&");
                try query.appendSlice("order=");
                try query.appendSlice(order);
            }
        }

        const full_path = if (query.items.len > 0)
            try std.fmt.allocPrint(self.allocator, "{s}?{s}", .{ path, query.items })
        else
            path;
        if (query.items.len > 0) self.allocator.free(path);

        const response = try self.http_client.get(full_path);
        self.allocator.free(full_path);
        defer self.allocator.free(response);

        return try self.parseMessageListResponse(response);
    }

    // ============================================================================
    // Run Operations
    // ============================================================================

    /// Creates a run in a thread.
    pub fn createRun(self: *Service, thread_id: []const u8, params: RunCreateParams) !Run {
        const path = try std.fmt.allocPrint(self.allocator, "/threads/{s}/runs", .{thread_id});
        defer self.allocator.free(path);

        const json_str = try self.serializeRunCreateParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post(path, json_str);
        defer self.allocator.free(response);

        return try self.parseRun(response);
    }

    /// Retrieves a run.
    pub fn getRun(self: *Service, thread_id: []const u8, run_id: []const u8) !Run {
        const path = try std.fmt.allocPrint(self.allocator, "/threads/{s}/runs/{s}", .{ thread_id, run_id });
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseRun(response);
    }

    /// Lists runs in a thread.
    pub fn listRuns(self: *Service, thread_id: []const u8, params: ?RunListParams) !RunListResponse {
        const path = try std.fmt.allocPrint(self.allocator, "/threads/{s}/runs", .{thread_id});
        defer self.allocator.free(path);

        var query = std.array_list.Managed(u8).init(self.allocator);
        defer query.deinit();

        if (params) |p| {
            if (p.limit) |limit| {
                try query.writer().print("limit={d}", .{limit});
            }
        }

        const full_path = if (query.items.len > 0)
            try std.fmt.allocPrint(self.allocator, "{s}?{s}", .{ path, query.items })
        else
            path;
        if (query.items.len > 0) self.allocator.free(path);

        const response = try self.http_client.get(full_path);
        self.allocator.free(full_path);
        defer self.allocator.free(response);

        return try self.parseRunListResponse(response);
    }

    // ============================================================================
    // Serialization
    // ============================================================================

    fn serializeCreateParams(self: *Service, params: AssistantCreateParams) ![]u8 {
        _ = self;
        return std.fmt.allocPrint(self.allocator,
            \\{{"model":"{s}","name":"{s}","description":"{s}","instructions":"{s}"}}
        , .{
            params.model,
            if (params.name) |n| n else "",
            if (params.description) |d| d else "",
            if (params.instructions) |i| i else "",
        });
    }

    fn serializeModifyParams(self: *Service, params: AssistantModifyParams) ![]u8 {
        _ = self;
        return std.fmt.allocPrint(self.allocator,
            \\{{"name":"{s}","description":"{s}","instructions":"{s}"}}
        , .{
            if (params.name) |n| n else "",
            if (params.description) |d| d else "",
            if (params.instructions) |i| i else "",
        });
    }

    fn serializeThreadCreateParams(self: *Service, params: ThreadCreateParams) ![]u8 {
        _ = self;
        if (params.metadata) |m| {
            return std.fmt.allocPrint(self.allocator,
                \\{{"metadata":{{"key":"{s}"}}}}
            , .{m});
        }
        return "{}";
    }

    fn serializeThreadModifyParams(self: *Service, params: ThreadModifyParams) ![]u8 {
        _ = self;
        if (params.metadata) |m| {
            return std.fmt.allocPrint(self.allocator,
                \\{{"metadata":{{"key":"{s}"}}}}
            , .{m});
        }
        return "{}";
    }

    fn serializeMessageCreateParams(self: *Service, params: MessageCreateParams) ![]u8 {
        _ = self;
        return std.fmt.allocPrint(self.allocator,
            \\{{"role":"{s}","content":"{s}"}}
        , .{ params.role, params.content });
    }

    fn serializeRunCreateParams(self: *Service, params: RunCreateParams) ![]u8 {
        _ = self;
        return std.fmt.allocPrint(self.allocator,
            \\{{"assistant_id":"{s}"}}
        , .{params.assistant_id});
    }

    // ============================================================================
    // Parsing
    // ============================================================================

    fn parseAssistant(self: *Service, response: []const u8) !Assistant {
        const id = self.parseJsonField(response, "id") orelse return error.ParseError;
        const object = self.parseJsonField(response, "object") orelse return error.ParseError;
        const created_at_str = self.parseJsonField(response, "created_at") orelse "0";
        const model = self.parseJsonField(response, "model") orelse return error.ParseError;
        const name = self.parseJsonField(response, "name");
        const description = self.parseJsonField(response, "description");
        const instructions = self.parseJsonField(response, "instructions");

        return Assistant{
            .id = try self.allocator.dupe(u8, id),
            .object = try self.allocator.dupe(u8, object),
            .created_at = std.fmt.parseInt(i64, created_at_str, 10) catch 0,
            .model = try self.allocator.dupe(u8, model),
            .name = if (name) |n| try self.allocator.dupe(u8, n) else null,
            .description = if (description) |d| try self.allocator.dupe(u8, d) else null,
            .instructions = if (instructions) |i| try self.allocator.dupe(u8, i) else null,
        };
    }

    fn parseDeleteResponse(self: *Service, response: []const u8) !AssistantDeleted {
        const id = self.parseJsonField(response, "id") orelse return error.ParseError;
        const deleted_str = self.parseJsonField(response, "deleted") orelse "false";

        return AssistantDeleted{
            .id = try self.allocator.dupe(u8, id),
            .deleted = std.mem.eql(u8, deleted_str, "true"),
        };
    }

    fn parseListResponse(self: *Service, response: []const u8) !AssistantListResponse {
        const data_str = self.parseJsonField(response, "data") orelse return error.ParseError;
        const has_more_str = self.parseJsonField(response, "has_more") orelse "false";

        return AssistantListResponse{
            .data = &.{},
            .has_more = std.mem.eql(u8, has_more_str, "true"),
        };
    }

    fn parseThread(self: *Service, response: []const u8) !Thread {
        const id = self.parseJsonField(response, "id") orelse return error.ParseError;
        const object = self.parseJsonField(response, "object") orelse return error.ParseError;
        const created_at_str = self.parseJsonField(response, "created_at") orelse "0";

        return Thread{
            .id = try self.allocator.dupe(u8, id),
            .object = try self.allocator.dupe(u8, object),
            .created_at = std.fmt.parseInt(i64, created_at_str, 10) catch 0,
        };
    }

    fn parseThreadDeleteResponse(self: *Service, response: []const u8) !ThreadDeleted {
        const id = self.parseJsonField(response, "id") orelse return error.ParseError;
        const deleted_str = self.parseJsonField(response, "deleted") orelse "false";

        return ThreadDeleted{
            .id = try self.allocator.dupe(u8, id),
            .deleted = std.mem.eql(u8, deleted_str, "true"),
        };
    }

    fn parseMessage(self: *Service, response: []const u8) !Message {
        const id = self.parseJsonField(response, "id") orelse return error.ParseError;
        const object = self.parseJsonField(response, "object") orelse return error.ParseError;
        const created_at_str = self.parseJsonField(response, "created_at") orelse "0";
        const thread_id = self.parseJsonField(response, "thread_id") orelse return error.ParseError;
        const role = self.parseJsonField(response, "role") orelse return error.ParseError;
        const content_str = self.parseJsonField(response, "content") orelse return error.ParseError;

        // Parse content array to get text
        const text_start = std.mem.indexOf(u8, content_str, "\"text\":\"") orelse return error.ParseError;
        const text_value_start = text_start + 9;
        const text_end = std.mem.indexOf(u8, content_str[text_value_start..], "\"") orelse return error.ParseError;
        const text = content_str[text_value_start .. text_value_start + text_end];

        return Message{
            .id = try self.allocator.dupe(u8, id),
            .object = try self.allocator.dupe(u8, object),
            .created_at = std.fmt.parseInt(i64, created_at_str, 10) catch 0,
            .thread_id = try self.allocator.dupe(u8, thread_id),
            .role = try self.allocator.dupe(u8, role),
            .content = try self.allocator.dupe(u8, text),
        };
    }

    fn parseMessageListResponse(self: *Service, response: []const u8) !MessageListResponse {
        const has_more_str = self.parseJsonField(response, "has_more") orelse "false";

        return MessageListResponse{
            .data = &.{},
            .has_more = std.mem.eql(u8, has_more_str, "true"),
        };
    }

    fn parseRun(self: *Service, response: []const u8) !Run {
        const id = self.parseJsonField(response, "id") orelse return error.ParseError;
        const object = self.parseJsonField(response, "object") orelse return error.ParseError;
        const created_at_str = self.parseJsonField(response, "created_at") orelse "0";
        const thread_id = self.parseJsonField(response, "thread_id") orelse return error.ParseError;
        const assistant_id_str = self.parseJsonField(response, "assistant_id") orelse return error.ParseError;
        const status = self.parseJsonField(response, "status") orelse return error.ParseError;

        return Run{
            .id = try self.allocator.dupe(u8, id),
            .object = try self.allocator.dupe(u8, object),
            .created_at = std.fmt.parseInt(i64, created_at_str, 10) catch 0,
            .thread_id = try self.allocator.dupe(u8, thread_id),
            .assistant_id = try self.allocator.dupe(u8, assistant_id_str),
            .status = try self.allocator.dupe(u8, status),
        };
    }

    fn parseRunListResponse(self: *Service, response: []const u8) !RunListResponse {
        const has_more_str = self.parseJsonField(response, "has_more") orelse "false";

        return RunListResponse{
            .data = &.{},
            .has_more = std.mem.eql(u8, has_more_str, "true"),
        };
    }

    fn parseJsonField(self: *Service, json_str: []const u8, field_name: []const u8) ?[]const u8 {
        _ = self;
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
        } else if (json_str[i] == '{') {
            var depth: u32 = 1;
            i += 1;
            while (i < json_str.len and depth > 0) {
                if (json_str[i] == '{') depth += 1;
                if (json_str[i] == '}') depth -= 1;
                i += 1;
            }
            return json_str[value_start..i];
        } else if (json_str[i] == '[') {
            var depth: u32 = 1;
            i += 1;
            while (i < json_str.len and depth > 0) {
                if (json_str[i] == '[') depth += 1;
                if (json_str[i] == ']') depth -= 1;
                i += 1;
            }
            return json_str[value_start..i];
        } else {
            const num_start = i;
            while (i < json_str.len and (std.ascii.isDigit(json_str[i]) or json_str[i] == '.' or json_str[i] == '-' or json_str[i] == 'e' or json_str[i] == 'E')) {
                i += 1;
            }
            return json_str[num_start..i];
        }
    }
};

// ============================================================================
// Request Types
// ============================================================================

pub const AssistantCreateParams = struct {
    model: []const u8,
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    instructions: ?[]const u8 = null,
};

pub const AssistantModifyParams = struct {
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    instructions: ?[]const u8 = null,
};

pub const AssistantListParams = struct {
    limit: ?u32 = null,
    order: ?[]const u8 = null,
    after: ?[]const u8 = null,
    before: ?[]const u8 = null,
};

pub const ThreadCreateParams = struct {
    metadata: ?[]const u8 = null,
};

pub const ThreadModifyParams = struct {
    metadata: ?[]const u8 = null,
};

pub const MessageCreateParams = struct {
    role: []const u8,
    content: []const u8,
};

pub const MessageListParams = struct {
    limit: ?u32 = null,
    order: ?[]const u8 = null,
    after: ?[]const u8 = null,
    before: ?[]const u8 = null,
};

pub const RunCreateParams = struct {
    assistant_id: []const u8,
};

pub const RunListParams = struct {
    limit: ?u32 = null,
};

// ============================================================================
// Response Types
// ============================================================================

pub const Assistant = struct {
    id: []const u8,
    object: []const u8,
    created_at: i64,
    model: []const u8,
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    instructions: ?[]const u8 = null,
};

pub const AssistantDeleted = struct {
    id: []const u8,
    deleted: bool,
};

pub const AssistantListResponse = struct {
    data: []Assistant,
    has_more: bool,
};

pub const Thread = struct {
    id: []const u8,
    object: []const u8,
    created_at: i64,
};

pub const ThreadDeleted = struct {
    id: []const u8,
    deleted: bool,
};

pub const Message = struct {
    id: []const u8,
    object: []const u8,
    created_at: i64,
    thread_id: []const u8,
    role: []const u8,
    content: []const u8,
};

pub const MessageListResponse = struct {
    data: []Message,
    has_more: bool,
};

pub const Run = struct {
    id: []const u8,
    object: []const u8,
    created_at: i64,
    thread_id: []const u8,
    assistant_id: []const u8,
    status: []const u8,
};

pub const RunListResponse = struct {
    data: []Run,
    has_more: bool,
};
