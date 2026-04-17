# Contributing to llmlite

Thank you for your interest in contributing to llmlite! This document provides guidelines and instructions for contributing.

## Code of Conduct

By participating in this project, you agree to maintain a respectful and inclusive environment for everyone.

## How to Contribute

### Reporting Issues

- Search existing issues before creating a new one
- Provide clear and descriptive titles
- Include code samples, error messages, and environment details
- Use issue templates when available

### Suggesting Features

- Open a discussion first to gauge interest
- Describe the use case and expected behavior
- Explain why this feature would benefit the project

### Pull Requests

1. **Fork the repository** and create a branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Follow the coding style**:
   - Zig 0.15+ is required
   - Run `zig build` to ensure compilation
   - Run `zig build test` to ensure tests pass
   - Follow existing code patterns in the project

3. **Write meaningful commit messages**:
   ```
   feat(provider): add thinking mode support for Kimi K2.5
   
   Add thinking parameter support to enable chain-of-thought reasoning
   for the Kimi K2.5 model. Includes tests for enabled/disabled states.
   ```

4. **Submit your pull request**:
   - Reference any related issues
   - Ensure CI passes
   - Be responsive to review feedback

## Development Setup

### Prerequisites

- Zig 0.15+
- Git
- Node.js 18+ (Web Dashboard development only)

### Building

```bash
# Clone the repository
git clone https://github.com/zouyee/llmlite.git
cd llmlite

# Build the project
zig build

# Run tests
zig build test

# Build release version
zig build -Doptimize=ReleaseSmall
```

### Running Specific Tests

```bash
# Provider-specific tests
zig build kimi-test              # Kimi tests
zig build minimax-test           # Minimax tests
zig build minimax-native-test    # Minimax native API tests
zig build openai-test            # OpenAI tests
zig build gemini-advanced-test   # Gemini advanced API tests
zig build gemma-test             # Gemma tests
zig build chat-test              # Chat completions tests

# All tests
zig build test
```

### Using the Makefile

```bash
make build              # Build the project
make build-release      # Build all release variants
make test               # Run all tests
make fmt                # Format code
make lint               # Run lint checks
make check              # Run all checks (fmt, lint, build)
make clean              # Clean build artifacts
make docker-build       # Build Docker image
make docker-test        # Run tests in Docker
```

## Project Structure

