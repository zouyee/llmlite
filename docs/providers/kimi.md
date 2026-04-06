# Kimi Provider (Moonshot AI)

## Overview

The Kimi provider provides access to Kimi models through the Moonshot AI API platform. Kimi is OpenAI-compatible with additional features like thinking mode (K2.5), partial mode, and vision support.

**Base URL**: `https://api.moonshot.cn/v1`

**Auth Type**: Bearer Token

## Supported Models

| Model | Description |
|-------|-------------|
| `kimi-k2.5` | Latest multimodal model with thinking |
| `kimi-k2-turbo-preview` | Fast K2 model |
| `kimi-k2-thinking` | Thinking-optimized K2 |
| `moonshot-v1-8k` | 8K context chat model |
| `moonshot-v1-32k` | 32K context chat model |
| `moonshot-v1-128k` | 128K context chat model |
| `moonshot-v1-8k-vision-preview` | Vision-enabled 8K model |
| `moonshot-v1-32k-vision-preview` | Vision-enabled 32K model |

## API Endpoints

### Chat Completions

**Endpoint**: `POST /chat/completions`

OpenAI-compatible endpoint:

```zig
var lm = language_model.LanguageModel.init(
    allocator,
    http_client,
    .moonshot,
    "kimi-k2.5",
);

const response = try lm.complete(.{
    .model = "kimi-k2.5",
    .messages = &.{
        .{ .role = .user, .content = "Hello!" },
    },
    .max_tokens = 100,
    .temperature = 0.7,
});
```

### Kimi-Specific Parameters

| Parameter | Type | Model | Description |
|-----------|------|-------|-------------|
| `thinking` | object | K2.5 only | Enable/disable thinking mode |
| `max_completion_tokens` | int | All | Max output tokens (preferred over max_tokens) |
| `partial` | bool | All | Prefill mode for JSON/roleplay |

### Thinking Mode (K2.5)

Kimi K2.5 supports explicit thinking chains:

```zig
// Enable thinking
const response = try lm.complete(.{
    .model = "kimi-k2.5",
    .messages = &.{.{ .role = .user, .content = "Solve: 2+2=?" }},
    .thinking = .{ .type = "enabled" },
});

// Disable thinking (direct answer)
const response = try lm.complete(.{
    .model = "kimi-k2.5",
    .messages = &.{.{ .role = .user, .content = "Say hello" }},
    .thinking = .{ .type = "disabled" },
});
```

### Partial Mode

Prefill model output for JSON mode or role-playing:

```zig
// JSON Mode with partial prefill
const response = try lm.complete(.{
    .model = "kimi-k2.5",
    .messages = &.{
        .{ .role = .system, .content = "Return valid JSON with name and age" },
        .{ .role = .user, .content = "I'm 25 years old" },
        .{ .role = .assistant, .content = "{", .partial = true },
    },
    .max_tokens = 1024,
});

// Role-playing with name
const response = try lm.complete(.{
    .model = "kimi-k2.5",
    .messages = &.{
        .{ .role = .system, .content = "You are Doctor KeliXi" },
        .{ .role = .user, .content = "Hello" },
        .{ .role = .assistant, .name = "KeliXi", .content = "", .partial = true },
    },
});
```

### Token Estimation

**Endpoint**: `POST /tokenizers/estimate-token-count`

```zig
var kimi_client = provider.kimi.KimiClient.init(allocator, http_client);

const estimate = try kimi_client.estimateTokenCount(.{
    .model = "kimi-k2.5",
    .messages = &.{
        .{ .role = .system, .content = "You are helpful" },
        .{ .role = .user, .content = "Hello!" },
    },
});
```

### Balance Query

**Endpoint**: `GET /users/me/balance`

```zig
var kimi_client = provider.kimi.KimiClient.init(allocator, http_client);

const balance = try kimi_client.getBalance();
std.debug.print("Available: {d} CNY\n", .{balance.available_balance});
std.debug.print("Voucher: {d} CNY\n", .{balance.voucher_balance});
std.debug.print("Cash: {d} CNY\n", .{balance.cash_balance});
```

## Files API

### Upload File

**Endpoint**: `POST /files`

