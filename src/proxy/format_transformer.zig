//! Format Transformer - API format conversion between Anthropic, OpenAI Chat, and OpenAI Responses
//!
//! Converts request and response bodies between different LLM API formats:
//! - Anthropic Messages API
//! - OpenAI Chat Completions API
//! - OpenAI Responses API
//!
//! Usage:
//!   var ft = FormatTransformer.init(allocator);
//!   defer ft.deinit();
//!   const format = FormatTransformer.detectFormat(body_json);
//!   const converted = try ft.transformRequestAnthropicToOpenAI(body);

const std = @import("std");
const json = std.json;

/// Supported API formats
pub const ApiFormat = enum {
    anthropic,
    openai_chat,
    openai_responses,
};

pub const FormatTransformer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FormatTransformer {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *FormatTransformer) void {
        _ = self;
    }

    /// Detect API format from a JSON body string.
    ///
    /// Detection rules:
    /// - Has "input" field → openai_responses
    /// - Has "messages" array + "model" + "system" field → anthropic
    /// - Has "messages" array + "model" → openai_chat
    /// - Default → openai_chat
    pub fn detectFormat(body_json: []const u8) ApiFormat {
        var parsed = json.parseFromSlice(
            json.Value,
            std.heap.page_allocator,
            body_json,
            .{},
        ) catch return .openai_chat;
        defer parsed.deinit();

        const obj = switch (parsed.value) {
            .object => |o| o,
            else => return .openai_chat,
        };

        if (obj.get("input") != null) return .openai_responses;

        const has_messages = if (obj.get("messages")) |m| m == .array else false;
        const has_model = obj.get("model") != null;

        if (has_messages and has_model) {
            if (obj.get("system") != null) return .anthropic;
            return .openai_chat;
        }

        return .openai_chat;
    }

    /// Convert Anthropic Messages request to OpenAI Chat Completions format.
    pub fn transformRequestAnthropicToOpenAI(self: *FormatTransformer, body: []const u8) ![]u8 {
        // Use arena for all intermediate JSON allocations
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var parsed = try json.parseFromSlice(json.Value, a, body, .{});
        _ = &parsed; // parsed is managed by arena

        const obj = switch (parsed.value) {
            .object => |o| o,
            else => return error.InvalidJson,
        };

        var new_obj = json.ObjectMap.init(a);

        if (obj.get("model")) |model| try new_obj.put("model", try cloneValue(a, model));
        if (obj.get("max_tokens")) |mt| try new_obj.put("max_completion_tokens", try cloneValue(a, mt));

        var messages = json.Array.init(a);

        if (obj.get("system")) |sys| {
            var sys_msg = json.ObjectMap.init(a);
            try sys_msg.put("role", json.Value{ .string = "system" });
            try sys_msg.put("content", try cloneValue(a, sys));
            try messages.append(json.Value{ .object = sys_msg });
        }

        if (obj.get("messages")) |msgs| {
            if (msgs == .array) {
                for (msgs.array.items) |msg| {
                    try messages.append(try cloneValue(a, msg));
                }
            }
        }

        try new_obj.put("messages", json.Value{ .array = messages });

        if (obj.get("temperature")) |t| try new_obj.put("temperature", try cloneValue(a, t));
        if (obj.get("top_p")) |t| try new_obj.put("top_p", try cloneValue(a, t));
        if (obj.get("stream")) |s| try new_obj.put("stream", try cloneValue(a, s));
        if (obj.get("tools")) |t| try new_obj.put("tools", try cloneValue(a, t));
        if (obj.get("stop_sequences")) |s| try new_obj.put("stop", try cloneValue(a, s));

        // Stringify into caller's allocator
        return try json.Stringify.valueAlloc(self.allocator, json.Value{ .object = new_obj }, .{});
    }

    /// Convert OpenAI Chat Completions request to Anthropic Messages format.
    pub fn transformRequestOpenAIToAnthropic(self: *FormatTransformer, body: []const u8) ![]u8 {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var parsed = try json.parseFromSlice(json.Value, a, body, .{});
        _ = &parsed;

        const obj = switch (parsed.value) {
            .object => |o| o,
            else => return error.InvalidJson,
        };

        var new_obj = json.ObjectMap.init(a);

        if (obj.get("model")) |model| try new_obj.put("model", try cloneValue(a, model));

        if (obj.get("max_completion_tokens")) |mt| {
            try new_obj.put("max_tokens", try cloneValue(a, mt));
        } else if (obj.get("max_tokens")) |mt| {
            try new_obj.put("max_tokens", try cloneValue(a, mt));
        }

        var messages = json.Array.init(a);

        if (obj.get("messages")) |msgs| {
            if (msgs == .array) {
                for (msgs.array.items) |msg| {
                    if (msg == .object) {
                        if (msg.object.get("role")) |role| {
                            if (role == .string and std.mem.eql(u8, role.string, "system")) {
                                if (msg.object.get("content")) |content| {
                                    try new_obj.put("system", try cloneValue(a, content));
                                }
                                continue;
                            }
                        }
                    }
                    try messages.append(try cloneValue(a, msg));
                }
            }
        }

        try new_obj.put("messages", json.Value{ .array = messages });

        if (obj.get("temperature")) |t| try new_obj.put("temperature", try cloneValue(a, t));
        if (obj.get("top_p")) |t| try new_obj.put("top_p", try cloneValue(a, t));
        if (obj.get("stream")) |s| try new_obj.put("stream", try cloneValue(a, s));
        if (obj.get("tools")) |t| try new_obj.put("tools", try cloneValue(a, t));
        if (obj.get("stop")) |s| try new_obj.put("stop_sequences", try cloneValue(a, s));

        return try json.Stringify.valueAlloc(self.allocator, json.Value{ .object = new_obj }, .{});
    }

    /// Convert Anthropic response to OpenAI Chat Completions response format.
    pub fn transformResponseAnthropicToOpenAI(self: *FormatTransformer, body: []const u8) ![]u8 {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var parsed = try json.parseFromSlice(json.Value, a, body, .{});
        _ = &parsed;

        const obj = switch (parsed.value) {
            .object => |o| o,
            else => return error.InvalidJson,
        };

        var new_obj = json.ObjectMap.init(a);

        if (obj.get("id")) |id| try new_obj.put("id", try cloneValue(a, id));
        try new_obj.put("object", json.Value{ .string = "chat.completion" });
        if (obj.get("model")) |model| try new_obj.put("model", try cloneValue(a, model));

        // Build choices
        var choices = json.Array.init(a);
        var choice = json.ObjectMap.init(a);
        try choice.put("index", json.Value{ .integer = 0 });

        // Map stop_reason → finish_reason
        var finish_reason: []const u8 = "stop";
        if (obj.get("stop_reason")) |sr| {
            if (sr == .string) {
                if (std.mem.eql(u8, sr.string, "end_turn")) {
                    finish_reason = "stop";
                } else if (std.mem.eql(u8, sr.string, "max_tokens")) {
                    finish_reason = "length";
                } else if (std.mem.eql(u8, sr.string, "tool_use")) {
                    finish_reason = "tool_calls";
                }
            }
        }
        try choice.put("finish_reason", json.Value{ .string = finish_reason });

        // Build message from content blocks
        var message = json.ObjectMap.init(a);
        try message.put("role", json.Value{ .string = "assistant" });

        if (obj.get("content")) |content| {
            if (content == .array) {
                var text_parts: std.ArrayListUnmanaged(u8) = .empty;
                for (content.array.items) |block| {
                    if (block == .object) {
                        if (block.object.get("type")) |btype| {
                            if (btype == .string and std.mem.eql(u8, btype.string, "text")) {
                                if (block.object.get("text")) |text| {
                                    if (text == .string) {
                                        if (text_parts.items.len > 0) try text_parts.append(a, '\n');
                                        try text_parts.appendSlice(a, text.string);
                                    }
                                }
                            }
                        }
                    }
                }
                const text_content = try text_parts.toOwnedSlice(a);
                try message.put("content", json.Value{ .string = text_content });
            } else if (content == .string) {
                try message.put("content", try cloneValue(a, content));
            }
        }

        try choice.put("message", json.Value{ .object = message });
        try choices.append(json.Value{ .object = choice });
        try new_obj.put("choices", json.Value{ .array = choices });

        // Transform usage
        if (obj.get("usage")) |usage| {
            if (usage == .object) {
                var new_usage = json.ObjectMap.init(a);
                const input_val = usage.object.get("input_tokens");
                const output_val = usage.object.get("output_tokens");

                if (input_val) |it| try new_usage.put("prompt_tokens", try cloneValue(a, it));
                if (output_val) |ot| try new_usage.put("completion_tokens", try cloneValue(a, ot));

                const input_i = if (input_val) |it| getInteger(it) else 0;
                const output_i = if (output_val) |ot| getInteger(ot) else 0;
                try new_usage.put("total_tokens", json.Value{ .integer = input_i + output_i });

                try new_obj.put("usage", json.Value{ .object = new_usage });
            }
        }

        return try json.Stringify.valueAlloc(self.allocator, json.Value{ .object = new_obj }, .{});
    }

    /// Transform a single SSE event data string between formats.
    /// OpenAI SSE → Anthropic SSE: delta.content → content_block_delta, finish_reason → stop_reason
    /// Anthropic SSE → OpenAI SSE: reverse
    pub fn transformSseEvent(self: *FormatTransformer, event_data: []const u8, from: ApiFormat, to: ApiFormat) ![]u8 {
        // Same format: return a copy
        if (from == to) {
            return try self.allocator.dupe(u8, event_data);
        }

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var parsed = json.parseFromSlice(json.Value, a, event_data, .{}) catch {
            // Malformed JSON: return a copy of input
            return try self.allocator.dupe(u8, event_data);
        };
        _ = &parsed;

        const obj = switch (parsed.value) {
            .object => |o| o,
            else => return try self.allocator.dupe(u8, event_data),
        };

        if (from == .openai_chat and to == .anthropic) {
            return try self.transformSseOpenAIToAnthropic(a, obj);
        } else if (from == .anthropic and to == .openai_chat) {
            return try self.transformSseAnthropicToOpenAI(a, obj);
        }

        // Unsupported conversion pair: return copy
        return try self.allocator.dupe(u8, event_data);
    }

    /// OpenAI Chat SSE → Anthropic SSE
    fn transformSseOpenAIToAnthropic(self: *FormatTransformer, a: std.mem.Allocator, obj: json.ObjectMap) ![]u8 {
        var new_obj = json.ObjectMap.init(a);

        // Check for finish_reason in choices[0]
        const choices = obj.get("choices");
        var has_finish = false;
        var finish_reason_str: ?[]const u8 = null;
        var delta_content: ?[]const u8 = null;

        if (choices) |ch| {
            if (ch == .array and ch.array.items.len > 0) {
                const first = ch.array.items[0];
                if (first == .object) {
                    // Extract delta.content
                    if (first.object.get("delta")) |delta| {
                        if (delta == .object) {
                            if (delta.object.get("content")) |content| {
                                if (content == .string) {
                                    delta_content = content.string;
                                }
                            }
                        }
                    }
                    // Extract finish_reason
                    if (first.object.get("finish_reason")) |fr| {
                        if (fr == .string) {
                            has_finish = true;
                            finish_reason_str = fr.string;
                        }
                    }
                }
            }
        }

        // Build content_block_delta event
        if (delta_content) |text| {
            try new_obj.put("type", json.Value{ .string = "content_block_delta" });
            try new_obj.put("index", json.Value{ .integer = 0 });

            var delta_obj = json.ObjectMap.init(a);
            try delta_obj.put("type", json.Value{ .string = "text_delta" });
            try delta_obj.put("text", json.Value{ .string = text });
            try new_obj.put("delta", json.Value{ .object = delta_obj });
        }

        // Map finish_reason → stop_reason
        if (has_finish) {
            if (finish_reason_str) |fr| {
                const stop_reason = mapFinishToStop(fr);
                try new_obj.put("type", json.Value{ .string = "message_delta" });
                var delta_obj = json.ObjectMap.init(a);
                try delta_obj.put("stop_reason", json.Value{ .string = stop_reason });
                try new_obj.put("delta", json.Value{ .object = delta_obj });
            }
        }

        // Preserve usage: prompt_tokens → input_tokens, completion_tokens → output_tokens
        if (obj.get("usage")) |usage| {
            if (usage == .object) {
                var new_usage = json.ObjectMap.init(a);
                if (usage.object.get("prompt_tokens")) |pt| try new_usage.put("input_tokens", try cloneValue(a, pt));
                if (usage.object.get("completion_tokens")) |ct| try new_usage.put("output_tokens", try cloneValue(a, ct));
                try new_obj.put("usage", json.Value{ .object = new_usage });
            }
        }

        // If we built nothing meaningful, return copy
        if (new_obj.count() == 0) {
            return try json.Stringify.valueAlloc(self.allocator, json.Value{ .object = obj }, .{});
        }

        return try json.Stringify.valueAlloc(self.allocator, json.Value{ .object = new_obj }, .{});
    }

    /// Anthropic SSE → OpenAI Chat SSE
    fn transformSseAnthropicToOpenAI(self: *FormatTransformer, a: std.mem.Allocator, obj: json.ObjectMap) ![]u8 {
        var new_obj = json.ObjectMap.init(a);

        const event_type = if (obj.get("type")) |t| (if (t == .string) t.string else null) else null;

        if (event_type) |et| {
            if (std.mem.eql(u8, et, "content_block_delta")) {
                // Extract delta.text → choices[0].delta.content
                if (obj.get("delta")) |delta| {
                    if (delta == .object) {
                        if (delta.object.get("text")) |text| {
                            if (text == .string) {
                                var choices = json.Array.init(a);
                                var choice = json.ObjectMap.init(a);
                                try choice.put("index", json.Value{ .integer = 0 });

                                var delta_obj = json.ObjectMap.init(a);
                                try delta_obj.put("content", json.Value{ .string = text.string });
                                try choice.put("delta", json.Value{ .object = delta_obj });
                                try choice.put("finish_reason", .null);

                                try choices.append(json.Value{ .object = choice });
                                try new_obj.put("choices", json.Value{ .array = choices });
                            }
                        }
                    }
                }
            } else if (std.mem.eql(u8, et, "message_delta")) {
                // Map stop_reason → finish_reason
                if (obj.get("delta")) |delta| {
                    if (delta == .object) {
                        if (delta.object.get("stop_reason")) |sr| {
                            if (sr == .string) {
                                const finish_reason = mapStopToFinish(sr.string);

                                var choices = json.Array.init(a);
                                var choice = json.ObjectMap.init(a);
                                try choice.put("index", json.Value{ .integer = 0 });
                                try choice.put("delta", json.Value{ .object = json.ObjectMap.init(a) });
                                try choice.put("finish_reason", json.Value{ .string = finish_reason });

                                try choices.append(json.Value{ .object = choice });
                                try new_obj.put("choices", json.Value{ .array = choices });
                            }
                        }
                    }
                }
            }
        }

        // Preserve usage: input_tokens → prompt_tokens, output_tokens → completion_tokens
        if (obj.get("usage")) |usage| {
            if (usage == .object) {
                var new_usage = json.ObjectMap.init(a);
                if (usage.object.get("input_tokens")) |it| try new_usage.put("prompt_tokens", try cloneValue(a, it));
                if (usage.object.get("output_tokens")) |ot| try new_usage.put("completion_tokens", try cloneValue(a, ot));

                const input_i = if (usage.object.get("input_tokens")) |it| getInteger(it) else 0;
                const output_i = if (usage.object.get("output_tokens")) |ot| getInteger(ot) else 0;
                try new_usage.put("total_tokens", json.Value{ .integer = input_i + output_i });

                try new_obj.put("usage", json.Value{ .object = new_usage });
            }
        }

        // If we built nothing meaningful, return the original as-is
        if (new_obj.count() == 0) {
            return try json.Stringify.valueAlloc(self.allocator, json.Value{ .object = obj }, .{});
        }

        return try json.Stringify.valueAlloc(self.allocator, json.Value{ .object = new_obj }, .{});
    }

    /// Map OpenAI finish_reason → Anthropic stop_reason
    fn mapFinishToStop(finish_reason: []const u8) []const u8 {
        if (std.mem.eql(u8, finish_reason, "stop")) return "end_turn";
        if (std.mem.eql(u8, finish_reason, "length")) return "max_tokens";
        if (std.mem.eql(u8, finish_reason, "tool_calls")) return "tool_use";
        return finish_reason;
    }

    /// Map Anthropic stop_reason → OpenAI finish_reason
    fn mapStopToFinish(stop_reason: []const u8) []const u8 {
        if (std.mem.eql(u8, stop_reason, "end_turn")) return "stop";
        if (std.mem.eql(u8, stop_reason, "max_tokens")) return "length";
        if (std.mem.eql(u8, stop_reason, "tool_use")) return "tool_calls";
        return stop_reason;
    }

    /// Convert Anthropic tool_use block to OpenAI tool_calls entry.
    /// Input:  {"type":"tool_use","id":"toolu_xxx","name":"get_weather","input":{"location":"SF"}}
    /// Output: {"id":"toolu_xxx","type":"function","function":{"name":"get_weather","arguments":"{\"location\":\"SF\"}"}}
    pub fn transformToolUseAnthropicToOpenAI(self: *FormatTransformer, tool_use_block: []const u8) ![]u8 {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var parsed = try json.parseFromSlice(json.Value, a, tool_use_block, .{});
        _ = &parsed;

        const obj = switch (parsed.value) {
            .object => |o| o,
            else => return error.InvalidJson,
        };

        var new_obj = json.ObjectMap.init(a);

        // Map id → id
        if (obj.get("id")) |id| {
            try new_obj.put("id", try cloneValue(a, id));
        }

        // Set type to "function"
        try new_obj.put("type", json.Value{ .string = "function" });

        // Build function object: name → function.name, input → function.arguments (stringified)
        var func_obj = json.ObjectMap.init(a);

        if (obj.get("name")) |name| {
            try func_obj.put("name", try cloneValue(a, name));
        }

        // Stringify input object to arguments string
        if (obj.get("input")) |input_val| {
            const args_str = try json.Stringify.valueAlloc(a, input_val, .{});
            try func_obj.put("arguments", json.Value{ .string = args_str });
        } else {
            try func_obj.put("arguments", json.Value{ .string = "{}" });
        }

        try new_obj.put("function", json.Value{ .object = func_obj });

        return try json.Stringify.valueAlloc(self.allocator, json.Value{ .object = new_obj }, .{});
    }

    /// Convert OpenAI tool_calls entry to Anthropic tool_use block.
    /// Input:  {"id":"call_xxx","type":"function","function":{"name":"get_weather","arguments":"{\"location\":\"SF\"}"}}
    /// Output: {"type":"tool_use","id":"call_xxx","name":"get_weather","input":{"location":"SF"}}
    pub fn transformToolCallOpenAIToAnthropic(self: *FormatTransformer, tool_call: []const u8) ![]u8 {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var parsed = try json.parseFromSlice(json.Value, a, tool_call, .{});
        _ = &parsed;

        const obj = switch (parsed.value) {
            .object => |o| o,
            else => return error.InvalidJson,
        };

        var new_obj = json.ObjectMap.init(a);

        // Set type to "tool_use"
        try new_obj.put("type", json.Value{ .string = "tool_use" });

        // Map id → id
        if (obj.get("id")) |id| {
            try new_obj.put("id", try cloneValue(a, id));
        }

        // Extract function.name → name, function.arguments (parse string to object) → input
        if (obj.get("function")) |func| {
            if (func == .object) {
                if (func.object.get("name")) |name| {
                    try new_obj.put("name", try cloneValue(a, name));
                }

                if (func.object.get("arguments")) |args| {
                    if (args == .string) {
                        // Parse arguments string back to JSON object
                        var args_parsed = json.parseFromSlice(json.Value, a, args.string, .{}) catch {
                            // If parsing fails, wrap as raw string in object
                            var fallback = json.ObjectMap.init(a);
                            try fallback.put("_raw", try cloneValue(a, args));
                            try new_obj.put("input", json.Value{ .object = fallback });
                            return try json.Stringify.valueAlloc(self.allocator, json.Value{ .object = new_obj }, .{});
                        };
                        _ = &args_parsed;
                        try new_obj.put("input", try cloneValue(a, args_parsed.value));
                    } else {
                        try new_obj.put("input", try cloneValue(a, args));
                    }
                } else {
                    try new_obj.put("input", json.Value{ .object = json.ObjectMap.init(a) });
                }
            }
        } else {
            try new_obj.put("input", json.Value{ .object = json.ObjectMap.init(a) });
        }

        return try json.Stringify.valueAlloc(self.allocator, json.Value{ .object = new_obj }, .{});
    }

    /// Convert Anthropic Messages request to OpenAI Responses API format.
    /// Maps: messages → input, model → model, system → instructions, max_tokens → max_output_tokens
    pub fn transformRequestAnthropicToResponses(self: *FormatTransformer, body: []const u8) ![]u8 {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var parsed = try json.parseFromSlice(json.Value, a, body, .{});
        _ = &parsed;

        const obj = switch (parsed.value) {
            .object => |o| o,
            else => return error.InvalidJson,
        };

        var new_obj = json.ObjectMap.init(a);

        if (obj.get("model")) |model| try new_obj.put("model", try cloneValue(a, model));
        if (obj.get("max_tokens")) |mt| try new_obj.put("max_output_tokens", try cloneValue(a, mt));
        if (obj.get("system")) |sys| try new_obj.put("instructions", try cloneValue(a, sys));

        // Map messages → input array
        if (obj.get("messages")) |msgs| {
            try new_obj.put("input", try cloneValue(a, msgs));
        }

        if (obj.get("temperature")) |t| try new_obj.put("temperature", try cloneValue(a, t));
        if (obj.get("top_p")) |t| try new_obj.put("top_p", try cloneValue(a, t));
        if (obj.get("stream")) |s| try new_obj.put("stream", try cloneValue(a, s));
        if (obj.get("tools")) |t| try new_obj.put("tools", try cloneValue(a, t));

        return try json.Stringify.valueAlloc(self.allocator, json.Value{ .object = new_obj }, .{});
    }

    /// Convert OpenAI Responses API request to Anthropic Messages format.
    /// Maps: input → messages, model → model, instructions → system, max_output_tokens → max_tokens
    pub fn transformRequestResponsesToAnthropic(self: *FormatTransformer, body: []const u8) ![]u8 {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var parsed = try json.parseFromSlice(json.Value, a, body, .{});
        _ = &parsed;

        const obj = switch (parsed.value) {
            .object => |o| o,
            else => return error.InvalidJson,
        };

        var new_obj = json.ObjectMap.init(a);

        if (obj.get("model")) |model| try new_obj.put("model", try cloneValue(a, model));
        if (obj.get("max_output_tokens")) |mt| try new_obj.put("max_tokens", try cloneValue(a, mt));
        if (obj.get("instructions")) |inst| try new_obj.put("system", try cloneValue(a, inst));

        // Map input → messages
        if (obj.get("input")) |input_val| {
            try new_obj.put("messages", try cloneValue(a, input_val));
        }

        if (obj.get("temperature")) |t| try new_obj.put("temperature", try cloneValue(a, t));
        if (obj.get("top_p")) |t| try new_obj.put("top_p", try cloneValue(a, t));
        if (obj.get("stream")) |s| try new_obj.put("stream", try cloneValue(a, s));
        if (obj.get("tools")) |t| try new_obj.put("tools", try cloneValue(a, t));

        return try json.Stringify.valueAlloc(self.allocator, json.Value{ .object = new_obj }, .{});
    }

    /// Map Anthropic thinking type/budget_tokens to OpenAI reasoning_effort.
    /// - "adaptive" → "xhigh"
    /// - "enabled" with budget < 4000 → "low"
    /// - "enabled" with budget 4000-15999 → "medium"
    /// - "enabled" with budget >= 16000 → "high"
    /// - "disabled" or null → null
    pub fn mapReasoningEffort(thinking_type: ?[]const u8, budget_tokens: ?i64) ?[]const u8 {
        const tt = thinking_type orelse return null;

        if (std.mem.eql(u8, tt, "adaptive")) return "xhigh";

        if (std.mem.eql(u8, tt, "enabled")) {
            const budget = budget_tokens orelse return "low";
            if (budget < 4000) return "low";
            if (budget < 16000) return "medium";
            return "high";
        }

        // "disabled" or any other value
        return null;
    }

    /// Convert OpenAI Chat Completions response to Anthropic Messages response format.
    pub fn transformResponseOpenAIToAnthropic(self: *FormatTransformer, body: []const u8) ![]u8 {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var parsed = try json.parseFromSlice(json.Value, a, body, .{});
        _ = &parsed;

        const obj = switch (parsed.value) {
            .object => |o| o,
            else => return error.InvalidJson,
        };

        var new_obj = json.ObjectMap.init(a);

        if (obj.get("id")) |id| try new_obj.put("id", try cloneValue(a, id));
        try new_obj.put("type", json.Value{ .string = "message" });
        if (obj.get("model")) |model| try new_obj.put("model", try cloneValue(a, model));
        try new_obj.put("role", json.Value{ .string = "assistant" });

        var content_arr = json.Array.init(a);

        if (obj.get("choices")) |choices| {
            if (choices == .array and choices.array.items.len > 0) {
                const first_choice = choices.array.items[0];
                if (first_choice == .object) {
                    if (first_choice.object.get("finish_reason")) |fr| {
                        if (fr == .string) {
                            if (std.mem.eql(u8, fr.string, "stop")) {
                                try new_obj.put("stop_reason", json.Value{ .string = "end_turn" });
                            } else if (std.mem.eql(u8, fr.string, "length")) {
                                try new_obj.put("stop_reason", json.Value{ .string = "max_tokens" });
                            } else if (std.mem.eql(u8, fr.string, "tool_calls")) {
                                try new_obj.put("stop_reason", json.Value{ .string = "tool_use" });
                            }
                        }
                    }

                    if (first_choice.object.get("message")) |message| {
                        if (message == .object) {
                            if (message.object.get("content")) |c| {
                                if (c == .string) {
                                    var text_block = json.ObjectMap.init(a);
                                    try text_block.put("type", json.Value{ .string = "text" });
                                    try text_block.put("text", try cloneValue(a, c));
                                    try content_arr.append(json.Value{ .object = text_block });
                                }
                            }
                        }
                    }
                }
            }
        }

        try new_obj.put("content", json.Value{ .array = content_arr });

        if (obj.get("usage")) |usage| {
            if (usage == .object) {
                var new_usage = json.ObjectMap.init(a);
                if (usage.object.get("prompt_tokens")) |pt| try new_usage.put("input_tokens", try cloneValue(a, pt));
                if (usage.object.get("completion_tokens")) |ct| try new_usage.put("output_tokens", try cloneValue(a, ct));
                try new_obj.put("usage", json.Value{ .object = new_usage });
            }
        }

        return try json.Stringify.valueAlloc(self.allocator, json.Value{ .object = new_obj }, .{});
    }
};

