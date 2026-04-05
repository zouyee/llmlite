//! Gemini Advanced APIs Tests
//!
//! Tests for Google Gemini advanced APIs:
//! - Caches API (context caching)
//! - Tunings API (model tuning)
//! - Documents API (document management)
//! - FileSearchStores API (vector search)
//! - Native Gemini APIs (Chat, Batch, Live)

const std = @import("std");
const testing = std.testing;

// Import modules by name (defined in build.zig)
const gemini_caches = @import("gemini_caches");
const gemini_tunings = @import("gemini_tunings");
const gemini_documents = @import("gemini_documents");
const gemini_file_search_stores = @import("gemini_file_search_stores");
const google = @import("google");
const file = @import("file");
const gemini_tokens = @import("gemini_tokens");

// ============================================================================
// Caches API Tests
// ============================================================================

test "CachedContent struct initialization" {
    const allocator = testing.allocator;

    const content = gemini_caches.CachedContent{
        .name = try allocator.dupe(u8, "cachedContents/test"),
        .model = try allocator.dupe(u8, "gemini-1.5-flash"),
        .display_name = try allocator.dupe(u8, "test-cache"),
        .size_bytes = 1024,
        .create_time = try allocator.dupe(u8, "2024-01-01T00:00:00Z"),
        .update_time = try allocator.dupe(u8, "2024-01-01T00:00:00Z"),
        .expire_time = try allocator.dupe(u8, "2024-01-02T00:00:00Z"),
        .ttl = try allocator.dupe(u8, "3600s"),
        .usage_metadata = .{
            .prompt_token_count = 100,
            .total_token_count = 150,
        },
    };
    defer {
        allocator.free(content.name);
        allocator.free(content.model);
        allocator.free(content.display_name.?);
        allocator.free(content.create_time.?);
        allocator.free(content.update_time.?);
        allocator.free(content.expire_time.?);
        allocator.free(content.ttl.?);
    }

    try testing.expectEqualStrings("cachedContents/test", content.name);
    try testing.expectEqualStrings("gemini-1.5-flash", content.model);
    try testing.expectEqual(@as(i64, 1024), content.size_bytes);
    try testing.expect(content.usage_metadata != null);
    try testing.expectEqual(@as(u32, 100), content.usage_metadata.?.prompt_token_count);
}

test "Content and Part structures" {
    const allocator = testing.allocator;

    // Test text part
    const text_part = gemini_caches.Part{ .text = try allocator.dupe(u8, "Hello") };
    defer allocator.free(text_part.text);

    // Test file_data part
    const file_part = gemini_caches.Part{ .file_data = .{
        .mime_type = try allocator.dupe(u8, "text/plain"),
        .file_uri = try allocator.dupe(u8, "gs://bucket/file.txt"),
    } };
    defer {
        allocator.free(file_part.file_data.mime_type);
        allocator.free(file_part.file_data.file_uri);
    }

    try testing.expectEqualStrings("Hello", text_part.text);
    try testing.expectEqualStrings("text/plain", file_part.file_data.mime_type);
}

test "CreateCachedContentParams struct" {
    const params = gemini_caches.CreateCachedContentParams{
        .model = "gemini-1.5-flash",
        .contents = &[_]gemini_caches.Content{},
        .display_name = "my-cache",
        .ttl = "3600s",
        .expires_after_seconds = 3600,
    };

    try testing.expectEqualStrings("gemini-1.5-flash", params.model);
    try testing.expectEqualStrings("my-cache", params.display_name.?);
    try testing.expectEqualStrings("3600s", params.ttl.?);
    try testing.expectEqual(@as(i64, 3600), params.expires_after_seconds.?);
}

test "CachedContent endpoint helpers" {
    try testing.expectEqualStrings("/cachedContents", gemini_caches.getCachedContentsListEndpoint);
}

// ============================================================================
// Tunings API Tests
// ============================================================================

