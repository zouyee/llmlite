//! Chat Completions Handler for llmlite Proxy
//!
//! Handles /v1/chat/completions requests

const std = @import("std");
const time_compat = @import("time_compat");
const http = @import("../../http.zig");
const chat_pkg = @import("../../chat.zig");
const types = @import("../../provider/types.zig");
const registry = @import("../../provider/registry.zig");

pub const ChatHandler = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    pub fn handle(self: *ChatHandler, request: *std.http.Server.Request, api_key: []const u8) !void {
        const body = try request.reader().allocRemaining(self.allocator, .limited(1_000_000));
        defer self.allocator.free(body);

        const chat_request = try std.json.parseFromSlice(
            ProxyChatCompletionRequest,
            self.allocator,
            body,
            .{},
        );
        defer chat_request.deinit();

        std.log.info("chat completions: model={s}", .{chat_request.value.model});

        // Route to provider based on model
        const target = self.routeModel(chat_request.value.model);
        std.log.info("routing to provider={s} model={s}", .{ target.provider_type.toString(), target.model });

        // Get provider config
        const provider_config = registry.getProviderConfig(target.provider_type);

        // Create provider-specific HTTP client
        var provider_http = http.HttpClient.initWithAuthType(
            self.allocator,
            provider_config.base_url,
            api_key,
            null,
            30000,
            provider_config.auth_type,
        );
        defer provider_http.deinit();

        // Transform request to provider format
        const transformed = try transformRequest(self.allocator, target.provider_type, &chat_request.value);
        defer self.allocator.free(transformed);

        // Get endpoint
        const endpoint = try getEndpoint(self.allocator, target.provider_type, target.model);
        defer self.allocator.free(endpoint);

        // Make request
        const response = try provider_http.post(endpoint, transformed);
        defer self.allocator.free(response);

        // Parse response
        const parsed = try parseResponse(self.allocator, self.io, target.provider_type, response);
        defer parsed.deinit();

        // Convert to proxy response format
        const proxy_response = try convertToProxyResponse(self.allocator, parsed);
        defer self.allocator.free(proxy_response);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = proxy_response,
        });
    }

    fn routeModel(self: *ChatHandler, model: []const u8) ProviderTarget {
        _ = self;
        // Check if model has provider prefix (e.g., "openai/gpt-4o")
        if (std.mem.find(u8, model, "/")) |idx| {
            const provider_str = model[0..idx];
            const model_name = model[idx + 1 ..];
            if (types.ProviderType.fromString(provider_str)) |provider_type| {
                return .{ .provider_type = provider_type, .model = model_name };
            }
        }
        // Default to OpenAI
        return .{ .provider_type = .openai, .model = model };
    }
};

pub const ProviderTarget = struct {
    provider_type: types.ProviderType,
    model: []const u8,
};

pub const ProxyChatCompletionRequest = struct {
    model: []const u8,
    messages: []ProxyChatMessage,
    stream: ?bool = false,
    temperature: ?f32 = null,
    top_p: ?f32 = null,
    max_tokens: ?u32 = null,
    n: ?u32 = null,
    stop: ?[]const u8 = null,
};

pub const ProxyChatMessage = struct {
    role: []const u8,
    content: []const u8,
    name: ?[]const u8 = null,
};

fn transformRequest(allocator: std.mem.Allocator, provider: types.ProviderType, req: *const ProxyChatCompletionRequest) ![]u8 {
    // Most providers use OpenAI format
    return switch (provider) {
        .openai, .moonshot, .minimax, .deepseek, .cohere, .fireworks, .cerebras, .mistral, .perplexity, .openai_compatible => try openaiTransformRequest(allocator, req),
        .anthropic => try anthropicTransformRequest(allocator, req),
        .google => try googleTransformRequest(allocator, req),
        .custom => try openaiTransformRequest(allocator, req),
    };
}

fn openaiTransformRequest(allocator: std.mem.Allocator, req: *const ProxyChatCompletionRequest) ![]u8 {
    var messages_json = std.ArrayList(u8).empty;
    defer messages_json.deinit(allocator);

    try messages_json.appendSlice(allocator, "[");
    for (req.messages, 0..) |msg, i| {
        if (i > 0) try messages_json.appendSlice(allocator, ",");
        try std.fmt.format(messages_json.writer(), "{{\"role\":\"{s}\",\"content\":\"{s}\"}}", .{ msg.role, msg.content });
    }
    try messages_json.appendSlice(allocator, "]");

    var result = std.ArrayList(u8).empty;
    defer result.deinit(allocator);

    try std.fmt.format(result.writer(), "{{\"model\":\"{s}\",\"messages\":{s},\"stream\":{s}", .{
        req.model,
        try messages_json.toOwnedSlice(allocator),
        if (req.stream) "true" else "false",
    });

    if (req.temperature) |v| {
        try std.fmt.format(result.writer(), ",\"temperature\":{d}", .{v});
    }
    if (req.max_tokens) |v| {
        try std.fmt.format(result.writer(), ",\"max_tokens\":{d}", .{v});
    }
    if (req.top_p) |v| {
        try std.fmt.format(result.writer(), ",\"top_p\":{d}", .{v});
    }

    try result.appendSlice(allocator, "}");
    return result.toOwnedSlice(allocator);
}