fn getInteger(val: json.Value) i64 {
    return switch (val) {
        .integer => |v| v,
        .float => |v| @intFromFloat(v),
        else => 0,
    };
}

fn cloneValue(allocator: std.mem.Allocator, value: json.Value) !json.Value {
    switch (value) {
        .null => return .null,
        .bool => |b| return json.Value{ .bool = b },
        .integer => |n| return json.Value{ .integer = n },
        .float => |f| return json.Value{ .float = f },
        .number_string => |s| return json.Value{ .number_string = try allocator.dupe(u8, s) },
        .string => |s| return json.Value{ .string = try allocator.dupe(u8, s) },
        .array => |arr| {
            var new_arr = json.Array.init(allocator);
            for (arr.items) |item| {
                try new_arr.append(try cloneValue(allocator, item));
            }
            return json.Value{ .array = new_arr };
        },
        .object => |obj| {
            var new_obj = json.ObjectMap.init(allocator);
            var it = obj.iterator();
            while (it.next()) |entry| {
                try new_obj.put(
                    try allocator.dupe(u8, entry.key_ptr.*),
                    try cloneValue(allocator, entry.value_ptr.*),
                );
            }
            return json.Value{ .object = new_obj };
        },
    }
}

// ============================================================================
// TESTS
// ============================================================================

