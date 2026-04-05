//! Realtime API - WebSocket-based real-time communication
//!
//! Reference: https://platform.openai.com/docs/api-reference/realtime
//!
//! The Realtime API enables bidirectional communication with OpenAI models
//! over WebSockets, supporting audio streaming, function calls, and more.

const std = @import("std");

// ============================================================================
// Realtime Client
// ============================================================================

pub const RealtimeClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    api_key: []const u8,
    model: []const u8,
    connection: ?RealtimeConnection,
    event_handlers: std.StringHashMap(RealtimeEventHandler),

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8, model: []const u8) RealtimeClient {
        return .{
            .allocator = allocator,
            .base_url = "wss://api.openai.com/v1/realtime",
            .api_key = api_key,
            .model = model,
            .connection = null,
            .event_handlers = std.StringHashMap(RealtimeEventHandler).init(allocator),
        };
    }

    pub fn deinit(self: *RealtimeClient) void {
        if (self.connection) |conn| {
            conn.close();
        }
        self.event_handlers.deinit();
    }

    /// Connect to the Realtime API
    pub fn connect(self: *RealtimeClient) !void {
        // In a full implementation, this would establish a WebSocket connection
        // For now, we create a placeholder connection
        self.connection = RealtimeConnection{
            .allocator = self.allocator,
            .url = try std.fmt.allocPrint(self.allocator, "{s}?model={s}", .{
                self.base_url, self.model,
            }),
            .connected = false,
        };
    }

    /// Disconnect from the Realtime API
    pub fn disconnect(self: *RealtimeClient) void {
        if (self.connection) |conn| {
            conn.close();
            self.connection = null;
        }
    }

    /// Send a session update event
    pub fn updateSession(self: *RealtimeClient, params: SessionUpdateParams) !void {
        if (self.connection) |conn| {
            const event_json = try serializeSessionUpdate(self.allocator, params);
            defer self.allocator.free(event_json);
            try conn.send(event_json);
        }
    }

    /// Send a conversation item to the model
    pub fn sendItem(self: *RealtimeClient, item: InputItem) !void {
        if (self.connection) |conn| {
            const event_json = try serializeInputItem(self.allocator, item);
            defer self.allocator.free(event_json);
            try conn.send(event_json);
        }
    }

    /// Create a response (triggers model to generate output)
    pub fn createResponse(self: *RealtimeClient) !void {
        if (self.connection) |conn| {
            try conn.send("{\"type\":\"response.create\"}");
        }
    }

    /// Register an event handler
    pub fn on(self: *RealtimeClient, event_type: []const u8, handler: RealtimeEventHandler) !void {
        const key = try self.allocator.dupe(u8, event_type);
        errdefer self.allocator.free(key);
        try self.event_handlers.put(key, handler);
    }

    /// Handle incoming events (call this when data is received)
    pub fn handleEvent(self: *RealtimeClient, event_json: []const u8) !void {
        const event_type = extractEventType(event_json);
        if (event_type) |etype| {
            if (self.event_handlers.get(etype)) |handler| {
                try handler(self.allocator, event_json);
            }
        }
    }
};

// ============================================================================
// Realtime Connection
// ============================================================================

pub const RealtimeConnection = struct {
    allocator: std.mem.Allocator,
    url: []const u8,
    connected: bool,

    pub fn close(self: *RealtimeConnection) void {
        self.allocator.free(self.url);
        self.connected = false;
    }

    pub fn send(self: *RealtimeConnection, data: []const u8) !void {
        // In a full implementation, this would send data over WebSocket
        _ = data;
        if (!self.connected) return error.NotConnected;
    }

    pub fn receive(self: *RealtimeConnection) ![]u8 {
        // In a full implementation, this would receive data from WebSocket
        if (!self.connected) return error.NotConnected;
        return "";
    }
};

// ============================================================================
// Event Types
// ============================================================================

pub const RealtimeEvent = union(enum) {
    session_updated: SessionUpdatedEvent,
    conversation_created: ConversationCreatedEvent,
    conversation_item_created: ItemCreatedEvent,
    conversation_item_deleted: ItemDeletedEvent,
    response_created: ResponseCreatedEvent,
    response_done: ResponseDoneEvent,
    response_audio_transcript_done: AudioTranscriptDoneEvent,
    response_audio_done: AudioDoneEvent,
    realtime_error: RealtimeErrorEvent,
};

pub const SessionUpdatedEvent = struct {
    session: Session,
};

pub const ConversationCreatedEvent = struct {
    conversation: Conversation,
};

pub const ItemCreatedEvent = struct {
    item: InputItem,
};

pub const ItemDeletedEvent = struct {
    item_id: []const u8,
};

pub const ResponseCreatedEvent = struct {
    response: Response,
};

pub const ResponseDoneEvent = struct {
    response: Response,
};

pub const AudioTranscriptDoneEvent = struct {
    transcript: []const u8,
};

