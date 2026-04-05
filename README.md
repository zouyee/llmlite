<p align="center">
  <img src="assets/logo.svg" alt="llmlite logo with Zig mascot" width="200"/>
</p>

# llmlite

**A lightweight, high-performance LLM SDK written in Zig**

[![CI](https://github.com/zouyee/llmlite/actions/workflows/ci.yml/badge.svg)](https://github.com/zouyee/llmlite/actions)
[![Zig](https://img.shields.io/badge/Zig-0.15+-orange.svg)](https://ziglang.org/)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

## Overview

llmlite is a lightweight, type-safe LLM SDK for Zig that provides a unified interface to multiple LLM providers. Inspired by [litellm](https://github.com/BerriAI/litellm), llmlite offers:

- **Unified API** - Call any OpenAI-compatible LLM through a consistent interface
- **Native Providers** - First-class support for Google Gemini, OpenAI, and Minimax
- **Native Zig** - Built with Zig 0.15+ for maximum performance
- **Type Safety** - Full type safety with compile-time checks
- **Zero Dependencies** - No external runtime dependencies

## Supported Providers

| Provider | Core API | Advanced APIs | Status |
|----------|----------|---------------|--------|
| **Google Gemini** | ✓ Chat, Embeddings | ✓ Caches, Tunings, Documents, Tokens, FileSearch | ✓ Full |
| **OpenAI** | ✓ Chat, Embeddings, Files | - | ✓ Full |
| **Minimax** | ✓ Chat, Embeddings, TTS | ✓ Video, Image, Music | ✓ Full |
| **OpenAI-Compatible** | ✓ Via OpenAI compatibility layer | - | ✓ Via Proxy |

### OpenAI-Compatible Providers

Any OpenAI-compatible API endpoint works out of the box. The following providers are pre-configured:

| Provider | Base URL |
|----------|----------|
| Anthropic | api.anthropic.com |
| Moonshot | api.moonshot.cn |
| DeepSeek | api.deepseek.com |
| Cohere | api.cohere.ai |
| Fireworks | api.fireworks.ai |
| Cerebras | api.cerebras.ai |
| Groq | api.groq.com |
| Mistral | api.mistral.ai |
| Perplexity | api.perplexity.ai |

## Features

### Core Capabilities
- **Text Generation** - Generate content with customizable parameters
- **Streaming Responses** - Real-time streaming with SSE support
- **Embeddings** - Generate text embeddings for RAG applications
- **Chat Completions** - Multi-turn conversational AI

### Advanced APIs (Gemini)
- **Context Caching** - Cache frequently used context for cost savings
- **Model Tuning** - Fine-tune models for specific use cases
- **Document Management** - Manage documents for RAG pipelines
- **Vector Search Stores** - Create searchable vector databases
- **Token Counting** - Count tokens before API calls
- **Batch Processing** - Process multiple requests efficiently
- **Real-time Live** - Bidirectional streaming for live applications

### Provider-Specific
- **OpenAI Files API** - Upload, download, list files
- **Minimax TTS/Video** - Text-to-speech and video generation
- **Minimax Image/Music** - Image generation and music creation

## Quick Start

### Installation

Add llmlite to your `build.zig`:

```zig
const llmlite = .{
    .url = "https://github.com/your-org/llmlite",
    .hash = "...",
};
```

### Basic Usage

```zig
const std = @import("std");
const llmlite = @import("llmlite");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize the provider
    var provider = try llmlite.Provider.init(allocator, "your-api-key", "gemini-2.0-flash");
    defer provider.deinit();

    // Create a chat completion
    const messages = &[_]llmlite.ChatMessage{
        .{ .role = "user", .content = "Hello, world!" },
    };

    const response = try provider.chat().complete(messages);
    std.debug.print("Response: {s}\n", .{response.content});
}
```

### Streaming

```zig
const stream = try provider.chat().completeStream(messages);
defer stream.deinit();

while (try stream.next()) |chunk| {
    std.debug.print("{s}", .{chunk.content});
}
```

### Gemini Advanced APIs

```zig
// Count tokens before API call
const tokens = try provider.tokens().countTokens(model, content);

// Create a cached context
const cache = try provider.caches().create(.{
    .model = "gemini-1.5-flash",
    .contents = &.{.{ .role = "user", .parts = &.{.{ .text = "Context..." }} }},
    .ttl = "3600s",
});

// Tune a model
const tuning = try provider.tunings().create(.{
    .base_model = "gemini-1.5-flash",
    .training_data_uri = "gs://bucket/data.jsonl",
    .display_name = "my-tuned-model",
});
```

## API Reference

### Core Modules

| Module | Description |
|--------|-------------|
| `llmlite.chat` | Chat completions |
| `llmlite.completion` | Text completions |
| `llmlite.embedding` | Generate embeddings |
| `llmlite.stream` | Streaming responses |
| `llmlite.file` | File management |
| `llmlite.model` | Model listing |

### Gemini Advanced Modules

| Module | Description |
|--------|-------------|
| `llmlite.gemini_caches` | Context caching |
| `llmlite.gemini_tunings` | Model tuning |
| `llmlite.gemini_documents` | Document management |
| `llmlite.gemini_file_search_stores` | Vector search |
| `llmlite.gemini_operations` | Async operations |
| `llmlite.gemini_tokens` | Token counting |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        llmlite                              │
├─────────────────────────────────────────────────────────────┤
│  Provider Layer    │   Language Model Wrapper              │
│  ─────────────     │   ──────────────────────              │
│  • gemini          │   • complete()                        │
│  • openai          │   • completeStream()                  │
│  • anthropic       │   • embeddings()                     │
│  • minimax         │                                      │
├─────────────────────────────────────────────────────────────┤
│  Advanced APIs (Gemini)                                     │
│  ─────────────────────────                                   │
│  • Caches • Tunings • Documents • FileSearchStores       │
│  • Operations • Tokens • Batch • Live                     │
├─────────────────────────────────────────────────────────────┤
│  HTTP Client                                                │
│  ───────────                                                │
│  • Bearer Auth • API Key • SSE Streaming                  │
└─────────────────────────────────────────────────────────────┘
```

## Comparison with Other SDKs

| Feature | llmlite | go-genai | litellm |
|---------|---------|----------|---------|
| Language | Zig | Go | Python |
| Bundle Size | ~500KB | ~5MB | ~50MB |
| Runtime Deps | None | None | Many |
| Type Safety | Full | Full | Partial |
| Gemini APIs | Full | Full | Partial |

## Examples

See the `examples/` directory for complete examples:

- `chat_basic.zig` - Basic chat completion
- `chat_stream.zig` - Streaming chat
- `gemini_advanced.zig` - Gemini-specific features
- `minimax_media.zig` - TTS and video generation

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Apache License 2.0 - see [LICENSE](LICENSE) for details.

## Links

- [Documentation](docs/)
- [API Reference](docs/)
- [Examples](examples/)
- [Changelog](CHANGELOG.md)