test "format_transformer - detectFormat anthropic body" {
    const body =
        \\{"model":"claude-3-5-sonnet","system":"You are helpful","messages":[{"role":"user","content":"Hi"}]}
    ;
    try std.testing.expectEqual(ApiFormat.anthropic, FormatTransformer.detectFormat(body));
}

test "format_transformer - detectFormat openai_chat body" {
    const body =
        \\{"model":"gpt-4o","messages":[{"role":"user","content":"Hi"}]}
    ;
    try std.testing.expectEqual(ApiFormat.openai_chat, FormatTransformer.detectFormat(body));
}

test "format_transformer - detectFormat openai_responses body" {
    const body =
        \\{"model":"gpt-4o","input":"Tell me a joke"}
    ;
    try std.testing.expectEqual(ApiFormat.openai_responses, FormatTransformer.detectFormat(body));
}

test "format_transformer - detectFormat defaults to openai_chat" {
    try std.testing.expectEqual(ApiFormat.openai_chat, FormatTransformer.detectFormat(
        \\{"foo":"bar"}
    ));
}

test "format_transformer - detectFormat invalid json defaults to openai_chat" {
    try std.testing.expectEqual(ApiFormat.openai_chat, FormatTransformer.detectFormat("not json"));
}

test "format_transformer - transformRequestAnthropicToOpenAI basic" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const input =
        \\{"model":"claude-3-5-sonnet","max_tokens":1024,"system":"You are helpful","messages":[{"role":"user","content":"Hello"}]}
    ;

    const output = try ft.transformRequestAnthropicToOpenAI(input);
    defer allocator.free(output);

    var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    try std.testing.expectEqualStrings("claude-3-5-sonnet", obj.get("model").?.string);
    try std.testing.expect(obj.get("max_completion_tokens") != null);
    try std.testing.expect(obj.get("max_tokens") == null);

    const msgs = obj.get("messages").?.array;
    try std.testing.expectEqual(@as(usize, 2), msgs.items.len);
    try std.testing.expectEqualStrings("system", msgs.items[0].object.get("role").?.string);
    try std.testing.expectEqualStrings("You are helpful", msgs.items[0].object.get("content").?.string);
    try std.testing.expectEqualStrings("user", msgs.items[1].object.get("role").?.string);
    try std.testing.expectEqualStrings("Hello", msgs.items[1].object.get("content").?.string);
}