fn anthropicTransformRequest(allocator: std.mem.Allocator, req: *const ProxyChatCompletionRequest) ![]u8 {
    // Extract system message and combine with first user message
    var system_content: ?[]const u8 = null;
    var user_content = std.ArrayList(u8).empty;
    defer user_content.deinit(allocator);

    for (req.messages) |msg| {
        if (std.mem.eql(u8, msg.role, "system")) {
            if (system_content == null) {
                system_content = msg.content;
            }
        } else if (std.mem.eql(u8, msg.role, "user")) {
            if (user_content.items.len > 0) {
                try user_content.appendSlice(allocator, "\n");
            }
            try user_content.appendSlice(allocator, msg.content);
        }
    }

    var result = std.ArrayList(u8).empty;
    defer result.deinit(allocator);

    try std.fmt.format(result.writer(), "{{\"model\":\"{s}\",\"messages\":[{{\"role\":\"user\",\"content\":\"{s}\"}}]", .{
        req.model,
        try user_content.toOwnedSlice(allocator),
    });

    if (system_content) |sys| {
        try std.fmt.format(result.writer(), ",\"system\":\"{s}\"", .{sys});
    }
    if (req.max_tokens) |v| {
        try std.fmt.format(result.writer(), ",\"max_tokens\":{d}", .{v});
    }
    if (req.temperature) |v| {
        try std.fmt.format(result.writer(), ",\"temperature\":{d}", .{v});
    }

    try result.appendSlice(allocator, "}");
    return result.toOwnedSlice(allocator);
}

fn googleTransformRequest(allocator: std.mem.Allocator, req: *const ProxyChatCompletionRequest) ![]u8 {
    // Google uses a different format with contents array
    var contents_json = std.ArrayList(u8).empty;
    defer contents_json.deinit(allocator);

    try contents_json.appendSlice(allocator, "[");
    for (req.messages, 0..) |msg, i| {
        if (i > 0) try contents_json.appendSlice(allocator, ",");
        const role_str = if (std.mem.eql(u8, msg.role, "user")) "user" else "model";
        try std.fmt.format(contents_json.writer(), "{{\"role\":\"{s}\",\"parts\":[{{\"text\":\"{s}\"}}]}}", .{ role_str, msg.content });
    }
    try contents_json.appendSlice(allocator, "]");

    return try std.fmt.allocPrint(allocator,
        \\{{"contents":{s}}}
    , .{try contents_json.toOwnedSlice(allocator)});
}

fn getEndpoint(allocator: std.mem.Allocator, provider: types.ProviderType, model: []const u8) ![]u8 {
    return switch (provider) {
        .google => try std.fmt.allocPrint(allocator, "/models/{s}:generateContent", .{model}),
        else => try allocator.dupe(u8, "/chat/completions"),
    };
}

fn parseResponse(allocator: std.mem.Allocator, io: std.Io, provider: types.ProviderType, response: []const u8) !chat_pkg.ChatCompletion {
    return switch (provider) {
        .anthropic => try parseAnthropicResponse(allocator, io, response),
        .google => try parseGoogleResponse(allocator, io, response),
        else => try parseOpenAIResponse(allocator, response),
    };
}

fn parseOpenAIResponse(allocator: std.mem.Allocator, response: []const u8) !chat_pkg.ChatCompletion {
    const parsed = try std.json.parseFromSlice(chat_pkg.ChatCompletion, allocator, response, .{});
    return parsed;
}