test "TuningTask struct initialization" {
    const allocator = testing.allocator;

    const task = gemini_tunings.TuningTask{
        .name = try allocator.dupe(u8, "tunedModels/test-model"),
        .base_model = try allocator.dupe(u8, "gemini-1.5-flash"),
        .display_name = try allocator.dupe(u8, "my-tuned-model"),
        .description = try allocator.dupe(u8, "A tuned model"),
        .state = .active,
        .create_time = try allocator.dupe(u8, "2024-01-01T00:00:00Z"),
        .update_time = try allocator.dupe(u8, "2024-01-01T00:00:00Z"),
        .error_message = null,
    };
    defer {
        allocator.free(task.name);
        allocator.free(task.base_model);
        allocator.free(task.display_name.?);
        allocator.free(task.description.?);
        allocator.free(task.create_time.?);
        allocator.free(task.update_time.?);
    }

    try testing.expectEqualStrings("tunedModels/test-model", task.name);
    try testing.expectEqualStrings("gemini-1.5-flash", task.base_model);
    try testing.expectEqual(gemini_tunings.TuningState.active, task.state);
}

test "TuningState enum toString" {
    try testing.expectEqualStrings("STATE_UNSPECIFIED", gemini_tunings.TuningState.unspecified.toString());
    try testing.expectEqualStrings("CREATING", gemini_tunings.TuningState.creating.toString());
    try testing.expectEqualStrings("ACTIVE", gemini_tunings.TuningState.active.toString());
    try testing.expectEqualStrings("FAILED", gemini_tunings.TuningState.failed.toString());
    try testing.expectEqualStrings("DELETING", gemini_tunings.TuningState.deleting.toString());
    try testing.expectEqualStrings("PAUSED", gemini_tunings.TuningState.paused.toString());
}

test "CreateTuningParams struct" {
    const params = gemini_tunings.CreateTuningParams{
        .base_model = "gemini-1.5-flash",
        .training_data_uri = "gs://bucket/training_data.jsonl",
        .training_examples_count = 100,
        .display_name = "my-tuned-model",
        .description = "A tuned model for testing",
        .epoch_count = 10,
        .batch_size = 4,
        .learning_rate = 0.03,
    };

    try testing.expectEqualStrings("gemini-1.5-flash", params.base_model);
    try testing.expectEqualStrings("gs://bucket/training_data.jsonl", params.training_data_uri);
    try testing.expectEqual(@as(i32, 100), params.training_examples_count);
    try testing.expectEqual(@as(i32, 10), params.epoch_count.?);
    try testing.expectEqual(@as(f32, 0.03), params.learning_rate.?);
}

test "TunedModels endpoint helpers" {
    try testing.expectEqualStrings("/tunedModels", gemini_tunings.getTunedModelsListEndpoint);
}

test "TuningTask with error state" {
    const allocator = testing.allocator;

    const task = gemini_tunings.TuningTask{
        .name = try allocator.dupe(u8, "tunedModels/failed-model"),
        .base_model = try allocator.dupe(u8, "gemini-1.5-flash"),
        .display_name = try allocator.dupe(u8, "failed-tuned-model"),
        .description = try allocator.dupe(u8, "A failed tuning task"),
        .state = .failed,
        .create_time = try allocator.dupe(u8, "2024-01-01T00:00:00Z"),
        .update_time = try allocator.dupe(u8, "2024-01-01T00:05:00Z"),
        .error_message = try allocator.dupe(u8, "Training failed due to insufficient data"),
    };
    defer {
        allocator.free(task.name);
        allocator.free(task.base_model);
        allocator.free(task.display_name.?);
        allocator.free(task.description.?);
        allocator.free(task.create_time.?);
        allocator.free(task.update_time.?);
        allocator.free(task.error_message.?);
    }

    try testing.expectEqual(gemini_tunings.TuningState.failed, task.state);
    try testing.expect(task.error_message != null);
    try testing.expectEqualStrings("Training failed due to insufficient data", task.error_message.?);
}

// ============================================================================
// Documents API Tests
// ============================================================================

test "Document struct initialization" {
    const allocator = testing.allocator;

    const doc = gemini_documents.Document{
        .name = try allocator.dupe(u8, "documents/test-doc"),
        .display_name = try allocator.dupe(u8, "test-document.pdf"),
        .mime_type = try allocator.dupe(u8, "application/pdf"),
        .size_bytes = 2048,
        .create_time = try allocator.dupe(u8, "2024-01-01T00:00:00Z"),
        .update_time = try allocator.dupe(u8, "2024-01-01T00:00:00Z"),
        .expire_time = null,
        .chunks_info = try allocator.dupe(u8, "{\"chunkCount\":10}"),
    };
    defer {
        allocator.free(doc.name);
        allocator.free(doc.display_name.?);
        allocator.free(doc.mime_type.?);
        allocator.free(doc.create_time.?);
        allocator.free(doc.update_time.?);
        allocator.free(doc.chunks_info.?);
    }

    try testing.expectEqualStrings("documents/test-doc", doc.name);
    try testing.expectEqualStrings("test-document.pdf", doc.display_name.?);
    try testing.expectEqual(@as(i64, 2048), doc.size_bytes);
}