test "format_transformer - transformRequestOpenAIToAnthropic basic" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const input =
        \\{"model":"gpt-4o","max_tokens":100,"messages":[{"role":"system","content":"You are helpful"},{"role":"user","content":"Hi"}]}
    ;

    const output = try ft.transformRequestOpenAIToAnthropic(input);
    defer allocator.free(output);

    var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    try std.testing.expectEqualStrings("gpt-4o", obj.get("model").?.string);
    try std.testing.expectEqualStrings("You are helpful", obj.get("system").?.string);

    const msgs = obj.get("messages").?.array;
    try std.testing.expectEqual(@as(usize, 1), msgs.items.len);
    try std.testing.expectEqualStrings("user", msgs.items[0].object.get("role").?.string);
    try std.testing.expectEqualStrings("Hi", msgs.items[0].object.get("content").?.string);
}

test "format_transformer - transformResponseAnthropicToOpenAI preserves usage" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const input =
        \\{"id":"msg_123","model":"claude-3-5-sonnet","content":[{"type":"text","text":"Hello!"}],"stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":5}}
    ;

    const output = try ft.transformResponseAnthropicToOpenAI(input);
    defer allocator.free(output);

    var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    try std.testing.expectEqualStrings("chat.completion", obj.get("object").?.string);

    const choices = obj.get("choices").?.array;
    try std.testing.expectEqual(@as(usize, 1), choices.items.len);
    const choice = choices.items[0].object;
    try std.testing.expectEqualStrings("stop", choice.get("finish_reason").?.string);
    try std.testing.expectEqualStrings("Hello!", choice.get("message").?.object.get("content").?.string);

    const usage = obj.get("usage").?.object;
    try std.testing.expectEqual(@as(i64, 10), usage.get("prompt_tokens").?.integer);
    try std.testing.expectEqual(@as(i64, 5), usage.get("completion_tokens").?.integer);
    try std.testing.expectEqual(@as(i64, 15), usage.get("total_tokens").?.integer);
}

