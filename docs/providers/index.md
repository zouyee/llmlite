# Provider Documentation

This directory contains detailed documentation for each LLM provider supported by llmlite.

## Native Providers

| Provider | Documentation | Core API | Advanced APIs | Status |
|----------|---------------|----------|---------------|--------|
| **OpenAI** | [openai.md](openai.md) | Chat, Embeddings, Files, Tools | Streaming, Vision, Batch, Assistants | ✓ Stable |
| **Google Gemini** | [google-gemini.md](google-gemini.md) | Chat, Embeddings | Caches, Tunings, Documents, Tokens, FileSearch, Operations, Live | ✓ Stable |
| **Minimax** | [minimax.md](minimax.md) | Chat, Embeddings, TTS | Video, Image, Music | ✓ Stable |
| **Kimi (Moonshot)** | [kimi.md](kimi.md) | Chat, Files | Token Estimation, Thinking Mode, Partial Mode | ✓ Stable |

## OpenAI-Compatible Providers

All handled via the unified `language_model.zig` — works out of the box:

| Provider | Base URL | Notes |
|----------|----------|-------|
| **Anthropic** | api.anthropic.com | Claude models (also has native `anthropic.zig` implementation) |
| **DeepSeek** | api.deepseek.com | DeepSeek V3/Coder |
| **Cohere** | api.cohere.ai | Command models |
| **Fireworks** | api.fireworks.ai | Fast inference |
| **Cerebras** | api.cerebras.ai | Ultra-fast inference |
| **Mistral** | api.mistral.ai | Mistral models |
| **Perplexity** | api.perplexity.ai | Real-time search models |
| **Custom** | Any URL | Any OpenAI-compatible API |

> All OpenAI-compatible providers are registered in `src/provider/registry.zig` and can be used directly via the proxy server.

## Quick Reference

### Base URLs

| Provider | Base URL |
|----------|----------|
| OpenAI | `https://api.openai.com/v1` |
| Google Gemini | `https://generativelanguage.googleapis.com/v1beta` |
| Anthropic | `https://api.anthropic.com/v1` |
| Minimax | `https://api.minimax.chat/v1` |
| Kimi/Moonshot | `https://api.moonshot.cn/v1` |
| DeepSeek | `https://api.deepseek.com/v1` |
| Mistral | `https://api.mistral.ai/v1` |
| Cohere | `https://api.cohere.ai/v1` |
| Fireworks | `https://api.fireworks.ai/inference/v1` |
| Cerebras | `https://api.cerebras.ai/v1` |
| Perplexity | `https://api.perplexity.ai` |

### Authentication

| Provider | Auth Type | Header |
|----------|-----------|--------|
| OpenAI | Bearer Token | `Authorization: Bearer <key>` |
| Google Gemini | API Key | `X-goog-api-key: <key>` or `?key=<key>` |
| Anthropic | API Key | `x-api-key: <key>` + `anthropic-version` |
| Minimax | Bearer Token | `Authorization: Bearer <key>` |
| Kimi/Moonshot | Bearer Token | `Authorization: Bearer <key>` |
| DeepSeek | Bearer Token | `Authorization: Bearer <key>` |
| Others | Bearer Token | `Authorization: Bearer <key>` |

### Feature Matrix

| Feature | OpenAI | Gemini | Anthropic | Minimax | Kimi |
|---------|--------|--------|-----------|---------|------|
| Chat | ✓ | ✓ | ✓ | ✓ | ✓ |
| Streaming | ✓ | ✓ | ✓ | ✓ | ✓ |
| Embeddings | ✓ | ✓ | - | ✓ | - |
| Vision | ✓ | ✓ | ✓ | - | ✓ |
| Files API | ✓ | - | - | - | ✓ |
| Function Calling | ✓ | - | ✓ | - | ✓ |
| JSON Mode | ✓ | ✓ | - | - | ✓ |
| Context Caching | - | ✓ | - | - | - |
| Model Tuning | - | ✓ | - | - | - |
| Token Counting | - | ✓ | - | - | ✓ |
| TTS/Audio | - | - | - | ✓ | - |
| Video | - | - | - | ✓ | - |
| Image | - | - | - | ✓ | - |
| Music | - | - | - | ✓ | - |
| Thinking Mode | - | - | - | - | ✓ |

## Provider Usage Modes

llmlite supports four usage modes:

### 1. Direct LanguageModel Usage

```zig
var lm = language_model.LanguageModel.init(allocator, &http_client, .openai, "gpt-4o");
const response = try lm.complete(params);
```

### 2. Via Provider Factory

```zig
var p = try provider.Provider.create(allocator, api_key, "google/gemini-1.5-flash");
var lm = try p.languageModel(http_client, "gemini-1.5-flash");
```

### 3. Via High-Level Client

```zig
var c = try client.Client.create(allocator, api_key, "openai/gpt-4o");
const response = try c.chat(&.{.{ .role = "user", .content = "Hello" }});
```

### 4. Via Proxy Server

```bash
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-xxx" \
  -d '{"model":"gpt-4o","messages":[...]}'
```

## Adding New Providers

To add a new provider:

1. Create provider module in `src/provider/<name>/`
2. Add provider config to `src/provider/registry.zig`
3. Create request transformer if API format differs from OpenAI
4. Add tests in `src/test/<name>_test.zig`
5. Add documentation in `docs/providers/<name>.md`
6. Register module in `build.zig`
