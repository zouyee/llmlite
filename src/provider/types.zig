const std = @import("std");

pub const http_mod = @import("http");
pub const chat_pkg = @import("chat");

pub const ProviderType = enum {
    openai,
    anthropic,
    google,
    moonshot,
    minimax,
    deepseek,
    cohere,
    fireworks,
    cerebras,
    groq,
    mistral,
    perplexity,
    openai_compatible,
    custom,

    pub fn toString(self: ProviderType) []const u8 {
        return switch (self) {
            .openai => "openai",
            .anthropic => "anthropic",
            .google => "google",
            .moonshot => "moonshot",
            .minimax => "minimax",
            .deepseek => "deepseek",
            .cohere => "cohere",
            .fireworks => "fireworks",
            .cerebras => "cerebras",
            .groq => "groq",
            .mistral => "mistral",
            .perplexity => "perplexity",
            .openai_compatible => "openai-compatible",
            .custom => "custom",
        };
    }

    pub fn fromString(s: []const u8) ?ProviderType {
        inline for (std.meta.fields(ProviderType)) |field| {
            if (std.mem.eql(u8, s, field.name)) {
                return @enumFromInt(field.value);
            }
        }
        return null;
    }
};

pub const ProviderConfig = struct {
    base_url: []const u8,
    auth_type: http_mod.AuthType,
    default_endpoint: ?[]const u8 = null,
};

pub const Model = struct {
    provider: ProviderType,
    name: []const u8,

    pub fn parse(model_str: []const u8) !Model {
        if (std.mem.indexOf(u8, model_str, "/")) |idx| {
            const provider_str = model_str[0..idx];
            const model_name = model_str[idx + 1 ..];
            const provider = ProviderType.fromString(provider_str) orelse {
                return error.InvalidProvider;
            };
            return Model{
                .provider = provider,
                .name = model_name,
            };
        } else {
            return Model{
                .provider = .openai,
                .name = model_str,
            };
        }
    }

    pub fn toString(self: Model) []const u8 {
        return std.fmt.comptimePrint("{s}/{s}", .{
            self.provider.toString(),
            self.name,
        });
    }
};

pub const PreRequestMiddleware = fn (
    allocator: std.mem.Allocator,
    params: *chat_pkg.CreateChatCompletionParams,
    model_name: []const u8,
) anyerror!void;

pub const PostResponseMiddleware = fn (
    allocator: std.mem.Allocator,
    response: *chat_pkg.ChatCompletion,
) anyerror!void;

pub const Middleware = struct {
    pre_request: ?PreRequestMiddleware = null,
    post_response: ?PostResponseMiddleware = null,
};