test "format_transformer - transformResponseOpenAIToAnthropic preserves usage" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const input =
        \\{"id":"chatcmpl-abc","model":"gpt-4o","choices":[{"index":0,"message":{"role":"assistant","content":"Hi there!"},"finish_reason":"stop"}],"usage":{"prompt_tokens":20,"completion_tokens":8,"total_tokens":28}}
    ;

    const output = try ft.transformResponseOpenAIToAnthropic(input);
    defer allocator.free(output);

    var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    try std.testing.expectEqualStrings("message", obj.get("type").?.string);
    try std.testing.expectEqualStrings("assistant", obj.get("role").?.string);

    const content = obj.get("content").?.array;
    try std.testing.expectEqual(@as(usize, 1), content.items.len);
    try std.testing.expectEqualStrings("text", content.items[0].object.get("type").?.string);
    try std.testing.expectEqualStrings("Hi there!", content.items[0].object.get("text").?.string);

    try std.testing.expectEqualStrings("end_turn", obj.get("stop_reason").?.string);

    const usage = obj.get("usage").?.object;
    try std.testing.expectEqual(@as(i64, 20), usage.get("input_tokens").?.integer);
    try std.testing.expectEqual(@as(i64, 8), usage.get("output_tokens").?.integer);
}

test "format_transformer - transformRequestAnthropicToOpenAI invalid json" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const result = ft.transformRequestAnthropicToOpenAI("not json");
    try std.testing.expectError(error.SyntaxError, result);
}

