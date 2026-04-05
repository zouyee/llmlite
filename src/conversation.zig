//! Conversations API - Multi-turn conversation state management
//!
//! Reference: https://platform.openai.com/docs/api-reference/conversations
//!
//! The Conversations API maintains state across multiple turns of interaction,
//! allowing for persistent conversations with the model.

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

    /// Creates a new conversation.
    pub fn create(self: *Service, params: ConversationCreateParams) !Conversation {
        const json_str = try self.serializeCreateParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/conversations", json_str);
        defer self.allocator.free(response);

        return try self.parseConversation(response);
    }

    /// Retrieves a conversation by ID.
    pub fn get(self: *Service, conversation_id: []const u8) !Conversation {
        const path = try std.fmt.allocPrint(self.allocator, "/conversations/{s}", .{conversation_id});
        defer self.allocator.free(path);

        const response = try self.http_client.get(path);
        defer self.allocator.free(response);

        return try self.parseConversation(response);
    }

    /// Lists all conversations.
    pub fn list(self: *Service, params: ?ConversationListParams) !ConversationListResponse {
        var path = std.ArrayList(u8).init(self.allocator);
        defer path.deinit();

        try path.appendSlice("/conversations");

        if (params) |p| {
            var first = true;
            if (p.after) |after| {
                try path.appendSlice(if (first) "?" else "&");
                try path.appendSlice("after=");
                try path.appendSlice(after);
                first = false;
            }
            if (p.limit) |limit| {
                try path.appendSlice(if (first) "?" else "&");
                try path.writer().print("limit={d}", .{limit});
            }
        }

        const response = try self.http_client.get(try path.toOwnedSlice());
        defer self.allocator.free(response);

        return try self.parseListResponse(response);
    }

    /// Deletes a conversation.
    pub fn delete(self: *Service, conversation_id: []const u8) !ConversationDeleted {
        const path = try std.fmt.allocPrint(self.allocator, "/conversations/{s}", .{conversation_id});
        defer self.allocator.free(path);

        const response = try self.http_client.delete(path);
        defer self.allocator.free(response);

        return try self.parseDeleteResponse(response);
    }

    // ============================================================================
    // Items API
    // ============================================================================

    /// Retrieves items in a conversation.
    pub fn listItems(self: *Service, conversation_id: []const u8, params: ?ConversationItemListParams) !ConversationItemListResponse {
        var path = std.ArrayList(u8).init(self.allocator);
        defer path.deinit();

        try path.writer().print("/conversations/{s}/items", .{conversation_id});

        if (params) |p| {
            var first = true;
            if (p.after) |after| {
                try path.appendSlice(if (first) "?" else "&");
                try path.appendSlice("after=");
                try path.appendSlice(after);
                first = false;
            }
            if (p.limit) |limit| {
                try path.appendSlice(if (first) "?" else "&");
                try path.writer().print("limit={d}", .{limit});
            }
            if (p.order) |order| {
                try path.appendSlice(if (first) "?" else "&");
                try path.appendSlice("order=");
                try path.appendSlice(order);
            }
        }

        const response = try self.http_client.get(try path.toOwnedSlice());
        defer self.allocator.free(response);

        return try self.parseItemListResponse(response);
    }

    // ============================================================================
    // Input Items API
    // ============================================================================

    /// Submit feedback for a conversation item.
    pub fn submitFeedback(self: *Service, conversation_id: []const u8, item_id: []const u8, params: FeedbackParams) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/conversations/{s}/items/{s}/feedback", .{ conversation_id, item_id });
        defer self.allocator.free(path);

        const json_str = try self.serializeFeedbackParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post(path, json_str);
        defer self.allocator.free(response);
    }

    // ============================================================================
    // Serialization
    // ============================================================================

    fn serializeCreateParams(self: *Service, params: ConversationCreateParams) ![]u8 {
        _ = self;
        if (params.metadata) |m| {
            return std.fmt.allocPrint(self.allocator,
                \\{{"metadata":{{"topic":"{s}"}}}}
            , .{m});
        }
        return "{\"metadata\":{\"topic\":\"default\"}}";
    }

    fn serializeFeedbackParams(self: *Service, params: FeedbackParams) ![]u8 {
        _ = self;
        return std.fmt.allocPrint(self.allocator,
            \\{{"feedback":"{s}"}}
        , .{params.feedback});
    }

    // ============================================================================
    // Parsing
    // ============================================================================

    fn parseConversation(self: *Service, response: []const u8) !Conversation {
        const id = self.parseJsonField(response, "id") orelse return error.ParseError;
        const object = self.parseJsonField(response, "object") orelse return error.ParseError;
        const metadata_str = self.parseJsonField(response, "metadata");

        return Conversation{
            .id = try self.allocator.dupe(u8, id),
            .object = try self.allocator.dupe(u8, object),
            .metadata = if (metadata_str) |s| try self.allocator.dupe(u8, s) else null,
        };
    }

    fn parseListResponse(self: *Service, response: []const u8) !ConversationListResponse {
        const data_str = self.parseJsonField(response, "data") orelse return error.ParseError;
        const has_more_str = self.parseJsonField(response, "has_more") orelse "false";
        const has_more = std.mem.eql(u8, has_more_str, "true");

        var conversations = std.ArrayListUnmanaged(Conversation){};
        errdefer {
            for (conversations.items) |c| self.freeConversation(c);
            conversations.deinit(self.allocator);
        }

        var search_idx: usize = 0;
        while (search_idx < data_str.len) {
            const obj_start = std.mem.indexOf(u8, data_str[search_idx..], "{") orelse break;
            const obj_end = findMatchingBrace(data_str[search_idx + obj_start ..]) orelse break;
            const conv_json = data_str[search_idx + obj_start .. search_idx + obj_start + obj_end + 1];

            const conv = try self.parseConversation(conv_json);
            try conversations.append(self.allocator, conv);

            search_idx += obj_start + obj_end + 1;
        }

        return ConversationListResponse{
            .data = try conversations.toOwnedSlice(self.allocator),
            .has_more = has_more,
        };
    }

    fn parseItemListResponse(self: *Service, response: []const u8) !ConversationItemListResponse {
        const data_str = self.parseJsonField(response, "data") orelse return error.ParseError;
        const has_more_str = self.parseJsonField(response, "has_more") orelse "false";
        const has_more = std.mem.eql(u8, has_more_str, "true");

        var items = std.ArrayListUnmanaged(ConversationItem){};
        errdefer {
            for (items.items) |item| self.freeConversationItem(item);
            items.deinit(self.allocator);
        }

        var search_idx: usize = 0;
        while (search_idx < data_str.len) {
            const obj_start = std.mem.indexOf(u8, data_str[search_idx..], "{") orelse break;
            const obj_end = findMatchingBrace(data_str[search_idx + obj_start ..]) orelse break;
            const item_json = data_str[search_idx + obj_start .. search_idx + obj_start + obj_end + 1];

            const item = try self.parseConversationItem(item_json);
            try items.append(self.allocator, item);

            search_idx += obj_start + obj_end + 1;
        }

        return ConversationItemListResponse{
            .data = try items.toOwnedSlice(self.allocator),
            .has_more = has_more,
        };
    }

    fn parseConversationItem(self: *Service, json_str: []const u8) !ConversationItem {
        const id = self.parseJsonField(json_str, "id") orelse return error.ParseError;
        const type_str = self.parseJsonField(json_str, "type") orelse return error.ParseError;
        const status = self.parseJsonField(json_str, "status");

        return ConversationItem{
            .id = try self.allocator.dupe(u8, id),
            .type = try self.allocator.dupe(u8, type_str),
            .status = if (status) |s| try self.allocator.dupe(u8, s) else null,
        };
    }

    fn parseDeleteResponse(self: *Service, response: []const u8) !ConversationDeleted {
        const id = self.parseJsonField(response, "id") orelse return error.ParseError;
        const deleted_str = self.parseJsonField(response, "deleted") orelse "false";

        return ConversationDeleted{
            .id = try self.allocator.dupe(u8, id),
            .deleted = std.mem.eql(u8, deleted_str, "true"),
        };
    }

    fn freeConversation(self: *Service, conv: Conversation) void {
        self.allocator.free(conv.id);
        self.allocator.free(conv.object);
        if (conv.metadata) |m| self.allocator.free(m);
    }

    fn freeConversationItem(self: *Service, item: ConversationItem) void {
        self.allocator.free(item.id);
        self.allocator.free(item.type);
        if (item.status) |s| self.allocator.free(s);
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

fn findMatchingBrace(data: []const u8) ?usize {
    if (data.len == 0 or data[0] != '{') return null;
    var depth: u32 = 1;
    var i: usize = 1;
    while (i < data.len and depth > 0) {
        if (data[i] == '{') depth += 1;
        if (data[i] == '}') depth -= 1;
        i += 1;
    }
    if (depth == 0) return i - 1;
    return null;
}

// ============================================================================
// Request Types
// ============================================================================

pub const ConversationCreateParams = struct {
    metadata: ?[]const u8 = null,
};

pub const ConversationListParams = struct {
    after: ?[]const u8 = null,
    limit: ?u32 = null,
};

pub const ConversationItemListParams = struct {
    after: ?[]const u8 = null,
    limit: ?u32 = null,
    order: ?[]const u8 = null, // "asc" or "desc"
};

pub const FeedbackParams = struct {
    feedback: []const u8, // "thumbs_up", "thumbs_down"
};

// ============================================================================
// Response Types
// ============================================================================

pub const Conversation = struct {
    id: []const u8,
    object: []const u8,
    metadata: ?[]const u8 = null,
};

pub const ConversationDeleted = struct {
    id: []const u8,
    deleted: bool,
};

pub const ConversationListResponse = struct {
    data: []Conversation,
    has_more: bool,
};

pub const ConversationItem = struct {
    id: []const u8,
    type: []const u8,
    status: ?[]const u8 = null,
};

pub const ConversationItemListResponse = struct {
    data: []ConversationItem,
    has_more: bool,
};

// ============================================================================
// Conversation Manager - High-level API
// ============================================================================

pub const ConversationManager = struct {
    allocator: std.mem.Allocator,
    service: *Service,
    current_conversation_id: ?[]const u8 = null,
    items: std.ArrayListUnmanaged(ConversationItem),

    pub fn init(allocator: std.mem.Allocator, service: *Service) ConversationManager {
        return .{
            .allocator = allocator,
            .service = service,
            .current_conversation_id = null,
            .items = std.ArrayListUnmanaged(ConversationItem){},
        };
    }

    pub fn deinit(self: *ConversationManager) void {
        if (self.current_conversation_id) |id| {
            self.allocator.free(id);
        }
        for (self.items.items) |item| {
            self.allocator.free(item.id);
            self.allocator.free(item.type);
            if (item.status) |s| self.allocator.free(s);
        }
        self.items.deinit(self.allocator);
    }

    /// Start a new conversation
    pub fn start(self: *ConversationManager, metadata: ?[]const u8) !void {
        const conv = try self.service.create(.{ .metadata = metadata });
        self.current_conversation_id = try self.allocator.dupe(u8, conv.id);
        self.allocator.free(conv.id);
        self.allocator.free(conv.object);
        if (conv.metadata) |m| self.allocator.free(m);
    }

    /// Continue the current conversation
    pub fn continue_(self: *ConversationManager) !void {
        if (self.current_conversation_id) |id| {
            const items_response = try self.service.listItems(id, null);
            // Store items...
            _ = items_response;
        }
    }

    /// Check if there's an active conversation
    pub fn hasActiveConversation(self: *ConversationManager) bool {
        return self.current_conversation_id != null;
    }
};
