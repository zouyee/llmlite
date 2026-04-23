//! Webhooks - Event handling for asynchronous operations
//!
//! Reference: https://platform.openai.com/docs/api-reference/webhooks
//!
//! Webhooks allow you to receive notifications when asynchronous operations
//! complete, such as batch processing or fine-tuning jobs.

const std = @import("std");
const time_compat = @import("time_compat");
const json = std.json;

// ============================================================================
// Webhook Event Types
// ============================================================================

pub const WebhookEventType = enum {
    batch_completed,
    batch_failed,
    fine_tuning_completed,
    message_created,
    message_done,
    response_created,
};

pub const WebhookEvent = union(WebhookEventType) {
    batch_completed: BatchCompletedEvent,
    batch_failed: BatchFailedEvent,
    fine_tuning_completed: FineTuningCompletedEvent,
    message_created: MessageCreatedEvent,
    message_done: MessageDoneEvent,
    response_created: ResponseCreatedEvent,
};

pub const BatchCompletedEvent = struct {
    id: []const u8,
    object: []const u8,
    completion_window: []const u8,
    created_at: i64,
    status: []const u8,
};

pub const BatchFailedEvent = struct {
    id: []const u8,
    object: []const u8,
    err: WebhookError,
};

pub const FineTuningCompletedEvent = struct {
    id: []const u8,
    object: []const u8,
    status: []const u8,
    trained_tokens: u32,
};

pub const MessageCreatedEvent = struct {
    id: []const u8,
    object: []const u8,
    created_at: i64,
    thread_id: []const u8,
};

pub const MessageDoneEvent = struct {
    id: []const u8,
    object: []const u8,
    created_at: i64,
    thread_id: []const u8,
    status: []const u8,
};

pub const ResponseCreatedEvent = struct {
    id: []const u8,
    object: []const u8,
    created_at: i64,
};

pub const WebhookError = struct {
    code: []const u8,
    message: []const u8,
    param: ?[]const u8 = null,
};

// ============================================================================
// Webhook Parser
// ============================================================================

pub const WebhookParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WebhookParser {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *WebhookParser) void {
        _ = self;
    }

    /// Parse a webhook event from JSON payload
    pub fn parse(self: *WebhookParser, payload: []const u8) !WebhookEvent {
        // Parse as generic JSON to extract event type
        const parsed = try json.parseFromSlice(json.Value, self.allocator, payload, .{});
        defer parsed.deinit();

        const root = parsed.value;
        const obj = root.object;

        // Extract event type
        const event_type_value = obj.get("event") orelse return error.MissingEventType;
        const event_type = event_type_value.string;

        // Extract data
        const data_value = obj.get("data") orelse return error.MissingData;
        const data_obj = data_value.object;

        if (std.mem.eql(u8, event_type, "batch.completed")) {
            return WebhookEvent{ .batch_completed = try self.parseBatchCompleted(data_obj) };
        } else if (std.mem.eql(u8, event_type, "batch.failed")) {
            return WebhookEvent{ .batch_failed = try self.parseBatchFailed(data_obj) };
        } else if (std.mem.eql(u8, event_type, "fine_tuning.job.completed")) {
            return WebhookEvent{ .fine_tuning_completed = try self.parseFineTuningCompleted(data_obj) };
        } else if (std.mem.eql(u8, event_type, "thread.message.created")) {
            return WebhookEvent{ .message_created = try self.parseMessageCreated(data_obj) };
        } else if (std.mem.eql(u8, event_type, "thread.message.done")) {
            return WebhookEvent{ .message_done = try self.parseMessageDone(data_obj) };
        } else if (std.mem.eql(u8, event_type, "response.created")) {
            return WebhookEvent{ .response_created = try self.parseResponseCreated(data_obj) };
        }

        return error.UnknownEventType;
    }

    fn parseBatchCompleted(self: *WebhookParser, obj: std.json.ObjectMap) !BatchCompletedEvent {
        return BatchCompletedEvent{
            .id = try self.getString(obj, "id"),
            .object = try self.getString(obj, "object"),
            .completion_window = self.getStringOr(obj, "completion_window", "24h"),
            .created_at = self.getI64(obj, "created_at"),
            .status = try self.getString(obj, "status"),
        };
    }

    fn parseBatchFailed(self: *WebhookParser, obj: std.json.ObjectMap) !BatchFailedEvent {
        const error_obj = obj.get("error") orelse return error.MissingError;
        const error_map = error_obj.object;

        return BatchFailedEvent{
            .id = try self.getString(obj, "id"),
            .object = try self.getString(obj, "object"),
            .err = WebhookError{
                .code = try self.getString(error_map, "code"),
                .message = try self.getString(error_map, "message"),
                .param = self.getStringOpt(error_map, "param"),
            },
        };
    }

    fn parseFineTuningCompleted(self: *WebhookParser, obj: std.json.ObjectMap) !FineTuningCompletedEvent {
        return FineTuningCompletedEvent{
            .id = try self.getString(obj, "id"),
            .object = try self.getString(obj, "object"),
            .status = try self.getString(obj, "status"),
            .trained_tokens = @intCast(self.getI64(obj, "trained_tokens")),
        };
    }

    fn parseMessageCreated(self: *WebhookParser, obj: std.json.ObjectMap) !MessageCreatedEvent {
        return MessageCreatedEvent{
            .id = try self.getString(obj, "id"),
            .object = try self.getString(obj, "object"),
            .created_at = self.getI64(obj, "created_at"),
            .thread_id = self.getStringOr(obj, "thread_id", ""),
        };
    }

    fn parseMessageDone(self: *WebhookParser, obj: std.json.ObjectMap) !MessageDoneEvent {
        return MessageDoneEvent{
            .id = try self.getString(obj, "id"),
            .object = try self.getString(obj, "object"),
            .created_at = self.getI64(obj, "created_at"),
            .thread_id = self.getStringOr(obj, "thread_id", ""),
            .status = try self.getString(obj, "status"),
        };
    }

    fn parseResponseCreated(self: *WebhookParser, obj: std.json.ObjectMap) !ResponseCreatedEvent {
        return ResponseCreatedEvent{
            .id = try self.getString(obj, "id"),
            .object = try self.getString(obj, "object"),
            .created_at = self.getI64(obj, "created_at"),
        };
    }

    fn getString(self: *WebhookParser, obj: std.json.ObjectMap, key: []const u8) ![]const u8 {
        const value = obj.get(key) orelse return error.MissingKey;
        return try self.allocator.dupe(u8, value.string);
    }

    fn getStringOpt(self: *WebhookParser, obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
        if (obj.get(key)) |value| {
            return self.allocator.dupe(u8, value.string) catch null;
        }
        return null;
    }

    fn getStringOr(self: *WebhookParser, obj: std.json.ObjectMap, key: []const u8, default: []const u8) []const u8 {
        if (obj.get(key)) |value| {
            return value.string;
        }
        return default;
    }

    fn getI64(self: *WebhookParser, obj: std.json.ObjectMap, key: []const u8) i64 {
        if (obj.get(key)) |value| {
            return @intCast(value.integer);
        }
        return 0;
    }
};