test "format_transformer - transformRequestOpenAIToAnthropic no system message" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const input =
        \\{"model":"gpt-4o","messages":[{"role":"user","content":"Hi"},{"role":"assistant","content":"Hello!"}]}
    ;

    const output = try ft.transformRequestOpenAIToAnthropic(input);
    defer allocator.free(output);

    var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;

    try std.testing.expect(obj.get("system") == null);

    const msgs = obj.get("messages").?.array;
    try std.testing.expectEqual(@as(usize, 2), msgs.items.len);
}


test "format_transformer - transformSseEvent openai to anthropic with content delta" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const input =
        \\{"choices":[{"index":0,"delta":{"content":"Hello world"},"finish_reason":null}]}
    ;

    const output = try ft.transformSseEvent(input, .openai_chat, .anthropic);
    defer allocator.free(output);

    var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("content_block_delta", obj.get("type").?.string);
    try std.testing.expectEqual(@as(i64, 0), obj.get("index").?.integer);

    const delta = obj.get("delta").?.object;
    try std.testing.expectEqualStrings("text_delta", delta.get("type").?.string);
    try std.testing.expectEqualStrings("Hello world", delta.get("text").?.string);
}

test "format_transformer - transformSseEvent anthropic to openai with content_block_delta" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const input =
        \\{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi there"}}
    ;

    const output = try ft.transformSseEvent(input, .anthropic, .openai_chat);
    defer allocator.free(output);

    var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    const choices = obj.get("choices").?.array;
    try std.testing.expectEqual(@as(usize, 1), choices.items.len);

    const choice = choices.items[0].object;
    try std.testing.expectEqual(@as(i64, 0), choice.get("index").?.integer);

    const delta = choice.get("delta").?.object;
    try std.testing.expectEqualStrings("Hi there", delta.get("content").?.string);

    // finish_reason should be null for content deltas
    try std.testing.expect(choice.get("finish_reason").? == .null);
}

test "format_transformer - transformSseEvent same format returns copy" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const input =
        \\{"type":"content_block_delta","delta":{"text":"test"}}
    ;

    const output = try ft.transformSseEvent(input, .anthropic, .anthropic);
    defer allocator.free(output);

    try std.testing.expectEqualStrings(input, output);
}

test "format_transformer - transformSseEvent with finish_reason mapping" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    // Test OpenAI "stop" → Anthropic "end_turn"
    {
        const input =
            \\{"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}
        ;
        const output = try ft.transformSseEvent(input, .openai_chat, .anthropic);
        defer allocator.free(output);

        var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
        defer parsed.deinit();

        const obj = parsed.value.object;
        try std.testing.expectEqualStrings("message_delta", obj.get("type").?.string);
        const delta = obj.get("delta").?.object;
        try std.testing.expectEqualStrings("end_turn", delta.get("stop_reason").?.string);
    }

    // Test OpenAI "length" → Anthropic "max_tokens"
    {
        const input =
            \\{"choices":[{"index":0,"delta":{},"finish_reason":"length"}]}
        ;
        const output = try ft.transformSseEvent(input, .openai_chat, .anthropic);
        defer allocator.free(output);

        var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
        defer parsed.deinit();

        const delta = parsed.value.object.get("delta").?.object;
        try std.testing.expectEqualStrings("max_tokens", delta.get("stop_reason").?.string);
    }

    // Test OpenAI "tool_calls" → Anthropic "tool_use"
    {
        const input =
            \\{"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}
        ;
        const output = try ft.transformSseEvent(input, .openai_chat, .anthropic);
        defer allocator.free(output);

        var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
        defer parsed.deinit();

        const delta = parsed.value.object.get("delta").?.object;
        try std.testing.expectEqualStrings("tool_use", delta.get("stop_reason").?.string);
    }

    // Test Anthropic "end_turn" → OpenAI "stop"
    {
        const input =
            \\{"type":"message_delta","delta":{"stop_reason":"end_turn"}}
        ;
        const output = try ft.transformSseEvent(input, .anthropic, .openai_chat);
        defer allocator.free(output);

        var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
        defer parsed.deinit();

        const choices = parsed.value.object.get("choices").?.array;
        const choice = choices.items[0].object;
        try std.testing.expectEqualStrings("stop", choice.get("finish_reason").?.string);
    }

    // Test Anthropic "max_tokens" → OpenAI "length"
    {
        const input =
            \\{"type":"message_delta","delta":{"stop_reason":"max_tokens"}}
        ;
        const output = try ft.transformSseEvent(input, .anthropic, .openai_chat);
        defer allocator.free(output);

        var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
        defer parsed.deinit();

        const choices = parsed.value.object.get("choices").?.array;
        const choice = choices.items[0].object;
        try std.testing.expectEqualStrings("length", choice.get("finish_reason").?.string);
    }

    // Test Anthropic "tool_use" → OpenAI "tool_calls"
    {
        const input =
            \\{"type":"message_delta","delta":{"stop_reason":"tool_use"}}
        ;
        const output = try ft.transformSseEvent(input, .anthropic, .openai_chat);
        defer allocator.free(output);

        var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
        defer parsed.deinit();

        const choices = parsed.value.object.get("choices").?.array;
        const choice = choices.items[0].object;
        try std.testing.expectEqualStrings("tool_calls", choice.get("finish_reason").?.string);
    }
}

test "format_transformer - transformSseEvent malformed json returns copy" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const input = "not valid json at all";
    const output = try ft.transformSseEvent(input, .openai_chat, .anthropic);
    defer allocator.free(output);

    try std.testing.expectEqualStrings(input, output);
}

