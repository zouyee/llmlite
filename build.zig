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

    // Version module
    const version_module = b.addModule("version", .{
        .root_source_file = b.path("src/version.zig"),
        .target = target,
        .optimize = optimize,
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
            .{ .name = "version", .module = version_module },
        },
    });

    const exe = b.addExecutable(.{
        .name = "llmlite",
        .root_module = main_module,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
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

    // Virtual Key module (must be declared before proxy_module)
    const virtual_key_module = b.addModule("virtual_key", .{
        .root_source_file = b.path("src/proxy/virtual_key.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Proxy Rate Limit module
    const proxy_rate_limit_module = b.addModule("proxy_rate_limit", .{
        .root_source_file = b.path("src/proxy/rate_limit.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Proxy Logger module
    const proxy_logger_module = b.addModule("proxy_logger", .{
        .root_source_file = b.path("src/proxy/logger.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Proxy Config module
    const proxy_config_module = b.addModule("proxy_config", .{
        .root_source_file = b.path("src/proxy/config.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = provider_types_module },
        },
    });

    // Proxy Middleware module
    const proxy_middleware_module = b.addModule("proxy_middleware", .{
        .root_source_file = b.path("src/proxy/middleware.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "virtual_key", .module = virtual_key_module },
            .{ .name = "proxy_rate_limit", .module = proxy_rate_limit_module },
        },
    });

    // Proxy Error Handler module
    const proxy_error_handler_module = b.addModule("proxy_error_handler", .{
        .root_source_file = b.path("src/proxy/error_handler.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Proxy Connection Pool module - HTTP connection reuse for edge routing
    const proxy_connection_pool_module = b.addModule("proxy_connection_pool", .{
        .root_source_file = b.path("src/proxy/connection_pool.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "http", .module = http_module },
            .{ .name = "types", .module = provider_types_module },
            .{ .name = "registry", .module = provider_registry_module },
        },
    });

    // Proxy Latency Health module - Latency tracking and health checking
    const proxy_latency_health_module = b.addModule("proxy_latency_health", .{
        .root_source_file = b.path("src/proxy/latency_health.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = provider_types_module },
        },
    });

    // Proxy Hot Reload module - Config file watching for edge scenarios
    const proxy_hot_reload_module = b.addModule("proxy_hot_reload", .{
        .root_source_file = b.path("src/proxy/hot_reload.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Proxy Circuit Breaker module - Circuit breaker pattern for edge routing
    const proxy_circuit_breaker_module = b.addModule("proxy_circuit_breaker", .{
        .root_source_file = b.path("src/proxy/circuit_breaker.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = provider_types_module },
        },
    });

    // Proxy Active Health Checker module - Active health probing for edge routing
    const proxy_active_health_module = b.addModule("proxy_active_health", .{
        .root_source_file = b.path("src/proxy/active_health.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = provider_types_module },
        },
    });

    // Proxy Analytics Types module - Shared types for tracking, gain stats, sessions
    const proxy_analytics_types_module = b.addModule("proxy_analytics_types", .{
        .root_source_file = b.path("src/proxy/analytics/types.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Proxy Analytics Tracking module - Tracking store and handler
    const proxy_analytics_tracking_module = b.addModule("proxy_analytics_tracking", .{
        .root_source_file = b.path("src/proxy/analytics/tracking.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "types", .module = proxy_analytics_types_module },
        },
    });

    // ============================================================================
    // llmlite-cmd modules - CLI Tool for LLM Token Optimization
    // ============================================================================

    // cmd_core submodules - each file becomes a module
    // Note: Modules are ordered so dependencies come before dependents
    const cmd_core_filter_module = b.addModule("filter", .{
        .root_source_file = b.path("src/cmd/core/filter.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_tracking_module = b.addModule("tracking", .{
        .root_source_file = b.path("src/cmd/core/tracking.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_lexer_module = b.addModule("lexer", .{
        .root_source_file = b.path("src/cmd/core/lexer.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_tee_module = b.addModule("tee", .{
        .root_source_file = b.path("src/cmd/core/tee.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_runner_module = b.addModule("runner", .{
        .root_source_file = b.path("src/cmd/core/runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "filter", .module = cmd_core_filter_module },
            .{ .name = "tracking", .module = cmd_core_tracking_module },
            .{ .name = "tee", .module = cmd_core_tee_module },
        },
    });
    const cmd_core_utils_module = b.addModule("utils", .{
        .root_source_file = b.path("src/cmd/core/utils.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_gain_module = b.addModule("gain", .{
        .root_source_file = b.path("src/cmd/core/gain.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_rules_module = b.addModule("rules", .{
        .root_source_file = b.path("src/cmd/core/rules.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_hook_module = b.addModule("hook", .{
        .root_source_file = b.path("src/cmd/core/hook.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "rules", .module = cmd_core_rules_module },
        },
    });
    const cmd_core_discover_module = b.addModule("discover", .{
        .root_source_file = b.path("src/cmd/core/discover.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "rules", .module = cmd_core_rules_module },
            .{ .name = "lexer", .module = cmd_core_lexer_module },
            .{ .name = "tracking", .module = cmd_core_tracking_module },
        },
    });
    const cmd_core_session_module = b.addModule("session", .{
        .root_source_file = b.path("src/cmd/core/session.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "rules", .module = cmd_core_rules_module },
            .{ .name = "lexer", .module = cmd_core_lexer_module },
        },
    });
    const cmd_core_config_module = b.addModule("config", .{
        .root_source_file = b.path("src/cmd/core/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_audit_module = b.addModule("audit", .{
        .root_source_file = b.path("src/cmd/core/audit.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_integrity_module = b.addModule("integrity", .{
        .root_source_file = b.path("src/cmd/core/integrity.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_learn_module = b.addModule("learn", .{
        .root_source_file = b.path("src/cmd/core/learn.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_cc_economics_module = b.addModule("cc_economics", .{
        .root_source_file = b.path("src/cmd/core/cc_economics.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_trust_module = b.addModule("trust", .{
        .root_source_file = b.path("src/cmd/core/trust.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_pytest_module = b.addModule("pytest", .{
        .root_source_file = b.path("src/cmd/core/pytest.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_cargo_module = b.addModule("cargo", .{
        .root_source_file = b.path("src/cmd/core/cargo.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_go_test_module = b.addModule("go_test", .{
        .root_source_file = b.path("src/cmd/core/go_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_java_module = b.addModule("java", .{
        .root_source_file = b.path("src/cmd/core/java.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_json_module = b.addModule("json", .{
        .root_source_file = b.path("src/cmd/core/json.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_ruff_module = b.addModule("ruff", .{
        .root_source_file = b.path("src/cmd/core/ruff.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_npm_module = b.addModule("npm", .{
        .root_source_file = b.path("src/cmd/core/npm.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_pnpm_module = b.addModule("pnpm", .{
        .root_source_file = b.path("src/cmd/core/pnpm.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_tsc_module = b.addModule("tsc", .{
        .root_source_file = b.path("src/cmd/core/tsc.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_golangci_lint_module = b.addModule("golangci_lint", .{
        .root_source_file = b.path("src/cmd/core/golangci_lint.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_vitest_module = b.addModule("vitest", .{
        .root_source_file = b.path("src/cmd/core/vitest.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_docker_module = b.addModule("docker", .{
        .root_source_file = b.path("src/cmd/core/docker.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_kubectl_module = b.addModule("kubectl", .{
        .root_source_file = b.path("src/cmd/core/kubectl.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_prettier_module = b.addModule("prettier", .{
        .root_source_file = b.path("src/cmd/core/prettier.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_mypy_module = b.addModule("mypy", .{
        .root_source_file = b.path("src/cmd/core/mypy.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_pip_module = b.addModule("pip", .{
        .root_source_file = b.path("src/cmd/core/pip.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_rspec_module = b.addModule("rspec", .{
        .root_source_file = b.path("src/cmd/core/rspec.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_rake_module = b.addModule("rake", .{
        .root_source_file = b.path("src/cmd/core/rake.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_rubocop_module = b.addModule("rubocop", .{
        .root_source_file = b.path("src/cmd/core/rubocop.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_dotnet_module = b.addModule("dotnet", .{
        .root_source_file = b.path("src/cmd/core/dotnet.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_playwright_module = b.addModule("playwright", .{
        .root_source_file = b.path("src/cmd/core/playwright.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_prisma_module = b.addModule("prisma", .{
        .root_source_file = b.path("src/cmd/core/prisma.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_nextjs_module = b.addModule("nextjs", .{
        .root_source_file = b.path("src/cmd/core/nextjs.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_eslint_module = b.addModule("eslint", .{
        .root_source_file = b.path("src/cmd/core/eslint.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_aws_module = b.addModule("aws", .{
        .root_source_file = b.path("src/cmd/core/aws.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_curl_module = b.addModule("curl", .{
        .root_source_file = b.path("src/cmd/core/curl.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_sync_module = b.addModule("sync", .{
        .root_source_file = b.path("src/cmd/core/sync.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_key_module = b.addModule("key", .{
        .root_source_file = b.path("src/cmd/core/key.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_ccusage_module = b.addModule("ccusage", .{
        .root_source_file = b.path("src/cmd/core/ccusage.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cmd_core_toml_filter_module = b.addModule("toml_filter", .{
        .root_source_file = b.path("src/cmd/core/toml_filter.zig"),
        .target = target,
        .optimize = optimize,
    });

    // cmd_core module - Core infrastructure for llmlite-cmd
    const cmd_core_module = b.addModule("cmd_core", .{
        .root_source_file = b.path("src/cmd/core/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "runner", .module = cmd_core_runner_module },
            .{ .name = "filter", .module = cmd_core_filter_module },
            .{ .name = "tracking", .module = cmd_core_tracking_module },
            .{ .name = "tee", .module = cmd_core_tee_module },
            .{ .name = "utils", .module = cmd_core_utils_module },
            .{ .name = "gain", .module = cmd_core_gain_module },
            .{ .name = "hook", .module = cmd_core_hook_module },
            .{ .name = "discover", .module = cmd_core_discover_module },
            .{ .name = "session", .module = cmd_core_session_module },
            .{ .name = "config", .module = cmd_core_config_module },
            .{ .name = "audit", .module = cmd_core_audit_module },
            .{ .name = "integrity", .module = cmd_core_integrity_module },
            .{ .name = "learn", .module = cmd_core_learn_module },
            .{ .name = "cc_economics", .module = cmd_core_cc_economics_module },
            .{ .name = "trust", .module = cmd_core_trust_module },
            .{ .name = "rules", .module = cmd_core_rules_module },
            .{ .name = "lexer", .module = cmd_core_lexer_module },
            .{ .name = "pytest", .module = cmd_core_pytest_module },
            .{ .name = "cargo", .module = cmd_core_cargo_module },
            .{ .name = "go_test", .module = cmd_core_go_test_module },
            .{ .name = "java", .module = cmd_core_java_module },
            .{ .name = "json", .module = cmd_core_json_module },
            .{ .name = "ruff", .module = cmd_core_ruff_module },
            .{ .name = "npm", .module = cmd_core_npm_module },
            .{ .name = "pnpm", .module = cmd_core_pnpm_module },
            .{ .name = "tsc", .module = cmd_core_tsc_module },
            .{ .name = "golangci_lint", .module = cmd_core_golangci_lint_module },
            .{ .name = "vitest", .module = cmd_core_vitest_module },
            .{ .name = "docker", .module = cmd_core_docker_module },
            .{ .name = "kubectl", .module = cmd_core_kubectl_module },
            .{ .name = "prettier", .module = cmd_core_prettier_module },
            .{ .name = "mypy", .module = cmd_core_mypy_module },
            .{ .name = "pip", .module = cmd_core_pip_module },
            .{ .name = "rspec", .module = cmd_core_rspec_module },
            .{ .name = "rake", .module = cmd_core_rake_module },
            .{ .name = "rubocop", .module = cmd_core_rubocop_module },
            .{ .name = "dotnet", .module = cmd_core_dotnet_module },
            .{ .name = "playwright", .module = cmd_core_playwright_module },
            .{ .name = "prisma", .module = cmd_core_prisma_module },
            .{ .name = "nextjs", .module = cmd_core_nextjs_module },
            .{ .name = "eslint", .module = cmd_core_eslint_module },
            .{ .name = "aws", .module = cmd_core_aws_module },
            .{ .name = "curl", .module = cmd_core_curl_module },
            .{ .name = "sync", .module = cmd_core_sync_module },
            .{ .name = "key", .module = cmd_core_key_module },
            .{ .name = "ccusage", .module = cmd_core_ccusage_module },
            .{ .name = "toml_filter", .module = cmd_core_toml_filter_module },
        },
    });

    // cmd module - Command dispatcher
    const cmd_module = b.addModule("cmd", .{
        .root_source_file = b.path("src/cmd/cmd.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "cmd_core", .module = cmd_core_module },
        },
    });

    // cmd_main module - CLI entry point
    const cmd_main_module = b.addModule("cmd_main", .{
        .root_source_file = b.path("src/cmd/cmd_main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "cmd", .module = cmd_module },
            .{ .name = "cmd_core", .module = cmd_core_module },
        },
    });

    // llmlite-cmd executable
    const cmd_exe = b.addExecutable(.{
        .name = "llmlite-cmd",
        .root_module = cmd_main_module,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });

    b.installArtifact(cmd_exe);

    const cmd_run_cmd = b.addRunArtifact(cmd_exe);
    const cmd_run_step = b.step("cmd", "Run llmlite-cmd");
    cmd_run_step.dependOn(&cmd_run_cmd.step);

    // Proxy Server module
    const proxy_module = b.addModule("proxy", .{
        .root_source_file = b.path("src/proxy/server.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "virtual_key", .module = virtual_key_module },
            .{ .name = "proxy_rate_limit", .module = proxy_rate_limit_module },
            .{ .name = "proxy_logger", .module = proxy_logger_module },
            .{ .name = "proxy_config", .module = proxy_config_module },
            .{ .name = "proxy_middleware", .module = proxy_middleware_module },
            .{ .name = "error_handler", .module = proxy_error_handler_module },
            .{ .name = "connection_pool", .module = proxy_connection_pool_module },
            .{ .name = "latency_health", .module = proxy_latency_health_module },
            .{ .name = "hot_reload", .module = proxy_hot_reload_module },
            .{ .name = "circuit_breaker", .module = proxy_circuit_breaker_module },
            .{ .name = "active_health", .module = proxy_active_health_module },
            .{ .name = "analytics", .module = proxy_analytics_tracking_module },
            .{ .name = "types", .module = provider_types_module },
            .{ .name = "registry", .module = provider_registry_module },
            .{ .name = "http", .module = http_module },
            .{ .name = "chat", .module = chat_module },
            .{ .name = "stream", .module = stream_module },
        },
    });

    // Proxy server executable
    const proxy_main_module = b.addModule("proxy_main", .{
        .root_source_file = b.path("src/proxy_main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "proxy", .module = proxy_module },
            .{ .name = "virtual_key", .module = virtual_key_module },
            .{ .name = "proxy_rate_limit", .module = proxy_rate_limit_module },
            .{ .name = "proxy_logger", .module = proxy_logger_module },
            .{ .name = "connection_pool", .module = proxy_connection_pool_module },
            .{ .name = "latency_health", .module = proxy_latency_health_module },
            .{ .name = "hot_reload", .module = proxy_hot_reload_module },
            .{ .name = "circuit_breaker", .module = proxy_circuit_breaker_module },
            .{ .name = "active_health", .module = proxy_active_health_module },
        },
    });

    const proxy_exe = b.addExecutable(.{
        .name = "llmlite-proxy",
        .root_module = proxy_main_module,
        .version = .{ .major = 0, .minor = 2, .patch = 0 },
    });

    b.installArtifact(proxy_exe);

    const proxy_run_cmd = b.addRunArtifact(proxy_exe);
    const proxy_run_step = b.step("proxy", "Run the proxy server");
    proxy_run_step.dependOn(&proxy_run_cmd.step);

    // Proxy Test module - runs all proxy component inline tests
    const proxy_test_module = b.addModule("proxy_test_runner", .{
        .root_source_file = b.path("src/test/proxy_test_runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "proxy_error_handler", .module = proxy_error_handler_module },
            .{ .name = "proxy_rate_limit", .module = proxy_rate_limit_module },
            .{ .name = "virtual_key", .module = virtual_key_module },
            .{ .name = "connection_pool", .module = proxy_connection_pool_module },
            .{ .name = "latency_health", .module = proxy_latency_health_module },
            .{ .name = "hot_reload", .module = proxy_hot_reload_module },
            .{ .name = "circuit_breaker", .module = proxy_circuit_breaker_module },
            .{ .name = "active_health", .module = proxy_active_health_module },
            .{ .name = "types", .module = provider_types_module },
        },
    });

    const proxy_test_exe = b.addTest(.{
        .name = "proxy_test",
        .root_module = proxy_test_module,
    });

    const proxy_test_step = b.step("proxy-test", "Run proxy component tests");
    proxy_test_step.dependOn(&proxy_test_exe.step);

    // Tracking and Analytics test module
    const tracking_test_module = b.addModule("tracking_test", .{
        .root_source_file = b.path("src/test/tracking_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "proxy_analytics_types", .module = proxy_analytics_types_module },
        },
    });

    const tracking_test_exe = b.addTest(.{
        .name = "tracking_test",
        .root_module = tracking_test_module,
    });

    const tracking_test_step = b.step("tracking-test", "Run tracking and analytics tests");
    tracking_test_step.dependOn(&tracking_test_exe.step);
}