// ============================================================================
// Webhook Handler
// ============================================================================

pub const WebhookHandler = struct {
    allocator: std.mem.Allocator,
    secret: ?[]const u8,
    parser: WebhookParser,

    pub fn init(allocator: std.mem.Allocator, secret: ?[]const u8) WebhookHandler {
        return .{
            .allocator = allocator,
            .secret = secret,
            .parser = WebhookParser.init(allocator),
        };
    }

    pub fn deinit(self: *WebhookHandler) void {
        self.parser.deinit();
        if (self.secret) |s| self.allocator.free(s);
    }

    /// Verify webhook signature
    pub fn verifySignature(self: *const WebhookHandler, payload: []const u8, signature: []const u8) bool {
        if (self.secret) |secret| {
            // In a real implementation, this would use HMAC-SHA256
            // For now, just check if signature is present
            return signature.len > 0;
        }
        return true; // No secret configured, skip verification
    }

    /// Handle incoming webhook request
    pub fn handle(self: *WebhookHandler, payload: []const u8, signature: ?[]const u8) !WebhookEvent {
        if (signature) |sig| {
            if (!self.verifySignature(payload, sig)) {
                return error.InvalidSignature;
            }
        }

        return try self.parser.parse(payload);
    }
};

// ============================================================================
// Webhook Event Dispatcher
// ============================================================================

pub const EventDispatcher = struct {
    allocator: std.mem.Allocator,
    handlers: std.StringHashMap(EventHandlerFunc),

    pub const EventHandlerFunc = fn (allocator: std.mem.Allocator, event: WebhookEvent) anyerror!void;

    pub fn init(allocator: std.mem.Allocator) EventDispatcher {
        return .{
            .allocator = allocator,
            .handlers = std.StringHashMap(EventHandlerFunc).init(allocator),
        };
    }

    pub fn deinit(self: *EventDispatcher) void {
        self.handlers.deinit();
    }

    /// Register a handler for a specific event type
    pub fn register(self: *EventDispatcher, event_type: []const u8, handler: EventHandlerFunc) !void {
        const key = try self.allocator.dupe(u8, event_type);
        errdefer self.allocator.free(key);
        try self.handlers.put(key, handler);
    }

    /// Dispatch an event to the appropriate handler
    pub fn dispatch(self: *EventDispatcher, event: WebhookEvent) !void {
        const event_type = self.getEventType(event);
        if (self.handlers.get(event_type)) |handler| {
            try handler(self.allocator, event);
        }
    }

    fn getEventType(self: *EventDispatcher, event: WebhookEvent) []const u8 {
        _ = self;
        return switch (event) {
            .batch_completed => "batch.completed",
            .batch_failed => "batch.failed",
            .fine_tuning_completed => "fine_tuning.job.completed",
            .message_created => "thread.message.created",
            .message_done => "thread.message.done",
            .response_created => "response.created",
        };
    }
};

// ============================================================================
// Webhook Verification Helper
// ============================================================================

pub const WebhookVerifier = struct {
    /// Create a webhook signature for testing (development use only)
    pub fn createSignature(payload: []const u8, secret: []const u8) ![]u8 {
        // In production, use HMAC-SHA256
        // This is a placeholder that just returns the payload hash
        var hash: [32]u8 = undefined;
        for (payload, 0..) |byte, i| {
            hash[i % 32] ^= byte;
        }

        var result: [64]u8 = undefined;
        for (hash, 0..) |byte, i| {
            std.fmt.formatIntHex(byte, 2, .lower, &result[i * 2 .. i * 2 + 2]);
        }

        return &result;
    }

    /// Verify timestamp to prevent replay attacks
    pub fn isTimestampValid(io: std.Io, timestamp: i64, max_age_seconds: i64) bool {
        const now = time_compat.timestamp(io);
        return @abs(now - timestamp) < max_age_seconds;
    }
};
