//! Cache Plugin for llmlite Proxy
//!
//! Provides simple TTL-based caching and semantic cache with embedding-based similarity.
//! Zero dependency for simple cache - uses in-memory storage.

const std = @import("std");
const time_compat = @import("time_compat");

// Zig 0.16.0 compat: managed StringArrayHashMap wrapper
fn StringArrayHashMap(comptime V: type) type {
    return struct {
        const Self = @This();
        unmanaged: std.StringArrayHashMapUnmanaged(V),
        allocator: std.mem.Allocator,
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .unmanaged = .empty, .allocator = allocator };
        }
        pub fn deinit(self: *Self) void { self.unmanaged.deinit(self.allocator); }
        pub fn put(self: *Self, key: []const u8, value: V) !void { return self.unmanaged.put(self.allocator, key, value); }
        pub fn get(self: Self, key: []const u8) ?V { return self.unmanaged.get(key); }
        pub fn getPtr(self: Self, key: []const u8) ?*V { return self.unmanaged.getPtr(key); }
        pub fn getOrPut(self: *Self, key: []const u8) !std.StringArrayHashMapUnmanaged(V).GetOrPutResult { return self.unmanaged.getOrPut(self.allocator, key); }
        pub fn getOrPutValue(self: *Self, key: []const u8, value: V) !std.StringArrayHashMapUnmanaged(V).GetOrPutResult { return self.unmanaged.getOrPutValue(self.allocator, key, value); }
        pub fn contains(self: Self, key: []const u8) bool { return self.unmanaged.contains(key); }
        pub fn count(self: Self) usize { return self.unmanaged.count(); }
        pub fn iterator(self: Self) std.StringArrayHashMapUnmanaged(V).Iterator { return self.unmanaged.iterator(); }
        pub fn fetchSwapRemove(self: *Self, key: []const u8) ?std.StringArrayHashMapUnmanaged(V).KV { return self.unmanaged.fetchSwapRemove(key); }
        pub fn fetchRemove(self: *Self, key: []const u8) ?std.StringArrayHashMapUnmanaged(V).KV { return self.unmanaged.fetchSwapRemove(key); }
        pub fn swapRemove(self: *Self, key: []const u8) bool { return self.unmanaged.swapRemove(key); }
        pub fn keys(self: Self) [][]const u8 { return self.unmanaged.keys(); }
        pub fn values(self: Self) []V { return self.unmanaged.values(); }
    };
}
const plugin = @import("plugin");
const http = @import("http");

// ============ Simple Cache Entry ============

const CacheEntry = struct {
    value: []u8,
    expires_at: i64,
};

// ============ Simple TTL Cache ============

