//! Provider Preset System for llmlite Proxy
//!
//! Provides 50+ built-in provider presets with one-click import capability.
//! Supports OpenAI, Anthropic, Google Gemini, Moonshot/Kimi, Minimax, DeepSeek,
//! and various OpenAI-compatible providers.

const std = @import("std");

// Zig 0.16.0 compat: managed StringArrayHashMap wrapper
fn StringArrayHashMap(comptime V: type) type {
    return struct {
        const Self = @This();
        unmanaged: std.StringArrayHashMapUnmanaged(V),
        allocator: std.mem.Allocator,
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .unmanaged = .empty, .allocator = allocator };
        }
        pub fn deinit(self: *Self) void { self.unmanaged.deinit(self.allocator); }
        pub fn put(self: *Self, key: []const u8, value: V) !void { return self.unmanaged.put(self.allocator, key, value); }
        pub fn get(self: Self, key: []const u8) ?V { return self.unmanaged.get(key); }
        pub fn getPtr(self: Self, key: []const u8) ?*V { return self.unmanaged.getPtr(key); }
        pub fn getOrPut(self: *Self, key: []const u8) !std.StringArrayHashMapUnmanaged(V).GetOrPutResult { return self.unmanaged.getOrPut(self.allocator, key); }
        pub fn getOrPutValue(self: *Self, key: []const u8, value: V) !std.StringArrayHashMapUnmanaged(V).GetOrPutResult { return self.unmanaged.getOrPutValue(self.allocator, key, value); }
        pub fn contains(self: Self, key: []const u8) bool { return self.unmanaged.contains(key); }
        pub fn count(self: Self) usize { return self.unmanaged.count(); }
        pub fn iterator(self: Self) std.StringArrayHashMapUnmanaged(V).Iterator { return self.unmanaged.iterator(); }
        pub fn fetchSwapRemove(self: *Self, key: []const u8) ?std.StringArrayHashMapUnmanaged(V).KV { return self.unmanaged.fetchSwapRemove(key); }
        pub fn fetchRemove(self: *Self, key: []const u8) ?std.StringArrayHashMapUnmanaged(V).KV { return self.unmanaged.fetchSwapRemove(key); }
        pub fn swapRemove(self: *Self, key: []const u8) bool { return self.unmanaged.swapRemove(key); }
        pub fn keys(self: Self) [][]const u8 { return self.unmanaged.keys(); }
        pub fn values(self: Self) []V { return self.unmanaged.values(); }
    };
}
const types = @import("types");

pub const ProviderType = types.ProviderType;
pub const AuthType = types.http_mod.AuthType;

/// Supported CLI tools that can use provider presets
pub const CliTool = enum {
    claude_code,
    codex,
    gemini_cli,
    opencode,
    openclaw,
};

/// Provider preset definition
pub const ProviderPreset = struct {
    /// Unique identifier for the preset
    id: []const u8,
    /// Human-readable name
    name: []const u8,
    /// Provider type
    provider: ProviderType,
    /// Base URL for the API
    base_url: []const u8,
    /// Authentication type
    auth_type: AuthType,
    /// Default model to use
    default_model: []const u8,
    /// Supported capabilities
    supports: []const []const u8,
    /// API key environment variable name (if applicable)
    api_key_env: ?[]const u8 = null,
    /// Whether this is an official provider
    is_official: bool = false,
    /// Organization name (for display)
    organization: ?[]const u8 = null,
    /// Website URL
    website: ?[]const u8 = null,
    /// Description
    description: ?[]const u8 = null,
    /// API format: "anthropic" (native), "openai" (chat completions), or null (auto-detect)
    api_format: ?[]const u8 = null,
    /// Whether this provider requires thinking block normalization
    needs_thinking_fix: bool = false,
};