test "ListDocumentsParams struct" {
    const params = gemini_documents.ListDocumentsParams{
        .page_size = 10,
        .page_token = "next-page-token",
    };

    try testing.expectEqual(@as(i32, 10), params.page_size.?);
    try testing.expectEqualStrings("next-page-token", params.page_token.?);
}

// ============================================================================
// FileSearchStores API Tests
// ============================================================================

test "FileSearchStore struct initialization" {
    const allocator = testing.allocator;

    const store = gemini_file_search_stores.FileSearchStore{
        .name = try allocator.dupe(u8, "filesearchStores/test-store"),
        .display_name = try allocator.dupe(u8, "test-vector-store"),
        .embedding_model = try allocator.dupe(u8, "text-embedding-004"),
        .description = try allocator.dupe(u8, "A vector search store"),
        .state = .active,
        .create_time = try allocator.dupe(u8, "2024-01-01T00:00:00Z"),
        .update_time = try allocator.dupe(u8, "2024-01-01T00:00:00Z"),
        .vector_count = 1000,
        .dimensions = 768,
    };
    defer {
        allocator.free(store.name);
        allocator.free(store.display_name);
        allocator.free(store.embedding_model);
        allocator.free(store.description.?);
        allocator.free(store.create_time.?);
        allocator.free(store.update_time.?);
    }

    try testing.expectEqualStrings("filesearchStores/test-store", store.name);
    try testing.expectEqual(gemini_file_search_stores.FileSearchStoreState.active, store.state);
    try testing.expectEqual(@as(i64, 1000), store.vector_count);
    try testing.expectEqual(@as(i32, 768), store.dimensions);
}

test "FileSearchStoreState enum toString" {
    try testing.expectEqualStrings("STATE_UNSPECIFIED", gemini_file_search_stores.FileSearchStoreState.unspecified.toString());
    try testing.expectEqualStrings("CREATING", gemini_file_search_stores.FileSearchStoreState.creating.toString());
    try testing.expectEqualStrings("ACTIVE", gemini_file_search_stores.FileSearchStoreState.active.toString());
    try testing.expectEqualStrings("FAILED", gemini_file_search_stores.FileSearchStoreState.failed.toString());
    try testing.expectEqualStrings("DELETING", gemini_file_search_stores.FileSearchStoreState.deleting.toString());
    try testing.expectEqualStrings("UPDATING", gemini_file_search_stores.FileSearchStoreState.updating.toString());
}

test "CreateFileSearchStoreParams struct" {
    var labels = std.StringHashMap([]const u8).init(testing.allocator);
    defer labels.deinit();
    try labels.put("environment", "test");
    try labels.put("version", "1.0");

    const params = gemini_file_search_stores.CreateFileSearchStoreParams{
        .display_name = "my-vector-store",
        .embedding_model = "text-embedding-004",
        .description = "A test vector store",
        .labels = labels,
    };

    try testing.expectEqualStrings("my-vector-store", params.display_name);
    try testing.expectEqualStrings("text-embedding-004", params.embedding_model);
    try testing.expect(params.labels != null);
    try testing.expectEqualStrings("test", params.labels.?.get("environment").?);
}

test "UploadFilesParams and ImportFilesParams structs" {
    const upload_params = gemini_file_search_stores.UploadFilesParams{
        .files = &.{
            "gs://bucket/file1.txt",
            "gs://bucket/file2.txt",
        },
    };
    try testing.expectEqual(@as(usize, 2), upload_params.files.len);

    const import_params = gemini_file_search_stores.ImportFilesParams{
        .gcs_uris = &.{"gs://bucket/files/*.txt"},
        .mime_type = "text/plain",
    };
    try testing.expectEqual(@as(usize, 1), import_params.gcs_uris.len);
    try testing.expectEqualStrings("text/plain", import_params.mime_type);
}