pub const AudioDoneEvent = struct {
    // No additional data
};

pub const RealtimeErrorEvent = struct {
    err: ErrorDetails,
};

pub const ErrorDetails = struct {
    code: []const u8,
    message: []const u8,
};

pub const Session = struct {
    id: []const u8,
    model: []const u8,
    expires_at: i64,
};

pub const Conversation = struct {
    id: []const u8,
};

pub const Response = struct {
    id: []const u8,
    status: []const u8,
};

pub const InputItem = union(enum) {
    message: MessageItem,
    function_call: FunctionCallItem,
};

pub const MessageItem = struct {
    role: []const u8, // "user" or "assistant"
    content: []const u8,
};

pub const FunctionCallItem = struct {
    call_id: []const u8,
    name: []const u8,
    arguments: []const u8,
};

// ============================================================================
// Request Types
// ============================================================================

pub const SessionUpdateParams = struct {
    modalities: ?[]const []const u8 = null, // ["text", "audio"]
    instructions: ?[]const u8 = null,
    voice: ?[]const u8 = null, // "alloy", "echo", "shimmer"
    input_audio_transcription: ?InputAudioTranscription = null,
    turn_detection: ?TurnDetection = null,
};

pub const InputAudioTranscription = struct {
    model: []const u8,
};

pub const TurnDetection = struct {
    type: []const u8 = "server_vad",
    threshold: ?f32 = null,
    prefix_padding_ms: ?u32 = null,
    silence_duration_ms: ?u32 = null,
};

// ============================================================================
// Event Handler
// ============================================================================

pub const RealtimeEventHandler = fn (allocator: std.mem.Allocator, event: []const u8) anyerror!void;

// ============================================================================
// Serialization Helpers
// ============================================================================

fn serializeSessionUpdate(allocator: std.mem.Allocator, params: SessionUpdateParams) ![]u8 {
    var parts = std.ArrayList(u8).init(allocator);
    defer parts.deinit();

    try parts.appendSlice(`{"type":"session.update","session":{`);

    var first = true;

    if (params.modalities) |m| {
        if (!first) try parts.appendSlice(",");
        first = false;
        try parts.appendSlice(`"modalities":[`);
        for (m, 0..) |modality, i| {
            if (i > 0) try parts.appendSlice(",");
            try parts.appendSlice(`"`);
            try parts.appendSlice(modality);
            try parts.appendSlice(`"`);
        }
        try parts.appendSlice("]");
    }

    if (params.instructions) |inst| {
        if (!first) try parts.appendSlice(",");
        first = false;
        try parts.appendSlice(`"instructions":"`);
        try parts.appendSlice(inst);
        try parts.appendSlice(`"`);
    }

    if (params.voice) |v| {
        if (!first) try parts.appendSlice(",");
        try parts.appendSlice(`"voice":"`);
        try parts.appendSlice(v);
        try parts.appendSlice(`"`);
    }

    try parts.appendSlice("}}");

    return parts.toOwnedSlice();
}

fn serializeInputItem(allocator: std.mem.Allocator, item: InputItem) ![]u8 {
    return switch (item) {
        .message => |msg| std.fmt.allocPrint(allocator,
            \\{{"type":"conversation.item.create","item":{{"type":"message","role":"{s}","content":[{{"type":"input_text","text":"{s}"}}]}}}}
        , .{ msg.role, msg.content }),
        .function_call => |fc| std.fmt.allocPrint(allocator,
            \\{{"type":"conversation.item.create","item":{{"type":"function_call","call_id":"{s}","name":"{s}","arguments":"{s}"}}}}
        , .{ fc.call_id, fc.name, fc.arguments }),
    };
}

fn extractEventType(event_json: []const u8) ?[]const u8 {
    const type_start = std.mem.indexOf(u8, event_json, "\"type\":\"") orelse return null;
    const value_start = type_start + 8;
    var value_end = value_start;
    while (value_end < event_json.len and event_json[value_end] != '"') {
        value_end += 1;
    }
    return event_json[value_start..value_end];
}

// ============================================================================
// Audio Streaming Support
// ============================================================================

pub const AudioStreamHandler = struct {
    allocator: std.mem.Allocator,
    client: *RealtimeClient,
    audio_buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, client: *RealtimeClient) AudioStreamHandler {
        return .{
            .allocator = allocator,
            .client = client,
            .audio_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *AudioStreamHandler) void {
        self.audio_buffer.deinit();
    }

    /// Send audio data
    pub fn sendAudio(self: *AudioStreamHandler, audio_data: []const u8) !void {
        // In a full implementation, this would send audio to the WebSocket
        try self.audio_buffer.appendSlice(audio_data);
    }

    /// Receive audio data
    pub fn receiveAudio(self: *AudioStreamHandler) ![]u8 {
        // In a full implementation, this would receive audio from the WebSocket
        return self.audio_buffer.items;
    }
};