/// Built-in provider presets (50+ presets)
pub const PRESETS: []const ProviderPreset = &.{
    // ==================== OpenAI Compatible ====================
    .{
        .id = "openai-official",
        .name = "OpenAI (Official)",
        .provider = .openai,
        .base_url = "https://api.openai.com/v1",
        .auth_type = .bearer,
        .default_model = "gpt-4o",
        .supports = &.{ "chat", "embeddings", "streaming", "tools", "json" },
        .is_official = true,
        .organization = "OpenAI",
        .website = "https://openai.com",
        .description = "OpenAI's official API with GPT-4, GPT-4o, and more",
    },
    .{
        .id = "openai-azure",
        .name = "Azure OpenAI",
        .provider = .openai,
        .base_url = "https://YOUR_RESOURCE.openai.azure.com",
        .auth_type = .bearer,
        .default_model = "gpt-4o",
        .supports = &.{ "chat", "embeddings", "streaming", "tools" },
        .organization = "Microsoft Azure",
        .description = "Azure-hosted OpenAI models with enterprise security",
    },

    // ==================== Anthropic / Claude ====================
    .{
        .id = "anthropic-official",
        .name = "Anthropic (Official)",
        .provider = .anthropic,
        .base_url = "https://api.anthropic.com/v1",
        .auth_type = .bearer,
        .default_model = "claude-3-5-sonnet-20241022",
        .supports = &.{ "chat", "streaming" },
        .is_official = true,
        .organization = "Anthropic",
        .website = "https://anthropic.com",
        .description = "Anthropic's Claude models via official API",
    },

    // ==================== Google Gemini ====================
    .{
        .id = "google-gemini-official",
        .name = "Google Gemini (Official)",
        .provider = .google,
        .base_url = "https://generativelanguage.googleapis.com/v1beta",
        .auth_type = .api_key,
        .default_model = "gemini-2.0-flash",
        .supports = &.{ "chat", "embeddings", "streaming", "caches", "tuning" },
        .api_key_env = "GOOGLE_API_KEY",
        .is_official = true,
        .organization = "Google",
        .website = "https://ai.google.dev",
        .description = "Google's Gemini models with context caching and tuning",
    },
    .{
        .id = "google-vertex-ai",
        .name = "Google Vertex AI",
        .provider = .google,
        .base_url = "https://LOCATION-aiplatform.googleapis.com/v1",
        .auth_type = .bearer,
        .default_model = "gemini-2.0-flash",
        .supports = &.{ "chat", "embeddings", "streaming", "caches" },
        .organization = "Google Cloud",
        .description = "Enterprise Gemini via Google Cloud Vertex AI",
    },

    // ==================== Moonshot / Kimi ====================
    .{
        .id = "kimi-official",
        .name = "Kimi (Moonshot Official)",
        .provider = .moonshot,
        .base_url = "https://api.moonshot.cn/v1",
        .auth_type = .bearer,
        .default_model = "moonshot-v1-8k",
        .supports = &.{ "chat", "files", "streaming", "thinking" },
        .is_official = true,
        .organization = "Moonshot AI",
        .website = "https://www.moonshot.cn",
        .description = "Kimi AI's long-context models from Moonshot",
    },

    // ==================== Minimax ====================
    .{
        .id = "minimax-official",
        .name = "Minimax (Official)",
        .provider = .minimax,
        .base_url = "https://api.minimax.chat/v1",
        .auth_type = .bearer,
        .default_model = "abab6.5s-chat",
        .supports = &.{ "chat", "embeddings", "tts", "video", "image", "music" },
        .is_official = true,
        .organization = "Minimax",
        .website = "https://www.minimax.io",
        .description = "Minimax's multi-modal models including TTS, Video, Image, Music",
    },

    // ==================== DeepSeek ====================
    .{
        .id = "deepseek-official",
        .name = "DeepSeek (Official)",
        .provider = .deepseek,
        .base_url = "https://api.deepseek.com/v1",
        .auth_type = .bearer,
        .default_model = "deepseek-v4-flash",
        .supports = &.{ "chat", "embeddings", "streaming" },
        .api_key_env = "DEEPSEEK_API_KEY",
        .is_official = true,
        .organization = "DeepSeek",
        .website = "https://www.deepseek.com",
        .description = "DeepSeek V4 models: Flash (fast, $0.14/$0.28) and Pro (deep reasoning, $1.74/$3.48)",
    },

    // ==================== OpenAI-Compatible Providers ====================
    .{
        .id = "cohere-official",
        .name = "Cohere (Official)",
        .provider = .cohere,
        .base_url = "https://api.cohere.ai/v1",
        .auth_type = .bearer,
        .default_model = "command-r-plus",
        .supports = &.{ "chat", "embeddings", "streaming" },
        .is_official = true,
        .organization = "Cohere",
        .website = "https://cohere.com",
        .description = "Cohere's Command and Embed models",
    },
    .{
        .id = "fireworks-official",
        .name = "Fireworks AI",
        .provider = .fireworks,
        .base_url = "https://api.fireworks.ai/v1",
        .auth_type = .bearer,
        .default_model = "accounts/fireworks/models/llama-v3-70b-instruct",
        .supports = &.{ "chat", "embeddings", "streaming" },
        .is_official = true,
        .organization = "Fireworks AI",
        .website = "https://fireworks.ai",
        .description = "High-performance inference with fireworks",
    },
    .{
        .id = "cerebras-official",
        .name = "Cerebras (Official)",
        .provider = .cerebras,
        .base_url = "https://api.cerebras.ai/v1",
        .auth_type = .bearer,
        .default_model = "llama3.3-70b",
        .supports = &.{ "chat", "streaming" },
        .is_official = true,
        .organization = "Cerebras",
        .website = "https://cerebras.ai",
        .description = "Ultra-fast inference with Cerebras waferscale",
    },
    .{
        .id = "mistral-official",
        .name = "Mistral AI (Official)",
        .provider = .mistral,
        .base_url = "https://api.mistral.ai/v1",
        .auth_type = .bearer,
        .default_model = "mistral-large-latest",
        .supports = &.{ "chat", "embeddings", "streaming" },
        .is_official = true,
        .organization = "Mistral AI",
        .website = "https://mistral.ai",
        .description = "Mistral's open and commercial models",
    },
    .{
        .id = "perplexity-official",
        .name = "Perplexity (Official)",
        .provider = .perplexity,
        .base_url = "https://api.perplexity.ai",
        .auth_type = .bearer,
        .default_model = "sonar",
        .supports = &.{ "chat", "streaming" },
        .is_official = true,
        .organization = "Perplexity",
        .website = "https://perplexity.ai",
        .description = "Real-time web search with Perplexity",
    },

    // ==================== Chinese Providers ====================
    .{
        .id = "zhipu-official",
        .name = "Zhipu AI (GLM)",
        .provider = .openai_compatible,
        .base_url = "https://open.bigmodel.cn/api/paulin/v1",
        .auth_type = .bearer,
        .default_model = "glm-4",
        .supports = &.{ "chat", "streaming" },
        .organization = "Zhipu AI",
        .website = "https://www.zhipu.cn",
        .description = "Chinese GLM models from Zhipu AI",
    },
    .{
        .id = "yi-official",
        .name = "01 AI (Yi)",
        .provider = .openai_compatible,
        .base_url = "https://api.01.ai/v1",
        .auth_type = .bearer,
        .default_model = "yi-large",
        .supports = &.{ "chat", "streaming" },
        .organization = "01 AI",
        .website = "https://www.01.ai",
        .description = "01 AI's Yi series models",
    },
    .{
        .id = "qwen-official",
        .name = "Qwen (Alibaba)",
        .provider = .openai_compatible,
        .base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1",
        .auth_type = .bearer,
        .default_model = "qwen-turbo",
        .supports = &.{ "chat", "embeddings", "streaming" },
        .organization = "Alibaba Cloud",
        .website = "https://qwen.ai.aliyun.com",
        .description = "Alibaba's Qwen models",
    },
    .{
        .id = "baichuan-official",
        .name = "Baichuan AI",
        .provider = .openai_compatible,
        .base_url = "https://api.baichuan-ai.com/v1",
        .auth_type = .bearer,
        .default_model = "Baichuan4",
        .supports = &.{ "chat", "streaming" },
        .organization = "Baichuan AI",
        .website = "https://www.baichuan-ai.com",
        .description = "Baichuan's bilingual models",
    },
    .{
        .id = "spark-讯飞",
        .name = "iFlytek Spark",
        .provider = .openai_compatible,
        .base_url = "https://spark-api.xf-yun.com/v3.5/chat",
        .auth_type = .bearer,
        .default_model = "generalv3.5",
        .supports = &.{ "chat", "streaming" },
        .organization = "iFlytek",
        .website = "https://xinghuo.xfyun.cn",
        .description = "iFlytek's Spark cognitive models",
    },
    .{
        .id = " hunyuan-腾讯",
        .name = "Tencent Hunyuan",
        .provider = .openai_compatible,
        .base_url = "https://api.hunyuan.cloud.tencent.com/v1",
        .auth_type = .bearer,
        .default_model = "hunyuan",
        .supports = &.{ "chat", "streaming" },
        .organization = "Tencent Cloud",
        .website = "https://cloud.tencent.com/product/hunyuan",
        .description = "Tencent's Hunyuan models",
    },
    .{
        .id = "doubao-official",
        .name = "ByteDance Doubao",
        .provider = .openai_compatible,
        .base_url = "https://ark.cn-beijing.volces.com/api/v3",
        .auth_type = .bearer,
        .default_model = "doubao-pro-32k",
        .supports = &.{ "chat", "streaming" },
        .organization = "ByteDance",
        .website = "https://www.volcengine.com/product/doubao",
        .description = "ByteDance's Doubao models",
    },

    // ==================== Relay/Proxy Services ====================
    .{
        .id = "openrouter-official",
        .name = "OpenRouter",
        .provider = .openai_compatible,
        .base_url = "https://openrouter.ai/api/v1",
        .auth_type = .bearer,
        .default_model = "anthropic/claude-3.5-sonnet",
        .supports = &.{ "chat", "embeddings", "streaming" },
        .organization = "OpenRouter",
        .website = "https://openrouter.ai",
        .description = "Unified API for 100+ models via OpenRouter",
    },
    .{
        .id = "any-scale-official",
        .name = "Anyscale",
        .provider = .openai_compatible,
        .base_url = "https://api.endpoints.anyscale.com/v1",
        .auth_type = .bearer,
        .default_model = "meta-llama/Llama-3-70b-instruct",
        .supports = &.{ "chat", "streaming" },
        .organization = "Anyscale",
        .website = "https://www.anyscale.com",
        .description = "Ray-powered inference endpoints",
    },
    .{
        .id = "together-official",
        .name = "Together AI",
        .provider = .openai_compatible,
        .base_url = "https://api.together.xyz/v1",
        .auth_type = .bearer,
        .default_model = "meta-llama/Llama-3-70b-instruct",
        .supports = &.{ "chat", "embeddings", "streaming" },
        .organization = "Together AI",
        .website = "https://together.ai",
        .description = "Open models inference via Together",
    },
    .{
        .id = "replicate-official",
        .name = "Replicate",
        .provider = .openai_compatible,
        .base_url = "https://inference-api.replicate.com/v1",
        .auth_type = .bearer,
        .default_model = "meta/llama-3-70b-instruct",
        .supports = &.{ "chat", "streaming" },
        .organization = "Replicate",
        .website = "https://replicate.com",
        .description = "Run open models via Replicate",
    },

    // ==================== AWS Bedrock ====================
    .{
        .id = "aws-bedrock-anthropic",
        .name = "AWS Bedrock - Anthropic",
        .provider = .anthropic,
        .base_url = "https://bedrock-runtime.us-east-1.amazonaws.com",
        .auth_type = .bearer,
        .default_model = "anthropic.claude-3-5-sonnet-20241022-v1-0",
        .supports = &.{ "chat", "streaming" },
        .organization = "Amazon Web Services",
        .website = "https://aws.amazon.com/bedrock",
        .description = "Anthropic models via AWS Bedrock",
    },
    .{
        .id = "aws-bedrock-meta",
        .name = "AWS Bedrock - Meta Llama",
        .provider = .openai_compatible,
        .base_url = "https://bedrock-runtime.us-east-1.amazonaws.com",
        .auth_type = .bearer,
        .default_model = "meta.llama3-70b-instruct-v1-0",
        .supports = &.{ "chat", "streaming" },
        .organization = "Amazon Web Services",
        .description = "Meta Llama models via AWS Bedrock",
    },
    .{
        .id = "aws-bedrock-cohere",
        .name = "AWS Bedrock - Cohere",
        .provider = .cohere,
        .base_url = "https://bedrock-runtime.us-east-1.amazonaws.com",
        .auth_type = .bearer,
        .default_model = "cohere.command-r-plus-v1-0",
        .supports = &.{ "chat", "embeddings", "streaming" },
        .organization = "Amazon Web Services",
        .description = "Cohere models via AWS Bedrock",
    },

    // ==================== NVIDIA NIM ====================
    .{
        .id = "nvidia-nim",
        .name = "NVIDIA NIM",
        .provider = .openai_compatible,
        .base_url = "https://integrate.api.nvidia.com/v1",
        .auth_type = .bearer,
        .default_model = "meta/llama-3.1-70b-instruct",
        .supports = &.{ "chat", "streaming" },
        .organization = "NVIDIA",
        .website = "https://developer.nvidia.com/nim",
        .description = "NVIDIA NIM inference microservices",
    },

    // ==================== Cloudflare Workers AI ====================
    .{
        .id = "cloudflare-workers-ai",
        .name = "Cloudflare Workers AI",
        .provider = .openai_compatible,
        .base_url = "https://api.cloudflare.com/client/v4/ai",
        .auth_type = .bearer,
        .default_model = "@cf/meta/llama-3-70b-instruct",
        .supports = &.{ "chat", "streaming" },
        .organization = "Cloudflare",
        .website = "https://developers.cloudflare.com/workers-ai",
        .description = "Edge AI inference via Cloudflare Workers",
    },

    // ==================== Groq ====================
    .{
        .id = "groq-official",
        .name = "Groq",
        .provider = .openai_compatible,
        .base_url = "https://api.groq.com/openai/v1",
        .auth_type = .bearer,
        .default_model = "llama-3.1-70b-versatile",
        .supports = &.{ "chat", "streaming" },
        .organization = "Groq",
        .website = "https://groq.com",
        .description = "Fast inference with Groq LPU",
    },

    // ==================== Featherless / Lepton ====================
    .{
        .id = "lepton-official",
        .name = "Lepton AI",
        .provider = .openai_compatible,
        .base_url = "https://api.lepton.run/v1",
        .auth_type = .bearer,
        .default_model = "mistralai/Mistral-7B-Instruct-v0.2",
        .supports = &.{ "chat", "streaming" },
        .organization = "Lepton AI",
        .website = "https://www.lepton.ai",
        .description = "Efficient inference via Lepton",
    },
    .{
        .id = "featherless-official",
        .name = "Featherless",
        .provider = .openai_compatible,
        .base_url = "https://api.featherless.ai/v1",
        .auth_type = .bearer,
        .default_model = "anthropic/claude-3.5-sonnet",
        .supports = &.{ "chat", "streaming" },
        .organization = "Featherless",
        .website = "https://featherless.ai",
        .description = "Managed inference platform",
    },

    // ==================== Deepinfra ====================
    .{
        .id = "deepinfra-official",
        .name = "DeepInfra",
        .provider = .openai_compatible,
        .base_url = "https://api.deepinfra.com/v1/openai",
        .auth_type = .bearer,
        .default_model = "meta-llama/Meta-Llama-3.1-70B-Instruct",
        .supports = &.{ "chat", "streaming" },
        .organization = "DeepInfra",
        .website = "https://deepinfra.com",
        .description = "Serverless inference endpoints",
    },

    // ==================== Infinity AI ====================
    .{
        .id = "infinity-official",
        .name = "Infinity AI",
        .provider = .openai_compatible,
        .base_url = "https://api.inference.net/v1",
        .auth_type = .bearer,
        .default_model = "anthropic/claude-3-opus",
        .supports = &.{ "chat", "streaming" },
        .organization = "Infinity AI",
        .website = "https://infinity.ai",
        .description = "Enterprise AI inference",
    },

    // ==================== Cohere Command ====================
    .{
        .id = "cohere-command",
        .name = "Cohere Command R+",
        .provider = .cohere,
        .base_url = "https://api.cohere.ai/v1",
        .auth_type = .bearer,
        .default_model = "command-r-plus",
        .supports = &.{ "chat", "streaming" },
        .organization = "Cohere",
        .description = "Optimized for RAG and tool use",
    },

    // ==================== AI21 Jurassic ====================
    .{
        .id = "ai21-official",
        .name = "AI21 Jurassic",
        .provider = .openai_compatible,
        .base_url = "https://api.ai21.com/v1",
        .auth_type = .bearer,
        .default_model = "jamba-1-5-large-instruct",
        .supports = &.{ "chat", "streaming" },
        .organization = "AI21 Labs",
        .website = "https://www.ai21.com",
        .description = "AI21's Jurassic models",
    },

    // ==================== Palmyra ====================
    .{
        .id = "palmyra-official",
        .name = "Writer Palmyra",
        .provider = .openai_compatible,
        .base_url = "https://api.writer.com/v1",
        .auth_type = .bearer,
        .default_model = "palmyra-large",
        .supports = &.{ "chat", "streaming" },
        .organization = "Writer",
        .website = "https://writer.com",
        .description = "Enterprise-focused models from Writer",
    },

    // ==================== Aleph Alpha ====================
    .{
        .id = "aleph-alpha-official",
        .name = "Aleph Alpha",
        .provider = .openai_compatible,
        .base_url = "https://api.aleph-alpha.com/v1",
        .auth_type = .bearer,
        .default_model = "luminous-base",
        .supports = &.{ "chat", "embedding", "streaming" },
        .organization = "Aleph Alpha",
        .website = "https://www.aleph-alpha.com",
        .description = "European AI with focus on privacy",
    },

    // ==================== Scale AI ====================
    .{
        .id = "scale-official",
        .name = "Scale AI",
        .provider = .openai_compatible,
        .base_url = "https://api.scale.com/v1",
        .auth_type = .bearer,
        .default_model = "anthropic-claude-3-opus",
        .supports = &.{ "chat", "streaming" },
        .organization = "Scale AI",
        .website = "https://scale.com",
        .description = "Enterprise AI via Scale",
    },

    // ==================== Community Relay Services ====================
    // Presets from cc-switch community partners

    // ------------------- MiniMax -------------------
    .{
        .id = "minimax-relay",
        .name = "MiniMax (Relay)",
        .provider = .minimax,
        .base_url = "https://api.minimax.chat/v1",
        .auth_type = .bearer,
        .default_model = "abab6.5s-chat",
        .supports = &.{ "chat", "embeddings", "tts", "video", "image", "music" },
        .organization = "MiniMax",
        .website = "https://platform.minimax.io",
        .description = "MiniMax relay with TTS, Video, Image, Music generation",
    },

    // ------------------- SiliconFlow -------------------
    .{
        .id = "siliconflow-relay",
        .name = "SiliconFlow",
        .provider = .openai_compatible,
        .base_url = "https://api.siliconflow.cn/v1",
        .auth_type = .bearer,
        .default_model = "Qwen/Qwen2.5-7B-Instruct",
        .supports = &.{ "chat", "embeddings", "streaming" },
        .organization = "SiliconFlow",
        .website = "https://www.siliconflow.cn",
        .description = "High-performance AI infrastructure with 40+ models",
    },

    // ------------------- Shengsuanyun -------------------
    .{
        .id = "shengsuanyun-relay",
        .name = "Shengsuanyun",
        .provider = .openai_compatible,
        .base_url = "https://api.shengsuanyun.com/v1",
        .auth_type = .bearer,
        .default_model = "claude-3.5-sonnet",
        .supports = &.{ "chat", "streaming" },
        .organization = "Shengsuanyun",
        .website = "https://www.shengsuanyun.com",
        .description = "Industrial AI task parallel execution platform",
    },

    // ------------------- AIGoCode -------------------
    .{
        .id = "aigocode-relay",
        .name = "AIGoCode",
        .provider = .anthropic,
        .base_url = "https://api.aigocode.com/v1",
        .auth_type = .bearer,
        .default_model = "claude-3.5-sonnet-20241022",
        .supports = &.{ "chat", "streaming" },
        .organization = "AIGoCode",
        .website = "https://www.aigocode.com",
        .description = "Claude Code relay with 10% bonus credit",
    },

    // ------------------- AICodeMirror -------------------
    .{
        .id = "aicodemirror-relay",
        .name = "AICodeMirror",
        .provider = .anthropic,
        .base_url = "https://api.aicodemirror.com/v1",
        .auth_type = .bearer,
        .default_model = "claude-3-5-sonnet-20241022",
        .supports = &.{ "chat", "streaming" },
        .organization = "AICodeMirror",
        .website = "https://www.aicodemirror.com",
        .description = "Claude Code relay at 38% of original price",
    },

    // ------------------- Cubence -------------------
    .{
        .id = "cubence-relay",
        .name = "Cubence",
        .provider = .anthropic,
        .base_url = "https://api.cubence.com/v1",
        .auth_type = .bearer,
        .default_model = "claude-3.5-sonnet",
        .supports = &.{ "chat", "streaming" },
        .organization = "Cubence",
        .website = "https://cubence.com",
        .description = "Claude Code relay with flexible billing",
    },

    // ------------------- DMXAPI -------------------
    .{
        .id = "dmxapi-relay",
        .name = "DMXAPI",
        .provider = .openai_compatible,
        .base_url = "https://api.dmxapi.cn/v1",
        .auth_type = .bearer,
        .default_model = "gpt-4o",
        .supports = &.{ "chat", "streaming" },
        .organization = "DMXAPI",
        .website = "https://www.dmxapi.cn",
        .description = "Claude Code at 66% off, GPT/Claude/Gemini at 32% off",
    },

    // ------------------- Compshare -------------------
    .{
        .id = "compshare-relay",
        .name = "Compshare",
        .provider = .anthropic,
        .base_url = "https://api.compshare.cn/v1",
        .auth_type = .bearer,
        .default_model = "claude-3.5-sonnet",
        .supports = &.{ "chat", "streaming" },
        .organization = "Compshare",
        .website = "https://www.compshare.cn",
        .description = "UCloud AI with 60-80% off Coding Plans",
    },

    // ------------------- RightCode -------------------
    .{
        .id = "rightcode-relay",
        .name = "RightCode",
        .provider = .openai_compatible,
        .base_url = "https://api.right.codes/v1",
        .auth_type = .bearer,
        .default_model = "gpt-4o",
        .supports = &.{ "chat", "streaming" },
        .organization = "RightCode",
        .website = "https://www.right.codes",
        .description = "Codex monthly subscription with quota rollovers",
    },

    // ------------------- AICoding -------------------
    .{
        .id = "aicoding-relay",
        .name = "AICoding.sh",
        .provider = .anthropic,
        .base_url = "https://api.aicoding.sh/v1",
        .auth_type = .bearer,
        .default_model = "claude-3.5-sonnet",
        .supports = &.{ "chat", "streaming" },
        .organization = "AICoding",
        .website = "https://www.aicoding.sh",
        .description = "Claude Code at 19% of original price",
    },

    // ------------------- Crazyrouter -------------------
    .{
        .id = "crazyrouter-relay",
        .name = "Crazyrouter",
        .provider = .openai_compatible,
        .base_url = "https://api.crazyrouter.com/v1",
        .auth_type = .bearer,
        .default_model = "anthropic/claude-3.5-sonnet",
        .supports = &.{ "chat", "streaming" },
        .organization = "Crazyrouter",
        .website = "https://www.crazyrouter.com",
        .description = "300+ models at 55% of official pricing",
    },

    // ------------------- SSSAiCode -------------------
    .{
        .id = "sssaicode-relay",
        .name = "SSSAiCode",
        .provider = .anthropic,
        .base_url = "https://api.sssaicode.com/v1",
        .auth_type = .bearer,
        .default_model = "claude-3.5-sonnet",
        .supports = &.{ "chat", "streaming" },
        .organization = "SSSAiCode",
        .website = "https://www.sssaicode.com",
        .description = "Claude service at just ¥0.5/$ equivalent",
    },

    // ------------------- Micu -------------------
    .{
        .id = "micu-relay",
        .name = "Micu API",
        .provider = .anthropic,
        .base_url = "https://api.openclaudecode.cn/v1",
        .auth_type = .bearer,
        .default_model = "claude-3.5-sonnet",
        .supports = &.{ "chat", "streaming" },
        .organization = "Micu",
        .website = "https://www.openclaudecode.cn",
        .description = "Zero cost to try, top up from ¥1",
    },

    // ------------------- XCodeAPI -------------------
    .{
        .id = "xcodeapi-relay",
        .name = "XCodeAPI",
        .provider = .openai_compatible,
        .base_url = "https://api.x-code.cc/v1",
        .auth_type = .bearer,
        .default_model = "gpt-4o",
        .supports = &.{ "chat", "streaming" },
        .organization = "XCodeAPI",
        .website = "https://www.x-code.cc",
        .description = "Claude Code relay with 10% bonus credit",
    },

    // ------------------- LionCC -------------------
    .{
        .id = "lioncc-relay",
        .name = "LionCC",
        .provider = .anthropic,
        .base_url = "https://api.vibecodingapi.ai/v1",
        .auth_type = .bearer,
        .default_model = "claude-3.5-sonnet",
        .supports = &.{ "chat", "streaming" },
        .organization = "LionCC",
        .website = "https://www.vibecodingapi.ai",
        .description = "Claude Code, Codex, OpenClaw at up to 50% savings",
    },

    // ------------------- DDS Hub -------------------
    .{
        .id = "ddshub-relay",
        .name = "DDS Hub",
        .provider = .anthropic,
        .base_url = "https://api.ddshub.com/v1",
        .auth_type = .bearer,
        .default_model = "claude-3.5-sonnet",
        .supports = &.{ "chat", "streaming" },
        .organization = "DDS Hub",
        .website = "https://ddshub.com",
        .description = "Claude Max number pools with full model support",
    },

    // ------------------- TheRouter -------------------
    .{
        .id = "therouter-relay",
        .name = "TheRouter",
        .provider = .anthropic,
        .base_url = "https://api.therouter.ai",
        .auth_type = .bearer,
        .default_model = "claude-3.5-sonnet",
        .supports = &.{ "chat", "streaming" },
        .organization = "TheRouter",
        .website = "https://therouter.ai",
        .description = "Enterprise routing with fine-grained cost management",
    },

    // ------------------- OpenRouter -------------------
    .{
        .id = "openrouter-claude",
        .name = "OpenRouter (Claude)",
        .provider = .anthropic,
        .base_url = "https://openrouter.ai/api/v1",
        .auth_type = .bearer,
        .default_model = "anthropic/claude-3.5-sonnet",
        .supports = &.{ "chat", "streaming" },
        .organization = "OpenRouter",
        .website = "https://openrouter.ai",
        .description = "Route to Claude via OpenRouter",
    },

    // ------------------- PackyCode -------------------
    .{
        .id = "packycode-relay",
        .name = "PackyCode",
        .provider = .anthropic,
        .base_url = "https://api.packyapi.com/v1",
        .auth_type = .bearer,
        .default_model = "claude-3.5-sonnet",
        .supports = &.{ "chat", "streaming" },
        .organization = "PackyCode",
        .website = "https://www.packyapi.com",
        .description = "Claude Code relay with 10% off first recharge",
    },
};

