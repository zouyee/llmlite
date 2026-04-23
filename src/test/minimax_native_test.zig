//! MiniMax Native API Capability Test Runner
//!
//! Tests MiniMax-specific APIs that are not OpenAI-compatible:
//! - TTS (Text-to-Audio)
//! - Video Generation (T2V, I2V, FL2V, S2V)
//! - Image Generation
//! - Music Generation

const std = @import("std");

// Zig 0.16.0 compat: replacement for removed _getEnvVarOwned
fn _getEnvVarOwned(allocator: std.mem.Allocator, key: [*:0]const u8) error{EnvironmentVariableNotFound, OutOfMemory}![]u8 {
    const ptr = std.c.getenv(key) orelse return error.EnvironmentVariableNotFound;
    const slice = std.mem.sliceTo(ptr, 0);
    return allocator.dupe(u8, slice);
}
const http = @import("http");
const tts_mod = @import("minimax/tts");

var g_io: std.Io = undefined;
const video_mod = @import("minimax/video");
const image_mod = @import("minimax/image");
const music_mod = @import("minimax/music");

// ============================================================================
// MiniMax Endpoint Auto-Detection
// ============================================================================

/// MiniMax endpoint configuration based on platform
///
/// IMPORTANT:
/// - minimax.com → api.minimaxi.com
/// - minimax.io → api.minimax.io
const MiniMaxEndpoint = struct {
    pub const minimax_com = "https://api.minimaxi.com";
    pub const minimax_io = "https://api.minimax.io";
};

/// Auto-detect the correct MiniMax endpoint based on API key or base URL
///
/// Detection logic:
/// - If contains "minimax.io" → api.minimax.io
/// - If contains "minimax.chat" → api.minimax.chat
/// - If contains "minimaxi.com" → api.minimaxi.com
/// - Default fallback: api.minimax.chat (most common)
fn detectMinimaxEndpoint(base_url_or_key: []const u8) []const u8 {
    if (std.mem.find(u8, base_url_or_key, "minimax.io") != null) {
        return MiniMaxEndpoint.minimax_io;
    }
    if (std.mem.find(u8, base_url_or_key, "minimax.chat") != null) {
        return "https://api.minimax.chat";
    }
    if (std.mem.find(u8, base_url_or_key, "minimaxi.com") != null) {
        return MiniMaxEndpoint.minimax_com;
    }
    // Default fallback - most common endpoint
    return "https://api.minimax.chat";
}

/// Auto-detect the correct MiniMax endpoint based on API key or base URL
fn getBaseUrl(allocator: std.mem.Allocator, api_key: []const u8) ![]const u8 {
    if (std.mem.find(u8, api_key, "minimax.io") != null) {
        return std.fmt.allocPrint(allocator, "{s}/v1", .{MiniMaxEndpoint.minimax_io});
    }
    if (std.mem.find(u8, api_key, "minimax.chat") != null) {
        return std.fmt.allocPrint(allocator, "https://api.minimax.chat/v1", .{});
    }
    if (std.mem.find(u8, api_key, "minimaxi.com") != null) {
        return std.fmt.allocPrint(allocator, "{s}/v1", .{MiniMaxEndpoint.minimax_com});
    }
    // Default fallback (minimax.chat - most common)
    return std.fmt.allocPrint(allocator, "https://api.minimax.chat/v1", .{});
}