pub const SimpleCache = struct {
    entries: StringArrayHashMap(CacheEntry),
    allocator: std.mem.Allocator,
    ttl_seconds: u32,
    max_entries: u32,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, ttl_seconds: u32, max_entries: u32) SimpleCache {
        return .{
            .entries = StringArrayHashMap(CacheEntry).init(allocator),
            .allocator = allocator,
            .ttl_seconds = ttl_seconds,
            .max_entries = max_entries,
        };
    }

    pub fn deinit(self: *SimpleCache) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.value);
        }
        self.entries.deinit();
    }

    pub fn toCache(self: *SimpleCache) plugin.Cache {
        return .{
            .interface = @ptrCast(self),
            .vtable = &.{
                .get = getWrapper,
                .set = setWrapper,
                .delete = deleteWrapper,
                .clear = clearWrapper,
                .close = closeWrapper,
            },
        };
    }

    fn getWrapper(interface: *anyopaque, key: []const u8) ?[]const u8 {
        const self: *SimpleCache = @ptrCast(@alignCast(interface));
        const entry = self.entries.get(key) orelse return null;

        // Check if expired
        const now = time_compat.timestamp(self.io);
        if (now > entry.expires_at) {
            // Clean up expired entry
            if (self.entries.fetchRemove(key)) |e| {
                self.allocator.free(e.key);
                self.allocator.free(e.value.value);
            }
            return null;
        }

        return entry.value;
    }

    fn setWrapper(interface: *anyopaque, key: []const u8, value: []const u8, ttl_seconds: u32) !void {
        const self: *SimpleCache = @ptrCast(@alignCast(interface));

        // Check if we need to evict
        if (!self.entries.contains(key) and self.entries.count() >= self.max_entries) {
            // Evict oldest expired entry, or oldest entry if all are expired
            try self.evictOldest();
        }

        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = try self.allocator.dupe(u8, value);
        const expires_at = time_compat.timestamp(self.io) + @as(i64, @intCast(ttl_seconds));

        if (self.entries.put(key_copy, .{ .value = value_copy, .expires_at = expires_at })) |old| {
            self.allocator.free(old.value);
        }
    }

    fn deleteWrapper(interface: *anyopaque, key: []const u8) bool {
        const self: *SimpleCache = @ptrCast(@alignCast(interface));
        if (self.entries.fetchRemove(key)) |e| {
            self.allocator.free(e.key);
            self.allocator.free(e.value.value);
            return true;
        }
        return false;
    }

    fn clearWrapper(interface: *anyopaque) void {
        const self: *SimpleCache = @ptrCast(@alignCast(interface));
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.value);
        }
        self.entries.clearRetainingCapacity();
    }

    fn closeWrapper(interface: *anyopaque) void {
        const self: *SimpleCache = @ptrCast(@alignCast(interface));
        self.deinit();
    }

    fn evictOldest(self: *SimpleCache) !void {
        var oldest_key: ?[]const u8 = null;
        var oldest_time: i64 = time_compat.timestamp(self.io);

        var it = self.entries.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.expires_at < oldest_time) {
                oldest_time = entry.value_ptr.expires_at;
                oldest_key = entry.key_ptr.*;
            }
        }

        if (oldest_key) |key| {
            if (self.entries.fetchRemove(key)) |e| {
                self.allocator.free(e.key);
                self.allocator.free(e.value.value);
            }
        }
    }
};

// ============ Semantic Cache (Embedding-based) ============
//
// True semantic cache that uses embedding vectors to find similar requests.
// This enables caching of semantically equivalent queries like:
//   "How do I bake a cake?" ≈ "What's the recipe for cake?"
//
// Architecture:
//   Request → Normalize Text → Embed → Cosine Similarity Search → Cache Hit/Miss
//
// Storage: embedding vector + response + metadata per entry
// Lookup: O(n) similarity search (can optimize with vector DB later)

pub const SemanticCacheEntry = struct {
    /// Text that was embedded (for debugging/logging)
    text: []u8,
    /// Normalized embedding vector (stored as f32 for efficiency)
    embedding: []f32,
    /// Cached response JSON
    response: []u8,
    /// TTL expiry timestamp
    expires_at: i64,
    /// Creation timestamp for LRU
    created_at: i64,
    /// Hit count for analytics
    hit_count: u64,
};

