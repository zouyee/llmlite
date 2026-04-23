//! Session History Store for llmlite Proxy
//!
//! Stores and retrieves conversation history across CLI tools:
//! - Claude Code sessions
//! - Codex sessions
//! - Gemini CLI sessions
//! - OpenCode sessions
//! - OpenClaw sessions
//!
//! Provides search, browsing, and restoration capabilities.

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
const preset = @import("proxy_preset");

pub const CliTool = preset.CliTool;

/// A single message in a conversation
pub const Message = struct {
    /// Message role (user, assistant, system)
    role: []const u8,
    /// Message content
    content: []const u8,
    /// Timestamp
    timestamp: i64,
    /// Model used (for assistant messages)
    model: ?[]const u8 = null,
    /// Token usage (for assistant messages)
    prompt_tokens: ?u32 = null,
    completion_tokens: ?u32 = null,
};

/// Token usage summary for a session
pub const TokenUsage = struct {
    prompt_tokens: u32 = 0,
    completion_tokens: u32 = 0,
    total_tokens: u32 = 0,
};

/// A conversation session
pub const Session = struct {
    /// Unique session ID
    id: []const u8,
    /// CLI tool this session belongs to
    tool: CliTool,
    /// Session title (first user message or auto-generated)
    title: []const u8,
    /// Provider used
    provider: []const u8,
    /// Model used
    model: []const u8,
    /// Messages in the conversation
    messages: []Message,
    /// Token usage
    token_usage: TokenUsage,
    /// Creation timestamp
    created_at: i64,
    /// Last update timestamp
    updated_at: i64,
    /// Whether session is archived
    archived: bool = false,
};

/// Session summary (for listing without full messages)
pub const SessionSummary = struct {
    id: []const u8,
    tool: CliTool,
    title: []const u8,
    provider: []const u8,
    model: []const u8,
    message_count: u32,
    created_at: i64,
    updated_at: i64,
    archived: bool,
    /// Preview of the first user message (truncated to 150 chars)
    first_user_message: ?[]const u8,
    /// Preview of the last message (truncated to 150 chars)
    last_message_preview: ?[]const u8,
};