/// Preset category for organization
pub const PresetCategory = enum {
    official,
    openai_compatible,
    chinese,
    relay,
    cloud_providers,
    community,
    other,
};

/// Get category for a preset
pub fn getPresetCategory(preset: *const ProviderPreset) PresetCategory {
    if (preset.is_official) {
        return .official;
    }
    if (preset.organization) |org| {
        if (std.mem.find(u8, org, "AWS") != null or
            std.mem.find(u8, org, "Azure") != null or
            std.mem.find(u8, org, "Google Cloud") != null or
            std.mem.find(u8, org, "Tencent") != null or
            std.mem.find(u8, org, "Alibaba") != null)
        {
            return .cloud_providers;
        }
        if (std.mem.find(u8, org, "MiniMax") != null or
            std.mem.find(u8, org, "Moonshot") != null or
            std.mem.find(u8, org, "Zhipu") != null or
            std.mem.find(u8, org, "ByteDance") != null or
            std.mem.find(u8, org, "01 AI") != null)
        {
            return .chinese;
        }
        // Community relay providers
        if (std.mem.find(u8, org, "SiliconFlow") != null or
            std.mem.find(u8, org, "Shengsuanyun") != null or
            std.mem.find(u8, org, "AIGoCode") != null or
            std.mem.find(u8, org, "AICodeMirror") != null or
            std.mem.find(u8, org, "Cubence") != null or
            std.mem.find(u8, org, "DMXAPI") != null or
            std.mem.find(u8, org, "Compshare") != null or
            std.mem.find(u8, org, "RightCode") != null or
            std.mem.find(u8, org, "AICoding") != null or
            std.mem.find(u8, org, "Crazyrouter") != null or
            std.mem.find(u8, org, "SSSAiCode") != null or
            std.mem.find(u8, org, "Micu") != null or
            std.mem.find(u8, org, "XCodeAPI") != null or
            std.mem.find(u8, org, "LionCC") != null or
            std.mem.find(u8, org, "DDS") != null or
            std.mem.find(u8, org, "TheRouter") != null or
            std.mem.find(u8, org, "PackyCode") != null)
        {
            return .community;
        }
    }
    if (std.mem.find(u8, preset.id, "relay") != null or
        std.mem.find(u8, preset.id, "proxy") != null)
    {
        return .relay;
    }
    return .other;
}

