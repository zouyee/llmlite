//! SSE Streaming - Server-Sent Events parsing for OpenAI streaming
//!
//! Reference: https://platform.openai.com/docs/api-reference/responses/stream
//!
//! This module provides:
//! - SSE event parsing
//! - Delta accumulation
//! - Streaming response handling

const std = @import("std");

// ============================================================================
// SSE Event Types
// ============================================================================

pub const SSEEvent = struct {
    event: ?[]const u8 = null,
    data: []const u8,
    id: ?[]const u8 = null,
    retry: ?u32 = null,
};

pub const StreamChunk = struct {
    index: u32,
    delta: []const u8,
    type: []const u8,
};

// ============================================================================
// SSE Parser
// ============================================================================

pub const SSEParser = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8),

    pub fn init(allocator: std.mem.Allocator) SSEParser {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayListUnmanaged(u8){},
        };
    }

    pub fn deinit(self: *SSEParser) void {
        self.buffer.deinit(self.allocator);
    }

    /// Feed more data to the parser
    pub fn feed(self: *SSEParser, data: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, data);
    }

    /// Parse all complete events from the buffer
    pub fn parseEvents(self: *SSEParser) ![]SSEEvent {
        var events = std.ArrayListUnmanaged(SSEEvent){};
        errdefer events.deinit(self.allocator);

        var start_idx: usize = 0;
        while (start_idx < self.buffer.items.len) {
            // Find end of event (double newline)
            const end_idx = findEventEnd(self.buffer.items[start_idx..]) orelse break;

            const event_data = self.buffer.items[start_idx .. start_idx + end_idx];
            if (event_data.len > 0) {
                const event = try parseEventData(self.allocator, event_data);
                try events.append(self.allocator, event);
            }

            start_idx += end_idx + 2; // Skip double newline
        }

        // Remove processed data from buffer
        if (start_idx > 0) {
            const remaining = try self.buffer.toOwnedSlice(self.allocator);
            defer self.allocator.free(remaining);
            try self.buffer.appendSlice(self.allocator, remaining[start_idx..]);
        }

        return try events.toOwnedSlice(self.allocator);
    }

    /// Parse a single line of SSE data
    fn parseEventData(allocator: std.mem.Allocator, data: []const u8) !SSEEvent {
        var event = SSEEvent{ .data = "" };

        var lines = std.mem.split(u8, data, "\n");
        while (lines.next()) |line| {
            if (line.len < 2) continue;

            if (std.mem.startsWith(u8, line, "event:")) {
                const value = trim(line[6..]);
                event.event = try allocator.dupe(u8, value);
            } else if (std.mem.startsWith(u8, line, "data:")) {
                const value = trim(line[5..]);
                event.data = try allocator.dupe(u8, value);
            } else if (std.mem.startsWith(u8, line, "id:")) {
                const value = trim(line[3..]);
                event.id = try allocator.dupe(u8, value);
            } else if (std.mem.startsWith(u8, line, "retry:")) {
                const value = trim(line[7..]);
                event.retry = std.fmt.parseInt(u32, value, 10) catch null;
            }
        }

        return event;
    }
};

fn findEventEnd(data: []const u8) ?usize {
    var i: usize = 0;
    while (i < data.len) {
        if (i + 1 < data.len and data[i] == '\n' and data[i + 1] == '\n') {
            return i;
        }
        if (i + 1 < data.len and data[i] == '\r' and data[i + 1] == '\n') {
            if (i + 3 < data.len and data[i + 2] == '\r' and data[i + 3] == '\n') {
                return i + 2;
            }
        }
        i += 1;
    }
    return null;
}

fn trim(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and (s[start] == ' ' or s[start] == '\t')) {
        start += 1;
    }
    var end = s.len;
    while (end > start and (s[end - 1] == ' ' or s[end - 1] == '\t')) {
        end -= 1;
    }
    return s[start..end];
}

// ============================================================================
// Streaming Response Handler
// ============================================================================

