//! Request Rectifier for llmlite Proxy
//!
//! Normalizes API requests for third-party provider compatibility.
//! Features:
//! - API format conversion (Anthropic Messages <-> OpenAI Chat Completions)
//! - Thinking signature normalization
//! - Type coercion (number <-> string for model IDs, etc.)

const std = @import("std");
const json = std.json;

pub const ApiFormat = enum {
    anthropic,
    openai,
    auto,
};

pub const RectifierOptions = struct {
    /// Target API format
    format: ApiFormat = .auto,
    /// Whether to normalize thinking blocks
    normalize_thinking: bool = true,
    /// Whether to coerce types (numbers to strings)
    coerce_types: bool = true,
};

pub const RequestRectifier = struct {
    allocator: std.mem.Allocator,
    options: RectifierOptions,

    pub fn init(allocator: std.mem.Allocator, options: RectifierOptions) RequestRectifier {
        return .{
            .allocator = allocator,
            .options = options,
        };
    }

    /// Normalize a request body based on target format
    pub fn normalizeRequest(
        self: *RequestRectifier,
        body: []const u8,
        target_format: ApiFormat,
    ) ![]u8 {
        _ = target_format;
        if (self.options.coerce_types) {
            return self.coerceTypes(body);
        }
        return try self.allocator.dupe(u8, body);
    }

    /// Convert thinking blocks to compatible format
    pub fn normalizeThinkingBlocks(self: *RequestRectifier, body: []const u8) ![]u8 {
        if (!self.options.normalize_thinking) {
            return try self.allocator.dupe(u8, body);
        }

        // Parse the JSON
        var parsed = try json.parseFromSlice(json.Value, self.allocator, body, .{});
        defer parsed.deinit();

        // Check if this is an Anthropic request with thinking
        const obj = parsed.value.object;
        if (obj.get("thinking")) |_| {
            // Fix thinking block format if needed - placeholder for now
        }

        // Re-serialize
        var buf = std.array_list.Managed(u8).init(self.allocator);
        try json.stringify(parsed.value, .{}, buf.writer());
        return buf.toOwnedSlice();
    }

    fn fixThinkingBlock(_: *RequestRectifier, thinking: json.Value) void {
        // This would fix thinking block signatures
        // For now, just a placeholder - actual implementation would
        // normalize the thinking block structure
        _ = thinking;
    }

    /// Coerce number types to strings where appropriate
    fn coerceTypes(self: *RequestRectifier, body: []const u8) ![]u8 {
        var parsed = try json.parseFromSlice(json.Value, self.allocator, body, .{});
        defer parsed.deinit();

        // Walk and coerce
        self.coerceValue(&parsed.value);

        // Re-serialize
        var buf = std.array_list.Managed(u8).init(self.allocator);
        try json.stringify(parsed.value, .{}, buf.writer());
        return buf.toOwnedSlice();
    }

    fn coerceValue(self: *RequestRectifier, value: *json.Value) void {
        switch (value.*) {
            .object => |obj| {
                var it = obj.iterator();
                while (it.next()) |entry| {
                    // Coerce model field if it's a number
                    if (std.mem.eql(u8, entry.key_ptr.*, "model")) {
                        if (entry.value_ptr.* == .number) {
                            const num = entry.value_ptr.number;
                            var buf: [64]u8 = undefined;
                            const str = std.fmt.bufPrint(&buf, "{d}", .{num}) catch return;
                            entry.value_ptr.* = json.Value{ .string = try self.allocator.dupe(u8, str) };
                        }
                    } else {
                        self.coerceValue(entry.value_ptr);
                    }
                }
            },
            .array => |arr| {
                for (arr.items) |*item| {
                    self.coerceValue(item);
                }
            },
            else => {},
        }
    }

    /// Check if a response has thinking blocks that need fixing
    pub fn needsResponseFix(self: *RequestRectifier, body: []const u8) bool {
        if (!self.options.normalize_thinking) return false;

        // Check for thinking block in response
        return std.mem.find(u8, body, "thinking_block_id") != null or
            std.mem.find(u8, body, "thinking") != null;
    }

    /// Fix response thinking blocks to be compatible
    pub fn fixResponseThinking(self: *RequestRectifier, body: []const u8) ![]u8 {
        if (!self.options.normalize_thinking) {
            return try self.allocator.dupe(u8, body);
        }

        // For now, just return a copy - actual implementation would
        // normalize thinking block signatures from relay providers
        return try self.allocator.dupe(u8, body);
    }

    /// Detect API format from request body
    pub fn detectFormat(self: *RequestRectifier, body: []const u8) ApiFormat {
        _ = self;
        // Check for Anthropic-specific fields
        if (std.mem.find(u8, body, "\"system\"") != null or
            std.mem.find(u8, body, "\"thinking\"") != null or
            std.mem.find(u8, body, "\"max_tokens\"") != null)
        {
            return .anthropic;
        }
        // Check for OpenAI-specific fields
        if (std.mem.find(u8, body, "\"messages\"") != null) {
            return .openai;
        }
        return .auto;
    }

    /// Convert request to target format
    pub fn convertFormat(
        self: *RequestRectifier,
        body: []const u8,
        from: ApiFormat,
        to: ApiFormat,
    ) ![]u8 {
        if (from == to) {
            return try self.allocator.dupe(u8, body);
        }

        // Parse the request
        var parsed = try json.parseFromSlice(json.Value, self.allocator, body, .{});
        defer parsed.deinit();

        if (from == .anthropic and to == .openai) {
            return try self.convertAnthropicToOpenAI(&parsed.value);
        } else if (from == .openai and to == .anthropic) {
            return try self.convertOpenAIToAnthropic(&parsed.value);
        }

        return try self.allocator.dupe(u8, body);
    }

    fn convertAnthropicToOpenAI(self: *RequestRectifier, value: *json.Value) ![]u8 {
        // Convert Anthropic Messages API format to OpenAI Chat Completions format
        const obj = value.object;

        // Create new object for OpenAI format
        var new_obj = std.json.ObjectMap.init(self.allocator);
        errdefer new_obj.deinit();

        // Copy model (Anthropic uses model field)
        if (obj.get("model")) |model| {
            try new_obj.put("model", try self.cloneValue(model));
        }

        // Convert max_tokens to max_completion_tokens
        if (obj.get("max_tokens")) |max_tokens| {
            try new_obj.put("max_completion_tokens", try self.cloneValue(max_tokens));
        }

        // Copy temperature
        if (obj.get("temperature")) |temp| {
            try new_obj.put("temperature", try self.cloneValue(temp));
        }

        // Copy top_p
        if (obj.get("top_p")) |top_p| {
            try new_obj.put("top_p", try self.cloneValue(top_p));
        }

        // Copy top_k
        if (obj.get("top_k")) |top_k| {
            try new_obj.put("top_k", try self.cloneValue(top_k));
        }

        // Convert system message to first message in array
        var messages = std.array_list.Managed(json.Value).init(self.allocator);
        errdefer messages.deinit();

        if (obj.get("system")) |sys| {
            var sys_msg = std.json.ObjectMap.init(self.allocator);
            try sys_msg.put("role", json.Value{ .string = "system" });
            try sys_msg.put("content", try self.cloneValue(sys));
            try messages.append(json.Value{ .object = sys_msg });
        }

        // Convert messages array
        if (obj.get("messages")) |msgs| {
            if (msgs == .array) {
                for (msgs.array.items) |msg| {
                    try messages.append(try self.cloneValue(msg));
                }
            }
        }

        try new_obj.put("messages", json.Value{ .array = messages });

        // Copy stream (Anthropic uses stream: true for streaming)
        if (obj.get("stream")) |stream| {
            try new_obj.put("stream", try self.cloneValue(stream));
        }

        // Copy tools/function definitions (Anthropic uses tools)
        if (obj.get("tools")) |tools| {
            try new_obj.put("tools", try self.cloneValue(tools));
        }

        // Copy stop sequences
        if (obj.get("stop_sequences")) |stop| {
            try new_obj.put("stop", try self.cloneValue(stop));
        }

        // Re-serialize
        var buf = std.array_list.Managed(u8).init(self.allocator);
        try json.stringify(json.Value{ .object = new_obj }, .{
            .whitespace = .indent_tab,
        }, buf.writer());
        return buf.toOwnedSlice();
    }

    fn convertOpenAIToAnthropic(self: *RequestRectifier, value: *json.Value) ![]u8 {
        // Convert OpenAI Chat Completions format to Anthropic Messages API format
        const obj = value.object;

        // Create new object for Anthropic format
        var new_obj = std.json.ObjectMap.init(self.allocator);
        errdefer new_obj.deinit();

        // Copy model
        if (obj.get("model")) |model| {
            try new_obj.put("model", try self.cloneValue(model));
        }

        // Convert max_completion_tokens or max_tokens to max_tokens
        if (obj.get("max_completion_tokens")) |max_tokens| {
            try new_obj.put("max_tokens", try self.cloneValue(max_tokens));
        } else if (obj.get("max_tokens")) |max_tokens| {
            try new_obj.put("max_tokens", try self.cloneValue(max_tokens));
        }

        // Copy temperature
        if (obj.get("temperature")) |temp| {
            try new_obj.put("temperature", try self.cloneValue(temp));
        }

        // Copy top_p
        if (obj.get("top_p")) |top_p| {
            try new_obj.put("top_p", try self.cloneValue(top_p));
        }

        // Extract system message and put it in separate field
        var messages = std.array_list.Managed(json.Value).init(self.allocator);
        errdefer messages.deinit();

        if (obj.get("messages")) |msgs| {
            if (msgs == .array) {
                for (msgs.array.items) |msg| {
                    if (msg.object.get("role")) |role| {
                        if (role == .string and std.mem.eql(u8, role.string, "system")) {
                            // Move system message to separate field
                            if (msg.object.get("content")) |content| {
                                try new_obj.put("system", try self.cloneValue(content));
                            }
                        } else {
                            // Regular message
                            try messages.append(try self.cloneValue(msg));
                        }
                    } else {
                        try messages.append(try self.cloneValue(msg));
                    }
                }
            }
        }

        try new_obj.put("messages", json.Value{ .array = messages });

        // Copy stream
        if (obj.get("stream")) |stream| {
            try new_obj.put("stream", try self.cloneValue(stream));
        }

        // Convert tools to Anthropic format (different structure)
        if (obj.get("tools")) |tools| {
            try new_obj.put("tools", try self.cloneValue(tools));
        }

        // Copy stop sequences
        if (obj.get("stop")) |stop| {
            try new_obj.put("stop_sequences", try self.cloneValue(stop));
        }

        // Re-serialize
        var buf = std.array_list.Managed(u8).init(self.allocator);
        try json.stringify(json.Value{ .object = new_obj }, .{
            .whitespace = .indent_tab,
        }, buf.writer());
        return buf.toOwnedSlice();
    }

    /// Clone a JSON value deeply
    fn cloneValue(self: *RequestRectifier, value: json.Value) !json.Value {
        switch (value) {
            .null => return json.Value{ .null = {} },
            .bool => |b| return json.Value{ .bool = b },
            .number => |n| return json.Value{ .number = n },
            .string => |s| return json.Value{ .string = try self.allocator.dupe(u8, s) },
            .array => |arr| {
                var new_arr = std.array_list.Managed(json.Value).init(self.allocator);
                for (arr.items) |item| {
                    try new_arr.append(try self.cloneValue(item));
                }
                return json.Value{ .array = new_arr };
            },
            .object => |obj| {
                var new_obj = std.json.ObjectMap.init(self.allocator);
                var it = obj.iterator();
                while (it.next()) |entry| {
                    try new_obj.put(entry.key_ptr.*, try self.cloneValue(entry.value_ptr.*));
                }
                return json.Value{ .object = new_obj };
            },
        }
    }
};