// ============================================================================
// Native Gemini APIs Tests (from google.zig)
// ============================================================================

test "GeminiChat struct initialization" {
    const allocator = testing.allocator;

    const chat = google.GeminiChat{
        .name = try allocator.dupe(u8, "chats/test-chat"),
        .model = try allocator.dupe(u8, "gemini-2.0-flash"),
        .history = &[_]google.Content{},
    };
    defer {
        allocator.free(chat.name);
        allocator.free(chat.model);
    }

    try testing.expectEqualStrings("chats/test-chat", chat.name);
    try testing.expectEqualStrings("gemini-2.0-flash", chat.model);
    try testing.expectEqual(@as(usize, 0), chat.history.len);
}

test "GenerateContentConfig struct" {
    const config = google.GenerateContentConfig{
        .temperature = 0.7,
        .max_output_tokens = 1000,
        .top_p = 0.9,
        .top_k = 40,
    };

    try testing.expectEqual(@as(f32, 0.7), config.temperature.?);
    try testing.expectEqual(@as(i32, 1000), config.max_output_tokens.?);
    try testing.expectEqual(@as(f32, 0.9), config.top_p.?);
    try testing.expectEqual(@as(i32, 40), config.top_k.?);
}

test "ChatResponse struct" {
    const allocator = testing.allocator;

    const response = google.ChatResponse{
        .text = try allocator.dupe(u8, "Hello! How can I help you?"),
        .done = true,
    };
    defer allocator.free(response.text);

    try testing.expectEqualStrings("Hello! How can I help you?", response.text);
    try testing.expect(response.done);
}

test "BatchJobSource union - inlined_requests" {
    const inlined = google.BatchJobSource{ .inlined_requests = &[_]google.InlinedRequest{} };

    switch (inlined) {
        .inlined_requests => |reqs| {
            try testing.expectEqual(@as(usize, 0), reqs.len);
        },
        else => unreachable,
    }
}

test "BatchJobSource union - gcs_uri" {
    const gcs = google.BatchJobSource{ .gcs_uri = &[_][]const u8{"gs://bucket/requests.jsonl"} };

    switch (gcs) {
        .gcs_uri => |uris| {
            try testing.expectEqual(@as(usize, 1), uris.len);
            try testing.expectEqualStrings("gs://bucket/requests.jsonl", uris[0]);
        },
        else => unreachable,
    }
}

test "BatchJobState enum toString" {
    try testing.expectEqualStrings("JOB_STATE_UNSPECIFIED", google.BatchJobState.unspecified.toString());
    try testing.expectEqualStrings("QUEUING", google.BatchJobState.queuing.toString());
    try testing.expectEqualStrings("PREPARING", google.BatchJobState.preparing.toString());
    try testing.expectEqualStrings("RUNNING", google.BatchJobState.running.toString());
    try testing.expectEqualStrings("SUCCEEDED", google.BatchJobState.succeeded.toString());
    try testing.expectEqualStrings("FAILED", google.BatchJobState.failed.toString());
    try testing.expectEqualStrings("CANCELLED", google.BatchJobState.cancelled.toString());
    try testing.expectEqualStrings("CANCELLING", google.BatchJobState.cancelling.toString());
}

test "BatchJob struct" {
    const allocator = testing.allocator;

    const job = google.BatchJob{
        .name = try allocator.dupe(u8, "batchJobs/test-job"),
        .state = .running,
        .display_name = try allocator.dupe(u8, "test-batch-job"),
        .create_time = try allocator.dupe(u8, "2024-01-01T00:00:00Z"),
        .update_time = try allocator.dupe(u8, "2024-01-01T00:01:00Z"),
        .completed_time = null,
    };
    defer {
        allocator.free(job.name);
        allocator.free(job.display_name.?);
        allocator.free(job.create_time.?);
        allocator.free(job.update_time.?);
    }

    try testing.expectEqualStrings("batchJobs/test-job", job.name);
    try testing.expectEqual(google.BatchJobState.running, job.state);
}

