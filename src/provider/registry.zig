//! Provider Registry - Provider Default Configuration
//!
//! Default base URL and authentication type for each provider

const std = @import("std");
const types = @import("types");

pub const ProviderType = types.ProviderType;
pub const ProviderConfig = types.ProviderConfig;

/// Provider default configuration table
const PROVIDER_CONFIGS: []const struct { provider: ProviderType, config: ProviderConfig } = &.{
    .{ .provider = .openai, .config = ProviderConfig{
        .base_url = "https://api.openai.com/v1",
        .auth_type = .bearer,
    } },
    .{ .provider = .anthropic, .config = ProviderConfig{
        .base_url = "https://api.anthropic.com/v1",
        .auth_type = .bearer,
    } },
    .{
        .provider = .google,
        .config = ProviderConfig{
            .base_url = "https://generativelanguage.googleapis.com/v1beta",
            .auth_type = .api_key,
            .default_endpoint = "/chat/completions", // Fallback for OpenAI compatibility mode
        },
    },
    .{ .provider = .moonshot, .config = ProviderConfig{
        .base_url = "https://api.kimi.com/coding/v1",
        .auth_type = .bearer,
    } },
    .{ .provider = .minimax, .config = ProviderConfig{
        .base_url = "https://api.minimax.chat/v1",
        .auth_type = .bearer,
    } },
    .{ .provider = .deepseek, .config = ProviderConfig{
        .base_url = "https://api.deepseek.com",
        .auth_type = .bearer,
    } },
    .{ .provider = .cohere, .config = ProviderConfig{
        .base_url = "https://api.cohere.ai/v1",
        .auth_type = .bearer,
    } },
    .{ .provider = .fireworks, .config = ProviderConfig{
        .base_url = "https://api.fireworks.ai/v1",
        .auth_type = .bearer,
    } },
    .{ .provider = .cerebras, .config = ProviderConfig{
        .base_url = "https://api.cerebras.ai/v1",
        .auth_type = .bearer,
    } },
    .{ .provider = .mistral, .config = ProviderConfig{
        .base_url = "https://api.mistral.ai/v1",
        .auth_type = .bearer,
    } },
    .{ .provider = .perplexity, .config = ProviderConfig{
        .base_url = "https://api.perplexity.ai",
        .auth_type = .bearer,
    } },
    .{ .provider = .openai_compatible, .config = ProviderConfig{
        .base_url = "https://api.openai.com/v1",
        .auth_type = .bearer,
    } },
};

/// Get provider default configuration
pub fn getProviderConfig(provider: ProviderType) ProviderConfig {
    for (PROVIDER_CONFIGS) |entry| {
        if (entry.provider == provider) {
            return entry.config;
        }
    }
    return .{
        .base_url = "https://api.openai.com/v1",
        .auth_type = .bearer,
    };
}
