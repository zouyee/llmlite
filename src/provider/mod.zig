//! Provider Module - Multi-Provider Support (Vercel AI SDK Style)
//!
//! Design Philosophy:
//! - Provider is the entry point for model access (similar to @ai-sdk/openai's createOpenAI())
//! - LanguageModel is a wrapper for specific models (similar to Vercel AI SDK's languageModel)
//! - Supports middleware wrapping (similar to wrapLanguageModel)
//! - Each Provider has its own RequestTransformer and ResponseParser
//!
//! Usage Example:
//!   var provider = try Provider.create(allocator, api_key, "google/gemini-1.5-flash");
//!   const model = provider.languageModel(http_client, "gpt-4o");
//!   const response = try model.complete(.{messages: &[.{role: .user, content: "Hello"}]});

// Re-export from submodules
pub const types = @import("types");
pub const registry = @import("registry");
pub const openai = @import("openai");
pub const anthropic = @import("anthropic");
pub const google = @import("google");
pub const language_model = @import("language_model");
pub const provider = @import("provider");

// Re-export Gemini advanced APIs
pub const gemini_caches = @import("gemini_caches");
pub const gemini_tunings = @import("gemini_tunings");
pub const gemini_documents = @import("gemini_documents");
pub const gemini_file_search_stores = @import("gemini_file_search_stores");
pub const gemini_operations = @import("gemini_operations");
pub const gemini_tokens = @import("gemini_tokens");

// Re-export commonly used types
pub const ProviderType = types.ProviderType;
pub const ProviderConfig = types.ProviderConfig;
pub const Model = types.Model;
pub const Middleware = types.Middleware;
pub const PreRequestMiddleware = types.PreRequestMiddleware;
pub const PostResponseMiddleware = types.PostResponseMiddleware;
pub const WrappedLanguageModel = language_model.WrappedLanguageModel;
pub const LanguageModel = language_model.LanguageModel;
pub const Provider = provider.Provider;
pub const Client = provider.Client;
pub const OpenAI = provider.OpenAI;

// Backward compatibility - re-export getProviderConfig
pub const getProviderConfig = registry.getProviderConfig;