test "GeminiLiveClient initialization" {
    const allocator = testing.allocator;

    var client = google.GeminiLiveClient.init(allocator, "gemini-2.0-flash", "test-api-key");
    defer client.deinit();

    try testing.expectEqualStrings("gemini-2.0-flash", client.model);
    try testing.expectEqualStrings("test-api-key", client.api_key);
    try testing.expect(!client.connected);
}

test "LiveConfig struct" {
    const config = google.LiveConfig{
        .modalities = &.{ "text", "audio" },
        .voice = "Kore",
        .temperature = 0.5,
    };

    try testing.expectEqual(@as(usize, 2), config.modalities.len);
    try testing.expectEqualStrings("Kore", config.voice.?);
    try testing.expectEqual(@as(f32, 0.5), config.temperature.?);
}

test "LiveMessage union" {
    const text_msg = google.LiveMessage{ .text = .{
        .text = "Hello",
    } };

    switch (text_msg) {
        .text => |msg| {
            try testing.expectEqualStrings("Hello", msg.text);
        },
        else => unreachable,
    }

    const audio_msg = google.LiveMessage{ .audio = .{
        .data = "base64-audio-data",
        .mime_type = "audio/pcm",
    } };

    switch (audio_msg) {
        .audio => |msg| {
            try testing.expectEqualStrings("base64-audio-data", msg.data);
            try testing.expectEqualStrings("audio/pcm", msg.mime_type);
        },
        else => unreachable,
    }
}

test "TextMessage and AudioMessage structs" {
    const text = google.TextMessage{ .text = "Hello" };
    try testing.expectEqualStrings("Hello", text.text);

    const audio = google.AudioMessage{
        .data = "audio-data",
        .mime_type = "audio/pcm",
    };
    try testing.expectEqualStrings("audio-data", audio.data);
    try testing.expectEqualStrings("audio/pcm", audio.mime_type);
}

// ============================================================================
// Operations API Tests (from gemini_operations.zig)
// ============================================================================

test "Operation struct initialization" {
    const allocator = testing.allocator;

    const op = gemini_operations.Operation{
        .name = try allocator.dupe(u8, "operations/test-op"),
        .done = false,
        .metadata = try allocator.dupe(u8, "{\"progress\":50}"),
        .err = null,
        .result = null,
    };
    defer {
        allocator.free(op.name);
        allocator.free(op.metadata.?);
    }

    try testing.expectEqualStrings("operations/test-op", op.name);
    try testing.expect(!op.done);
    try testing.expectEqualStrings("{\"progress\":50}", op.metadata.?);
}

test "OperationError struct" {
    const err = gemini_operations.OperationError{
        .code = 13,
        .message = "Internal error",
    };

    try testing.expectEqual(@as(i32, 13), err.code);
    try testing.expectEqualStrings("Internal error", err.message);
}

test "ListOperationsParams struct" {
    const params = gemini_operations.ListOperationsParams{
        .filter = "done:true",
        .page_size = 10,
        .page_token = "next-token",
    };

    try testing.expectEqualStrings("done:true", params.filter.?);
    try testing.expectEqual(@as(i32, 10), params.page_size.?);
    try testing.expectEqualStrings("next-token", params.page_token.?);
}

// ============================================================================
// Files API Tests (RegisterFiles)
// ============================================================================

test "RegisterFilesParams struct" {
    const params = file.RegisterFilesParams{
        .gcs_uris = &[_][]const u8{
            "gs://bucket/file1.txt",
            "gs://bucket/file2.pdf",
        },
    };

    try testing.expectEqual(@as(usize, 2), params.gcs_uris.len);
    try testing.expectEqualStrings("gs://bucket/file1.txt", params.gcs_uris[0]);
    try testing.expectEqualStrings("gs://bucket/file2.pdf", params.gcs_uris[1]);
}

test "FileObject struct" {
    const obj = file.FileObject{
        .id = "file-123",
        .bytes = 1024,
        .created_at = 1234567890,
        .filename = "test.txt",
        .purpose = "batch",
        .status = "processed",
    };

    try testing.expectEqualStrings("file-123", obj.id);
    try testing.expectEqual(@as(u32, 1024), obj.bytes);
    try testing.expectEqual(@as(u64, 1234567890), obj.created_at);
    try testing.expectEqualStrings("test.txt", obj.filename);
    try testing.expectEqualStrings("batch", obj.purpose);
    try testing.expectEqualStrings("processed", obj.status);
}

