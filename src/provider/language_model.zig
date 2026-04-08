//! LanguageModel - Wrapper for specific models (similar to Vercel AI SDK's languageModel)
//!
//! LanguageModel is responsible for interacting with specific models, selecting the correct request/response handling based on provider type
//!
//! Fallback mechanism: If the registered provider call fails, it falls back to OpenAI compatible interface

const std = @import("std");
const types = @import("types");
const http_mod = @import("http");
const chat_pkg = @import("chat");
const openai = @import("openai");
const anthropic = @import("anthropic");
const google = @import("google");

pub const ProviderType = types.ProviderType;
pub const Model = types.Model;
pub const Middleware = types.Middleware;
pub const PreRequestMiddleware = types.PreRequestMiddleware;
pub const PostResponseMiddleware = types.PostResponseMiddleware;

// ============================================================================
// WrappedLanguageModel - LanguageModel with Middleware
// ============================================================================

pub const WrappedLanguageModel = struct {
    allocator: std.mem.Allocator,
    inner: *LanguageModel,
    middlewares: []Middleware,

    pub fn complete(self: *WrappedLanguageModel, params: chat_pkg.CreateChatCompletionParams) !chat_pkg.ChatCompletion {
        var transformed_params = params;

        // Apply pre-request middlewares
        for (self.middlewares) |middleware| {
            if (middleware.pre_request) |pre| {
                try pre(self.allocator, &transformed_params, self.inner.name);
            }
        }

        // Call the inner model
        var response = try self.inner.complete(transformed_params);

        // Apply post-response middlewares
        for (self.middlewares) |middleware| {
            if (middleware.post_response) |post| {
                try post(self.allocator, &response);
            }
        }

        return response;
    }

    pub fn deinit(self: *WrappedLanguageModel) void {
        self.allocator.free(self.middlewares);
    }
};

// ============================================================================
// LanguageModel - Wrapper for specific models (with Fallback mechanism)
// ============================================================================

pub const LanguageModel = struct {
    allocator: std.mem.Allocator,
    provider: ProviderType,
    name: []const u8,
    http_client: *http_mod.HttpClient,

    /// Create language model
    pub fn init(allocator: std.mem.Allocator, http_client: *http_mod.HttpClient, provider: ProviderType, name: []const u8) LanguageModel {
        return .{
            .allocator = allocator,
            .provider = provider,
            .name = name,
            .http_client = http_client,
        };
    }

    pub fn deinit(self: *LanguageModel) void {
        _ = self;
    }

    /// Send chat completion request (with Fallback mechanism)
    ///
    /// If the registered provider implementation fails, it automatically falls back to OpenAI compatible interface
    pub fn complete(self: *const LanguageModel, params: chat_pkg.CreateChatCompletionParams) !chat_pkg.ChatCompletion {
        // Step 1: Try to use provider-specific request transformer
        var transformed: []u8 = undefined;
        var transformed_needs_free = false;
        errdefer if (transformed_needs_free) self.allocator.free(transformed);

        transformed = transformRequest(self.allocator, self.provider, params) catch |err| {
            // If provider-specific transform fails, fall back to OpenAI compatible format
            std.log.debug("Provider {} request transform failed: {}, falling back to OpenAI format", .{ self.provider, err });
            transformed = try openai.transformRequest(self.allocator, params);
            transformed_needs_free = true;
            return self.completeWithTransformed(transformed, transformed_needs_free);
        };
        transformed_needs_free = true;

        return self.completeWithTransformed(transformed, false);
    }

    /// Complete chat with transformed request
    fn completeWithTransformed(self: *const LanguageModel, transformed: []u8, transformed_needs_free: bool) !chat_pkg.ChatCompletion {
        defer if (transformed_needs_free) self.allocator.free(transformed);

        // Step 2: Send request using provider-specific endpoint
        const endpoint = try getEndpoint(self.allocator, self.provider, self.name, false);
        defer self.allocator.free(endpoint);
        const response = try self.http_client.post(endpoint, transformed);
        errdefer self.allocator.free(response);

        // Step 3: Try to use provider-specific response parser, fall back to OpenAI format on failure
        return parseResponseWithFallback(self.allocator, self.provider, response);
    }

    /// Send streaming chat completion request
    pub fn completeStream(self: *const LanguageModel, params: chat_pkg.CreateChatCompletionParams) ![]u8 {
        const transformed = try transformRequest(self.allocator, self.provider, params);
        defer self.allocator.free(transformed);

        // Use provider-specific endpoint (streaming)
        const endpoint = try getEndpoint(self.allocator, self.provider, self.name, true);
        defer self.allocator.free(endpoint);
        const response = try self.http_client.post(endpoint, transformed);

        // Transfer ownership to caller - do NOT free here
        return response;
    }
};

// ============================================================================
// Request Transformer - Convert common parameters to provider-specific format
// ============================================================================

fn transformRequest(allocator: std.mem.Allocator, provider: ProviderType, params: chat_pkg.CreateChatCompletionParams) ![]u8 {
    return switch (provider) {
        .openai, .moonshot, .minimax, .deepseek, .cohere, .fireworks, .cerebras, .mistral, .perplexity, .openai_compatible => openai.transformRequest(allocator, params),
        .anthropic => anthropic.transformRequest(allocator, params),
        .google => google.transformRequest(allocator, params),
        .custom => openai.transformRequest(allocator, params), // Custom defaults to OpenAI format
    };
}

// ============================================================================
// Endpoint Helper - Get provider-specific API endpoint
// ============================================================================

/// Get provider-specific API endpoint path
fn getEndpoint(allocator: std.mem.Allocator, provider: ProviderType, model: []const u8, streaming: bool) ![]const u8 {
    return switch (provider) {
        .google => if (streaming)
            try std.fmt.allocPrint(allocator, "/models/{s}:streamGenerateContent", .{model})
        else
            try std.fmt.allocPrint(allocator, "/models/{s}:generateContent", .{model}),
        else => try std.fmt.allocPrint(allocator, "/chat/completions", .{}),
    };
}

// ============================================================================
// Response Parser - Convert provider response to common format (with Fallback)
// ============================================================================

/// Use provider-specific parser, fall back to OpenAI compatible format on failure
fn parseResponseWithFallback(allocator: std.mem.Allocator, provider: ProviderType, response: []const u8) !chat_pkg.ChatCompletion {
    // Try provider-specific parser
    if (parseResponse(allocator, provider, response)) |result| {
        return result;
    } else |err| {
        // If parsing fails, try OpenAI compatible format as fallback
        std.log.debug("Provider {} response parse failed: {}, falling back to OpenAI format", .{ provider, err });
        return openai.parseResponse(allocator, response);
    }
}

/// Main response parsing function
fn parseResponse(allocator: std.mem.Allocator, provider: ProviderType, response: []const u8) !chat_pkg.ChatCompletion {
    return switch (provider) {
        .openai, .moonshot, .minimax, .deepseek, .cohere, .fireworks, .cerebras, .mistral, .perplexity, .openai_compatible, .google => openai.parseResponse(allocator, response),
        .anthropic => anthropic.parseResponse(allocator, response),
        .custom => openai.parseResponse(allocator, response),
    };
}