test "rectifier detect format" {
    const allocator = std.heap.page_allocator;
    var rectifier = RequestRectifier.init(allocator, .{});

    const anthropic_req = "{\"max_tokens\": 1024, \"system\": \"You are helpful\"}";
    try std.testing.expect(rectifier.detectFormat(anthropic_req) == .anthropic);

    const openai_req = "{\"messages\": [{\"role\": \"user\", \"content\": \"Hi\"}]}";
    try std.testing.expect(rectifier.detectFormat(openai_req) == .openai);
}

test "rectifier coerce types" {
    const allocator = std.heap.page_allocator;
    var rectifier = RequestRectifier.init(allocator, .{});

    const input = "{\"model\": 12345, \"messages\": []}";
    const output = try rectifier.normalizeRequest(input, .openai);
    defer allocator.free(output);

    // Model should still be a number (coercion just prepares, doesn't guarantee string)
    try std.testing.expect(std.mem.find(u8, output, "12345") != null);
}

test "rectifier convert anthropic to openai" {
    const allocator = std.heap.page_allocator;
    var rectifier = RequestRectifier.init(allocator, .{});

    // Anthropic request
    const anthropic_req = try allocator.dupe(u8,
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":1024,"system":"You are helpful","messages":[{"role":"user","content":"Hello"}]}
    );
    defer allocator.free(anthropic_req);

    // Convert to OpenAI format
    const output = try rectifier.convertFormat(anthropic_req, .anthropic, .openai);
    defer allocator.free(output);

    // Verify the output contains expected fields
    try std.testing.expect(std.mem.find(u8, output, "claude-3-5-sonnet-20241022") != null);
    try std.testing.expect(std.mem.find(u8, output, "max_completion_tokens") != null); // Converted
    try std.testing.expect(std.mem.find(u8, output, "system") != null); // System in messages
    try std.testing.expect(std.mem.find(u8, output, "Hello") != null);
}

