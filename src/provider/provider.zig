//! Provider - Provider Main Entry (similar to @ai-sdk/xxx's createXxx functions)
//!
//! Provider is the entry point for model access, responsible for creating LanguageModel instances

const std = @import("std");
const http = @import("http");
const chat_pkg = @import("chat");
const types = @import("types");
const registry = @import("registry");
const language_model = @import("language_model");

pub const ProviderType = types.ProviderType;
pub const ProviderConfig = types.ProviderConfig;
pub const Model = types.Model;
pub const LanguageModel = language_model.LanguageModel;
pub const WrappedLanguageModel = language_model.WrappedLanguageModel;
pub const Middleware = types.Middleware;

// ============================================================================
// Provider - Provider Main Entry
// ============================================================================

pub const Provider = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    provider_type: ProviderType,
    config: ProviderConfig,
    api_key: []const u8,

    /// Create provider instance (auto-detects provider via model string)
    ///
    /// Usage example:
    ///   var provider = try Provider.create(allocator, io, api_key, "google/gemini-1.5-flash");
    ///   const model = provider.languageModel(http_client, "gemini-1.5-flash");
    pub fn create(allocator: std.mem.Allocator, io: std.Io, api_key: []const u8, model_str: []const u8) !Provider {
        const model = try Model.parse(model_str);
        const config = registry.getProviderConfig(model.provider);

        return Provider{
            .allocator = allocator,
            .io = io,
            .provider_type = model.provider,
            .config = config,
            .api_key = try allocator.dupe(u8, api_key),
        };
    }

    /// Create provider with custom configuration
    pub fn createCustom(allocator: std.mem.Allocator, io: std.Io, api_key: []const u8, base_url: []const u8, auth_type: http.AuthType, provider_type: ProviderType) !Provider {
        const config = ProviderConfig{
            .base_url = base_url,
            .auth_type = auth_type,
        };

        return Provider{
            .allocator = allocator,
            .io = io,
            .provider_type = provider_type,
            .config = config,
            .api_key = try allocator.dupe(u8, api_key),
        };
    }

    pub fn deinit(self: *Provider) void {
        self.allocator.free(self.api_key);
    }

    /// Create HTTP client (lazy-loaded, for LanguageModel to use)
    pub fn createHttpClient(self: *Provider) http.HttpClient {
        return http.HttpClient.initWithAuthType(
            self.allocator,
            self.io,
            self.config.base_url,
            self.api_key,
            null,
            60000,
            self.config.auth_type,
        );
    }

    /// Get language model (similar to Vercel AI SDK's languageModel(modelId))
    ///
    /// Usage example:
    ///   const model = provider.languageModel(http_client, "gpt-4o");
    ///   const model = provider.languageModel(http_client, "gemini-1.5-flash");
    pub fn languageModel(self: *Provider, http_client: *http.HttpClient, model_name: []const u8) LanguageModel {
        return LanguageModel.init(self.allocator, http_client, self.provider_type, model_name);
    }

    /// Get provider type
    pub fn getProviderType(self: *Provider) ProviderType {
        return self.provider_type;
    }

    /// Get base URL
    pub fn getBaseUrl(self: *Provider) []const u8 {
        return self.config.base_url;
    }
};

// ============================================================================
// Client - Backward-compatible Client Wrapper (preserves original API)
// ============================================================================

pub const Client = struct {
    allocator: std.mem.Allocator,
    provider_type: ProviderType,
    model: []const u8,
    http_client: http.HttpClient,

    /// Create client (auto-detects provider via model string)
    pub fn create(allocator: std.mem.Allocator, io: std.Io, api_key: []const u8, model_str: []const u8) !Client {
        const model = try Model.parse(model_str);
        const config = registry.getProviderConfig(model.provider);

        return Client{
            .allocator = allocator,
            .provider_type = model.provider,
            .model = try allocator.dupe(u8, model.name),
            .http_client = http.HttpClient.initWithAuthType(
                allocator,
                io,
                config.base_url,
                api_key,
                null,
                60000,
                config.auth_type,
            ),
        };
    }

    /// Create client for custom provider
    pub fn createCustom(allocator: std.mem.Allocator, io: std.Io, api_key: []const u8, base_url: []const u8, auth_type: http.AuthType, provider_type: ProviderType, model_name: []const u8) !Client {
        return Client{
            .allocator = allocator,
            .provider_type = provider_type,
            .model = try allocator.dupe(u8, model_name),
            .http_client = http.HttpClient.initWithAuthType(
                allocator,
                io,
                base_url,
                api_key,
                null,
                60000,
                auth_type,
            ),
        };
    }

    /// Default initialization (OpenAI) - backward compatible
    pub fn init(allocator: std.mem.Allocator, io: std.Io, api_key: []const u8) Client {
        return create(allocator, io, api_key, "openai/gpt-4o") catch unreachable;
    }

    /// Backward compatible: initialize with custom base URL
    pub fn initWithBaseUrl(allocator: std.mem.Allocator, io: std.Io, api_key: []const u8, base_url: []const u8) Client {
        return createCustom(allocator, io, api_key, base_url, .bearer, .openai, "gpt-4o") catch unreachable;
    }

    pub fn deinit(self: *Client) void {
        self.allocator.free(self.model);
        self.http_client.deinit();
    }

    /// Get language model
    pub fn languageModel(self: *Client) LanguageModel {
        return LanguageModel.init(self.allocator, &self.http_client, self.provider_type, self.model);
    }

    /// Direct completion (simple API)
    pub fn complete(self: *Client, messages: []const chat_pkg.Message) !chat_pkg.ChatCompletion {
        const model = self.languageModel();
        return try model.complete(.{
            .messages = messages,
            .model = self.model,
            .stream = false,
        });
    }

    /// Get provider
    pub fn getProvider(self: *Client) ProviderType {
        return self.provider_type;
    }

    /// Get model name
    pub fn getModel(self: *Client) []const u8 {
        return self.model;
    }

    /// Get HTTP client
    pub fn getHttpClient(self: *Client) *http.HttpClient {
        return &self.http_client;
    }
};

/// OpenAI alias (backward compatible)
pub const OpenAI = Client;
