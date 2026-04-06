# OpenAI Provider

## Overview

The OpenAI provider provides access to OpenAI's language models through a unified interface. OpenAI's API is the de facto standard for LLM APIs and is used as the foundation for many other providers' compatibility layers.

**Base URL**: `https://api.openai.com/v1`

**Auth Type**: Bearer Token

## Supported Models

| Model | Description |
|-------|-------------|
| GPT-4o | Latest GPT-4 with vision capabilities |
| GPT-4 Turbo | Fast GPT-4 with 128K context |
| GPT-4 | Original GPT-4 |
| GPT-3.5 Turbo | Fast, cost-effective model |

## API Endpoints

### Chat Completions

**Endpoint**: `POST /chat/completions`

```zig
const response = try lm.complete(.{
    .model = "gpt-4o",
    .messages = &.{
        .{ .role = .user, .content = "Hello!" },
    },
    .max_tokens = 100,
    .temperature = 0.7,
});
```

**Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `model` | string | Yes | Model ID (e.g., "gpt-4o") |
| `messages` | array | Yes | Array of message objects |
| `temperature` | float | No | Sampling temperature (0-2) |
| `max_tokens` | int | No | Maximum tokens to generate |
| `top_p` | float | No | Nucleus sampling threshold |
| `n` | int | No | Number of completions (1-5) |
| `stream` | bool | No | Enable streaming (default: false) |
| `stop` | string/array | No | Stop sequences |
| `presence_penalty` | float | No | Presence penalty (-2 to 2) |
| `frequency_penalty` | float | No | Frequency penalty (-2 to 2) |
| `tools` | array | No | Function calling tools |
| `tool_choice` | object | No | Tool choice strategy |
| `response_format` | object | No | JSON mode |

### Embeddings

**Endpoint**: `POST /embeddings`

```zig
const embedding = try lm.embeddings(.{
    .model = "text-embedding-3-small",
    .input = "Hello world",
});
```

### Files API

**Endpoint**: `POST /files`

```zig
// Upload file
const file = try file_service.uploadFile(content, "example.txt", .assistants);

// List files
const list = try file_service.listFiles();

// Delete file
const deleted = try file_service.deleteFile(file_id);
```

### Vision Support

OpenAI GPT-4o supports vision through content arrays:

```zig
const response = try lm.complete(.{
    .model = "gpt-4o",
    .messages = &.{
        .{
            .role = .user,
            .parts = &[_]chat.MessageContentPart{
                .{ .image_url = .{ .image_url = .{ .url = "data:image/png;base64,..." } } },
                .{ .text = .{ .text = "Describe this image" } },
            },
        },
    },
});
```

### Streaming

```zig
const stream = try lm.completeStream(.{
    .model = "gpt-4o",
    .messages = &.{.{ .role = .user, .content = "Count to 5" }},
    .stream = true,
});
defer allocator.free(stream);

while (try stream.next()) |chunk| {
    std.debug.print("{s}", .{chunk.delta.content});
}
```

### Function Calling / Tools

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
    .model = "gpt-4o",
    .messages = &.{.{ .role = .user, .content = "What's the weather in Beijing?" }},
    .tools = tools,
});
```

## Response Format

```json
{
  "id": "chatcmpl-xxx",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "gpt-4o",
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
    "total_tokens": 30
  }
}
```

## Error Handling

```zig
const response = lm.complete(params) catch |err| {
    switch (err) {
        error.AuthenticationError => std.debug.print("Invalid API key\n", .{}),
        error.RateLimitError => std.debug.print("Rate limited\n", .{}),
        error.ServerError => std.debug.print("Server error\n", .{}),
        else => std.debug.print("Error: {}\n", .{err}),
    }
    return err;
};
```

## Rate Limits

OpenAI rate limits vary by tier:
- Free tier: 3 RPM for GPT-4, 60 RPM for GPT-3.5
- Paid tiers: Higher limits available

## References

- [OpenAI API Documentation](https://platform.openai.com/docs/api-reference)
- [OpenAI SDK](https://github.com/openai/openai-python)