test "format_transformer - transformSseEvent preserves usage openai to anthropic" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const input =
        \\{"choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":15,"completion_tokens":7}}
    ;

    const output = try ft.transformSseEvent(input, .openai_chat, .anthropic);
    defer allocator.free(output);

    var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
    defer parsed.deinit();

    const usage = parsed.value.object.get("usage").?.object;
    try std.testing.expectEqual(@as(i64, 15), usage.get("input_tokens").?.integer);
    try std.testing.expectEqual(@as(i64, 7), usage.get("output_tokens").?.integer);
}

test "format_transformer - transformSseEvent preserves usage anthropic to openai" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const input =
        \\{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"input_tokens":20,"output_tokens":10}}
    ;

    const output = try ft.transformSseEvent(input, .anthropic, .openai_chat);
    defer allocator.free(output);

    var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
    defer parsed.deinit();

    const usage = parsed.value.object.get("usage").?.object;
    try std.testing.expectEqual(@as(i64, 20), usage.get("prompt_tokens").?.integer);
    try std.testing.expectEqual(@as(i64, 10), usage.get("completion_tokens").?.integer);
    try std.testing.expectEqual(@as(i64, 30), usage.get("total_tokens").?.integer);
}

test "format_transformer - transformToolUseAnthropicToOpenAI basic conversion" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const input =
        \\{"type":"tool_use","id":"toolu_abc123","name":"get_weather","input":{"location":"SF","units":"celsius"}}
    ;

    const output = try ft.transformToolUseAnthropicToOpenAI(input);
    defer allocator.free(output);

    var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("toolu_abc123", obj.get("id").?.string);
    try std.testing.expectEqualStrings("function", obj.get("type").?.string);

    const func = obj.get("function").?.object;
    try std.testing.expectEqualStrings("get_weather", func.get("name").?.string);

    // arguments should be a stringified JSON
    const args_str = func.get("arguments").?.string;
    var args_parsed = try json.parseFromSlice(json.Value, allocator, args_str, .{});
    defer args_parsed.deinit();

    try std.testing.expectEqualStrings("SF", args_parsed.value.object.get("location").?.string);
    try std.testing.expectEqualStrings("celsius", args_parsed.value.object.get("units").?.string);
}

test "format_transformer - transformToolCallOpenAIToAnthropic basic conversion" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const input =
        \\{"id":"call_xyz789","type":"function","function":{"name":"get_weather","arguments":"{\"location\":\"SF\",\"units\":\"celsius\"}"}}
    ;

    const output = try ft.transformToolCallOpenAIToAnthropic(input);
    defer allocator.free(output);

    var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("tool_use", obj.get("type").?.string);
    try std.testing.expectEqualStrings("call_xyz789", obj.get("id").?.string);
    try std.testing.expectEqualStrings("get_weather", obj.get("name").?.string);

    const input_obj = obj.get("input").?.object;
    try std.testing.expectEqualStrings("SF", input_obj.get("location").?.string);
    try std.testing.expectEqualStrings("celsius", input_obj.get("units").?.string);
}

test "format_transformer - tool_use round-trip Anthropic to OpenAI to Anthropic preserves fields" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const original =
        \\{"type":"tool_use","id":"toolu_roundtrip","name":"search","input":{"query":"zig lang","limit":10}}
    ;

    // Anthropic → OpenAI
    const openai_output = try ft.transformToolUseAnthropicToOpenAI(original);
    defer allocator.free(openai_output);

    // OpenAI → Anthropic
    const anthropic_output = try ft.transformToolCallOpenAIToAnthropic(openai_output);
    defer allocator.free(anthropic_output);

    var parsed = try json.parseFromSlice(json.Value, allocator, anthropic_output, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("tool_use", obj.get("type").?.string);
    try std.testing.expectEqualStrings("toolu_roundtrip", obj.get("id").?.string);
    try std.testing.expectEqualStrings("search", obj.get("name").?.string);

    const input_obj = obj.get("input").?.object;
    try std.testing.expectEqualStrings("zig lang", input_obj.get("query").?.string);
    try std.testing.expectEqual(@as(i64, 10), input_obj.get("limit").?.integer);
}