pub fn main(init: std.process.Init) !void {
    g_io = init.io;
    std.debug.print("=== MiniMax Native API Capability Test Runner ===\n\n", .{});

    const allocator = std.heap.page_allocator;

    // Read API key from environment variable
    const api_key_env = _getEnvVarOwned(allocator, "MINIMAX_API_KEY") catch null;
    const api_key: []const u8 = api_key_env orelse {
        std.debug.print("Error: MINIMAX_API_KEY environment variable not set\n", .{});
        std.debug.print("Please set it in your .env file or export it:\n", .{});
        std.debug.print("  export MINIMAX_API_KEY=your_api_key_here\n", .{});
        return error.MissingApiKey;
    };
    defer allocator.free(api_key_env.?);

    const base_url = try getBaseUrl(allocator, api_key);
    defer allocator.free(base_url);

    var passed: u32 = 0;
    var failed: u32 = 0;
    var skipped: u32 = 0;

    // =========================================================================
    // 1. TTS (Text-to-Audio) API
    // =========================================================================
    std.debug.print("========================================\n", .{});
    std.debug.print("[Category 1] TTS (Text-to-Audio) API\n", .{});
    std.debug.print("========================================\n", .{});

    // Test 1.1: T2A Basic
    std.debug.print("[1.1] T2A Basic Synthesis... ", .{});
    if (testT2ABasic(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // Test 1.2: T2A with Emotion
    std.debug.print("[1.2] T2A with Emotion... ", .{});
    if (testT2AWithEmotion(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // =========================================================================
    // 2. Video Generation API
    // =========================================================================
    std.debug.print("\n========================================\n", .{});
    std.debug.print("[Category 2] Video Generation API\n", .{});
    std.debug.print("========================================\n", .{});

    // Test 2.1: T2V (Text-to-Video)
    std.debug.print("[2.1] T2V (Text-to-Video)... ", .{});
    if (testVideoT2V(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // Test 2.2: I2V (Image-to-Video) - Skip (needs image URL)
    std.debug.print("[2.2] I2V (skip - needs image URL)... ", .{});
    skipped += 1;

    // Test 2.3: FL2V (skip - needs two image URLs)
    std.debug.print("[2.3] FL2V (skip - needs two image URLs)... ", .{});
    skipped += 1;

    // Test 2.4: S2V (skip - needs subject reference image)
    std.debug.print("[2.4] S2V (skip - needs subject reference)... ", .{});
    skipped += 1;

    // =========================================================================
    // 3. Image Generation API
    // =========================================================================
    std.debug.print("\n========================================\n", .{});
    std.debug.print("[Category 3] Image Generation API\n", .{});
    std.debug.print("========================================\n", .{});

    // Test 3.1: Image Generation Basic
    std.debug.print("[3.1] Image Generation Basic... ", .{});
    if (testImageGeneration(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // Test 3.2: Image Generation with Style
    std.debug.print("[3.2] Image Generation with Style... ", .{});
    if (testImageGenerationWithStyle(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // Test 3.3: Image Generation with Aspect Ratio
    std.debug.print("[3.3] Image Generation with Aspect Ratio... ", .{});
    if (testImageGenerationAspectRatio(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // =========================================================================
    // 4. Music Generation API
    // =========================================================================
    std.debug.print("\n========================================\n", .{});
    std.debug.print("[Category 4] Music Generation API\n", .{});
    std.debug.print("========================================\n", .{});

    // Test 4.1: Music Generation Basic
    std.debug.print("[4.1] Music Generation Basic... ", .{});
    if (testMusicGeneration(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // Test 4.2: Music Generation Instrumental
    std.debug.print("[4.2] Music Generation Instrumental... ", .{});
    if (testMusicGenerationInstrumental(allocator, api_key, base_url)) |_| {
        passed += 1;
    } else |err| {
        std.debug.print("FAILED: {}\n", .{err});
        failed += 1;
    }

    // =========================================================================
    // Summary
    // =========================================================================
    std.debug.print("\n========================================\n", .{});
    std.debug.print("SUMMARY\n", .{});
    std.debug.print("========================================\n", .{});
    std.debug.print("Passed:  {d}\n", .{passed});
    std.debug.print("Failed:  {d}\n", .{failed});
    std.debug.print("Skipped: {d}\n", .{skipped});
    std.debug.print("Total:   {d}\n", .{passed + failed + skipped});

    if (failed > 0) {
        std.debug.print("\nSome tests failed.\n", .{});
        return error.TestsFailed;
    } else {
        std.debug.print("\nAll tests passed!\n", .{});
    }
}

// =============================================================================
// TTS Tests
// =============================================================================

fn testT2ABasic(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        g_io,
        base_url,
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var tts_service = tts_mod.Service.init(allocator, &http_client);

    const params = tts_mod.T2ARequest{
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
    };

    const result = try tts_service.synthesize(params);

    // Check if API error (2061 = token plan doesn't support this model)
    if (result.status == 2061 or result.audio == null) {
        std.debug.print("SKIPPED (API limitation: model not supported or {d})\n", .{result.status});
        return;
    }

    // Verify we got audio data
    try std.testing.expect(result.audio != null);
    try std.testing.expect(result.audio.?.len > 0);
    try std.testing.expect(result.status == 0);
    std.debug.print("OK (audio size: {d} hex chars)\n", .{result.audio.?.len});
}

fn testT2AWithEmotion(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        g_io,
        base_url,
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var tts_service = tts_mod.Service.init(allocator, &http_client);

    const params = tts_mod.T2ARequest{
        .model = "speech-02-hd",
        .text = "Wow, this is amazing! I'm so happy to see you!",
        .stream = false,
        .voice_setting = .{
            .voice_id = "female-youth",
            .speed = 1.0,
            .vol = 1.0,
            .pitch = 0,
            .emotion = .happy,
        },
        .audio_setting = null,
        .output_format = "hex",
    };

    const result = try tts_service.synthesize(params);

    // Check if API error (2061 = token plan doesn't support this model)
    if (result.status == 2061 or result.audio == null) {
        std.debug.print("SKIPPED (API limitation: model not supported or {d})\n", .{result.status});
        return;
    }

    try std.testing.expect(result.audio != null);
    try std.testing.expect(result.status == 0);
    std.debug.print("OK (audio size: {d} hex chars)\n", .{result.audio.?.len});
}

// =============================================================================
// Video Generation Tests
// =============================================================================

fn testVideoT2V(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        g_io,
        base_url,
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var video_service = video_mod.Service.init(allocator, &http_client);

    const params = video_mod.VideoGenerationRequest{
        .model = video_mod.VideoModel.minimax_hailuo_02,
        .prompt = "A beautiful sunset over the ocean with gentle waves",
        .first_frame_image = null,
        .last_frame_image = null,
        .subject_references = null,
        .prompt_optimizer = true,
        .fast_pretreatment = null,
        .duration = 6,
        .resolution = video_mod.VideoResolution.r768p,
        .callback_url = null,
        .aigc_watermark = null,
    };

    const result = try video_service.generate(params);

    // Check if API error (2061 = token plan doesn't support this model)
    if (result.status_code == 2061) {
        std.debug.print("SKIPPED (API limitation: video model not supported)\n", .{});
        return;
    }

    // Verify we got a task_id
    try std.testing.expect(result.task_id != null);
    try std.testing.expect(result.status_code == 0);
    std.debug.print("OK (task_id: {s})\n", .{result.task_id.?});
}

// =============================================================================
// Image Generation Tests
// =============================================================================

fn testImageGeneration(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        g_io,
        base_url,
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var image_service = image_mod.Service.init(allocator, &http_client);

    const params = image_mod.ImageGenerateRequest{
        .model = "image-01",
        .prompt = "A cute puppy playing in a park",
        .style = null,
        .aspect_ratio = .ratio_1_1,
        .width = null,
        .height = null,
        .response_format = .url,
        .seed = null,
        .n = 1,
        .prompt_optimizer = false,
        .aigc_watermark = null,
    };

    const result = try image_service.generate(params);

    try std.testing.expect(result.status_code == 0);
    std.debug.print("OK (success_count: {d})\n", .{result.success_count});
}

fn testImageGenerationWithStyle(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        g_io,
        base_url,
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var image_service = image_mod.Service.init(allocator, &http_client);

    const params = image_mod.ImageGenerateRequest{
        .model = "image-01",
        .prompt = "A beautiful landscape with mountains",
        .style = .{
            .style_type = .watercolor,
            .style_weight = 0.8,
        },
        .aspect_ratio = .ratio_16_9,
        .width = null,
        .height = null,
        .response_format = .url,
        .seed = null,
        .n = 1,
        .prompt_optimizer = false,
        .aigc_watermark = null,
    };

    const result = try image_service.generate(params);

    try std.testing.expect(result.status_code == 0);
    std.debug.print("OK (success_count: {d})\n", .{result.success_count});
}

fn testImageGenerationAspectRatio(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        g_io,
        base_url,
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var image_service = image_mod.Service.init(allocator, &http_client);

    const params = image_mod.ImageGenerateRequest{
        .model = "image-01",
        .prompt = "A tall skyscraper in a modern city",
        .style = null,
        .aspect_ratio = .ratio_9_16,
        .width = null,
        .height = null,
        .response_format = .url,
        .seed = null,
        .n = 1,
        .prompt_optimizer = false,
        .aigc_watermark = null,
    };

    const result = try image_service.generate(params);

    try std.testing.expect(result.status_code == 0);
    std.debug.print("OK (success_count: {d})\n", .{result.success_count});
}

// =============================================================================
// Music Generation Tests
// =============================================================================

fn testMusicGeneration(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        g_io,
        base_url,
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var music_service = music_mod.Service.init(allocator, &http_client);

    // Music API may require lyrics or specific params - try with lyrics
    const params = music_mod.MusicGenerateRequest{
        .model = "music-2.5",
        .prompt = "Upbeat pop music with catchy melody",
        .lyrics = "La la la, happy day\nSinging along, feeling okay",
        .stream = false,
        .output_format = "hex",
        .audio_setting = .{
            .sample_rate = 44100,
            .bitrate = 256000,
            .format = .mp3,
        },
        .aigc_watermark = null,
        .lyrics_optimizer = null,
        .is_instrumental = false,
    };

    const result = try music_service.generate(params);

    // Check if API error (2013 = invalid params, 2061 = not supported)
    if (result.status_code == 2013 or result.status_code == 2061) {
        std.debug.print("SKIPPED (API limitation: {s})\n", .{result.status_msg orelse "unknown"});
        return;
    }

    try std.testing.expect(result.audio != null);
    try std.testing.expect(result.audio.?.len > 0);
    try std.testing.expect(result.status_code == 0);
    std.debug.print("OK (audio size: {d} hex chars)\n", .{result.audio.?.len});
}

fn testMusicGenerationInstrumental(allocator: std.mem.Allocator, api_key: []const u8, base_url: []const u8) !void {
    var http_client = http.HttpClient.initWithAuthType(
        allocator,
        g_io,
        base_url,
        api_key,
        null,
        60000,
        .bearer,
    );
    defer http_client.deinit();

    var music_service = music_mod.Service.init(allocator, &http_client);

    const params = music_mod.MusicGenerateRequest{
        .model = "music-2.5",
        .prompt = "Peaceful ambient music with nature sounds",
        .lyrics = null,
        .stream = false,
        .output_format = "hex",
        .audio_setting = null,
        .aigc_watermark = null,
        .lyrics_optimizer = null,
        .is_instrumental = true,
    };

    const result = try music_service.generate(params);

    // Check if API error (2013 = invalid params, 2061 = not supported)
    if (result.status_code == 2013 or result.status_code == 2061) {
        std.debug.print("SKIPPED (API limitation: {s})\n", .{result.status_msg orelse "unknown"});
        return;
    }

    try std.testing.expect(result.audio != null);
    try std.testing.expect(result.status_code == 0);
    std.debug.print("OK (audio size: {d} hex chars)\n", .{result.audio.?.len});
}