test "FileDeleted struct" {
    const del = file.FileDeleted{
        .id = "file-123",
        .deleted = true,
    };

    try testing.expectEqualStrings("file-123", del.id);
    try testing.expect(del.deleted);
}

test "FilePurpose enum" {
    try testing.expectEqualStrings("assistants", file.FilePurpose.assistants.toString());
    try testing.expectEqualStrings("batch", file.FilePurpose.batch.toString());
    try testing.expectEqualStrings("fine-tune", file.FilePurpose.fine_tune.toString());
    try testing.expectEqualStrings("vision", file.FilePurpose.vision.toString());
    try testing.expectEqualStrings("user_data", file.FilePurpose.user_data.toString());
}

// ============================================================================
// FileSearchStores Upload Tests
// ============================================================================

test "FileSearchStore uploadFiles method signature" {
    // Test that the uploadFiles params are correctly structured
    const params = gemini_file_search_stores.UploadFilesParams{
        .files = &[_][]const u8{
            "gs://bucket/file1.txt",
            "gs://bucket/file2.txt",
        },
    };

    try testing.expectEqual(@as(usize, 2), params.files.len);
    try testing.expectEqualStrings("gs://bucket/file1.txt", params.files[0]);
    try testing.expectEqualStrings("gs://bucket/file2.txt", params.files[1]);
}

test "FileSearchStore importFiles params" {
    const params = gemini_file_search_stores.ImportFilesParams{
        .gcs_uris = &[_][]const u8{"gs://bucket/*.txt"},
        .mime_type = "text/plain",
    };

    try testing.expectEqual(@as(usize, 1), params.gcs_uris.len);
    try testing.expectEqualStrings("text/plain", params.mime_type);
}

// ============================================================================
// Tokens API Tests (gemini_tokens.zig)
// ============================================================================

test "CountTokensParams struct" {
    // Test with empty contents - simpler to avoid type issues
    const params = gemini_tokens.CountTokensParams{
        .contents = &[_]gemini_tokens.Content{},
        .model = "gemini-1.5-flash",
    };

    try testing.expectEqualStrings("gemini-1.5-flash", params.model.?);
    try testing.expectEqual(@as(usize, 0), params.contents.len);
}

test "CountTokensResult struct" {
    const result = gemini_tokens.CountTokensResult{
        .total_tokens = 500,
        .total_billable_characters = 2500,
    };

    try testing.expectEqual(@as(u32, 500), result.total_tokens);
    try testing.expectEqual(@as(u32, 2500), result.total_billable_characters);
}

test "Token Content and Part structures" {
    const text_part = gemini_tokens.Part{ .text = "Test content" };

    switch (text_part) {
        .text => |t| {
            try testing.expectEqualStrings("Test content", t);
        },
        else => unreachable,
    }

    const file_part = gemini_tokens.Part{ .file_data = .{
        .mime_type = "text/plain",
        .file_uri = "gs://bucket/file.txt",
    } };

    switch (file_part) {
        .file_data => |f| {
            try testing.expectEqualStrings("text/plain", f.mime_type);
            try testing.expectEqualStrings("gs://bucket/file.txt", f.file_uri);
        },
        else => unreachable,
    }
}

// ============================================================================
// Chat Streaming Methods Tests
// ============================================================================

test "Chat Part union types" {
    const text_part = google.Part{ .text = "Hello" };

    switch (text_part) {
        .text => |t| {
            try testing.expectEqualStrings("Hello", t);
        },
    }
}

test "Chat Content with multiple parts" {
    const allocator = testing.allocator;

    const text = try allocator.dupe(u8, "First message");
    defer allocator.free(text);

    const part1 = google.Part{ .text = text };

    var parts_array = std.ArrayListUnmanaged(google.Part){};
    errdefer parts_array.deinit(allocator);
    try parts_array.append(allocator, part1);

    const content = google.Content{
        .role = "user",
        .parts = try parts_array.toOwnedSlice(allocator),
    };
    defer allocator.free(content.parts);

    try testing.expectEqualStrings("user", content.role);
    try testing.expectEqual(@as(usize, 1), content.parts.len);
}

// Import operations module
const gemini_operations = @import("gemini_operations");
