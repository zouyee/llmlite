# Changelog

All notable changes to llmlite will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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

### Deprecated
- None

### Removed
- None

### Security
- AGPL-3.0 ensures source code availability for network use