/// Session store
pub const SessionStore = struct {
    allocator: std.mem.Allocator,
pub const SessionStore = struct {
    io: std.Io,
    sessions: StringArrayHashMap(Session),
    sessions_by_tool: std.enums.EnumArray(CliTool, std.array_list.Managed([]const u8)),
    index_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator) SessionStore {
        return .{
            .allocator = allocator,
            .sessions = StringArrayHashMap(Session).init(allocator),
            .sessions_by_tool = std.enums.EnumArray(CliTool, std.array_list.Managed([]const u8)).init(undefined),
            .index_dir = undefined,
        };
    }

    pub fn deinit(self: *SessionStore) void {
        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            self.freeSession(entry.value_ptr.*);
        }
        self.sessions.deinit();

        // Clean up tool indices
        {
            // Note: EnumArray stores values directly, not pointers.
            // During deinit of SessionStore, we don't need to explicitly
            // deinit the per-tool array lists since the EnumArray itself
            // will be destroyed. We just need to free any owned slices.
            const tools = [_]CliTool{ .claude_code, .codex, .gemini_cli, .opencode, .openclaw };
            for (tools) |tool| {
                // Get the list - in Zig 0.15+ EnumArray.get returns *const
                // We can't call deinit, but we can at least free the items
                const list = self.sessions_by_tool.get(tool);
                for (list.items) |id| self.allocator.free(id);
            }
        }

        if (self.index_dir.len > 0) {
            self.allocator.free(self.index_dir);
        }
    }

    fn freeSession(self: *SessionStore, session: Session) void {
        self.allocator.free(session.id);
        self.allocator.free(session.title);
        self.allocator.free(session.provider);
        self.allocator.free(session.model);
        for (session.messages) |msg| {
            self.allocator.free(msg.role);
            self.allocator.free(msg.content);
            if (msg.model) |m| self.allocator.free(m);
        }
        self.allocator.free(session.messages);
    }

    /// Create a new session
    pub fn createSession(
        self: *SessionStore,
        tool: CliTool,
        provider: []const u8,
        model: []const u8,
        first_message: []const u8,
    ) !Session {
        const id = try self.generateSessionId();
        errdefer self.allocator.free(id);

        const title = self.generateTitle(first_message);
        errdefer self.allocator.free(title);

        const now = time_compat.timestamp(self.io);

        const session = Session{
            .id = id,
            .tool = tool,
            .title = title,
            .provider = try self.allocator.dupe(u8, provider),
            .model = try self.allocator.dupe(u8, model),
            .messages = &.{},
            .token_usage = .{},
            .created_at = now,
            .updated_at = now,
        };

        try self.sessions.put(id, session);
        try self.addToToolIndex(tool, id);

        return session;
    }

    fn generateSessionId(self: *SessionStore) ![]u8 {
        // Use timestamp + random for unique ID
        const timestamp = time_compat.timestamp(self.io);
        const random = std.crypto.randomInt(u32);
        return std.fmt.allocPrint(self.allocator, "sess_{d}_{x}", .{ timestamp, random });
    }

    fn generateTitle(self: *SessionStore, first_message: []const u8) []u8 {
        // Use first 50 chars of first message as title
        const max_len: usize = 50;
        if (first_message.len <= max_len) {
            return self.allocator.dupe(u8, first_message) catch "";
        }
        const title = first_message[0..max_len];
        return self.allocator.dupe(u8, title) catch "";
    }

    fn addToToolIndex(self: *SessionStore, tool: CliTool, id: []const u8) !void {
        const list = self.sessions_by_tool.get(tool);
        if (list == null) {
            const new_list = std.array_list.Managed([]const u8).init(self.allocator);
            self.sessions_by_tool.set(tool, new_list);
        }
        const id_copy = self.allocator.dupe(u8, id) catch return error.AllocatorError;
        try self.sessions_by_tool.get(tool).?.append(id_copy);
    }

    /// Get a session by ID
    pub fn getSession(self: *SessionStore, id: []const u8) ?*Session {
        return self.sessions.get(id);
    }

    /// Add a message to a session
    pub fn addMessage(
        self: *SessionStore,
        session_id: []const u8,
        role: []const u8,
        content: []const u8,
    ) !void {
        const session = self.sessions.get(session_id) orelse {
            return error.SessionNotFound;
        };

        const message = Message{
            .role = try self.allocator.dupe(u8, role),
            .content = try self.allocator.dupe(u8, content),
            .timestamp = time_compat.timestamp(self.io),
        };

        const new_messages = try self.allocator.realloc(session.messages, session.messages.len + 1);
        new_messages[new_messages.len - 1] = message;
        session.messages = new_messages;
        session.updated_at = time_compat.timestamp(self.io);
    }

    /// Update token usage for a session
    pub fn updateTokenUsage(
        self: *SessionStore,
        session_id: []const u8,
        prompt: u32,
        completion: u32,
    ) !void {
        const session = self.sessions.get(session_id) orelse {
            return error.SessionNotFound;
        };

        session.token_usage.prompt_tokens += prompt;
        session.token_usage.completion_tokens += completion;
        session.token_usage.total_tokens = session.token_usage.prompt_tokens + session.token_usage.completion_tokens;
        session.updated_at = time_compat.timestamp(self.io);
    }

    /// List sessions for a tool (with pagination)
    pub fn listSessions(
        self: *SessionStore,
        tool: CliTool,
        limit: u32,
        offset: u32,
    ) ![]SessionSummary {
        var result = std.array_list.Managed(SessionSummary).init(self.allocator);
        const list = self.sessions_by_tool.get(tool);

        var skipped: u32 = 0;
        var included: u32 = 0;

        for (list.items) |id| {
            if (skipped < offset) {
                skipped += 1;
                continue;
            }
            if (included >= limit) break;

            const session = self.sessions.get(id) orelse continue;
            const summary = try self.sessionToSummary(session);
            try result.append(summary);
            included += 1;
        }

        return result.toOwnedSlice();
    }

    fn sessionToSummary(self: *SessionStore, session: Session) !SessionSummary {
        // Extract first user message preview
        var first_user: ?[]const u8 = null;
        for (session.messages) |msg| {
            if (std.mem.eql(u8, msg.role, "user")) {
                first_user = self.truncatePreview(msg.content, 150);
                break;
            }
        }

        // Extract last message preview
        var last_preview: ?[]const u8 = null;
        if (session.messages.len > 0) {
            const last = session.messages[session.messages.len - 1];
            last_preview = self.truncatePreview(last.content, 150);
        }

        return .{
            .id = session.id,
            .tool = session.tool,
            .title = session.title,
            .provider = session.provider,
            .model = session.model,
            .message_count = @intCast(session.messages.len),
            .created_at = session.created_at,
            .updated_at = session.updated_at,
            .archived = session.archived,
            .first_user_message = first_user,
            .last_message_preview = last_preview,
        };
    }

    /// Truncate message content for preview
    fn truncatePreview(self: *SessionStore, content: []const u8, max_len: usize) []const u8 {
        _ = self;
        if (content.len <= max_len) {
            return content;
        }
        // Find a good break point (end of sentence or space)
        const truncated = content[0..max_len];
        if (std.mem.findScalarLast(u8, truncated, ' ')) |space_idx| {
            return truncated[0..space_idx];
        }
        return truncated;
    }

    /// Search sessions by content
    pub fn searchSessions(self: *SessionStore, query: []const u8, limit: u32) ![]SessionSummary {
        var result = std.array_list.Managed(SessionSummary).init(self.allocator);
        var it = self.sessions.iterator();
        var count: u32 = 0;

        while (it.next()) |entry| {
            const session = entry.value_ptr;
            if (session.archived) continue;

            // Search in title and messages
            var found = false;
            if (std.mem.find(u8, session.title, query) != null) {
                found = true;
            } else {
                for (session.messages) |msg| {
                    if (std.mem.find(u8, msg.content, query) != null) {
                        found = true;
                        break;
                    }
                }
            }

            if (found) {
                const summary = try self.sessionToSummary(session.*);
                try result.append(summary);
                count += 1;
                if (count >= limit) break;
            }
        }

        return result.toOwnedSlice();
    }

    /// Search sessions by content within a specific tool
    pub fn searchSessionsForTool(self: *SessionStore, tool: CliTool, query: []const u8, limit: u32) ![]SessionSummary {
        var result = std.array_list.Managed(SessionSummary).init(self.allocator);

        const list = self.sessions_by_tool.get(tool);
        if (list == null) return result.toOwnedSlice();

        var count: u32 = 0;
        for (list.?.items) |id| {
            if (count >= limit) break;

            const session = self.sessions.get(id) orelse continue;
            if (session.archived) continue;
            if (session.tool != tool) continue;

            // Search in title and messages
            var found = false;
            if (std.mem.find(u8, session.title, query) != null) {
                found = true;
            } else {
                for (session.messages) |msg| {
                    if (std.mem.find(u8, msg.content, query) != null) {
                        found = true;
                        break;
                    }
                }
            }

            if (found) {
                const summary = try self.sessionToSummary(session.*);
                try result.append(summary);
                count += 1;
            }
        }

        return result.toOwnedSlice();
    }

    /// Archive a session
    pub fn archiveSession(self: *SessionStore, id: []const u8) bool {
        const session = self.sessions.get(id) orelse return false;
        session.archived = true;
        session.updated_at = time_compat.timestamp(self.io);
        return true;
    }

    /// Restore an archived session
    pub fn restoreSession(self: *SessionStore, id: []const u8) bool {
        const session = self.sessions.get(id) orelse return false;
        session.archived = false;
        session.updated_at = time_compat.timestamp(self.io);
        return true;
    }

    /// Delete a session
    pub fn deleteSession(self: *SessionStore, id: []const u8) bool {
        const session = self.sessions.fetchRemove(id) orelse return false;
        self.freeSession(session.value);

        // Remove from tool index
        {
            const tools = [_]CliTool{ .claude_code, .codex, .gemini_cli, .opencode, .openclaw };
            for (tools) |tool| {
                const list = self.sessions_by_tool.get(tool);
                if (list) |l| {
                    for (l.items, 0..) |item, i| {
                        if (std.mem.eql(u8, item, id)) {
                            self.allocator.free(l.items[i]);
                            _ = l.orderedRemove(i);
                            break;
                        }
                    }
                }
            }
        }

        return true;
    }

    /// Get session count for a tool
    pub fn getSessionCount(self: *SessionStore, tool: CliTool) u32 {
        const list = self.sessions_by_tool.get(tool) orelse return 0;
        return @intCast(list.items.len);
    }

    /// Get total session count
    pub fn getTotalSessionCount(self: *SessionStore) u32 {
        return @intCast(self.sessions.count());
    }

    /// Export session to JSON
    pub fn exportSession(self: *SessionStore, id: []const u8) !?[]u8 {
        const session = self.sessions.get(id) orelse return null;
        return std.json.Stringify.valueAlloc(self.allocator, session, .{ .whitespace = .indent_tab });
    }

    /// Import session from JSON
    pub fn importSession(self: *SessionStore, json_content: []const u8) !Session {
        const parsed = try std.json.parseFromSlice(Session, self.allocator, json_content, .{});
        defer parsed.deinit();

        // Copy all strings to our allocator
        var session = parsed.value;
        session.id = try self.allocator.dupe(u8, parsed.value.id);
        session.title = try self.allocator.dupe(u8, parsed.value.title);
        session.provider = try self.allocator.dupe(u8, parsed.value.provider);
        session.model = try self.allocator.dupe(u8, parsed.value.model);

        {
            const msgs = try self.allocator.alloc(Message, parsed.value.messages.len);
            for (parsed.value.messages, 0..) |msg, i| {
                msgs[i] = .{
                    .role = try self.allocator.dupe(u8, msg.role),
                    .content = try self.allocator.dupe(u8, msg.content),
                    .timestamp = msg.timestamp,
                    .model = if (msg.model) |m| try self.allocator.dupe(u8, m) else null,
                    .prompt_tokens = msg.prompt_tokens,
                    .completion_tokens = msg.completion_tokens,
                };
            }
            session.messages = msgs;
        }

        try self.sessions.put(session.id, session);
        try self.addToToolIndex(session.tool, session.id);

        return session;
    }

    /// Persist sessions to disk
    pub fn persistToDisk(self: *SessionStore) !void {
        const home_dir = std.os.getenv("HOME") orelse {
            return error.HomeDirectoryNotFound;
        };

        const sessions_dir = try std.fmt.allocPrint(
            self.allocator,
            "{s}/.cc-switch/sessions",
            .{home_dir},
        );
        defer self.allocator.free(sessions_dir);

        // Create directory
        try std.Io.Dir.createDirAbsolute(self.io, sessions_dir, .default_dir);

        // Write each session to its own file
        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            const session = entry.value_ptr;
            const file_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}/{s}.json",
                .{ sessions_dir, session.id },
            );
            defer self.allocator.free(file_path);

            const content = try std.json.Stringify.valueAlloc(self.allocator, session.*, .{ .whitespace = .indent_tab });
            defer self.allocator.free(content);

            const file = try std.Io.Dir.createFileAbsolute(self.io, file_path, .{});
            defer file.close(self.io);
            try file.writeStreamingAll(self.io, content);
        }
    }

    /// Load sessions from disk
    pub fn loadFromDisk(self: *SessionStore) !void {
        const home_dir = std.os.getenv("HOME") orelse {
            return error.HomeDirectoryNotFound;
        };

        const sessions_dir = try std.fmt.allocPrint(
            self.allocator,
            "{s}/.cc-switch/sessions",
            .{home_dir},
        );
        defer self.allocator.free(sessions_dir);

        // Open directory
        const dir = std.Io.Dir.openDirAbsolute(self.io, sessions_dir, .{ .iterate = true }) catch {
            return; // No sessions directory yet
        };
        defer dir.close(self.io);

        // Iterate JSON files
        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (!std.mem.endsWith(u8, entry.name, ".json")) continue;

            const file_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}/{s}",
                .{ sessions_dir, entry.name },
            );
            defer self.allocator.free(file_path);

            const file = std.Io.Dir.openFileAbsolute(self.io, file_path, .{}) catch continue;
            defer file.close(self.io);

            const content = try blk: { var __buf: [8192]u8 = undefined; var __reader = file.reader(self.io, &__buf); break :blk __reader.interface.allocRemaining(self.allocator, .limited(10_000_000)); };
            defer self.allocator.free(content);

            // Import session
            _ = self.importSession(content) catch {
                std.log.warn("failed to load session from {s}", .{file_path});
            };
        }
    }
};