pub const StreamHandler = struct {
    allocator: std.mem.Allocator,
    parser: SSEParser,
    accumulated_text: std.ArrayListUnmanaged(u8),
    chunks: std.ArrayListUnmanaged(StreamChunk),

    pub fn init(allocator: std.mem.Allocator) StreamHandler {
        return .{
            .allocator = allocator,
            .parser = SSEParser.init(allocator),
            .accumulated_text = std.ArrayListUnmanaged(u8){},
            .chunks = std.ArrayListUnmanaged(StreamChunk){},
        };
    }

    pub fn deinit(self: *StreamHandler) void {
        self.parser.deinit();
        self.accumulated_text.deinit(self.allocator);
        for (self.chunks.items) |chunk| {
            self.allocator.free(chunk.delta);
        }
        self.chunks.deinit(self.allocator);
    }

    /// Process streaming data
    pub fn feed(self: *StreamHandler, data: []const u8) !void {
        try self.parser.feed(data);

        const events = try self.parser.parseEvents();
        defer {
            for (events) |e| {
                self.allocator.free(e.data);
                if (e.event) |ev| self.allocator.free(ev);
                if (e.id) |id| self.allocator.free(id);
            }
            self.allocator.free(events);
        }

        for (events) |event| {
            try self.processEvent(event);
        }
    }

    fn processEvent(self: *StreamHandler, event: SSEEvent) !void {
        // Skip ping events
        if (std.mem.eql(u8, event.data, "[DONE]")) {
            return;
        }

        // Parse the SSE data format: "0:\"...\"\n\n"
        // Or JSON format for chat completions
        if (parseSSEData(event.data)) |delta| {
            defer self.allocator.free(delta);

            try self.accumulated_text.appendSlice(self.allocator, delta);

            const chunk = StreamChunk{
                .index = @as(u32, @intCast(self.chunks.items.len)),
                .delta = try self.allocator.dupe(u8, delta),
                .type = "content_delta",
            };
            try self.chunks.append(self.allocator, chunk);
        }
    }

    /// Get accumulated text
    pub fn getText(self: *StreamHandler) []const u8 {
        return self.accumulated_text.items;
    }

    /// Get all chunks
    pub fn getChunks(self: *StreamHandler) []const StreamChunk {
        return self.chunks.items;
    }

    /// Check if streaming is complete
    pub fn isComplete(self: *StreamHandler) bool {
        return self.parser.buffer.items.len == 0;
    }
};

/// Parse SSE data format (0:"text"\n\n)
fn parseSSEData(data: []const u8) ?[]const u8 {
    // Format: 0:"content"
    if (data.len >= 4 and data[1] == ':' and data[2] == '"') {
        const start = 3;
        var end = start;
        while (end < data.len and data[end] != '"') {
            end += 1;
        }
        return data[start..end];
    }

    // Try JSON format
    return extractTextFromJson(data);
}

/// Extract text delta from JSON format
fn extractTextFromJson(data: []const u8) ?[]const u8 {
    // Look for "content":"text" pattern
    const content_start = std.mem.indexOf(u8, data, "\"content\":\"") orelse return null;
    const value_start = content_start + 11;
    var value_end = value_start;
    while (value_end < data.len and data[value_end] != '"') {
        value_end += 1;
    }
    return data[value_start..value_end];
}

// ============================================================================
// Chat Completion Streaming
// ============================================================================

pub const ChatStreamHandler = struct {
    allocator: std.mem.Allocator,
    handler: StreamHandler,

    pub fn init(allocator: std.mem.Allocator) ChatStreamHandler {
        return .{
            .allocator = allocator,
            .handler = StreamHandler.init(allocator),
        };
    }

    pub fn deinit(self: *ChatStreamHandler) void {
        self.handler.deinit();
    }

    pub fn feed(self: *ChatStreamHandler, data: []const u8) !void {
        try self.handler.feed(data);
    }

    pub fn getText(self: *ChatStreamHandler) []const u8 {
        return self.handler.getText();
    }

    pub fn getChunks(self: *ChatStreamHandler) []const StreamChunk {
        return self.handler.getChunks();
    }
};

// ============================================================================
// Response Streaming (new API)
// ============================================================================