```zig
const file_mod = @import("file");
var file_service = file_mod.Service.init(allocator, http_client);

// Upload for extraction
const file = try file_service.uploadFile(pdf_content, "document.pdf", .file_extract);

// Upload for vision
const image = try file_service.uploadFile(img_content, "photo.png", .image);

// Upload for video understanding
const video = try file_service.uploadFile(vid_content, "clip.mp4", .video);
```

**Supported Purposes**:
- `file-extract`: PDF, DOC, TXT extraction
- `image`: Vision understanding
- `video`: Video understanding

### List Files

**Endpoint**: `GET /files`

```zig
const files = try file_service.listFiles();
for (files.data) |f| {
    std.debug.print("File: {s} ({d} bytes)\n", .{ f.filename, f.bytes });
}
```

### Get File Info

**Endpoint**: `GET /files/{file_id}`

```zig
const info = try file_service.getFile(file_id);
```

### Delete File

**Endpoint**: `DELETE /files/{file_id}`

```zig
const deleted = try file_service.deleteFile(file_id);
```

### Download Content

**Endpoint**: `GET /files/{file_id}/content`

```zig
const content = try file_service.downloadContent(file_id);
```

## Vision Support

Kimi supports vision through content arrays:

```zig
const response = try lm.complete(.{
    .model = "kimi-k2.5",
    .messages = &.{
        .{
            .role = .user,
            .parts = &[_]chat.MessageContentPart{
                .{
                    .image_url = .{
                        .image_url = .{
                            .url = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUg...",
                        },
                    },
                },
                .{ .text = .{ .text = "Describe this image" } },
            },
        },
    },
});
```

**Supported URL Formats**:
- `data:image/png;base64,...` - Base64 encoded
- `ms://<file_id>` - File ID from Files API

## Tool Use / Function Calling

OpenAI-compatible function calling:

```zig
const tools = &[_]chat.ToolDefinition{
    .{
        .type = "function",
        .function = .{
            .name = "get_weather",
            .description = "Get weather for a location",
            .parameters = "{\"type\":\"object\",\"properties\":{\"location\":{\"type\":\"string\"}}}",
        },
    },
};

const response = try lm.complete(.{
    .model = "kimi-k2.5",
    .messages = &.{.{ .role = .user, .content = "Weather in Beijing?" }},
    .tools = tools,
});
```

## Streaming

```zig
const stream = try lm.completeStream(.{
    .model = "kimi-k2.5",
    .messages = &.{.{ .role = .user, .content = "Count to 5" }},
    .stream = true,
});

while (try stream.next()) |chunk| {
    if (chunk.delta.content) |c| {
        std.debug.print("{s}", .{c});
    }
}
```

## Response Format

```json
{
  "id": "cmpl-xxx",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "kimi-k2.5",
  "choices": [{
    "index": 0,
    "message": {
      "role": "assistant",
      "content": "Hello!"
    },
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 20,
    "total_tokens": 30,
    "cached_tokens": 5
  }
}
```

**Note**: `cached_tokens` is included when context caching is used.

## Error Handling

```zig
const response = lm.complete(params) catch |err| {
    switch (err) {
        error.AuthenticationError => std.debug.print("Invalid API key\n", .{}),
        error.ContentFiltered => std.debug.print("Content filtered\n", .{}),
        error.RateLimitError => std.debug.print("Rate limited\n", .{}),
        else => std.debug.print("Error: {}\n", .{err}),
    }
    return err;
};

// Parse Kimi-specific errors
const kimi_error = provider.kimi.parseKimiError(response_body);
```

## Model-Specific Constraints

| Parameter | kimi-k2.5 | moonshot-v1 |
|-----------|-----------|-------------|
| `temperature` | Not modifiable | Default: 0.0, Range: [0, 1] |
| `top_p` | Default: 0.95, Not modifiable | Default: 1.0 |
| `n` | Default: 1, Not modifiable | Default: 1, Max: 5 |
| `presence_penalty` | Not modifiable | Default: 0.0, Range: [-2, 2] |
| `frequency_penalty` | Not modifiable | Default: 0.0, Range: [-2, 2] |

## Rate Limits

Rate limits vary by subscription tier. Check the [Moonshot console](https://platform.moonshot.cn/console) for your limits.

## References

- [Kimi API Documentation](https://platform.moonshot.cn/docs/api/chat)
- [API Overview](https://platform.moonshot.cn/docs/overview)
- [Console](https://platform.moonshot.cn/console)
- [Pricing](https://platform.moonshot.cn/docs/pricing/chat)