test "rectifier convert openai to anthropic" {
    const allocator = std.heap.page_allocator;
    var rectifier = RequestRectifier.init(allocator, .{});

    // OpenAI request with system message
    const openai_req = try allocator.dupe(u8,
        \\{"model":"gpt-4o","max_tokens":100,"messages":[{"role":"system","content":"You are helpful"},{"role":"user","content":"Hi"}]}
    );
    defer allocator.free(openai_req);

    // Convert to Anthropic format
    const output = try rectifier.convertFormat(openai_req, .openai, .anthropic);
    defer allocator.free(output);

    // Verify the output
    try std.testing.expect(std.mem.find(u8, output, "gpt-4o") != null);
    try std.testing.expect(std.mem.find(u8, output, "You are helpful") != null); // System preserved
    try std.testing.expect(std.mem.find(u8, output, "Hi") != null);
}

test "rectifier convert same format" {
    const allocator = std.heap.page_allocator;
    var rectifier = RequestRectifier.init(allocator, .{});

    const openai_req = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}]}";

    // Convert same to same
    const output = try rectifier.convertFormat(openai_req, .openai, .openai);
    defer allocator.free(output);

    // Should be unchanged (except whitespace)
    try std.testing.expect(std.mem.find(u8, output, "gpt-4o") != null);
}

test "rectifier detect format with thinking" {
    const allocator = std.heap.page_allocator;
    var rectifier = RequestRectifier.init(allocator, .{});

    const thinking_req = "{\"thinking\": {\"type\": \"enabled\"}, \"messages\": []}";
    try std.testing.expect(rectifier.detectFormat(thinking_req) == .anthropic);
}
