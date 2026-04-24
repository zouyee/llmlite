<p align="center">
  <img src="assets/logo.svg" alt="llmlite logo with Zig mascot" width="200"/>
</p>

# llmlite

**A lightweight, high-performance LLM SDK, Edge Router & CLI Tool written in Zig**

[![CI](https://github.com/zouyee/llmlite/actions/workflows/ci.yml/badge.svg)](https://github.com/zouyee/llmlite/actions)
[![Zig](https://img.shields.io/badge/Zig-0.16+-orange.svg)](https://ziglang.org/)
[![License](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)
[![Binary Size](https://img.shields.io/badge/Binary%20Size-672KB-success)](build.zig)

## Overview

llmlite is a **zero-dependency, edge-ready LLM toolkit** written in Zig, consisting of three tightly integrated components:

- **llmlite SDK** — A unified, type-safe LLM client library supporting 12+ providers (OpenAI, Anthropic, Gemini, Kimi, Minimax, DeepSeek, etc.) through a single `LanguageModel` interface. Covers chat completions, streaming, embeddings, vision, function calling, structured output, and provider-specific advanced APIs (Gemini caching/tuning, Minimax TTS/video/image/music, Kimi thinking mode).

- **llmlite-proxy** — A production-grade AI gateway and edge router in a 672KB binary. Provides OpenAI-compatible API endpoints with virtual key management, multi-provider routing with automatic failover, circuit breaker, latency-based health tracking (P50/P95/P99), connection pooling, rate limiting, cost tracking, team/project multi-tenancy, simple & semantic caching, hot-reload configuration, and a plugin system. Designed as a drop-in backend for AI agents — any tool that speaks the OpenAI API (including [Hermes Agent](https://github.com/NousResearch/Hermes-Agent), Claude Code, Cursor, Copilot) can route through llmlite-proxy to gain multi-provider failover, spend control, and edge deployment with zero code changes.

- **llmlite-cmd** — A CLI command proxy that intercepts developer tool output (git, cargo, npm, pytest, docker, kubectl, and 50+ more) and applies intelligent filtering strategies to reduce LLM token consumption by 60–90%. Includes SQLite-based savings tracking, shell hook integration (bash/zsh), [**Kiro IDE/kiro-cli integration**](docs/kiro-integration.md), TDD cycle detection, a `learn` module that detects recurring CLI mistakes from command history, and a **CLI Memory** system (inspired by claude-mem) that records, categorizes, and retrieves command executions with full-text search. When `llmlite-proxy` is running, cmd automatically reports token savings to the proxy for centralized analytics.

Unlike Python-based solutions (LiteLLM ~50MB, vLLM Semantic Router requires K8s/Docker), llmlite delivers:

- **Edge-Ready** — 672KB single static binary, no Docker/K8s/Python required
- **Agent-First** — OpenAI-compatible gateway purpose-built for AI agents like [Hermes Agent](https://github.com/NousResearch/Hermes-Agent); just set `OPENAI_BASE_URL=http://localhost:4000/v1` and get multi-provider routing, failover, and cost tracking for free
- **Zig Native** — Built with Zig 0.16+ for maximum performance, memory safety, and cross-compilation to any target (Linux, macOS, ARM, WASM)
- **Zero Dependencies** — Fully self-contained, no runtime needed
- **Type Safety** — Compile-time checks eliminate runtime type errors

### Key Differentiators

| vs | llmlite Advantage |
|----|-------------------|
| **vLLM Semantic Router** | Native binary, no K8s/Docker, 672KB vs hundreds of MB |
| **LiteLLM** | 100x smaller (672KB vs 50MB+), zero runtime deps, built-in CLI token optimizer |
| **Direct API calls** | Automatic failover, spend tracking, rate limiting, caching — no code changes |

## Components

llmlite consists of five core components:

| Component | Description | Binary |
|-----------|-------------|--------|
| **llmlite SDK** | Unified multi-provider LLM client library | `llmlite` |
| **llmlite-proxy** | Production-grade AI gateway / Edge Router | `llmlite-proxy` |
| **llmlite-cmd** | Developer command companion: intelligent output filtering, direct LLM API access, proxy management, cross-session memory, shell hooks, and token savings tracking | `llmlite-cmd` |
| **llmlite-mcp** | MCP (Model Context Protocol) server | `llmlite-mcp` |
| **Web Dashboard** | React management panel | `web/` |

## Quick Start

```bash
# Build for edge (672KB)
zig build -Doptimize=ReleaseSmall

# Run the proxy server
./zig-out/bin/llmlite-proxy

# Run the CLI tool
./zig-out/bin/llmlite-cmd git status

# Use as SDK
const llmlite = @import("llmlite");
```

## Edge Routing Features

llmlite-proxy includes production-grade edge routing:

| Feature | Description |
|---------|-------------|
| **Connection Pooling** | Per-provider HTTP connection reuse |
| **Latency Tracking** | Moving average, P50/P95/P99 percentiles |
| **Circuit Breaker** | CLOSED→OPEN→HALF_OPEN state machine |
| **Active Health Check** | Periodic provider probing |
| **Hot Reload** | Zero-downtime config updates |
| **Virtual Keys** | API key management with spend tracking |
| **Rate Limiting** | Per-key QPS and quota controls |
| **Cost Tracking** | Real-time spend monitoring by key/team/model |
| **Simple Cache** | TTL-based in-memory response caching |
| **Semantic Cache** | Embedding-based similarity caching |
| **Guardrails** | Content filtering and PII detection framework |
| **Savings Tracking** | Receive token savings reports from llmlite-cmd |
| **Unified Analytics** | Aggregate API cost + cmd savings in one view |
| **CLI Memory** | Cross-session command memory with FTS5 search |
| **LLM CLI** | Direct chat/completion/embed via llmlite-cmd |
| **Proxy Management CLI** | Health, metrics, provider, analytics queries |

### Endpoints

```bash
# Health checks (K8s-compatible)
curl http://localhost:4000/health/live   # Liveness
curl http://localhost:4000/health/ready  # Readiness

# Prometheus metrics
curl http://localhost:4000/metrics
curl http://localhost:4000/metrics/latency  # Per-provider latency

# Chat Completions (OpenAI-compatible)
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-xxx" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-4o", "messages": [{"role": "user", "content": "Hi"}]}'

# Embeddings
curl -X POST http://localhost:4000/v1/embeddings \
  -H "Authorization: Bearer sk-xxx" \
  -H "Content-Type: application/json" \
  -d '{"model": "text-embedding-ada-002", "input": "Hello world"}'

# Key management (admin)
curl -X POST http://localhost:4000/key/create -d '{"key_id": "sk-test"}'

# Savings tracking (from llmlite-cmd)
curl -X POST http://localhost:4000/tracking/savings \
  -H "Content-Type: application/json" \
  -d '{"timestamp":1700000000,"original_cmd":"git status","raw_output_tokens":1000,"filtered_output_tokens":400,"saved_tokens":600,"savings_pct":60.0,"exit_code":0,"hostname":"localhost"}'

# Unified analytics (cmd + API cost)
curl http://localhost:4000/analytics/unified?days=30
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  llmlite-proxy (672KB, zero dependencies)                    │
├─────────────────────────────────────────────────────────────┤
│  Edge Router                                               │
│  ├── Connection Pool (per-provider)                        │
│  ├── Latency Tracker (P50/P95/P99)                        │
│  ├── Circuit Breaker (auto-failover)                      │
│  ├── Active Health Checker                                │
│  └── Hot Config Reload                                    │
├─────────────────────────────────────────────────────────────┤
│  Gateway                                                   │
│  ├── Virtual Keys (sk-xxx)                                │
│  ├── Rate Limiting                                         │
│  ├── Cost Tracking                                         │
│  ├── Team/Project Multi-tenancy                            │
│  └── Simple + Semantic Cache                              │
├─────────────────────────────────────────────────────────────┤
│  Plugin System                                             │
│  ├── KV Store: memory (default), sqlite (optional)        │
│  ├── Cache: simple (TTL), semantic (embedding)            │
│  ├── Guardrails: content filter, PII detection            │
│  └── Cost Tracker: per key/team/model tracking            │
├─────────────────────────────────────────────────────────────┤
│  Providers (12+ supported)                                 │
│  ├── OpenAI, Anthropic, Google Gemini                     │
│  ├── Moonshot/Kimi, Minimax, DeepSeek                     │
│  └── Mistral, Cohere, Fireworks, Cerebras, Perplexity     │
├─────────────────────────────────────────────────────────────┤
│  CLI Tool (llmlite-cmd)                                    │
│  ├── Command output filtering (60-90% token reduction)    │
│  ├── Direct LLM API access (chat, complete, embed)        │
│  ├── Proxy management (health, metrics, providers)        │
│  ├── 50+ commands (git, cargo, npm, pytest, docker...)    │
│  ├── CLI Memory (FTS5 search, cross-session)              │
│  ├── SQLite tracking                                       │
│  └── Shell hooks (bash/zsh)                               │
├─────────────────────────────────────────────────────────────┤
│  MCP Server (llmlite-mcp)                                  │
│  ├── Router status queries                                │
│  ├── Provider health checks                               │
│  ├── Virtual key management                               │
│  └── Cost summaries                                       │
└─────────────────────────────────────────────────────────────┘
```

## Hermes Agent Integration

llmlite-proxy is purpose-built as a lightweight backend for AI agents. Any agent that speaks the OpenAI API can route through llmlite-proxy to gain multi-provider failover, cost tracking, and edge deployment — with zero code changes.

### Supported Agents

| Agent | Integration | How |
|-------|-------------|-----|
| [Hermes Agent](https://github.com/NousResearch/Hermes-Agent) | ✅ Drop-in | Set `OPENAI_BASE_URL` |
| Claude Code | ✅ Drop-in | Set `OPENAI_BASE_URL` |
| Cursor | ✅ Drop-in | Custom API endpoint |
| GitHub Copilot | ✅ Drop-in | Custom API endpoint |
| Any OpenAI-compatible agent | ✅ Drop-in | Set base URL |

### Architecture

```
┌──────────────────┐     ┌─────────────────────────┐     ┌──────────────────────────┐
│  Hermes Agent    │     │  llmlite-proxy:4000     │     │  OpenAI                  │
│  Claude Code     │────▶│  672KB, zero deps        │────▶│  Gemini / Kimi / ...     │
│  Cursor / Any    │     │  failover + cost track   │     │  (auto-failover)         │
└──────────────────┘     └─────────────────────────┘     └──────────────────────────┘
```

### Quick Setup

```bash
# 1. Build and deploy proxy
zig build -Doptimize=ReleaseSmall
./zig-out/bin/llmlite-proxy

# 2. Create a virtual key
curl -X POST http://localhost:4000/key/create \
  -H "Content-Type: application/json" \
  -d '{"key_id": "sk-hermes", "team_id": "hermes-team"}'

# 3. Point your agent at llmlite-proxy
export OPENAI_BASE_URL=http://localhost:4000/v1
export OPENAI_API_KEY=sk-hermes

# 4. Run Hermes Agent (or any OpenAI-compatible agent) — done
hermes model gpt-4o
```

### What You Get

| Benefit | Description |
|---------|-------------|
| **Multi-Provider Routing** | Route to OpenAI, Gemini, Kimi, DeepSeek, etc. via a single endpoint |
| **Automatic Failover** | Circuit breaker detects provider outages and reroutes instantly |
| **Latency Routing** | Requests go to the fastest healthy provider (P50/P95/P99 tracking) |
| **Cost Tracking** | Monitor spend per virtual key, team, and model in real time |
| **Rate Limiting** | Per-key QPS and quota controls prevent runaway costs |
| **Edge Deploy** | Run on any device — no Docker, no K8s, just a 672KB binary |
| **MCP Integration** | Expose router status, health checks, and key management as MCP tools |

## Comparison with Other Solutions

| Feature | llmlite | vLLM Semantic Router | LiteLLM |
|---------|---------|---------------------|---------|
| **Binary Size** | 672KB | ~500MB (Docker) | 50MB+ |
| **Runtime Deps** | None | Docker/K8s | Python + pip |
| **Type Safety** | Full (Zig comptime) | Partial | Partial |
| **Edge Deploy** | ✅ Native | ❌ | ❌ |
| **Circuit Breaker** | ✅ Built-in | ❌ | ❌ |
| **Latency Metrics** | ✅ P50/P95/P99 | ❌ | ⚠️ |
| **Hot Reload** | ✅ | ❌ | ⚠️ |
| **Cold Start** | < 10ms | Slow | ~2000ms |

## Supported Providers

### Native Providers (Full Implementation)

| Provider | Core API | Advanced APIs | Status |
|----------|----------|---------------|--------|
| **OpenAI** | Chat, Embeddings, Files, Tools | Streaming, Vision, Batch, Assistants | ✓ Stable |
| **Google Gemini** | Chat, Embeddings | Caches, Tunings, Documents, Tokens, FileSearch, Operations, Live | ✓ Stable |
| **Anthropic** | Chat, Vision, Tools | Streaming (SSE) | ✓ Stable |
| **Minimax** | Chat, Embeddings, TTS | Video, Image, Music | ✓ Stable |
| **Kimi (Moonshot)** | Chat, Files | Token Estimation, Thinking Mode, Partial Mode | ✓ Stable |

### OpenAI-Compatible Providers

All handled via the unified `language_model.zig` — works out of the box:

| Provider | Base URL | Notes |
|----------|----------|-------|
| **DeepSeek** | api.deepseek.com | DeepSeek V3/Coder |
| **Cohere** | api.cohere.ai | Command models |
| **Fireworks** | api.fireworks.ai | Fast inference |
| **Cerebras** | api.cerebras.ai | Ultra-fast inference |
| **Mistral** | api.mistral.ai | Mistral models |
| **Perplexity** | api.perplexity.ai | Real-time search models |
| **Custom** | Any URL | Any OpenAI-compatible API |

### Provider Feature Matrix

| Feature | OpenAI | Gemini | Anthropic | Minimax | Kimi |
|---------|--------|--------|-----------|---------|------|
| **Chat** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Streaming** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Embeddings** | ✓ | ✓ | - | ✓ | - |
| **Vision** | ✓ | ✓ | ✓ | - | ✓ |
| **Files API** | ✓ | - | - | - | ✓ |
| **Function Calling** | ✓ | - | ✓ | - | ✓ |
| **JSON Mode** | ✓ | ✓ | - | - | ✓ |
| **Context Caching** | - | ✓ | - | - | - |
| **Model Tuning** | - | ✓ | - | - | - |
| **Token Counting** | - | ✓ | - | - | ✓ |
| **TTS/Audio** | - | - | - | ✓ | - |
| **Video Generation** | - | - | - | ✓ | - |
| **Image Generation** | - | - | - | ✓ | - |
| **Music Generation** | - | - | - | ✓ | - |
| **Thinking Mode** | - | - | - | - | ✓ |

## SDK Usage

### Installation

Add llmlite to your `build.zig`:

```zig
const llmlite = .{
    .url = "https://github.com/zouyee/llmlite",
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

    var provider = try llmlite.Provider.init(allocator, "your-api-key", "gemini-2.0-flash");
    defer provider.deinit();

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

### Vision

```zig
const response = try lm.complete(.{
    .model = "gpt-4o",
    .messages = &.{
        .{
            .role = .user,
            .parts = &[_]MessageContentPart{
                .{ .image_url = .{ .image_url = .{ .url = "data:image/png;base64,..." } } },
                .{ .text = .{ .text = "Describe this" } },
            },
        },
    },
});
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

### Proxy Server

```bash
# Build and run
zig build proxy
./zig-out/bin/llmlite-proxy

# With config file
./zig-out/bin/llmlite-proxy config.json
```

## CLI Tool (llmlite-cmd)

llmlite-cmd is a command-line proxy that intercepts developer commands and filters output, reducing LLM token consumption by 60-90%.

```bash
# Install shell hook
llmlite-cmd init -g

# Kiro IDE / kiro-cli integration
# See docs/kiro-integration.md for full setup
llmlite-cmd git status      # 80% token reduction
llmlite-cmd cargo test      # 90% token reduction
llmlite-cmd npm test         # 90% token reduction
llmlite-cmd pytest           # 90% token reduction

# Direct LLM API access (via proxy)
llmlite-cmd llm chat "Explain Zig's comptime"
llmlite-cmd llm chat "Hello" --model claude-3-sonnet --provider anthropic
llmlite-cmd llm complete "Write a fibonacci function in Zig" --max-tokens 500
llmlite-cmd llm embed "machine learning"
llmlite-cmd llm models --provider openai
llmlite-cmd llm providers

# Proxy management
llmlite-cmd proxy start                    # Start proxy
llmlite-cmd proxy start --tui              # Start with TUI dashboard
llmlite-cmd proxy status                   # Check if running
llmlite-cmd proxy health                   # Readiness probe
llmlite-cmd proxy metrics                  # Prometheus metrics
llmlite-cmd proxy providers                # List configured providers
llmlite-cmd proxy analytics gain           # Token savings
llmlite-cmd proxy analytics team           # Team analytics
llmlite-cmd proxy keys list                # Virtual keys

# View savings statistics
llmlite-cmd gain              # Query proxy unified endpoint (default)
llmlite-cmd gain --local      # Use local history.db only
llmlite-cmd gain --graph
llmlite-cmd gain --json
llmlite-cmd gain --csv

# CLI Memory (cross-session command memory)
llmlite-cmd memory search "auth bug"     # Full-text search memories
llmlite-cmd memory list --cat fix        # List recent bug fixes
llmlite-cmd memory show 42               # Show full memory details
llmlite-cmd memory timeline 42           # Context around memory
llmlite-cmd memory stats                 # Memory statistics

# Work Modes (affects which categories are recorded)
llmlite-cmd memory mode show             # Current mode and settings
llmlite-cmd memory mode set infra        # Switch to infra mode
llmlite-cmd memory mode list             # List all modes
```

Supported command categories:
- **Git**: status, diff, log, add, commit, push, pull
- **Cargo**: test, build, clippy, bench
- **NPM/PNPM**: test, run, install, list, vitest
- **Python**: pytest, ruff, mypy, pip
- **Docker**: ps, images, logs, compose
- **Kubectl**: get, logs, describe, apply
- **Go**: test, build, vet
- **System**: ls, tree, cat, grep, find
- **More**: eslint, tsc, prettier, prisma, playwright, rake, rspec, rubocop, dotnet, aws, curl, nextjs

### Kiro Integration

llmlite integrates with both [Kiro IDE](https://kiro.dev) (VS Code extension) and `kiro-cli` (terminal agent) via `preToolUse` hooks. When Kiro is about to execute a shell command, llmlite suggests a token-optimized alternative — reducing context window usage by 60–99%.

- **kiro-cli**: Fully supported via agent-level hooks. See [docs/kiro-integration.md](docs/kiro-integration.md) for setup.
- **Kiro IDE**: Project-level hook included (`.kiro/hooks/llmlite.kiro.hook`). Functional but awaiting upstream fix for stdin passthrough ([Kiro#7500](https://github.com/kirodotdev/Kiro/issues/7500)).

## MCP Server

llmlite provides an MCP (Model Context Protocol) server that exposes routing and management capabilities as tools for AI agents.

```bash
# Build the MCP server
zig build -Doptimize=ReleaseSmall
# Binary at zig-out/bin/llmlite-mcp
```

Available tools: `llmlite_router_status`, `llmlite_health_check`, `llmlite_cost_summary`, `llmlite_key_list`, `llmlite_key_create`, `llmlite_key_revoke`

See [MCP documentation](docs/mcp.md) for details.

## Web Dashboard

Management panel built with React + TypeScript + TailwindCSS:

- Provider management (add/edit/delete/drag-sort)
- MCP server configuration
- Session management
- Settings panel
- Real-time health status monitoring
- Multi-language support (EN/ZH/JA)

```bash
cd web && npm install && npm run dev
# Visit http://localhost:3000
```

## API Reference

### Core Modules

| Module | Description |
|--------|-------------|
| `llmlite.chat` | Chat completions |
| `llmlite.completion` | Text completions |
| `llmlite.embedding` | Text embeddings |
| `llmlite.stream` | Streaming responses |
| `llmlite.file` | File management |
| `llmlite.model` | Model listing |
| `llmlite.image` | Image generation |
| `llmlite.audio` | Audio/TTS |
| `llmlite.tool` | Function calling |
| `llmlite.structured_output` | JSON Schema structured output |
| `llmlite.batch` | Batch processing |
| `llmlite.responses` | Responses API |
| `llmlite.assistant` | Assistants API (Beta) |
| `llmlite.conversation` | Multi-turn conversation state |
| `llmlite.realtime` | WebSocket real-time communication |
| `llmlite.webhook` | Webhook event handling |
| `llmlite.azure` | Azure OpenAI support |
| `llmlite.finetune` | Model fine-tuning |
| `llmlite.moderation` | Content moderation |
| `llmlite.pagination` | Cursor pagination |
| `llmlite.container` | Container management |
| `llmlite.grader` | Grading service |
| `llmlite.skill` | Skill management |

### Gemini Advanced Modules

| Module | Description |
|--------|-------------|
| `llmlite.gemini_caches` | Context caching |
| `llmlite.gemini_tunings` | Model tuning |
| `llmlite.gemini_documents` | Document management |
| `llmlite.gemini_file_search_stores` | Vector search |
| `llmlite.gemini_operations` | Async operations |
| `llmlite.gemini_tokens` | Token counting |

## Building & Development

### Prerequisites

- Zig 0.16+
- Git
- Node.js 18+ (Web Dashboard only)

### Build Commands

```bash
make build              # Build the project
make build-release      # Build all release variants
make run                # Run the application
make test               # Run all tests
make test-kimi          # Run Kimi tests
make test-minimax       # Run Minimax tests
make test-minimax-native # Run Minimax native API tests
make fmt                # Format code
make lint               # Run lint checks
make check              # Run all checks (fmt, lint, build)
make clean              # Clean build artifacts
make docker-build       # Build Docker image
make docker-run         # Run Docker container
make docker-test        # Run tests in Docker
make info               # Show project info
```

### Zig Build Commands

```bash
zig build                              # Debug build
zig build -Doptimize=ReleaseSmall      # 672KB edge binary
zig build -Doptimize=ReleaseSafe       # Safe release
zig build -Doptimize=ReleaseFast       # Fast release
zig build run                          # Run main program
zig build test                         # Run unit tests
zig build proxy                        # Build proxy server
zig build cmd                          # Build CLI tool

# Provider tests
zig build kimi-test                    # Kimi tests
zig build minimax-test                 # Minimax tests
zig build minimax-native-test          # Minimax native API tests
zig build openai-test                  # OpenAI tests
zig build gemini-advanced-test         # Gemini advanced API tests
zig build gemma-test                   # Gemma tests
zig build chat-test                    # Chat completions tests

# Proxy & Cmd tests
zig build property-test                # Property-based correctness tests (40 tests)
zig build integration-test             # Proxy-cmd integration tests
zig build persistence-test             # Proxy SQLite persistence tests
zig build savings-reporter-test        # Savings reporter unit tests
zig build gain-test                    # Gain command unit tests
zig build tracking-test                # Tracking & analytics tests
zig build proxy-test                   # Proxy component tests
```

### Docker

```bash
# Build production image (scratch + 672KB binary)
docker build -t llmlite .

# Use docker-compose
docker-compose up llmlite-proxy
```

## Documentation

- [Provider API Docs](docs/providers/) — Detailed per-provider documentation
- [Architecture](docs/ARCHITECTURE.md) — llmlite-cmd architecture
- [Roadmap](docs/roadmap.md) — Project roadmap
- [Proxy-Cmd Integration](.kiro/specs/proxy-cmd-integration/tasks.md) — Proxy-cmd integration spec
- [LiteLLM Alignment](docs/litellm-alignment.md) — Competitive analysis
- [Provider Usage Modes](docs/provider-usage-modes.md) — Usage patterns & competitive analysis
- [GUI Migration Plan](docs/gui-migration-plan.md) — Web UI development plan
- [Kiro Integration](docs/kiro-integration.md) — Kiro IDE & kiro-cli hook setup
- [MCP Integration](docs/mcp.md) — MCP server documentation
- [Chinese Docs](docs/zh/README.md) — Chinese README
- [Changelog](CHANGELOG.md) — Version history
- [Contributing](CONTRIBUTING.md) — How to contribute

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

AGPL-3.0 — see [LICENSE](LICENSE) for details.