pub const SemanticCache = struct {
    /// Entries stored as a list for similarity search
    /// Note: For production with many entries, use a vector index (HNSW, IVF-PQ)
    entries: std.array_list.Managed(SemanticCacheEntry),
    allocator: std.mem.Allocator,
    ttl_seconds: u32,
    max_entries: u32,
    /// Minimum cosine similarity threshold (0.0 - 1.0)
    similarity_threshold: f32,
    /// Embedding model to use
    embedding_model: []const u8,
    /// HTTP client for embedding API (can be null for hash-only mode)
    http_client: ?*http.HttpClient,
    /// Embedding dimension (e.g., 1536 for text-embedding-ada-002)
    embedding_dim: u32,

    pub fn init(
        allocator: std.mem.Allocator,
        ttl_seconds: u32,
        max_entries: u32,
        similarity_threshold: f32,
        embedding_model: []const u8,
        http_client: ?*http.HttpClient,
        embedding_dim: u32,
    ) SemanticCache {
        return .{
            .entries = std.array_list.Managed(SemanticCacheEntry).init(allocator),
            .allocator = allocator,
            .ttl_seconds = ttl_seconds,
            .max_entries = max_entries,
            .similarity_threshold = similarity_threshold,
            .embedding_model = embedding_model,
            .http_client = http_client,
            .embedding_dim = embedding_dim,
        };
    }

    pub fn deinit(self: *SemanticCache) void {
        for (self.entries.items) |*entry| {
            self.allocator.free(entry.text);
            self.allocator.free(entry.embedding);
            self.allocator.free(entry.response);
        }
        self.entries.deinit();
    }

    /// Normalize chat completion request to searchable text
    /// Extracts and concatenates all text content from messages
    pub fn normalizeRequest(self: *SemanticCache, request_json: []const u8) ![]u8 {
        _ = self;
        return try extractTextFromMessages(self.allocator, request_json);
    }

    /// Generate embedding for text using the configured embedding API
    /// Falls back to hash if no HTTP client configured
    pub fn generateEmbedding(self: *SemanticCache, text: []const u8) ![]f32 {
        if (self.http_client) |client| {
            return try self.callEmbeddingApi(client, text);
        }
        // Fallback: generate deterministic "embedding" from hash
        return try self.hashToEmbedding(text);
    }

    /// Find best matching entry using cosine similarity
    /// Returns (response, similarity_score) on cache hit, null on miss
    pub fn findSimilar(self: *SemanticCache, query_embedding: []const f32) !?struct { []u8, f32 } {
        var best_similarity: f32 = 0;
        var best_idx: ?usize = null;
        const now = time_compat.timestamp(self.io);

        for (self.entries.items, 0..) |*entry, idx| {
            // Skip expired entries
            if (now > entry.expires_at) continue;

            const similarity = cosineSimilarity(query_embedding, entry.embedding);
            if (similarity > best_similarity) {
                best_similarity = similarity;
                best_idx = idx;
            }
        }

        if (best_idx) |idx| {
            if (best_similarity >= self.similarity_threshold) {
                // Increment hit count
                self.entries.items[idx].hit_count += 1;
                return .{
                    self.entries.items[idx].response,
                    best_similarity,
                };
            }
        }

        return null;
    }

    /// Store a new embedding-response pair
    pub fn store(self: *SemanticCache, text: []const u8, embedding: []f32, response: []u8) !void {
        // Evict if necessary
        if (self.entries.items.len >= self.max_entries) {
            try self.evictLRU();
        }

        const entry = SemanticCacheEntry{
            .text = try self.allocator.dupe(u8, text),
            .embedding = try self.allocator.dupe(f32, embedding),
            .response = try self.allocator.dupe(u8, response),
            .expires_at = time_compat.timestamp(self.io) + @as(i64, @intCast(self.ttl_seconds)),
            .created_at = time_compat.timestamp(self.io),
            .hit_count = 0,
        };

        try self.entries.append(entry);
    }

    /// Evict least recently used entry (oldest by creation time with lowest hit count)
    fn evictLRU(self: *SemanticCache) !void {
        if (self.entries.items.len == 0) return;

        var oldest_idx: usize = 0;
        var oldest_time: i64 = self.entries.items[0].created_at;

        for (self.entries.items, 0..) |entry, idx| {
            // Prefer evicting entries with low hit counts
            const score = @as(i64, entry.created_at) - @as(i64, @intCast(entry.hit_count * 100));
            const oldest_score = @as(i64, oldest_time) - @as(i64, @intCast(self.entries.items[oldest_idx].hit_count * 100));
            if (score < oldest_score) {
                oldest_idx = idx;
                oldest_time = entry.created_at;
            }
        }

        // Remove entry
        const entry = self.entries.orderedRemove(oldest_idx);
        self.allocator.free(entry.text);
        self.allocator.free(entry.embedding);
        self.allocator.free(entry.response);
    }

    /// Call embedding API to generate embedding vector
    fn callEmbeddingApi(self: *SemanticCache, client: *http.HttpClient, text: []const u8) ![]f32 {
        const request_body = try std.fmt.allocPrint(self.allocator,
            \\{{"model":"{s}","input":"{s}"}}
        , .{ self.embedding_model, text });
        defer self.allocator.free(request_body);

        const response = try client.post("/embeddings", request_body);
        defer self.allocator.free(response);

        return try parseEmbeddingResponse(self.allocator, response);
    }

    /// Fallback: generate deterministic "embedding" from SHA256 hash
    /// Used when no embedding API is configured
    /// Creates a pseudo-embedding that's consistent for the same input
    fn hashToEmbedding(self: *SemanticCache, text: []const u8) ![]f32 {
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha256.Sha256.hash(text, &hash);

        // Convert hash to pseudo-embedding vector
        const embedding = try self.allocator.alloc(f32, self.embedding_dim);
        for (0..self.embedding_dim) |i| {
            // Use pairs of bytes to create f32 values normalized to [-1, 1]
            const idx = (i * 2) % 32;
            const val = @as(f32, @floatFromInt(@as(u16, hash[idx]) << 8 | hash[idx + 1])) / 32768.0 - 1.0;
            embedding[i] = val;
        }

        return embedding;
    }

    /// Search cached entries by text similarity (fallback when embedding unavailable)
    /// Uses simple keyword overlap for matching
    pub fn searchByText(self: *SemanticCache, query_text: []const u8) ?[]u8 {
        var best_score: f32 = 0;
        var best_response: ?[]u8 = null;
        const now = time_compat.timestamp(self.io);

        const query_words = std.mem.splitScalar(u8, query_text, ' ');

        for (self.entries.items) |entry| {
            if (now > entry.expires_at) continue;

            // Simple word overlap score
            var overlap: f32 = 0;
            var query_word_count: f32 = 0;
            var entry_word_count: f32 = 0;

            var qi = std.mem.splitScalar(u8, query_text, ' ');
            while (qi.next()) |word| {
                if (word.len > 2) { // Ignore very short words
                    query_word_count += 1;
                    if (std.mem.find(u8, entry.text, word) != null) {
                        overlap += 1;
                    }
                }
            }

            var ei = std.mem.splitScalar(u8, entry.text, ' ');
            while (ei.next()) |word| {
                if (word.len > 2) entry_word_count += 1;
            }

            if (query_word_count > 0 and entry_word_count > 0) {
                const score = (overlap / query_word_count + overlap / entry_word_count) / 2;
                if (score > best_score and score >= 0.5) {
                    best_score = score;
                    best_response = entry.response;
                }
            }
        }

        return best_response;
    }
};