fn parseAnthropicResponse(allocator: std.mem.Allocator, io: std.Io, response: []const u8) !chat_pkg.ChatCompletion {
    const parsed = try std.json.parseFromSlice(struct {
        id: []const u8,
        type: []const u8,
        role: []const u8,
        content: []const u8,
        model: []const u8,
        stop_reason: []const u8,
        stop_sequence: ?[]const u8,
        usage: struct {
            input_tokens: u32,
            output_tokens: u32,
        },
    }, allocator, response, .{});
    defer parsed.deinit();

    var choices = try allocator.alloc(chat_pkg.ChatCompletionChoice, 1);
    choices[0] = .{
        .finish_reason = try allocator.dupe(u8, parsed.value.stop_reason),
        .index = 0,
        .logprobs = null,
        .message = .{
            .role = .assistant,
            .content = try allocator.dupe(u8, parsed.value.content),
        },
    };

    return .{
        .id = try allocator.dupe(u8, parsed.value.id),
        .choices = choices,
        .created = @intCast(time_compat.timestamp(io)),
        .model = try allocator.dupe(u8, parsed.value.model),
        .usage = .{
            .prompt_tokens = parsed.value.usage.input_tokens,
            .completion_tokens = parsed.value.usage.output_tokens,
            .total_tokens = parsed.value.usage.input_tokens + parsed.value.usage.output_tokens,
        },
    };
}

fn parseGoogleResponse(allocator: std.mem.Allocator, io: std.Io, response: []const u8) !chat_pkg.ChatCompletion {
    const parsed = try std.json.parseFromSlice(struct {
        candidates: []struct {
            content: struct {
                parts: []struct {
                    text: []const u8,
                },
                role: []const u8,
            },
            finish_reason: []const u8,
        },
        usage_metadata: struct {
            prompt_token_count: u32,
            candidates_token_count: u32,
            total_token_count: u32,
        },
    }, allocator, response, .{});
    defer parsed.deinit();

    var content_buf = std.ArrayList(u8).empty;
    defer content_buf.deinit(allocator);

    if (parsed.value.candidates.len > 0) {
        for (parsed.value.candidates[0].content.parts) |part| {
            if (content_buf.items.len > 0) {
                try content_buf.appendSlice(allocator, "\n");
            }
            try content_buf.appendSlice(allocator, part.text);
        }
    }

    var choices = try allocator.alloc(chat_pkg.ChatCompletionChoice, 1);
    choices[0] = .{
        .finish_reason = if (parsed.value.candidates.len > 0)
            try allocator.dupe(u8, parsed.value.candidates[0].finish_reason)
        else
            try allocator.dupe(u8, "stop"),
        .index = 0,
        .logprobs = null,
        .message = .{
            .role = .assistant,
            .content = try content_buf.toOwnedSlice(allocator),
        },
    };

    return .{
        .id = try std.fmt.allocPrint(allocator, "gemini-{d}", .{time_compat.timestamp(io)}),
        .choices = choices,
        .created = @intCast(time_compat.timestamp(io)),
        .model = "gemini",
        .usage = .{
            .prompt_tokens = parsed.value.usage_metadata.prompt_token_count,
            .completion_tokens = parsed.value.usage_metadata.candidates_token_count,
            .total_tokens = parsed.value.usage_metadata.total_token_count,
        },
    };
}

fn convertToProxyResponse(allocator: std.mem.Allocator, completion: chat_pkg.ChatCompletion) ![]u8 {
    var choices_json = std.ArrayList(u8).empty;
    defer choices_json.deinit(allocator);

    try choices_json.appendSlice(allocator, "[");
    for (completion.choices, 0..) |choice, i| {
        if (i > 0) try choices_json.appendSlice(allocator, ",");
        const role_str = choice.message.role.toString();
        try std.fmt.format(choices_json.writer(),
            \\{{"index":{d},"message":{{"role":"{s}","content":"
        , .{ choice.index, role_str });

        // Escape content for JSON
        if (choice.message.content) |c| {
            for (c) |char| {
                switch (char) {
                    '"' => try choices_json.appendSlice(allocator, "\\\""),
                    '\\' => try choices_json.appendSlice(allocator, "\\\\"),
                    '\n' => try choices_json.appendSlice(allocator, "\\n"),
                    '\r' => try choices_json.appendSlice(allocator, "\\r"),
                    '\t' => try choices_json.appendSlice(allocator, "\\t"),
                    else => try choices_json.append(allocator, char),
                }
            }
        }

        try choices_json.appendSlice(allocator, "\"},\"finish_reason\":\"");
        try choices_json.appendSlice(allocator, choice.finish_reason);
        try choices_json.appendSlice(allocator, "\"}");
    }
    try choices_json.appendSlice(allocator, "]");

    return try std.fmt.allocPrint(allocator,
        \\{{"id":"{s}","object":"chat.completion","created":{d},"model":"{s}","choices":{s},"usage":{{"prompt_tokens":{d},"completion_tokens":{d},"total_tokens":{d}}}}}
    , .{
        completion.id,
        completion.created,
        completion.model,
        try choices_json.toOwnedSlice(allocator),
        completion.usage.prompt_tokens,
        completion.usage.completion_tokens,
        completion.usage.total_tokens,
    });
}
