# Provider Documentation

This directory contains detailed documentation for each LLM provider supported by llmlite.

## Providers

| Provider | Documentation | Status |
|----------|---------------|--------|
| **OpenAI** | [openai.md](openai.md) | ✓ Stable |
| **Google Gemini** | [google-gemini.md](google-gemini.md) | ✓ Stable |
| **Minimax** | [minimax.md](minimax.md) | ✓ Stable |
| **Kimi (Moonshot)** | [kimi.md](kimi.md) | ✓ Stable |

## Quick Reference

### Base URLs

| Provider | Base URL |
|----------|----------|
| OpenAI | `https://api.openai.com/v1` |
| Google Gemini | `https://generativelanguage.googleapis.com/v1beta` |
| Minimax | `https://api.minimax.chat/v1` |
| Kimi/Moonshot | `https://api.moonshot.cn/v1` |

### Authentication

| Provider | Auth Type | Header |
|----------|-----------|--------|
| OpenAI | Bearer Token | `Authorization: Bearer <key>` |
| Google Gemini | API Key | `X-goog-api-key: <key>` or `?key=<key>` |
| Minimax | Bearer Token | `Authorization: Bearer <key>` |
| Kimi/Moonshot | Bearer Token | `Authorization: Bearer <key>` |

## Provider Selection

Choose a provider based on your requirements:

- **OpenAI**: Standard API, widest compatibility
- **Google Gemini**: Advanced features (caching, tuning), large context
- **Minimax**: Media generation (TTS, video, image, music)
- **Kimi**: Cost-effective, thinking mode, OpenAI-compatible

## Adding New Providers

To add a new provider:

1. Create provider module in `src/provider/<name>/`
2. Add provider config to `src/provider/registry.zig`
3. Create request transformer if API format differs from OpenAI
4. Add tests in `src/test/<name>_test.zig`
5. Add documentation in `docs/providers/<name>.md`