```
llmlite/
├── src/
│   ├── main.zig                # SDK entry point, re-exports public API
│   ├── client.zig              # Main OpenAI client implementation
│   ├── http.zig                # HTTP client (Bearer, API Key auth)
│   ├── chat.zig                # Chat completion types
│   ├── embedding.zig           # Embedding API
│   ├── stream.zig              # SSE streaming responses
│   ├── tool.zig                # Function calling
│   ├── structured_output.zig   # JSON Schema support
│   ├── batch.zig               # Batch processing
│   ├── responses.zig           # Responses API
│   ├── conversation.zig        # Multi-turn conversation state
│   ├── realtime.zig            # WebSocket real-time communication
│   ├── webhook.zig             # Webhook event handling
│   ├── azure.zig               # Azure OpenAI support
│   ├── assistant.zig           # Assistants API (Beta)
│   ├── file.zig                # File management
│   ├── image.zig               # Image generation
│   ├── audio.zig               # Audio/TTS
│   ├── moderation.zig          # Content moderation
│   ├── finetune.zig            # Model fine-tuning
│   ├── model.zig               # Model listing
│   ├── completion.zig          # Text completions
│   ├── pagination.zig          # Cursor pagination
│   ├── container.zig           # Container management
│   ├── grader.zig              # Grading service
│   ├── skill.zig               # Skill management
│   ├── betathread.zig          # Beta Thread (deprecated)
│   ├── version.zig             # Version info
│   ├── types.zig               # Common types
│   ├── vector_stores.zig       # Vector stores
│   ├── proxy_main.zig          # Proxy entry point
│   ├── mcp_main.zig            # MCP entry point
│   │
│   ├── provider/               # Provider implementations
│   │   ├── mod.zig             # Provider module re-exports
│   │   ├── types.zig           # Provider common types
│   │   ├── registry.zig        # Provider registry
│   │   ├── provider.zig        # Provider factory
│   │   ├── language_model.zig  # Unified language model interface
│   │   ├── openai.zig          # OpenAI provider
│   │   ├── anthropic.zig       # Anthropic provider
│   │   ├── google.zig          # Google Gemini provider
│   │   ├── gemini_caches.zig   # Gemini context caching
│   │   ├── gemini_tunings.zig  # Gemini model tuning
│   │   ├── gemini_documents.zig # Gemini document management
│   │   ├── gemini_file_search_stores.zig # Gemini vector search
│   │   ├── gemini_operations.zig # Gemini async operations
│   │   ├── gemini_tokens.zig   # Gemini token counting
│   │   ├── kimi/mod.zig        # Kimi/Moonshot provider
│   │   └── minimax/            # Minimax provider
│   │       ├── mod.zig         # Minimax main module
│   │       ├── tts.zig         # Text-to-speech
│   │       ├── video.zig       # Video generation
│   │       ├── image.zig       # Image generation
│   │       └── music.zig       # Music generation
│   │
│   ├── proxy/                  # Proxy server
│   │   ├── server.zig          # HTTP server
│   │   ├── router.zig          # Multi-provider routing
│   │   ├── virtual_key.zig     # Virtual key management
│   │   ├── rate_limit.zig      # Rate limiting
│   │   ├── cost.zig            # Cost tracking
│   │   ├── team.zig            # Team/project management
│   │   ├── middleware.zig      # Auth middleware
│   │   ├── config.zig          # Configuration types
│   │   ├── config_loader.zig   # JSON config loader
│   │   ├── persistence.zig     # JSON file persistence
│   │   ├── logger.zig          # Request logging
│   │   ├── connection_pool.zig # Connection pooling
│   │   ├── latency_health.zig  # Latency tracking
│   │   ├── circuit_breaker.zig # Circuit breaker
│   │   ├── active_health.zig   # Active health checking
│   │   ├── hot_reload.zig      # Hot reload
│   │   ├── plugin.zig          # Plugin interface
│   │   ├── pipeline.zig        # Request pipeline
│   │   ├── session_store.zig   # Session storage
│   │   ├── thinking_budget.zig # Thinking token budgeting
│   │   ├── thinking_optimizer.zig # Thinking optimization
│   │   ├── copilot_optimizer.zig # Copilot optimization
│   │   ├── handlers/           # Request handlers
│   │   │   ├── chat.zig        # Chat handler
│   │   │   ├── embeddings.zig  # Embeddings handler
│   │   │   ├── health.zig      # Health checks
│   │   │   ├── key.zig         # Key management API
│   │   │   ├── team.zig        # Team management API
│   │   │   ├── provider.zig    # Provider management
│   │   │   └── management.zig  # General management
│   │   ├── plugins/            # Plugin implementations
│   │   │   ├── cache.zig       # Simple & semantic cache
│   │   │   ├── cost.zig        # Cost tracking plugin
│   │   │   ├── guardrail.zig   # Content guardrails
│   │   │   ├── kv_sqlite.zig   # SQLite KV backend
│   │   │   ├── registry.zig    # Plugin registry
│   │   │   └── store.zig       # Storage abstraction
│   │   └── analytics/          # Analytics
│   │       ├── tracking.zig    # Usage tracking
│   │       └── types.zig       # Analytics types
│   │
│   ├── cmd/                    # CLI tool
│   │   ├── cmd_main.zig        # CLI entry point
│   │   ├── cmd.zig             # Command parsing and dispatch
│   │   └── core/               # Core infrastructure
│   │       ├── mod.zig         # Module re-exports
│   │       ├── runner.zig      # 6-phase execution framework
│   │       ├── filter.zig      # 12+ filtering strategies
│   │       ├── tracking.zig    # SQLite tracking
│   │       ├── tee.zig         # Failure recovery
│   │       ├── utils.zig       # Utility functions
│   │       ├── hook.zig        # Shell hooks
│   │       └── ... (50+ command modules)
│   │
│   ├── mcp/                    # MCP server
│   │   ├── server.zig          # MCP server implementation
│   │   ├── tools.zig           # Tool definitions
│   │   └── types.zig           # MCP types
│   │
│   ├── desktop/                # Desktop integration
│   │   └── tray.zig            # System tray
│   │
│   └── test/                   # Test files (25+)
│
├── web/                        # Web frontend
│   ├── src/
│   │   ├── App.tsx             # Main app
│   │   ├── components/         # UI components
│   │   │   ├── providers/      # Provider management
│   │   │   ├── mcp/            # MCP management
│   │   │   ├── sessions/       # Session management
│   │   │   └── settings/       # Settings panel
│   │   ├── hooks/              # React hooks
│   │   ├── lib/api/            # API client
│   │   └── i18n/               # i18n (EN/ZH/JA)
│   ├── package.json
│   └── vite.config.ts
│
├── docs/                       # Documentation
│   ├── providers/              # Provider docs
│   ├── zh/                     # Chinese docs
│   ├── ARCHITECTURE.md         # Architecture design
│   ├── roadmap.md              # Roadmap
│   └── ...
│
├── build.zig                   # Zig build system
├── build.zig.zon               # Zig package dependencies
├── Makefile                    # Make commands
├── Dockerfile                  # Docker multi-stage build
├── docker-compose.yml          # Docker Compose
└── .env.example                # Environment variable template
```

## Coding Guidelines

### Zig Conventions

1. **Error handling**: Use Zig's built-in error types and try/catch
2. **Memory**: Prefer allocation-free patterns when possible
3. **Types**: Use structured types, avoid `any`
4. **Documentation**: Document public APIs with doc comments

### Example

```zig
/// A brief description of what this function does.
///
/// Longer description if needed, explaining the behavior,
/// parameters, and return value.
///
/// # Parameters
/// - `allocator`: Memory allocator for internal use
/// - `params`: The parameters for the operation
///
/// # Errors
/// Returns an error if the operation fails
pub fn myFunction(allocator: std.mem.Allocator, params: MyParams) !Result {
    // implementation
}
```

## Adding a New Provider

1. Create provider module in `src/provider/<name>/`
2. Add provider configuration to `src/provider/registry.zig`
3. Create request transformer if API format differs from OpenAI
4. Add tests in `src/test/<name>_test.zig`
5. Add documentation in `docs/providers/<name>.md`
6. Register module and test target in `build.zig`
7. Update the provider table in README.md

## Adding a New CLI Command (llmlite-cmd)

1. Create command module in `src/cmd/core/` (e.g., `mycommand.zig`)
2. Implement a filtering strategy (see `filter.zig` for strategies)
3. Register the command in `src/cmd/cmd.zig`
4. Add tests to `src/test/cmd_test.zig`
5. Update the command list in `docs/ARCHITECTURE.md`

## Documentation

- Update README.md when adding new features
- Add provider documentation in `docs/providers/`
- Include code examples for new functionality
- Keep Chinese docs in `docs/zh/` in sync

## License

By contributing to llmlite, you agree that your contributions will be licensed under the GNU Affero General Public License version 3 (AGPL-3.0).