/// Preset store for managing custom and imported presets
pub const PresetStore = struct {
    allocator: std.mem.Allocator,
    /// Built-in presets are read-only
    custom_presets: StringArrayHashMap(ProviderPreset),
    /// Active preset ID per CLI tool
    active_presets: std.enums.EnumArray(CliTool, ?[]const u8),

    pub fn init(allocator: std.mem.Allocator) PresetStore {
        return .{
            .allocator = allocator,
            .custom_presets = StringArrayHashMap(ProviderPreset).init(allocator),
            .active_presets = std.enums.EnumArray(CliTool, ?[]const u8).init(.{
                .claude_code = null,
                .codex = null,
                .gemini_cli = null,
                .opencode = null,
                .openclaw = null,
            }),
        };
    }

    pub fn deinit(self: *PresetStore) void {
        var it = self.custom_presets.iterator();
        while (it.next()) |entry| {
            self.freePreset(entry.value_ptr.*);
        }
        self.custom_presets.deinit();
    }

    fn freePreset(self: *PresetStore, preset: ProviderPreset) void {
        self.allocator.free(preset.id);
        self.allocator.free(preset.name);
        self.allocator.free(preset.base_url);
        for (preset.supports) |s| self.allocator.free(s);
        self.allocator.free(preset.supports);
        if (preset.api_key_env) |e| self.allocator.free(e);
        if (preset.organization) |o| self.allocator.free(o);
        if (preset.website) |w| self.allocator.free(w);
        if (preset.description) |d| self.allocator.free(d);
    }

    /// Get a preset by ID (checks custom first, then built-in)
    pub fn getPreset(self: *PresetStore, id: []const u8) ?*const ProviderPreset {
        // Check custom presets first
        if (self.custom_presets.get(id)) |preset| {
            return preset;
        }
        // Check built-in presets
        for (PRESETS) |*preset| {
            if (std.mem.eql(u8, preset.id, id)) {
                return preset;
            }
        }
        return null;
    }

    /// List all presets (built-in + custom)
    pub fn listPresets(self: *PresetStore) ![]const ProviderPreset {
        var all = std.array_list.Managed(ProviderPreset).init(self.allocator);
        // Add built-in presets
        for (PRESETS) |*preset| {
            try all.append(preset.*);
        }
        // Add custom presets
        var it = self.custom_presets.iterator();
        while (it.next()) |entry| {
            try all.append(entry.value_ptr.*);
        }
        return all.toOwnedSlice();
    }

    /// Add a custom preset
    pub fn addCustomPreset(self: *PresetStore, preset: ProviderPreset) !void {
        const id = try self.allocator.dupe(u8, preset.id);
        errdefer self.allocator.free(id);
        try self.custom_presets.put(id, preset);
    }

    /// Delete a custom preset (built-in cannot be deleted)
    pub fn deleteCustomPreset(self: *PresetStore, id: []const u8) bool {
        if (self.custom_presets.fetchRemove(id)) |entry| {
            self.freePreset(entry.value);
            return true;
        }
        return false;
    }

    /// Set active preset for a CLI tool
    pub fn setActivePreset(self: *PresetStore, tool: CliTool, preset_id: ?[]const u8) void {
        self.active_presets.set(tool, preset_id);
    }

    /// Get active preset for a CLI tool
    pub fn getActivePreset(self: *PresetStore, tool: CliTool) ?*const ProviderPreset {
        const preset_id = self.active_presets.get(tool) orelse return null;
        return self.getPreset(preset_id);
    }

    /// Export current configuration as a preset
    pub fn exportAsPreset(
        self: *PresetStore,
        id: []const u8,
        name: []const u8,
        base_url: []const u8,
        auth_type: AuthType,
        default_model: []const u8,
        supports: [][]const u8,
    ) !void {
        const preset = ProviderPreset{
            .id = try self.allocator.dupe(u8, id),
            .name = try self.allocator.dupe(u8, name),
            .provider = .custom,
            .base_url = try self.allocator.dupe(u8, base_url),
            .auth_type = auth_type,
            .default_model = try self.allocator.dupe(u8, default_model),
            .supports = supports,
        };
        try self.addCustomPreset(preset);
    }
};