test "format_transformer - tool_use handles missing fields gracefully" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    // Anthropic tool_use with missing input field
    {
        const input =
            \\{"type":"tool_use","id":"toolu_no_input","name":"ping"}
        ;
        const output = try ft.transformToolUseAnthropicToOpenAI(input);
        defer allocator.free(output);

        var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
        defer parsed.deinit();

        const func = parsed.value.object.get("function").?.object;
        try std.testing.expectEqualStrings("ping", func.get("name").?.string);
        // Should default to "{}" when input is missing
        try std.testing.expectEqualStrings("{}", func.get("arguments").?.string);
    }

    // OpenAI tool_call with missing function field
    {
        const input =
            \\{"id":"call_no_func","type":"function"}
        ;
        const output = try ft.transformToolCallOpenAIToAnthropic(input);
        defer allocator.free(output);

        var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
        defer parsed.deinit();

        const obj = parsed.value.object;
        try std.testing.expectEqualStrings("tool_use", obj.get("type").?.string);
        try std.testing.expectEqualStrings("call_no_func", obj.get("id").?.string);
        // input should default to empty object
        try std.testing.expectEqual(@as(usize, 0), obj.get("input").?.object.count());
    }

    // OpenAI tool_call with function but missing arguments
    {
        const input =
            \\{"id":"call_no_args","type":"function","function":{"name":"noop"}}
        ;
        const output = try ft.transformToolCallOpenAIToAnthropic(input);
        defer allocator.free(output);

        var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
        defer parsed.deinit();

        const obj = parsed.value.object;
        try std.testing.expectEqualStrings("noop", obj.get("name").?.string);
        try std.testing.expectEqual(@as(usize, 0), obj.get("input").?.object.count());
    }
}

test "format_transformer - transformRequestAnthropicToResponses basic" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const input =
        \\{"model":"claude-3-5-sonnet","max_tokens":2048,"system":"Be concise","messages":[{"role":"user","content":"Hello"}]}
    ;

    const output = try ft.transformRequestAnthropicToResponses(input);
    defer allocator.free(output);

    var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("claude-3-5-sonnet", obj.get("model").?.string);
    try std.testing.expectEqual(@as(i64, 2048), obj.get("max_output_tokens").?.integer);
    try std.testing.expectEqualStrings("Be concise", obj.get("instructions").?.string);
    try std.testing.expect(obj.get("max_tokens") == null);
    try std.testing.expect(obj.get("system") == null);

    const items = obj.get("input").?.array;
    try std.testing.expectEqual(@as(usize, 1), items.items.len);
    try std.testing.expectEqualStrings("user", items.items[0].object.get("role").?.string);
}

test "format_transformer - transformRequestResponsesToAnthropic basic" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const input =
        \\{"model":"gpt-4o","max_output_tokens":1024,"instructions":"Be helpful","input":[{"role":"user","content":"Hi"}]}
    ;

    const output = try ft.transformRequestResponsesToAnthropic(input);
    defer allocator.free(output);

    var parsed = try json.parseFromSlice(json.Value, allocator, output, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("gpt-4o", obj.get("model").?.string);
    try std.testing.expectEqual(@as(i64, 1024), obj.get("max_tokens").?.integer);
    try std.testing.expectEqualStrings("Be helpful", obj.get("system").?.string);
    try std.testing.expect(obj.get("max_output_tokens") == null);
    try std.testing.expect(obj.get("instructions") == null);

    const msgs = obj.get("messages").?.array;
    try std.testing.expectEqual(@as(usize, 1), msgs.items.len);
    try std.testing.expectEqualStrings("user", msgs.items[0].object.get("role").?.string);
}

test "format_transformer - Responses API round-trip preserves fields" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const original =
        \\{"model":"claude-3-5-sonnet","max_tokens":4096,"system":"You are helpful","messages":[{"role":"user","content":"Test"}],"temperature":0.7}
    ;

    const responses_fmt = try ft.transformRequestAnthropicToResponses(original);
    defer allocator.free(responses_fmt);

    const back = try ft.transformRequestResponsesToAnthropic(responses_fmt);
    defer allocator.free(back);

    var parsed = try json.parseFromSlice(json.Value, allocator, back, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("claude-3-5-sonnet", obj.get("model").?.string);
    try std.testing.expectEqual(@as(i64, 4096), obj.get("max_tokens").?.integer);
    try std.testing.expectEqualStrings("You are helpful", obj.get("system").?.string);

    const msgs = obj.get("messages").?.array;
    try std.testing.expectEqual(@as(usize, 1), msgs.items.len);
    try std.testing.expectEqualStrings("Test", msgs.items[0].object.get("content").?.string);
}

test "format_transformer - transformRequestAnthropicToResponses invalid json" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const result = ft.transformRequestAnthropicToResponses("not json");
    try std.testing.expectError(error.SyntaxError, result);
}

test "format_transformer - transformRequestResponsesToAnthropic invalid json" {
    const allocator = std.testing.allocator;
    var ft = FormatTransformer.init(allocator);
    defer ft.deinit();

    const result = ft.transformRequestResponsesToAnthropic("not json");
    try std.testing.expectError(error.SyntaxError, result);
}

test "format_transformer - mapReasoningEffort adaptive returns xhigh" {
    const result = FormatTransformer.mapReasoningEffort("adaptive", null);
    try std.testing.expectEqualStrings("xhigh", result.?);
}

test "format_transformer - mapReasoningEffort enabled low budget" {
    const result = FormatTransformer.mapReasoningEffort("enabled", 2000);
    try std.testing.expectEqualStrings("low", result.?);
}

test "format_transformer - mapReasoningEffort enabled medium budget" {
    const result = FormatTransformer.mapReasoningEffort("enabled", 8000);
    try std.testing.expectEqualStrings("medium", result.?);
}

test "format_transformer - mapReasoningEffort enabled high budget" {
    const result = FormatTransformer.mapReasoningEffort("enabled", 16000);
    try std.testing.expectEqualStrings("high", result.?);
}

test "format_transformer - mapReasoningEffort enabled boundary 3999 is low" {
    const result = FormatTransformer.mapReasoningEffort("enabled", 3999);
    try std.testing.expectEqualStrings("low", result.?);
}

test "format_transformer - mapReasoningEffort enabled boundary 4000 is medium" {
    const result = FormatTransformer.mapReasoningEffort("enabled", 4000);
    try std.testing.expectEqualStrings("medium", result.?);
}

test "format_transformer - mapReasoningEffort enabled boundary 15999 is medium" {
    const result = FormatTransformer.mapReasoningEffort("enabled", 15999);
    try std.testing.expectEqualStrings("medium", result.?);
}

test "format_transformer - mapReasoningEffort disabled returns null" {
    const result = FormatTransformer.mapReasoningEffort("disabled", null);
    try std.testing.expect(result == null);
}

test "format_transformer - mapReasoningEffort null type returns null" {
    const result = FormatTransformer.mapReasoningEffort(null, null);
    try std.testing.expect(result == null);
}

test "format_transformer - mapReasoningEffort enabled no budget defaults to low" {
    const result = FormatTransformer.mapReasoningEffort("enabled", null);
    try std.testing.expectEqualStrings("low", result.?);
}
