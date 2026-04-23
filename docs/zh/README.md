# llmlite

**轻量级、高性能的 LLM SDK、Edge Router 与 CLI 工具，使用 Zig 编写**

[![CI](https://github.com/zouyee/llmlite/actions/workflows/ci.yml/badge.svg)](https://github.com/zouyee/llmlite/actions)
[![Zig](https://img.shields.io/badge/Zig-0.16+-orange.svg)](https://ziglang.org/)
[![License](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)
[![Binary Size](https://img.shields.io/badge/Binary%20Size-672KB-success)](build.zig)

## 概述

llmlite 是一个**零依赖、边缘就绪的 LLM SDK 和 AI 网关**，使用 Zig 编写。与 Python 方案（LiteLLM ~50MB、vLLM Semantic Router 需要 K8s/Docker）不同，llmlite 提供：

- **边缘就绪** - 672KB 单一二进制文件，无需 Docker/K8s
- **边缘场景** - 可部署到 IoT 设备、CLI 工具、WASM、嵌入式系统
- **Zig 原生** - 使用 Zig 0.16+ 构建，极致性能与内存安全
- **零依赖** - 完全自包含，无需 Python/Node.js 运行时
- **类型安全** - 编译时检查消除运行时类型错误

## 项目组成

| 组件 | 描述 | 二进制 |
|------|------|--------|
| **llmlite SDK** | 统一的多 Provider LLM 客户端库 | `llmlite` |
| **llmlite-proxy** | 生产级 AI 网关 / Edge Router | `llmlite-proxy` |
| **llmlite-cmd** | 开发者命令助手：智能输出过滤、跨会话记忆、Shell Hook、Token 节省追踪 | `llmlite-cmd` |
| **llmlite-mcp** | MCP (Model Context Protocol) 服务器 | `llmlite-mcp` |
| **Web Dashboard** | React 管理面板 | `web/` |

## 支持的提供商

### 原生 Provider（完整实现）

| 提供商 | 核心 API | 高级 API | 状态 |
|--------|----------|----------|------|
| **OpenAI** | Chat, Embeddings, Files, Tools | Streaming, Vision, Batch, Assistants | ✓ 稳定 |
| **Google Gemini** | Chat, Embeddings | Caches, Tunings, Documents, Tokens, FileSearch, Operations, Live | ✓ 稳定 |
| **Anthropic** | Chat, Vision, Tools | Streaming (SSE) | ✓ 稳定 |
| **Minimax** | Chat, Embeddings, TTS | Video, Image, Music | ✓ 稳定 |
| **Kimi (Moonshot)** | Chat, Files | Token Estimation, Thinking Mode, Partial Mode | ✓ 稳定 |

### OpenAI 兼容提供商

通过统一的 `language_model.zig` 处理，以下提供商开箱即用：

| 提供商 | Base URL | 说明 |
|--------|----------|------|
| **DeepSeek** | api.deepseek.com | DeepSeek V3/Coder |
| **Cohere** | api.cohere.ai | Command 系列 |
| **Fireworks** | api.fireworks.ai | 快速推理 |
| **Cerebras** | api.cerebras.ai | 超快推理 |
| **Mistral** | api.mistral.ai | Mistral 系列 |
| **Perplexity** | api.perplexity.ai | 实时搜索模型 |
| **自定义端点** | 任意 URL | 任何 OpenAI 兼容 API |

### 功能矩阵

| 功能 | OpenAI | Gemini | Anthropic | Minimax | Kimi |
|------|--------|--------|-----------|---------|------|
| Chat | ✓ | ✓ | ✓ | ✓ | ✓ |
| Streaming | ✓ | ✓ | ✓ | ✓ | ✓ |
| Embeddings | ✓ | ✓ | - | ✓ | - |
| Vision | ✓ | ✓ | ✓ | - | ✓ |
| Function Calling | ✓ | - | ✓ | - | ✓ |
| TTS/Media | - | - | - | ✓ | - |
| Thinking Mode | - | - | - | - | ✓ |

## 功能特性

### 核心能力

- **文本生成** - 可自定义参数生成内容
- **流式响应** - SSE 支持实时流式输出
- **向量嵌入** - 为 RAG 应用生成文本向量
- **对话补全** - 多轮对话 AI
- **Function Calling** - 工具调用支持
- **结构化输出** - JSON Schema 支持
- **Vision** - 图像理解
- **批量处理** - 高效处理多个请求

### 代理服务器 (AI Gateway / Edge Router)

- **Edge Routing** - 连接池、延迟追踪、熔断器
- **Virtual Key 管理** - 创建、撤销、追踪 API Keys
- **多提供商路由** - 自动故障转移、健康追踪
- **速率限制** - 每 Key QPS 和配额控制
- **成本追踪** - 按 Key/Team/Model 实时监控
- **Team/项目管理** - 多租户与预算限制
- **简单缓存** - 基于 TTL 的内存响应缓存
- **语义缓存** - 基于 Embedding 的相似度缓存
- **热重载** - 零停机配置更新
- **插件系统** - 可扩展的插件架构
- **Savings 追踪** - 接收 llmlite-cmd 上报的 token 节省数据
- **统一分析** - 聚合 API 成本 + cmd savings 统一视图
- **SQLite 持久化** - Virtual Key / Team / Project / Spend 数据持久化

### CLI 工具 (llmlite-cmd)

- **命令输出过滤** - 60-90% Token 减少
- **50+ 命令支持** - git, cargo, npm, pytest, docker, kubectl 等
- **SQLite 追踪** - 持久化 Token 节省统计
- **异步上报** - 向 llmlite-proxy 上报 savings 数据（JSONL 本地队列兜底）
- **CLI Memory** - 跨会话命令记忆，自动分类 + FTS5 全文搜索（inspired by claude-mem）
- **Shell Hook** - bash/zsh 自动集成
- **失败恢复** - Tee 机制保存原始输出

### 高级 API (Gemini)

- **上下文缓存** - 缓存常用上下文以节省成本
- **模型微调** - 为特定用例微调模型
- **文档管理** - 为 RAG 管道管理文档
- **向量搜索存储** - 创建可搜索的向量数据库
- **Token 计数** - API 调用前计算 Token
- **实时 Live** - 双向流式直播应用

### MCP 集成

- **Router 状态查询** - 查询边缘路由器状态
- **Provider 健康检查** - 检查所有 Provider 健康状态
- **Virtual Key 管理** - 创建/撤销 Key
- **成本摘要** - 查询消费统计

### Web Dashboard

- **Provider 管理** - 添加/编辑/删除/拖拽排序
- **MCP 服务器配置** - MCP 服务器管理
- **会话管理** - 会话追踪
- **设置面板** - 系统配置
- **多语言支持** - 中/英/日

## 快速开始

### 安装

将 llmlite 添加到 `build.zig`：

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

    var provider = try llmlite.Provider.init(allocator, "your-api-key", "gemini-2.0-flash");
    defer provider.deinit();

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

### 代理服务器

```bash
# 构建并运行
zig build proxy
./zig-out/bin/llmlite-proxy

# 使用配置文件
./zig-out/bin/llmlite-proxy config.json
```

### CLI 工具

```bash
# 安装 Shell Hook
llmlite-cmd init -g

# 使用
llmlite-cmd git status
llmlite-cmd cargo test
llmlite-cmd npm test

# 查看节省统计（优先查询 proxy unified 端点，fallback 到本地）
llmlite-cmd gain
llmlite-cmd gain --local     # 强制使用本地 history.db
llmlite-cmd gain --graph
llmlite-cmd gain --json
llmlite-cmd gain --csv

# CLI Memory（跨会话命令记忆）
llmlite-cmd memory search "auth bug"    # 全文搜索记忆
llmlite-cmd memory list --cat fix       # 列出近期 bug 修复
llmlite-cmd memory show 42              # 查看完整记忆详情
llmlite-cmd memory timeline 42          # 查看记忆上下文
llmlite-cmd memory stats                # 记忆统计

# 工作模式（影响记录的类别）
llmlite-cmd memory mode show            # 当前模式及设置
llmlite-cmd memory mode set infra       # 切换到 infra 模式
llmlite-cmd memory mode list            # 列出所有模式
```

### Gemini 高级 API

```zig
// Token 计数
const tokens = try provider.tokens().countTokens(model, content);

// 上下文缓存
const cache = try provider.caches().create(.{
    .model = "gemini-1.5-flash",
    .contents = &.{.{ .role = "user", .parts = &.{.{ .text = "上下文..." }} }},
    .ttl = "3600s",
});

// 模型微调
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
| `llmlite.embedding` | 向量嵌入 |
| `llmlite.stream` | 流式响应 |
| `llmlite.file` | 文件管理 |
| `llmlite.model` | 模型列表 |
| `llmlite.image` | 图像生成 |
| `llmlite.audio` | 音频/TTS |
| `llmlite.tool` | Function Calling |
| `llmlite.structured_output` | JSON Schema 结构化输出 |
| `llmlite.batch` | 批量处理 |
| `llmlite.responses` | Responses API |
| `llmlite.assistant` | Assistants API (Beta) |
| `llmlite.conversation` | 多轮对话状态管理 |
| `llmlite.realtime` | WebSocket 实时通信 |
| `llmlite.webhook` | Webhook 事件处理 |
| `llmlite.azure` | Azure OpenAI 支持 |

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
│  ├── Provider 层: openai, anthropic, gemini, minimax, kimi │
│  ├── Language Model 统一接口                                │
│  └── 高级 API: chat, stream, embedding, tool, batch...     │
├─────────────────────────────────────────────────────────────┤
│  代理服务器 (llmlite-proxy)                                │
│  ├── HTTP 服务器 (端口 4000)                               │
│  ├── Virtual Key 管理 (sk-xxx)                            │
│  ├── 多提供商路由与故障转移                                 │
│  ├── Edge Routing: 连接池, 延迟追踪, 熔断器               │
│  ├── 速率限制 • 成本追踪 • 多租户                          │
│  └── 插件系统: Cache, Guardrail, Cost Tracker             │
├─────────────────────────────────────────────────────────────┤
│  CLI 工具 (llmlite-cmd)                                    │
│  ├── 命令输出过滤 (60-90% Token 减少)                      │
│  ├── 50+ 命令支持                                          │
│  ├── SQLite 追踪 + Shell Hook                             │
│  └── CLI Memory (跨会话记忆 + FTS5 搜索)                  │
├─────────────────────────────────────────────────────────────┤
│  MCP 服务器 (llmlite-mcp)                                  │
│  └── AI Agent 工具接口                                     │
└─────────────────────────────────────────────────────────────┘
```

## 与其他方案对比

| 特性 | llmlite | LiteLLM | vLLM Semantic Router |
|------|---------|---------|---------------------|
| 语言 | Zig | Python | Python |
| 二进制大小 | 672KB | ~50MB | ~500MB (Docker) |
| 运行时依赖 | 无 | 多个 | Docker/K8s |
| 类型安全 | 完整 (comptime) | 部分 | 部分 |
| 边缘部署 | ✅ | ❌ | ❌ |
| 冷启动 | < 10ms | ~2000ms | 慢 |
| 熔断器 | ✅ 内置 | ❌ | ❌ |

## 构建与开发

```bash
make build              # 构建项目
make build-release      # 构建 Release 版本
make test               # 运行单元测试
make test-all           # 运行所有测试（含 property / integration / persistence）
make test-property      # Property-Based 正确性测试
make test-integration   # Proxy-cmd 集成测试
make test-persistence   # Proxy SQLite 持久化测试
make test-savings-reporter # Savings reporter 单元测试
make test-gain          # Gain 命令单元测试
make fmt                # 格式化代码
make check              # 运行所有检查
make clean              # 清理构建产物
make docker-build       # 构建 Docker 镜像
```

## 贡献

欢迎贡献！请参阅 [CONTRIBUTING.md](../../CONTRIBUTING.md) 了解指南。

## 许可证

AGPL-3.0 - 详见 [LICENSE](../../LICENSE)。

## 链接

- [English README](../../README.md)
- [提供商文档](../providers/)
- [架构设计](../ARCHITECTURE.md)
- [发展路线图](../roadmap.md)
- [更新日志](../../CHANGELOG.md)