// ============ Helper Functions ============

/// Extract text content from a chat completion request JSON
/// Concatenates all message content into a single searchable string
fn extractTextFromMessages(allocator: std.mem.Allocator, json_str: []const u8) ![]u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    errdefer result.deinit();

    // Find "messages" array in JSON
    const messages_start = std.mem.find(u8, json_str, "\"messages\":") orelse {
        // No messages, just use the whole JSON as text
        return allocator.dupe(u8, json_str);
    };

    // Find the opening bracket of the messages array
    var arr_start: ?usize = null;
    var depth: u32 = 0;
    for (json_str[messages_start..], messages_start..) |c, i| {
        if (c == '[' and depth == 0) {
            arr_start = i;
            depth = 1;
            break;
        }
        if (c == '{') depth += 1;
    }

    if (arr_start == null) {
        return allocator.dupe(u8, json_str);
    }

    // Parse each message and extract "content" field
    var i = arr_start.? + 1;
    while (i < json_str.len) {
        // Skip whitespace
        while (i < json_str.len and (json_str[i] == ' ' or json_str[i] == '\n' or json_str[i] == '\t' or json_str[i] == ',')) {
            i += 1;
        }

        if (i >= json_str.len or json_str[i] != '{') break;

        // Find content field in this message object
        const content_start = std.mem.findPos(u8, json_str, i, "\"content\":\"") orelse blk: {
            // Try 'content':' (single quotes)
            break :blk std.mem.findPos(u8, json_str, i, "'content':'") orelse blk2: {
                // No content in this message
                // Find end of object
                var d: u32 = 0;
                var j = i;
                while (j < json_str.len) {
                    if (json_str[j] == '{') d += 1;
                    if (json_str[j] == '}') {
                        d -= 1;
                        if (d == 0) {
                            i = j + 1;
                            break :blk2 null;
                        }
                    }
                    j += 1;
                }
                break :blk2 null;
            }
        };

        // Find the closing quote for content
        var content_end = content_start + 11; // len("\"content\":\"")
        while (content_end < json_str.len) {
            if (json_str[content_end] == '"' and json_str[content_end - 1] != '\\') {
                break;
            }
            content_end += 1;
        }

        // Append content to result with separator
        if (result.items.len > 0) {
            try result.append(' ');
        }
        try result.appendSlice(json_str[content_start + 10..content_end]);

        // Find end of this message object
        var d: u32 = 0;
        var j = i;
        while (j < json_str.len) {
            if (json_str[j] == '{') d += 1;
            if (json_str[j] == '}') {
                d -= 1;
                if (d == 0) {
                    i = j + 1;
                    break;
                }
            }
            j += 1;
        }
    }

    if (result.items.len == 0) {
        return allocator.dupe(u8, json_str);
    }

    return result.toOwnedSlice();
}

