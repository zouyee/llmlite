# llmlite

**轻量级、高性能的 Zig LLM SDK**

[![CI](https://github.com/zouyee/llmlite/actions/workflows/ci.yml/badge.svg)](https://github.com/zouyee/llmlite/actions)
[![Zig](https://img.shields.io/badge/Zig-0.15+-orange.svg)](https://ziglang.org/)
[![License](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)

## 概述

llmlite 是一个轻量级、类型安全的 Zig LLM SDK，提供统一的接口来调用多个 LLM 提供商。灵感来自 [litellm](https://github.com/BerriAI/litellm)，llmlite 提供：

- **统一 API** - 通过一致的接口调用任何 OpenAI 兼容的 LLM
- **原生支持** - 一级支持 Google Gemini、OpenAI 和 Minimax
- **原生 Zig** - 使用 Zig 0.15+ 构建，性能卓越
- **类型安全** - 编译时完整类型检查
- **零依赖** - 无外部运行时依赖

## 支持的提供商

| 提供商 | 核心 API | 高级 API | 状态 |
|--------|----------|----------|------|
| **Google Gemini** | ✓ Chat, Embeddings | ✓ Caches, Tunings, Documents, Tokens, FileSearch | ✓ 完整 |
| **OpenAI** | ✓ Chat, Embeddings, Files | - | ✓ 完整 |
| **Minimax** | ✓ Chat, Embeddings, TTS | ✓ Video, Image, Music | ✓ 完整 |
| **OpenAI 兼容** | ✓ 通过 OpenAI 兼容层 | - | ✓ 通过代理 |

### OpenAI 兼容提供商

任何 OpenAI 兼容的 API 端点都可以开箱即用。以下提供商已预配置：

| 提供商 | Base URL |
|--------|----------|
| Anthropic | api.anthropic.com |
| Moonshot/Kimi | api.moonshot.cn |
| DeepSeek | api.deepseek.com |
| Cohere | api.cohere.ai |
| Fireworks | api.fireworks.ai |
| Cerebras | api.cerebras.ai |
| Mistral | api.mistral.ai |
| Perplexity | api.perplexity.ai |

> **注意**: 所有通过 OpenAI 兼容格式的提供商都使用统一的 `language_model.zig` 处理。它们可与代理服务器开箱即用。

## 功能特性

### 核心能力

- **文本生成** - 可自定义参数生成内容
- **流式响应** - SSE 支持实时流式输出
- **向量嵌入** - 为 RAG 应用生成文本向量
- **对话补全** - 多轮对话 AI

### 代理服务器 (AI Gateway)
- **Virtual Key 管理** - 创建、撤销、跟踪 API keys
- **多提供商路由** - 自动故障转移、健康追踪
- **速率限制** - 每 key QPS 和配额控制
- **成本追踪** - 按 key/team/model 实时监控
- **Team/项目管理** - 多租户与预算限制
- **简单缓存** - 基于 TTL 的内存响应缓存
- **语义缓存** - 基于 embedding 的相似度缓存

### 高级 API (Gemini)
- **上下文缓存** - 缓存常用上下文以节省成本
- **模型微调** - 为特定用例微调模型
- **文档管理** - 为 RAG 管道管理文档
- **向量搜索存储** - 创建可搜索的向量数据库
- **Token 计数** - API 调用前计算 token
- **批量处理** - 高效处理多个请求
- **实时 Live** - 双向流式直播应用

### 本地模型支持 (计划中)
- **Ollama 集成** - 通过 OpenAI 兼容 API 连接本地 Ollama
- **llama.cpp 绑定** - 直接加载 GGUF 模型 (未来)

### 提供商特定功能
- **OpenAI Files API** - 上传、下载、列出文件
- **Minimax TTS/Video** - 文本转语音和视频生成
- **Minimax Image/Music** - 图像生成和音乐创作

## 快速开始

### 安装

将 llmlite 添加到您的 `build.zig`:

```zig
const llmlite = .{
    .url = "https://github.com/zouyee/llmlite",
    .hash = "...",
};
```

### 基本用法

```zig
const std = @import("std");
const llmlite = @import("llmlite");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始化提供商
    var provider = try llmlite.Provider.init(allocator, "your-api-key", "gemini-2.0-flash");
    defer provider.deinit();

    // 创建聊天补全
    const messages = &[_]llmlite.ChatMessage{
        .{ .role = "user", .content = "你好，世界！" },
    };

    const response = try provider.chat().complete(messages);
    std.debug.print("响应: {s}\n", .{response.content});
}
```

### 流式输出

```zig
const stream = try provider.chat().completeStream(messages);
defer stream.deinit();

while (try stream.next()) |chunk| {
    std.debug.print("{s}", .{chunk.content});
}
```

### Gemini 高级 API

```zig
// API 调用前计算 token
const tokens = try provider.tokens().countTokens(model, content);

// 创建缓存上下文
const cache = try provider.caches().create(.{
    .model = "gemini-1.5-flash",
    .contents = &.{.{ .role = "user", .parts = &.{.{ .text = "上下文..." }} }},
    .ttl = "3600s",
});

// 微调模型
const tuning = try provider.tunings().create(.{
    .base_model = "gemini-1.5-flash",
    .training_data_uri = "gs://bucket/data.jsonl",
    .display_name = "我的微调模型",
});
```

## API 参考

### 核心模块

| 模块 | 描述 |
|------|------|
| `llmlite.chat` | 聊天补全 |
| `llmlite.completion` | 文本补全 |
| `llmlite.embedding` | 生成向量 |
| `llmlite.stream` | 流式响应 |
| `llmlite.file` | 文件管理 |
| `llmlite.model` | 模型列表 |

### Gemini 高级模块

| 模块 | 描述 |
|------|------|
| `llmlite.gemini_caches` | 上下文缓存 |
| `llmlite.gemini_tunings` | 模型微调 |
| `llmlite.gemini_documents` | 文档管理 |
| `llmlite.gemini_file_search_stores` | 向量搜索 |
| `llmlite.gemini_operations` | 异步操作 |
| `llmlite.gemini_tokens` | Token 计数 |

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│                        llmlite                              │
├─────────────────────────────────────────────────────────────┤
│  SDK (库)                                                   │
│  ────────────────                                          │
│  Provider 层          │   Language Model 包装器             │
│  • openai            │   • complete()                       │
│  • anthropic        │   • completeStream()                  │
│  • google/gemini    │   • embeddings()                      │
│  • minimax          │   • live() (Gemini)                   │
│  • moonshot/kimi    │                                      │
│  • deepseek         │                                      │
│  • + 6 more...     │                                      │
├─────────────────────────────────────────────────────────────┤
│  代理服务器 (llmlite-proxy)                                │
│  ─────────────────────────────────                          │
│  • 端口 4000 的 HTTP 服务器                                 │
│  • Virtual Key 管理 (sk-xxx)                              │
│  • 多提供商路由与故障转移                                   │
│  • 速率限制 • 成本追踪                                     │
│  • Team/项目 多租户                                        │
│  • 简单 & 语义缓存                                        │
│  • JSON 文件持久化                                         │
├─────────────────────────────────────────────────────────────┤
│  插件系统 (默认零依赖)                                      │
│  ───────────────────────────────────────────                │
│  • KV Store: memory (默认), sqlite (可选)                 │
│  • Cache: simple (TTL), semantic (基于 embedding)         │
│  • Guardrails: 内容过滤, PII 检测                          │
│  • Cost Tracker: 按 key/team/model 追踪                    │
└─────────────────────────────────────────────────────────────┘
```

## 与其他 SDK 对比

| 特性 | llmlite | go-genai | litellm |
|------|---------|----------|---------|
| 语言 | Zig | Go | Python |
| 体积 | ~500KB | ~5MB | ~50MB |
| 运行时依赖 | 无 | 无 | 多个 |
| 类型安全 | 完整 | 完整 | 部分 |

## 示例

请参阅 `examples/` 目录获取完整示例：

- `chat_basic.zig` - 基础聊天补全
- `chat_stream.zig` - 流式聊天
- `gemini_advanced.zig` - Gemini 特定功能
- `minimax_media.zig` - TTS 和视频生成

## 贡献

欢迎贡献！请参阅 [CONTRIBUTING.md](../CONTRIBUTING.md) 了解指南。

## 许可证

AGPL-3.0 - 有关详细信息，请参阅 [LICENSE](../../LICENSE)。

## 链接

- [English README](../../README.md)
- [提供商文档](../providers/)
- [示例](../../examples/)
- [更新日志](../../CHANGELOG.md)
