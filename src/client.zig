//! OpenAI Client Main Module
//!
//! Aligned with openai-go design, providing convenient API access
//!
//! Supports multiple providers, following Vercel AI SDK design philosophy:
//! - Model string contains provider info (e.g., "openai/gpt-4o", "google/gemini-1.5-flash")
//! - Top-level interface definition, each provider implements specific methods
//!
//! Usage Example:
//!   var client = try Client.create(allocator, api_key, "google/gemini-1.5-flash");
//!   var client = try Client.create(allocator, api_key, "gpt-4o");  // default openai

const std = @import("std");

// ============================================================================
// Re-exports from provider.zig
// ============================================================================

pub const http_pkg = @import("http");
pub const chat = @import("chat");
pub const ProviderType = @import("provider").ProviderType;
pub const Model = @import("provider").Model;
pub const ClientProtocol = @import("provider").ClientProtocol;
pub const BaseClient = @import("provider").BaseClient;
pub const Client = @import("provider").Client;
pub const OpenAI = Client;

// Re-export types for convenience
pub const AuthType = http_pkg.AuthType;
pub const ProviderConfig = @import("provider").ProviderConfig;
pub const getProviderConfig = @import("provider").getProviderConfig;