/// Calculate cosine similarity between two embedding vectors
/// Returns value in range [-1, 1], where 1 = identical direction
fn cosineSimilarity(a: []const f32, b: []const f32) f32 {
    if (a.len != b.len) return 0;

    var dot_product: f32 = 0;
    var norm_a: f32 = 0;
    var norm_b: f32 = 0;

    for (a, b) |a_val, b_val| {
        dot_product += a_val * b_val;
        norm_a += a_val * a_val;
        norm_b += b_val * b_val;
    }

    if (norm_a == 0 or norm_b == 0) return 0;

    return dot_product / (std.math.sqrt(norm_a) * std.math.sqrt(norm_b));
}

/// Parse embedding response from OpenAI-compatible API
/// Expected format: {"data":[{"embedding":[...],"index":0}],"usage":{"prompt_tokens":...}}
fn parseEmbeddingResponse(allocator: std.mem.Allocator, response: []const u8) ![]f32 {
    // Find "embedding" array
    const emb_start = std.mem.find(u8, response, "\"embedding\":") orelse {
        return error.ParseError;
    };

    // Find opening bracket
    const arr_start = std.mem.findPos(u8, response, emb_start, "[") orelse {
        return error.ParseError;
    };

    // Find closing bracket (matching)
    var depth: u32 = 1;
    var i = arr_start + 1;
    while (i < response.len and depth > 0) {
        if (response[i] == '[') depth += 1;
        if (response[i] == ']') depth -= 1;
        i += 1;
    }

    const emb_str = response[arr_start..i];

    // Parse float array
    var floats = std.array_list.Managed(f32).init(allocator);
    errdefer floats.deinit();

    var num_start: ?usize = null;
    for (emb_str, 0..) |c, idx| {
        if (c == '-' or (c >= '0' and c <= '9') or c == '.') {
            if (num_start == null) num_start = idx;
        } else if (c == ',' or c == ']') {
            if (num_start) |start| {
                const num_str = emb_str[start..idx];
                if (std.fmt.parseFloat(f32, num_str)) |val| {
                    try floats.append(val);
                } else |_| {}
                num_start = null;
            }
        }
    }

    return floats.toOwnedSlice();
}