pub const ResponseStreamHandler = struct {
    allocator: std.mem.Allocator,
    handler: StreamHandler,
    output_items: std.ArrayListUnmanaged(ResponseOutputItemPartial),

    pub fn init(allocator: std.mem.Allocator) ResponseStreamHandler {
        return .{
            .allocator = allocator,
            .handler = StreamHandler.init(allocator),
            .output_items = std.ArrayListUnmanaged(ResponseOutputItemPartial){},
        };
    }

    pub fn deinit(self: *ResponseStreamHandler) void {
        self.handler.deinit();
        for (self.output_items.items) |item| {
            self.allocator.free(item.id);
            if (item.content) |c| self.allocator.free(c);
            if (item.name) |n| self.allocator.free(n);
            if (item.arguments) |a| self.allocator.free(a);
        }
        self.output_items.deinit(self.allocator);
    }

    pub fn feed(self: *ResponseStreamHandler, data: []const u8) !void {
        try self.handler.feed(data);

        const events = try self.handler.parser.parseEvents();
        defer {
            for (events) |e| {
                self.allocator.free(e.data);
                if (e.event) |ev| self.allocator.free(ev);
                if (e.id) |id| self.allocator.free(id);
            }
            self.allocator.free(events);
        }

        for (events) |event| {
            try self.processResponseEvent(event);
        }
    }

    fn processResponseEvent(self: *ResponseStreamHandler, event: SSEEvent) !void {
        if (std.mem.eql(u8, event.data, "[DONE]")) {
            return;
        }

        // Parse response-specific events
        if (event.event) |ev| {
            if (std.mem.eql(u8, ev, "response.output_item.added")) {
                // New output item added
                const id = extractFieldFromJson(event.data, "id") orelse return;
                try self.output_items.append(self.allocator, .{
                    .id = try self.allocator.dupe(u8, id),
                    .index = self.output_items.items.len,
                });
            } else if (std.mem.eql(u8, ev, "response.content_part.added")) {
                // Content part added
                const index_str = extractFieldFromJson(event.data, "index") orelse return;
                const index = std.fmt.parseInt(u32, index_str, 10) catch return;

                // Update the item at index
                if (index < self.output_items.items.len) {
                    const content = extractTextDeltaFromEvent(event.data) orelse return;
                    self.output_items.items[index].content = try self.allocator.dupe(u8, content);
                }
            } else if (std.mem.eql(u8, ev, "response.content_part.done")) {
                // Content part done
            } else if (std.mem.eql(u8, ev, "response.output_item.done")) {
                // Output item done
            } else if (std.mem.eql(u8, ev, "response.done")) {
                // Response done
            }
        } else {
            // Text delta event (no event type)
            if (extractTextDeltaFromEvent(event.data)) |delta| {
                // Append to last item or create new text item
                if (self.output_items.items.len == 0) {
                    try self.output_items.append(self.allocator, .{
                        .id = try self.allocator.dupe(u8, "text"),
                        .index = 0,
                        .content = try self.allocator.dupe(u8, delta),
                    });
                } else {
                    const last_idx = self.output_items.items.len - 1;
                    const last = &self.output_items.items[last_idx];
                    const new_content = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{
                        if (last.content) |c| c else "", delta,
                    });
                    if (last.content) |c| self.allocator.free(c);
                    last.content = new_content;
                }
            }
        }
    }

    pub fn getOutputItems(self: *ResponseStreamHandler) []const ResponseOutputItemPartial {
        return self.output_items.items;
    }
};

pub const ResponseOutputItemPartial = struct {
    id: []const u8,
    index: u32,
    type: ?[]const u8 = null,
    content: ?[]const u8 = null,
    name: ?[]const u8 = null,
    arguments: ?[]const u8 = null,
};

fn extractFieldFromJson(data: []const u8, field: []const u8) ?[]const u8 {
    const pattern = std.fmt.comptimePrint("{s}\":\"", .{field});
    const start = std.mem.indexOf(u8, data, pattern) orelse return null;
    const value_start = start + pattern.len;
    var value_end = value_start;
    while (value_end < data.len and data[value_end] != '"') {
        value_end += 1;
    }
    return data[value_start..value_end];
}

fn extractTextDeltaFromEvent(data: []const u8) ?[]const u8 {
    // Try "delta":"text" pattern
    const delta_start = std.mem.indexOf(u8, data, "\"delta\":\"") orelse return null;
    const value_start = delta_start + 9;
    var value_end = value_start;
    while (value_end < data.len and data[value_end] != '"') {
        value_end += 1;
    }
    return data[value_start..value_end];
}

// ============================================================================
// Async Streaming Support
// ============================================================================

pub const AsyncStreamReader = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8),
    completed: bool,

    pub fn init(allocator: std.mem.Allocator) AsyncStreamReader {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayListUnmanaged(u8){},
            .completed = false,
        };
    }

    pub fn deinit(self: *AsyncStreamReader) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn append(self: *AsyncStreamReader, data: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, data);
    }

    pub fn readLine(self: *AsyncStreamReader) ?[]const u8 {
        for (self.buffer.items, 0..) |byte, i| {
            if (byte == '\n') {
                const line = self.buffer.items[0..i];
                // Remove the line from buffer
                const remaining = self.buffer.items[i + 1 ..];
                self.buffer.shrinkRetainingCapacity(0);
                try self.buffer.appendSlice(self.allocator, remaining);
                return line;
            }
        }
        return null;
    }

    pub fn markComplete(self: *AsyncStreamReader) void {
        self.completed = true;
    }

    pub fn isComplete(self: *AsyncStreamReader) bool {
        return self.completed and self.buffer.items.len == 0;
    }
};
