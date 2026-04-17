# Changelog

All notable changes to llmlite will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added

#### CLI Tool (llmlite-cmd)
- **Command Proxy** (`src/cmd/`): CLI command proxy that intercepts developer commands and filters output
- **6-Phase Execution Framework** (`src/cmd/core/runner.zig`): Execute → Filter → Tee → Print → Track → Exit
- **12+ Filter Strategies** (`src/cmd/core/filter.zig`): stats, errors_only, grouping, deduplication, failure_focus, tree_compression, etc.
- **SQLite Token Tracking** (`src/cmd/core/tracking.zig`): Persistent token savings statistics
- **Shell Hook System** (`src/cmd/core/hook.zig`): bash/zsh automatic integration
- **50+ Command Modules**: git, cargo, npm, pytest, docker, kubectl, go, aws, eslint, tsc, prettier, prisma, playwright, rake, rspec, rubocop, dotnet, curl, nextjs, vitest, pnpm, pip, mypy, ruff, etc.
- **Failure Recovery** (`src/cmd/core/tee.zig`): Saves raw output on failure
- **Analytics** (`src/cmd/core/gain.zig`, `discover.zig`): Token savings statistics and discovery

#### MCP Server
- **MCP Server** (`src/mcp/`): Model Context Protocol server implementation
- **Tools**: `llmlite_router_status`, `llmlite_health_check`, `llmlite_cost_summary`, `llmlite_key_list`, `llmlite_key_create`, `llmlite_key_revoke`
- **JSON-RPC 2.0** over stdio protocol support

#### Web Dashboard
- **React Frontend** (`web/`): React 18 + TypeScript + TailwindCSS management panel
- **Provider Management**: Add/edit/delete/drag-sort providers
- **MCP Server Configuration**: MCP server management UI
- **Session Management**: Session tracking
- **Settings Panel**: System configuration
- **i18n**: Multi-language support (EN/ZH/JA)
- **Health Status**: Real-time health status monitoring

#### SDK Enhancements
- **Responses API** (`src/responses.zig`): New primary API interface
- **Container Module** (`src/container.zig`): Container management API
- **Grader Module** (`src/grader.zig`): Grading service
- **Skill Module** (`src/skill.zig`): Skill management API
- **BetaThread Module** (`src/betathread.zig`): Beta thread management
- **Vector Stores** (`src/vector_stores.zig`): Vector store support
- **Types Module** (`src/types.zig`): Common type definitions

#### Proxy Enhancements
- **Thinking Budget** (`src/proxy/thinking_budget.zig`): Thinking token budget management
- **Thinking Optimizer** (`src/proxy/thinking_optimizer.zig`): Thinking mode optimization
- **Thinking Rectifier** (`src/proxy/thinking_rectifier.zig`): Thinking response normalization
- **Copilot Optimizer** (`src/proxy/copilot_optimizer.zig`): Copilot optimization
- **App Type Router** (`src/proxy/app_type_router.zig`): App-type based routing
- **Sync Engine** (`src/proxy/sync_engine.zig`): Sync engine
- **MCP Manager** (`src/proxy/mcp_manager.zig`): MCP integration management
- **Database Module** (`src/proxy/database.zig`): Database support
- **WebDAV** (`src/proxy/webdav.zig`): WebDAV support
- **TUI** (`src/proxy/tui.zig`): Terminal UI dashboard
- **Deep Link** (`src/proxy/deep_link.zig`): Deep linking support

#### Desktop Integration
- **System Tray** (`src/desktop/tray.zig`): System tray support

#### Documentation
- Comprehensive update of all documentation to reflect current project state
- Updated README.md with all components (SDK, Proxy, CLI, MCP, Web)
- Updated CONTRIBUTING.md with full project structure and development guide
- Updated provider docs index with all 12+ providers
- Updated Chinese docs (docs/zh/README.md)
- Updated roadmap to reflect current progress

## [0.2.0] - 2026-04-08

### Added

#### Edge Routing Features
- **Connection Pooling** (`src/proxy/connection_pool.zig`): Per-provider HTTP connection reuse with idle timeout management
- **Latency Tracker** (`src/proxy/latency_health.zig`): Moving average and P50/P95/P99 percentiles per provider
- **Circuit Breaker** (`src/proxy/circuit_breaker.zig`): CLOSED→OPEN→HALF_OPEN state machine with configurable thresholds
- **Active Health Checker** (`src/proxy/active_health.zig`): Periodic provider probing with consecutive success/failure tracking
- **Hot Reload Config** (`src/proxy/hot_reload.zig`): File watching for zero-downtime config updates

#### Edge Routing Endpoints
- `GET /health/live` - Kubernetes-compatible liveness probe
- `GET /health/ready` - Kubernetes-compatible readiness probe
- `GET /metrics/latency` - Per-provider latency percentiles (P50/P95/P99)

#### Proxy Enhancements
- Real embeddings provider routing with circuit breaker and health tracking
- Dynamic latency metrics endpoint with actual provider stats
- Comprehensive test coverage: 75 tests for edge routing components

#### Documentation
- Edge routing positioning (672KB binary, vs vLLM Semantic Router/LiteLLM)
- Phase 3 implementation plan with edge routing architecture
- Updated README with edge scenarios (IoT, CLI, WASM, embedded systems)

### Changed

#### Build Optimization
- ReleaseSmall build mode: **672KB** binary (down from ~5MB Debug)
- Added `-Doptimize=ReleaseSmall` for edge deployments

#### Documentation
- Updated README with edge routing positioning
- Added binary size badge (672KB)
- Added vLLM Semantic Router comparison table

### Fixed
- Percentile calculation bug in latency_health.zig
- Placeholder tests in persistence.zig and kv_sqlite.zig
- String format issues in server.zig

## [0.1.0] - 2026-04-06

### Added

#### Providers
- **OpenAI Provider**: Full chat, embeddings, files API support with streaming and function calling
- **Google Gemini Provider**: Full chat, embeddings, plus advanced APIs (caches, tunings, documents, tokens, file search, operations, live)
- **Minimax Provider**: Chat, embeddings, TTS (speech-02-hd, speech-01-hd), video generation, image generation, music generation
- **Kimi (Moonshot) Provider**: Chat, files API, token estimation, balance query, thinking mode (K2.5), partial mode

#### Core Features
- Unified `LanguageModel` interface for all providers
- Vision support via content arrays (image_url, video_url)
- Streaming responses with SSE support
- JSON mode support
- Function calling / tools
- Multi-turn conversations
- Comprehensive error handling

#### Documentation
- Provider-specific API documentation (EN/CN)
- Feature matrix comparison table
- Code examples for all providers
- Architecture diagram

#### Build & Development
- Zig 0.15+ build system
- Makefile with common targets
- Docker support with multi-stage builds
- CONTRIBUTING guidelines

### Changed
- License changed from Apache 2.0 to AGPL-3.0

### Fixed
- Compilation errors in test files
- API key environment variable handling
- JSON response parsing for Minimax media APIs

### Security
- AGPL-3.0 ensures source code availability for network use
