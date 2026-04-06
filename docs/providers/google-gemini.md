# Google Gemini Provider

## Overview

The Google Gemini provider provides access to Google's Gemini models with advanced features like context caching, model tuning, and real-time streaming.

**Base URL**: `https://generativelanguage.googleapis.com/v1beta`

**Auth Type**: API Key (query parameter)

## Supported Models

| Model | Description |
|-------|-------------|
| `gemini-2.0-flash` | Latest fast model with 1M context |
| `gemini-1.5-flash` | Balanced speed and quality |
| `gemini-1.5-pro` | Highest quality, 2M context |
| `gemini-1.5-flash-8b` | Lightweight, 32K context |
| `gemini-2.5-pro-preview` | Preview of next generation |

## API Endpoints

### Chat Completions

**Endpoint**: `POST /models/{model}:generateContent`

```zig
const response = try lm.complete(.{
    .model = "gemini-2.0-flash",
    .messages = &.{
        .{ .role = .user, .content = "Hello!" },
    },
});
```

**Gemini-Specific Parameters**:

| Parameter | Type | Description |
|-----------|------|-------------|
| `generationConfig.candidateCount` | int | Number of responses (1-8) |
| `generationConfig.maxOutputTokens` | int | Max tokens in response |
| `generationConfig.temperature` | float | Sampling temperature |
| `generationConfig.topP` | float | Top P sampling |
| `generationConfig.topK` | int | Top K sampling |
| `safetySettings` | array | Content filtering settings |

### Embeddings

**Endpoint**: `POST /models/{model}:embedContent`

```zig
const embedding = try lm.embeddings(.{
    .model = "text-embedding-004",
    .content = "Hello world",
});
```

## Advanced APIs

Gemini provides several advanced APIs not available in standard OpenAI-compatible providers.

### Context Caching

Cache frequently used context for cost savings and faster inference.

**Endpoint**: `POST /v1beta/cachedContent`

```zig
const cache = try provider.caches().create(.{
    .model = "gemini-1.5-flash",
    .contents = &.{
        .{
            .role = "user",
            .parts = &.{.{ .text = "You are a helpful assistant specialized in..." }},
        },
    },
    .ttl = "3600s",  // 1 hour
});
```

**Use cached context**:
```zig
const response = try lm.complete(.{
    .model = "gemini-1.5-flash",
    .messages = &.{.{ .role = .user, .content = "Based on the context, answer..." }},
    .cached_content = cache.name,
});
```

### Model Tuning

Fine-tune Gemini models for specific use cases.

**Endpoint**: `POST /v1beta/tunedModels`

```zig
const tuning = try provider.tunings().create(.{
    .base_model = "gemini-1.5-flash",
    .training_data_uri = "gs://bucket/training_data.jsonl",
    .display_name = "my-tuned-model",
    .description = "Model tuned for customer support",
});
```

### Document Management

Manage documents for RAG pipelines.

**Endpoint**: `POST /v1beta/documents`

```zig
const doc = try provider.documents().create(.{
    .model = "gemini-1.5-flash",
    .display_name = "My Document",
});
```

### Vector Search Stores

Create searchable vector databases.

**Endpoint**: `POST /v1beta/stores`

```zig
const store = try provider.stores().create(.{
    .display_name = "my-vector-store",
    .description = "Store for product embeddings",
});
```

### Token Counting

Count tokens before API calls to estimate costs.

**Endpoint**: `POST /v1beta/models/{model}:countTokens`

```zig
const tokens = try provider.tokens().countTokens(.{
    .model = "gemini-1.5-flash",
    .content = "Hello, world!",
});
```

### Batch Processing

Process multiple requests efficiently.

**Endpoint**: `POST /v1beta/models/{model}:batchGenerateContent`

```zig
const batch_result = try provider.operations().createBatch(.{
    .model = "gemini-1.5-flash",
    .requests = requests[..],
});
```

### Real-time Live

Bidirectional streaming for live applications.

**Endpoint**: `POST /v1beta/models/{model}:streamGenerateContent`

```zig
// Real-time streaming with bidirectional communication
const live = try lm.live(.{
    .model = "gemini-2.0-flash",
    .config = .{
        .responseModalities = &.{"TEXT", "AUDIO"},
    },
});
```

## Vision Support

Gemini supports vision natively:

```zig
const response = try lm.complete(.{
    .model = "gemini-2.0-flash",
    .messages = &.{
        .{
            .role = .user,
            .parts = &[_]chat.MessageContentPart{
                .{ .image_url = .{ .image_url = .{ .url = "gs://bucket/image.png" } } },
                .{ .text = .{ .text = "Describe this image" } },
            },
        },
    },
});
```

## Safety Settings

Gemini provides granular content filtering:

```zig
const response = try lm.complete(.{
    .model = "gemini-2.0-flash",
    .messages = &.{.{ .role = .user, .content = "Hello" }},
    .safety_settings = &.{
        .{ .category = .HARM_CATEGORY_HARASSMENT, .threshold = .BLOCK_ONLY_HIGH },
    },
});
```

## Response Format

```json
{
  "candidates": [{
    "content": {
      "parts": [{"text": "Hello!"}],
      "role": "model"
    },
    "finishReason": "STOP",
    "index": 0,
    "safetyRatings": [...]
  }],
  "promptFeedback": {
    "safetyRatings": [...]
  }
}
```

## Error Handling

```zig
const response = lm.complete(params) catch |err| {
    switch (err) {
        error.BlockedPrompt => std.debug.print("Content blocked by safety filters\n", .{}),
        error.Safety => std.debug.print("Safety rating issue\n", .{}),
        error.InvalidArgument => std.debug.print("Invalid request\n", .{}),
        else => std.debug.print("Error: {}\n", .{err}),
    }
    return err;
};
```

## Rate Limits

| Tier | Requests/minute | Tokens/minute |
|------|-----------------|---------------|
| Free | 15 | 1M |
| Spark | 150 | 10M |
| Pro | 150 | 10M |
| Ultra | 1000 | 40M |

## References

- [Gemini API Documentation](https://ai.google.dev/gemini-api/docs)
- [Gemini API Reference](https://ai.google.dev/gemini-api/reference)
- [Pricing](https://ai.google.dev/gemini-api/pricing)