// ============ Plugin Interface Wrappers ============

fn semanticGetWrapper(interface: *anyopaque, key: []const u8) ?[]const u8 {
    const self: *SemanticCache = @ptrCast(@alignCast(interface));
    _ = key;

    // For semantic cache, key should be the full request JSON
    // We search by text similarity since semantic cache doesn't use exact keys

    // Normalize request to text
    const text = self.normalizeRequest(key) catch return null;
    defer self.allocator.free(text);

    // Try text-based search as fallback
    if (self.http_client == null) {
        return self.searchByText(text);
    }

    // Generate embedding
    const embedding = self.generateEmbedding(text) catch return null;
    defer self.allocator.free(embedding);

    // Find similar entry
    if (self.findSimilar(embedding)) |result| {
        return result[0];
    }

    return null;
}

fn semanticSetWrapper(interface: *anyopaque, key: []const u8, value: []const u8, ttl_seconds: u32) !void {
    const self: *SemanticCache = @ptrCast(@alignCast(interface));
    _ = ttl_seconds;

    // Normalize request to text
    const text = try self.normalizeRequest(key);

    // Generate embedding
    const embedding = try self.generateEmbedding(text);
    defer self.allocator.free(embedding);

    // Store
    try self.store(text, embedding, value);
}

fn semanticDeleteWrapper(interface: *anyopaque, key: []const u8) bool {
    const self: *SemanticCache = @ptrCast(@alignCast(interface));
    _ = key;

    // For semantic cache, deletion by exact key isn't meaningful
    // Could implement deletion by similarity threshold, but for now just return false
    _ = self;
    return false;
}

fn semanticClearWrapper(interface: *anyopaque) void {
    const self: *SemanticCache = @ptrCast(@alignCast(interface));
    for (self.entries.items) |*entry| {
        self.allocator.free(entry.text);
        self.allocator.free(entry.embedding);
        self.allocator.free(entry.response);
    }
    self.entries.clearRetainingCapacity();
}

fn semanticCloseWrapper(interface: *anyopaque) void {
    const self: *SemanticCache = @ptrCast(@alignCast(interface));
    self.deinit();
}

pub fn semanticCacheToCache(self: *SemanticCache) plugin.Cache {
    return .{
        .interface = @ptrCast(self),
        .vtable = &.{
            .get = semanticGetWrapper,
            .set = semanticSetWrapper,
            .delete = semanticDeleteWrapper,
            .clear = semanticClearWrapper,
            .close = semanticCloseWrapper,
        },
    };
}

// ============ Plugin Info ============

pub const SIMPLE_CACHE_INFO = plugin.PluginInfo{
    .name = "cache.simple",
    .version = "1.0.0",
    .description = "Simple TTL-based in-memory cache",
    .plugin_type = .cache,
    .dependencies = &.{},
};

pub const SEMANTIC_CACHE_INFO = plugin.PluginInfo{
    .name = "cache.semantic",
    .version = "1.0.0",
    .description = "Semantic embedding-based cache for request deduplication",
    .plugin_type = .cache,
    .dependencies = &.{"http"},
};

test "cache plugin" {
    std.debug.print("Cache plugin test\n", .{});
}

test "cosine similarity" {
    const a = &[_]f32{ 1.0, 0.0, 0.0 };
    const b = &[_]f32{ 1.0, 0.0, 0.0 };
    const sim = cosineSimilarity(a, b);
    std.debug.print("identical vectors similarity: {d}\n", .{sim});
    try std.testing.expect(sim > 0.99);
}

test "text extraction" {
    const json = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello world\"}]}";
    const text = try extractTextFromMessages(std.heap.page_allocator, json);
    defer std.heap.page_allocator.free(text);
    std.debug.print("extracted text: {s}\n", .{text});
    try std.testing.expect(std.mem.find(u8, text, "Hello world") != null);
}