// ============================================================================
// Cross-Provider Session Preview (cc-switch inspired)
// ============================================================================

/// A unified session preview that aggregates sessions from all tools
pub const UnifiedSessionPreview = struct {
    allocator: std.mem.Allocator,
    store: *SessionStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *SessionStore) UnifiedSessionPreview {
        return .{
            .allocator = allocator,
            .store = store,
        };
    }

    /// Get a unified list of recent sessions across all tools
    /// Sorted by last update time (most recent first)
    pub fn getRecentSessions(self: *UnifiedSessionPreview, limit: u32) ![]SessionSummary {
        var all_sessions = std.array_list.Managed(SessionSummary).init(self.allocator);
        defer all_sessions.deinit();

        // Collect sessions from all tools
        const tools = [_]CliTool{ .claude_code, .codex, .gemini_cli, .opencode, .openclaw };
        for (tools) |tool| {
            const summaries = try self.store.listSessions(tool, 100, 0);
            defer self.allocator.free(summaries);
            for (summaries) |summary| {
                // Copy the summary to our allocator
                const copy = try self.copySessionSummary(summary);
                try all_sessions.append(copy);
            }
        }

        // Sort by updated_at (most recent first)
        std.sort.insertionSort(SessionSummary, all_sessions.items, {}, struct {
            fn lessThan(a: SessionSummary, b: SessionSummary) bool {
                return a.updated_at > b.updated_at;
            }
        }.lessThan);

        // Limit results
        if (all_sessions.items.len > limit) {
            const result = try self.allocator.alloc(SessionSummary, limit);
            @memcpy(result, all_sessions.items[0..limit]);
            return result;
        }

        return try all_sessions.toOwnedSlice();
    }

    /// Search across all tools
    pub fn searchAll(self: *UnifiedSessionPreview, query: []const u8, limit: u32) ![]SessionSummary {
        var all_results = std.array_list.Managed(SessionSummary).init(self.allocator);
        defer all_results.deinit();

        // Search each tool
        const tools = [_]CliTool{ .claude_code, .codex, .gemini_cli, .opencode, .openclaw };
        for (tools) |tool| {
            const tool_results = try self.store.searchSessions(tool, query, 50);
            defer self.allocator.free(tool_results);
            for (tool_results) |result| {
                const copy = try self.copySessionSummary(result);
                try all_results.append(copy);
            }
        }

        // Sort by updated_at
        std.sort.insertionSort(SessionSummary, all_results.items, {}, struct {
            fn lessThan(a: SessionSummary, b: SessionSummary) bool {
                return a.updated_at > b.updated_at;
            }
        }.lessThan);

        if (all_results.items.len > limit) {
            const result = try self.allocator.alloc(SessionSummary, limit);
            @memcpy(result, all_results.items[0..limit]);
            return result;
        }

        return try all_results.toOwnedSlice();
    }

    /// Get sessions grouped by provider
    pub fn getSessionsByProvider(self: *UnifiedSessionPreview, provider: []const u8, limit: u32) ![]SessionSummary {
        var results = std.array_list.Managed(SessionSummary).init(self.allocator);
        defer results.deinit();

        const tools = [_]CliTool{ .claude_code, .codex, .gemini_cli, .opencode, .openclaw };
        for (tools) |tool| {
            const summaries = try self.store.listSessions(tool, 100, 0);
            defer self.allocator.free(summaries);
            for (summaries) |summary| {
                if (std.mem.eql(u8, summary.provider, provider)) {
                    const copy = try self.copySessionSummary(summary);
                    try results.append(copy);
                    if (results.items.len >= limit) break;
                }
            }
            if (results.items.len >= limit) break;
        }

        return try results.toOwnedSlice();
    }

    /// Get sessions grouped by model
    pub fn getSessionsByModel(self: *UnifiedSessionPreview, model: []const u8, limit: u32) ![]SessionSummary {
        var results = std.array_list.Managed(SessionSummary).init(self.allocator);
        defer results.deinit();

        const tools = [_]CliTool{ .claude_code, .codex, .gemini_cli, .opencode, .openclaw };
        for (tools) |tool| {
            const summaries = try self.store.listSessions(tool, 100, 0);
            defer self.allocator.free(summaries);
            for (summaries) |summary| {
                if (std.mem.eql(u8, summary.model, model)) {
                    const copy = try self.copySessionSummary(summary);
                    try results.append(copy);
                    if (results.items.len >= limit) break;
                }
            }
            if (results.items.len >= limit) break;
        }

        return try results.toOwnedSlice();
    }

    /// Get total token usage across all sessions
    pub fn getTotalTokenUsage(self: *UnifiedSessionPreview) !TokenUsage {
        var total = TokenUsage{};

        const tools = [_]CliTool{ .claude_code, .codex, .gemini_cli, .opencode, .openclaw };
        for (tools) |tool| {
            const summaries = try self.store.listSessions(tool, 1000, 0);
            defer self.allocator.free(summaries);

            for (summaries) |summary| {
                // We need to get full session for token usage
                if (self.store.getSession(summary.id)) |session| {
                    total.prompt_tokens += session.token_usage.prompt_tokens;
                    total.completion_tokens += session.token_usage.completion_tokens;
                    total.total_tokens += session.token_usage.total_tokens;
                }
            }
        }

        return total;
    }

    /// Copy a SessionSummary to our allocator
    fn copySessionSummary(self: *UnifiedSessionPreview, original: SessionSummary) !SessionSummary {
        return .{
            .id = try self.allocator.dupe(u8, original.id),
            .tool = original.tool,
            .title = try self.allocator.dupe(u8, original.title),
            .provider = try self.allocator.dupe(u8, original.provider),
            .model = try self.allocator.dupe(u8, original.model),
            .message_count = original.message_count,
            .created_at = original.created_at,
            .updated_at = original.updated_at,
            .archived = original.archived,
            .first_user_message = if (original.first_user_message) |m| try self.allocator.dupe(u8, m) else null,
            .last_message_preview = if (original.last_message_preview) |m| try self.allocator.dupe(u8, m) else null,
        };
    }
};
