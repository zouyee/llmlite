const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // HTTP module - all other modules depend on it
    const http_module = b.addModule("http", .{
        .root_source_file = b.path("src/http.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Chat module - depends on http
    const chat_module = b.addModule("chat", .{
        .root_source_file = b.path("src/chat.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Responses module - new primary API, depends on http
    const responses_module = b.addModule("responses", .{
        .root_source_file = b.path("src/responses.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Tool module - function calling support, depends on http
    const tool_module = b.addModule("tool", .{
        .root_source_file = b.path("src/tool.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Structured Output module - JSON Schema support, depends on http
    const structured_output_module = b.addModule("structured_output", .{
        .root_source_file = b.path("src/structured_output.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Stream module - SSE streaming, depends on http
    const stream_module = b.addModule("stream", .{
        .root_source_file = b.path("src/stream.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Batch module - batch processing API, depends on http
    const batch_module = b.addModule("batch", .{
        .root_source_file = b.path("src/batch.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Azure module - Azure OpenAI support, depends on http
    const azure_module = b.addModule("azure", .{
        .root_source_file = b.path("src/azure.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Conversation module - multi-turn conversation state management, depends on http
    const conversation_module = b.addModule("conversation", .{
        .root_source_file = b.path("src/conversation.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Webhook module - webhook event handling, depends on http
    const webhook_module = b.addModule("webhook", .{
        .root_source_file = b.path("src/webhook.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Realtime module - WebSocket real-time communication, depends on http
    const realtime_module = b.addModule("realtime", .{
        .root_source_file = b.path("src/realtime.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Assistant module - Assistants API (Beta), depends on http
    const assistant_module = b.addModule("assistant", .{
        .root_source_file = b.path("src/assistant.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Embedding module - depends on http
    const embedding_module = b.addModule("embedding", .{
        .root_source_file = b.path("src/embedding.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Model module - depends on http
    const model_module = b.addModule("model", .{
        .root_source_file = b.path("src/model.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // File module - depends on http
    const file_module = b.addModule("file", .{
        .root_source_file = b.path("src/file.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Image module - depends on http
    const image_module = b.addModule("image", .{
        .root_source_file = b.path("src/image.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Audio module - depends on http
    const audio_module = b.addModule("audio", .{
        .root_source_file = b.path("src/audio.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Moderation module - depends on http
    const moderation_module = b.addModule("moderation", .{
        .root_source_file = b.path("src/moderation.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Finetune module - depends on http
    const finetune_module = b.addModule("finetune", .{
        .root_source_file = b.path("src/finetune.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Pagination module - cursor pagination helper, depends on http
    const pagination_module = b.addModule("pagination", .{
        .root_source_file = b.path("src/pagination.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Completion module - legacy text completion API, depends on http
    const completion_module = b.addModule("completion", .{
        .root_source_file = b.path("src/completion.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Container module - container management API, depends on http
    const container_module = b.addModule("container", .{
        .root_source_file = b.path("src/container.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Grader module - grading service, depends on http
    const grader_module = b.addModule("grader", .{
        .root_source_file = b.path("src/grader.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Skill module - skill management API, depends on http
    const skill_module = b.addModule("skill", .{
        .root_source_file = b.path("src/skill.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // BetaThread module - Beta thread management (deprecated), depends on http
    const betathread_module = b.addModule("betathread", .{
        .root_source_file = b.path("src/betathread.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Provider submodules - each file is an independent module
    // provider_types - depends on http and chat
    const provider_types_module = b.addModule("provider_types", .{
        .root_source_file = b.path("src/provider/types.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
            .{ .name = "chat", .module = chat_module },
        },
    });

    // provider_registry - depends on provider_types
    const provider_registry_module = b.addModule("provider_registry", .{
        .root_source_file = b.path("src/provider/registry.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = provider_types_module },
        },
    });

    // provider_openai - depends on http and chat
    const provider_openai_module = b.addModule("provider_openai", .{
        .root_source_file = b.path("src/provider/openai.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = provider_types_module },
            .{ .name = "http", .module = http_module },
            .{ .name = "chat", .module = chat_module },
        },
    });

    // provider_anthropic - depends on http and chat
    const provider_anthropic_module = b.addModule("provider_anthropic", .{
        .root_source_file = b.path("src/provider/anthropic.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = provider_types_module },
            .{ .name = "http", .module = http_module },
            .{ .name = "chat", .module = chat_module },
        },
    });

    // provider_google - depends on http and chat
    const provider_google_module = b.addModule("provider_google", .{
        .root_source_file = b.path("src/provider/google.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = provider_types_module },
            .{ .name = "http", .module = http_module },
            .{ .name = "chat", .module = chat_module },
        },
    });

    // Gemini Caches API - context caching
    const gemini_caches_module = b.addModule("gemini_caches", .{
        .root_source_file = b.path("src/provider/gemini_caches.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Gemini Tunings API - model tuning
    const gemini_tunings_module = b.addModule("gemini_tunings", .{
        .root_source_file = b.path("src/provider/gemini_tunings.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Gemini Documents API - document management
    const gemini_documents_module = b.addModule("gemini_documents", .{
        .root_source_file = b.path("src/provider/gemini_documents.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Gemini FileSearchStores API - vector search storage
    const gemini_file_search_stores_module = b.addModule("gemini_file_search_stores", .{
        .root_source_file = b.path("src/provider/gemini_file_search_stores.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Gemini Operations API - async operations management
    const gemini_operations_module = b.addModule("gemini_operations", .{
        .root_source_file = b.path("src/provider/gemini_operations.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // Gemini Tokens API - token counting
    const gemini_tokens_module = b.addModule("gemini_tokens", .{
        .root_source_file = b.path("src/provider/gemini_tokens.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // provider_language_model - depends on all provider submodules
    const provider_language_model_module = b.addModule("provider_language_model", .{
        .root_source_file = b.path("src/provider/language_model.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = provider_types_module },
            .{ .name = "http", .module = http_module },
            .{ .name = "chat", .module = chat_module },
            .{ .name = "openai", .module = provider_openai_module },
            .{ .name = "anthropic", .module = provider_anthropic_module },
            .{ .name = "google", .module = provider_google_module },
        },
    });

    // provider_provider - depends on http, chat, types, registry, language_model
    const provider_provider_module = b.addModule("provider_provider", .{
        .root_source_file = b.path("src/provider/provider.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
            .{ .name = "chat", .module = chat_module },
            .{ .name = "types", .module = provider_types_module },
            .{ .name = "registry", .module = provider_registry_module },
            .{ .name = "language_model", .module = provider_language_model_module },
        },
    });

    // Provider module - re-exports all submodules, maintains backward compatibility
    const provider_module = b.addModule("provider", .{
        .root_source_file = b.path("src/provider/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
            .{ .name = "chat", .module = chat_module },
            .{ .name = "types", .module = provider_types_module },
            .{ .name = "registry", .module = provider_registry_module },
            .{ .name = "openai", .module = provider_openai_module },
            .{ .name = "anthropic", .module = provider_anthropic_module },
            .{ .name = "google", .module = provider_google_module },
            .{ .name = "language_model", .module = provider_language_model_module },
            .{ .name = "provider", .module = provider_provider_module },
            .{ .name = "file", .module = file_module },
            .{ .name = "image", .module = image_module },
            .{ .name = "audio", .module = audio_module },
            .{ .name = "moderation", .module = moderation_module },
            .{ .name = "embedding", .module = embedding_module },
            // Gemini advanced API
            .{ .name = "gemini_caches", .module = gemini_caches_module },
            .{ .name = "gemini_tunings", .module = gemini_tunings_module },
            .{ .name = "gemini_documents", .module = gemini_documents_module },
            .{ .name = "gemini_file_search_stores", .module = gemini_file_search_stores_module },
            .{ .name = "gemini_operations", .module = gemini_operations_module },
            .{ .name = "gemini_tokens", .module = gemini_tokens_module },
        },
    });

    // Main module - depends on all submodules
    const main_module = b.addModule("main", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
            .{ .name = "chat", .module = chat_module },
            .{ .name = "responses", .module = responses_module },
            .{ .name = "tool", .module = tool_module },
            .{ .name = "structured_output", .module = structured_output_module },
            .{ .name = "stream", .module = stream_module },
            .{ .name = "batch", .module = batch_module },
            .{ .name = "azure", .module = azure_module },
            .{ .name = "conversation", .module = conversation_module },
            .{ .name = "webhook", .module = webhook_module },
            .{ .name = "realtime", .module = realtime_module },
            .{ .name = "assistant", .module = assistant_module },
            .{ .name = "embedding", .module = embedding_module },
            .{ .name = "model", .module = model_module },
            .{ .name = "file", .module = file_module },
            .{ .name = "image", .module = image_module },
            .{ .name = "audio", .module = audio_module },
            .{ .name = "moderation", .module = moderation_module },
            .{ .name = "finetune", .module = finetune_module },
            .{ .name = "pagination", .module = pagination_module },
            .{ .name = "completion", .module = completion_module },
            .{ .name = "container", .module = container_module },
            .{ .name = "grader", .module = grader_module },
            .{ .name = "skill", .module = skill_module },
            .{ .name = "betathread", .module = betathread_module },
            .{ .name = "provider", .module = provider_module },
        },
    });

    const exe = b.addExecutable(.{
        .name = "llmlite",
        .root_module = main_module,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the program");
    run_step.dependOn(&run_cmd.step);

    // Kimi test example - independent module, depends on main and chat
    const kimi_module = b.addModule("kimi_test", .{
        .root_source_file = b.path("src/kimi_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "main", .module = main_module },
            .{ .name = "chat", .module = chat_module },
        },
    });

    const kimi_exe = b.addExecutable(.{
        .name = "kimi_test",
        .root_module = kimi_module,
    });

    const kimi_run_cmd = b.addRunArtifact(kimi_exe);
    const kimi_run_step = b.step("kimi-test", "Run Kimi integration test");
    kimi_run_step.dependOn(&kimi_run_cmd.step);

    // Gemma test example - independent module, depends on main and chat module
    const gemma_module = b.addModule("gemma_test", .{
        .root_source_file = b.path("src/gemma_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "main", .module = main_module },
            .{ .name = "http", .module = http_module },
            .{ .name = "chat", .module = chat_module },
        },
    });

    const gemma_exe = b.addExecutable(.{
        .name = "gemma_test",
        .root_module = gemma_module,
    });

    const gemma_run_cmd = b.addRunArtifact(gemma_exe);
    const gemma_run_step = b.step("gemma-test", "Run Gemma integration test");
    gemma_run_step.dependOn(&gemma_run_cmd.step);

    // MiniMax Runner test - independent module, depends on main and all submodules
    const minimax_runner_module = b.addModule("minimax_runner", .{
        .root_source_file = b.path("src/test/minimax_runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "main", .module = main_module },
            .{ .name = "http", .module = http_module },
            .{ .name = "chat", .module = chat_module },
            .{ .name = "embedding", .module = embedding_module },
            .{ .name = "image", .module = image_module },
            .{ .name = "audio", .module = audio_module },
            .{ .name = "file", .module = file_module },
            .{ .name = "moderation", .module = moderation_module },
            .{ .name = "completion", .module = completion_module },
            .{ .name = "provider", .module = provider_module },
            .{ .name = "language_model", .module = provider_language_model_module },
        },
    });

    const minimax_runner_exe = b.addExecutable(.{
        .name = "minimax_runner",
        .root_module = minimax_runner_module,
    });

    const minimax_runner_cmd = b.addRunArtifact(minimax_runner_exe);
    const minimax_runner_step = b.step("minimax-test", "Run MiniMax integration test");
    minimax_runner_step.dependOn(&minimax_runner_cmd.step);

    // OpenAI Runner test - independent module, depends on main and all submodules
    const openai_runner_module = b.addModule("openai_runner", .{
        .root_source_file = b.path("src/test/openai_runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "main", .module = main_module },
            .{ .name = "http", .module = http_module },
            .{ .name = "chat", .module = chat_module },
            .{ .name = "embedding", .module = embedding_module },
            .{ .name = "image", .module = image_module },
            .{ .name = "audio", .module = audio_module },
            .{ .name = "file", .module = file_module },
            .{ .name = "moderation", .module = moderation_module },
            .{ .name = "completion", .module = completion_module },
            .{ .name = "provider", .module = provider_module },
            .{ .name = "language_model", .module = provider_language_model_module },
        },
    });

    const openai_runner_exe = b.addExecutable(.{
        .name = "openai_runner",
        .root_module = openai_runner_module,
    });

    const openai_runner_cmd = b.addRunArtifact(openai_runner_exe);
    const openai_runner_step = b.step("openai-test", "Run OpenAI integration test");
    openai_runner_step.dependOn(&openai_runner_cmd.step);

    // Gemini Advanced APIs test - independent module
    const gemini_advanced_module = b.addModule("gemini_advanced_test", .{
        .root_source_file = b.path("src/test/gemini_advanced_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
            .{ .name = "provider", .module = provider_module },
            .{ .name = "gemini_caches", .module = gemini_caches_module },
            .{ .name = "gemini_tunings", .module = gemini_tunings_module },
            .{ .name = "gemini_documents", .module = gemini_documents_module },
            .{ .name = "gemini_file_search_stores", .module = gemini_file_search_stores_module },
            .{ .name = "gemini_operations", .module = gemini_operations_module },
            .{ .name = "gemini_tokens", .module = gemini_tokens_module },
            .{ .name = "google", .module = provider_google_module },
            .{ .name = "file", .module = file_module },
        },
    });

    const gemini_advanced_exe = b.addTest(.{
        .name = "gemini_advanced_test",
        .root_module = gemini_advanced_module,
    });

    const gemini_advanced_step = b.step("gemini-advanced-test", "Run Gemini advanced APIs test");
    gemini_advanced_step.dependOn(&gemini_advanced_exe.step);

    // Unit test module - uses itself as root, imports required modules
    const test_module = b.addModule("test", .{
        .root_source_file = b.path("src/test/openai_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "client", .module = main_module },
            .{ .name = "chat", .module = chat_module },
            .{ .name = "embedding", .module = embedding_module },
            .{ .name = "model", .module = model_module },
            .{ .name = "file", .module = file_module },
            .{ .name = "image", .module = image_module },
            .{ .name = "audio", .module = audio_module },
            .{ .name = "moderation", .module = moderation_module },
            .{ .name = "finetune", .module = finetune_module },
            .{ .name = "completion", .module = completion_module },
            .{ .name = "pagination", .module = pagination_module },
            .{ .name = "batch", .module = batch_module },
            .{ .name = "responses", .module = responses_module },
        },
    });

    // Unit test - uses separate test_module
    const test_exe = b.addTest(.{
        .name = "openai_test",
        .root_module = test_module,
    });

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&test_exe.step);

    // Chat Only Runner test - tests only Chat Completions
    const chat_runner_module = b.addModule("chat_runner", .{
        .root_source_file = b.path("src/test/chat_only_runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "main", .module = main_module },
            .{ .name = "http", .module = http_module },
            .{ .name = "chat", .module = chat_module },
            .{ .name = "language_model", .module = provider_language_model_module },
        },
    });

    const chat_runner_exe = b.addExecutable(.{
        .name = "chat_runner",
        .root_module = chat_runner_module,
    });

    const chat_runner_cmd = b.addRunArtifact(chat_runner_exe);
    const chat_runner_step = b.step("chat-test", "Run Chat Completions test");
    chat_runner_step.dependOn(&chat_runner_cmd.step);

    // MiniMax Provider Modules - TTS, Video, Image, Music
    const minimax_tts_module = b.addModule("minimax_tts", .{
        .root_source_file = b.path("src/provider/minimax/tts.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    const minimax_video_module = b.addModule("minimax_video", .{
        .root_source_file = b.path("src/provider/minimax/video.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    const minimax_image_module = b.addModule("minimax_image", .{
        .root_source_file = b.path("src/provider/minimax/image.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    const minimax_music_module = b.addModule("minimax_music", .{
        .root_source_file = b.path("src/provider/minimax/music.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
        },
    });

    // MiniMax Native API Test - tests TTS, Video, Image, Music APIs
    const minimax_native_module = b.addModule("minimax_native_test", .{
        .root_source_file = b.path("src/test/minimax_native_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
            .{ .name = "minimax/tts", .module = minimax_tts_module },
            .{ .name = "minimax/video", .module = minimax_video_module },
            .{ .name = "minimax/image", .module = minimax_image_module },
            .{ .name = "minimax/music", .module = minimax_music_module },
        },
    });

    const minimax_native_exe = b.addExecutable(.{
        .name = "minimax_native_test",
        .root_module = minimax_native_module,
    });

    const minimax_native_cmd = b.addRunArtifact(minimax_native_exe);
    const minimax_native_step = b.step("minimax-native-test", "Run MiniMax Native APIs test");
    minimax_native_step.dependOn(&minimax_native_cmd.step);
}
