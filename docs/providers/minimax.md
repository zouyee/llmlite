# Minimax Provider

## Overview

The Minimax provider provides access to Minimax's language models and media generation APIs including TTS, video, image, and music generation.

**Base URL**: `https://api.minimax.chat/v1`

**Auth Type**: Bearer Token

## Supported Models

### Chat Models

| Model | Description |
|-------|-------------|
| `MiniMax-M2.7` | Latest flagship chat model |
| `MiniMax-Text-01` | Text-focused model |

### Media Models

| Model | Type | Description |
|-------|------|-------------|
| `speech-02-hd` | TTS | High-definition text-to-speech |
| `speech-02-turbo` | TTS | Fast text-to-speech |
| `speech-01-hd` | TTS | Premium text-to-speech |
| `minimax-hailuo-02` | Video | Text-to-video generation |
| `MiniMax-Hailuo-2.3` | Video | Advanced video generation |
| `image-01` | Image | High-quality image generation |
| `music-2.5` | Music | Music generation |

## API Endpoints

### Chat Completions

**Endpoint**: `POST /chat/completions`

OpenAI-compatible endpoint:

```zig
var lm = language_model.LanguageModel.init(
    allocator,
    http_client,
    .minimax,
    "MiniMax-M2.7",
);

const response = try lm.complete(.{
    .model = "MiniMax-M2.7",
    .messages = &.{
        .{ .role = .user, .content = "Hello!" },
    },
    .max_tokens = 100,
    .temperature = 0.7,
});
```

**Parameters**: Same as OpenAI Chat Completions

### Text-to-Speech (TTS)

**Endpoint**: `POST /t2a_v2`

```zig
const tts_result = try tts_service.synthesize(.{
    .model = "speech-02-hd",
    .text = "Hello, this is a test of the text to speech system.",
    .stream = false,
    .voice_setting = .{
        .voice_id = "male-qn-qingse",
        .speed = 1.0,
        .vol = 1.0,
        .pitch = 0,
        .emotion = .calm,
    },
    .audio_setting = .{
        .sample_rate = 32000,
        .bitrate = 128000,
        .format = .mp3,
        .channel = 1,
    },
    .output_format = "hex",
});
```

**Voice IDs**:

| ID | Description |
|----|-------------|
| `male-qn-qingse` | Male, calm |
| `female-youth` | Female, youthful |
| `female-tianmei` | Female, sweet |
| `male-baimay` | Male, professional |

**Emotions**: `happy`, `sad`, `angry`, `fearful`, `disgusted`, `surprised`, `calm`, `fluent`, `whisper`

### Video Generation

**Endpoint**: `POST /video_generation`

**Modes**:
- T2V (Text-to-Video)
- I2V (Image-to-Video)
- FL2V (First-Last Frame Video)
- S2V (Subject Reference Video)

```zig
// Text-to-Video
const video_result = try video_service.generate(.{
    .model = .minimax_hailuo_02,
    .prompt = "A beautiful sunset over the ocean with gentle waves",
    .duration = 6,
    .resolution = .r768p,
});
```

**Resolutions**: `r512p`, `r720p`, `r768p`, `r1080p`

### Image Generation

**Endpoint**: `POST /image_generation`

```zig
const image_result = try image_service.generate(.{
    .model = "image-01",
    .prompt = "A cute puppy playing in a park",
    .style = .{
        .style_type = .watercolor,
        .style_weight = 0.8,
    },
    .aspect_ratio = .ratio_1_1,
    .response_format = .url,
    .n = 1,
});
```

**Style Types**: `cartoon`, `energetic`, `medieval`, `watercolor`

**Aspect Ratios**: `1:1`, `16:9`, `4:3`, `3:2`, `2:3`, `3:4`, `9:16`, `21:9`

### Music Generation

**Endpoint**: `POST /music_generation`

```zig
const music_result = try music_service.generate(.{
    .model = "music-2.5",
    .prompt = "Upbeat pop music with catchy melody",
    .lyrics = "La la la, happy day\nSinging along",
    .is_instrumental = false,
    .output_format = "hex",
});
```

## Response Formats

### TTS Response
```json
{
  "data": {
    "audio": "hex_encoded_audio_data",
    "status": 2
  },
  "base_resp": {
    "status_code": 0,
    "status_msg": "success"
  }
}
```

### Video Response
```json
{
  "task_id": "xxx",
  "status_code": 0,
  "base_resp": {
    "status_msg": "success"
  }
}
```

### Image Response
```json
{
  "id": "xxx",
  "data": {
    "image_urls": ["https://..."]
  },
  "metadata": {
    "success_count": 1,
    "failed_count": 0
  },
  "base_resp": {
    "status_code": 0,
    "status_msg": "success"
  }
}
```

## Error Codes

| Code | Description |
|------|-------------|
| 0 | Success |
| 1001 | Invalid request |
| 1002 | Missing parameters |
| 1003 | Invalid API key |
| 1004 | API key expired |
| 2001 | Model not found |
| 2013 | Invalid parameters |
| 2061 | Model not supported by current plan |

## Rate Limits

Rate limits vary by subscription tier. Check your account dashboard for specific limits.

## References

- [Minimax API Documentation](https://platform.minimaxi.com/docs/api-reference/)
- [Console](https://platform.minimaxi.com/console)
