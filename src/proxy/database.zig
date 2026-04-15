//! Database Layer for llmlite Proxy
//!
//! JSON file-based database providing SQLite-like operations.
//! This is a zero-dependency persistence layer that stores:
//! - providers.json: Provider configurations
//! - mcp_servers.json: MCP server definitions
//! - sync_items.json: Sync item configurations
//! - sessions/: Session history files
//! - config.json: Global configuration
//!
//! Design goals:
//! - Zero external dependencies
//! - Atomic writes (temp file + rename)
//! - Thread-safe operations
//! - ACID-like semantics via atomic file operations

const std = @import("std");
const preset = @import("preset");
const mcp_manager = @import("mcp_manager");
const sync_engine = @import("sync_engine");
const session_store = @import("session_store");

pub const CliTool = preset.CliTool;
pub const ProviderPreset = preset.ProviderPreset;
pub const McpServer = mcp_manager.McpServer;
pub const McpServerState = mcp_manager.McpServerState;
pub const SyncItem = sync_engine.SyncItem;
pub const Session = session_store.Session;

/// Database errors
pub const DbError = error{
    FileNotFound,
    InvalidFormat,
    IoError,
    SerializationError,
    ItemNotFound,
    ItemAlreadyExists,
};

/// Database configuration
pub const DbConfig = struct {
    /// Base directory for all data
    base_path: []const u8,
    /// Enable atomic writes (temp file + rename)
    atomic_writes: bool = true,
    /// Sync to disk after each write
    sync_on_write: bool = false,
};

/// Main database struct
pub const Database = struct {
    allocator: std.mem.Allocator,
    config: DbConfig,
    mutex: std.Thread.Mutex,

    // Paths
    providers_path: []const u8,
    mcp_servers_path: []const u8,
    sync_items_path: []const u8,
    sessions_dir: []const u8,
    config_file_path: []const u8,

    // In-memory caches (loaded on init)
    providers: std.StringArrayHashMap(ProviderRecord),
    mcp_servers: std.StringArrayHashMap(McpServerRecord),
    sync_items: std.StringArrayHashMap(SyncItemRecord),
    global_config: GlobalConfig,

    pub fn init(allocator: std.mem.Allocator, config: DbConfig) !Database {
        const base_path = try allocator.dupe(u8, config.base_path);
        errdefer allocator.free(base_path);

        // Initialize paths
        const providers_path = try std.fmt.allocPrint(allocator, "{s}/providers.json", .{base_path});
        errdefer allocator.free(providers_path);

        const mcp_servers_path = try std.fmt.allocPrint(allocator, "{s}/mcp_servers.json", .{base_path});
        errdefer allocator.free(mcp_servers_path);

        const sync_items_path = try std.fmt.allocPrint(allocator, "{s}/sync_items.json", .{base_path});
        errdefer allocator.free(sync_items_path);

        const sessions_dir = try std.fmt.allocPrint(allocator, "{s}/sessions", .{base_path});
        errdefer allocator.free(sessions_dir);

        const config_file_path = try std.fmt.allocPrint(allocator, "{s}/config.json", .{base_path});
        errdefer allocator.free(config_file_path);

        var db = Database{
            .allocator = allocator,
            .config = config,
            .mutex = std.Thread.Mutex{},
            .providers_path = providers_path,
            .mcp_servers_path = mcp_servers_path,
            .sync_items_path = sync_items_path,
            .sessions_dir = sessions_dir,
            .config_file_path = config_file_path,
            .providers = std.StringArrayHashMap(ProviderRecord).init(allocator),
            .mcp_servers = std.StringArrayHashMap(McpServerRecord).init(allocator),
            .sync_items = std.StringArrayHashMap(SyncItemRecord).init(allocator),
            .global_config = .{},
        };

        // Ensure directories exist
        try db.ensureDir(base_path);
        try db.ensureDir(sessions_dir);

        // Load existing data
        db.load() catch |e| {
            std.log.warn("failed to load existing database: {}, starting fresh", .{e});
        };

        return db;
    }

    pub fn deinit(self: *Database) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.allocator.free(self.config.base_path);
        self.allocator.free(self.providers_path);
        self.allocator.free(self.mcp_servers_path);
        self.allocator.free(self.sync_items_path);
        self.allocator.free(self.sessions_dir);
        self.allocator.free(self.config_file_path);

        {
            var it = self.providers.iterator();
            while (it.next()) |entry| {
                self.freeProviderRecord(entry.value_ptr.*);
            }
            self.providers.deinit();
        }

        {
            var it = self.mcp_servers.iterator();
            while (it.next()) |entry| {
                self.freeMcpServerRecord(entry.value_ptr.*);
            }
            self.mcp_servers.deinit();
        }

        {
            var it = self.sync_items.iterator();
            while (it.next()) |entry| {
                self.freeSyncItemRecord(entry.value_ptr.*);
            }
            self.sync_items.deinit();
        }

        self.freeGlobalConfig(self.global_config);
    }

    fn ensureDir(self: *Database, path: []const u8) !void {
        _ = self;
        try std.fs.cwd().makePath(path);
    }

    /// Load all data from disk
    pub fn load(self: *Database) !void {
        self.loadProviders() catch |e| {
            std.log.debug("no providers to load: {}", .{e});
        };
        self.loadMcpServers() catch |e| {
            std.log.debug("no mcp_servers to load: {}", .{e});
        };
        self.loadSyncItems() catch |e| {
            std.log.debug("no sync_items to load: {}", .{e});
        };
        self.loadGlobalConfig() catch |e| {
            std.log.debug("no global config to load: {}", .{e});
        };
    }

    /// Save all data to disk
    pub fn save(self: *Database) !void {
        try self.saveProviders();
        try self.saveMcpServers();
        try self.saveSyncItems();
        try self.saveGlobalConfig();
    }

    // ============ Providers ============

    fn loadProviders(self: *Database) !void {
        const content = try self.readFile(self.providers_path);
        defer self.allocator.free(content);

        const parsed = try std.json.parseFromSlice([]const ProviderRecord, self.allocator, content, .{});
        defer parsed.deinit();

        for (parsed.value) |record| {
            const record_copy = try self.cloneProviderRecord(record);
            try self.providers.put(record_copy.id, record_copy);
        }
    }

    fn saveProviders(self: *Database) !void {
        var records = std.ArrayList(ProviderRecord).init(self.allocator);
        defer records.deinit();

        var it = self.providers.iterator();
        while (it.next()) |entry| {
            try records.append(entry.value_ptr.*);
        }

        const content = try std.json.stringifyAlloc(self.allocator, records.items, .{
            .whitespace = .indent_tab,
        });
        defer self.allocator.free(content);

        try self.writeFileAtomic(self.providers_path, content);
    }

    pub fn createProvider(self: *Database, record: ProviderRecord) !void {
        if (self.providers.contains(record.id)) {
            return DbError.ItemAlreadyExists;
        }
        const record_copy = try self.cloneProviderRecord(record);
        errdefer self.freeProviderRecord(record_copy);
        try self.providers.put(record_copy.id, record_copy);
        try self.saveProviders();
    }

    pub fn getProvider(self: *Database, id: []const u8) ?*const ProviderRecord {
        return self.providers.get(id);
    }

    pub fn updateProvider(self: *Database, record: ProviderRecord) !void {
        if (!self.providers.contains(record.id)) {
            return DbError.ItemNotFound;
        }
        const existing = self.providers.getPtr(record.id).?;
        self.freeProviderRecord(existing.*);
        existing.* = try self.cloneProviderRecord(record);
        try self.saveProviders();
    }

    pub fn deleteProvider(self: *Database, id: []const u8) !void {
        if (self.providers.fetchRemove(id)) |entry| {
            self.freeProviderRecord(entry.value);
            try self.saveProviders();
        }
    }

    pub fn listProviders(self: *Database) []ProviderRecord {
        var result = std.ArrayList(ProviderRecord).init(self.allocator);
        var it = self.providers.iterator();
        while (it.next()) |entry| {
            result.append(entry.value_ptr.*) catch {};
        }
        return result.toOwnedSlice();
    }

    fn cloneProviderRecord(self: *Database, record: ProviderRecord) !ProviderRecord {
        _ = self;
        return .{
            .id = record.id,
            .name = record.name,
            .provider_type = record.provider_type,
            .base_url = record.base_url,
            .api_key = record.api_key,
            .enabled = record.enabled,
            .is_default = record.is_default,
            .created_at = record.created_at,
            .updated_at = record.updated_at,
            .settings = record.settings,
        };
    }

    fn freeProviderRecord(self: *Database, record: ProviderRecord) void {
        _ = self;
        _ = record;
    }

    // ============ MCP Servers ============

    fn loadMcpServers(self: *Database) !void {
        const content = try self.readFile(self.mcp_servers_path);
        defer self.allocator.free(content);

        const parsed = try std.json.parseFromSlice([]const McpServerRecord, self.allocator, content, .{});
        defer parsed.deinit();

        for (parsed.value) |record| {
            const record_copy = try self.cloneMcpServerRecord(record);
            try self.mcp_servers.put(record_copy.name, record_copy);
        }
    }

    fn saveMcpServers(self: *Database) !void {
        var records = std.ArrayList(McpServerRecord).init(self.allocator);
        defer records.deinit();

        var it = self.mcp_servers.iterator();
        while (it.next()) |entry| {
            try records.append(entry.value_ptr.*);
        }

        const content = try std.json.stringifyAlloc(self.allocator, records.items, .{
            .whitespace = .indent_tab,
        });
        defer self.allocator.free(content);

        try self.writeFileAtomic(self.mcp_servers_path, content);
    }

    pub fn createMcpServer(self: *Database, record: McpServerRecord) !void {
        if (self.mcp_servers.contains(record.name)) {
            return DbError.ItemAlreadyExists;
        }
        const record_copy = try self.cloneMcpServerRecord(record);
        errdefer self.freeMcpServerRecord(record_copy);
        try self.mcp_servers.put(record_copy.name, record_copy);
        try self.saveMcpServers();
    }

    pub fn getMcpServer(self: *Database, name: []const u8) ?*const McpServerRecord {
        return self.mcp_servers.get(name);
    }

    pub fn updateMcpServer(self: *Database, record: McpServerRecord) !void {
        if (!self.mcp_servers.contains(record.name)) {
            return DbError.ItemNotFound;
        }
        const existing = self.mcp_servers.getPtr(record.name).?;
        self.freeMcpServerRecord(existing.*);
        existing.* = try self.cloneMcpServerRecord(record);
        try self.saveMcpServers();
    }

    pub fn deleteMcpServer(self: *Database, name: []const u8) !void {
        if (self.mcp_servers.fetchRemove(name)) |entry| {
            self.freeMcpServerRecord(entry.value);
            try self.saveMcpServers();
        }
    }

    pub fn listMcpServers(self: *Database) []McpServerRecord {
        var result = std.ArrayList(McpServerRecord).init(self.allocator);
        var it = self.mcp_servers.iterator();
        while (it.next()) |entry| {
            result.append(entry.value_ptr.*) catch {};
        }
        return result.toOwnedSlice();
    }

    fn cloneMcpServerRecord(self: *Database, record: McpServerRecord) !McpServerRecord {
        _ = self;
        return record;
    }

    fn freeMcpServerRecord(self: *Database, record: McpServerRecord) void {
        _ = self;
        _ = record;
    }

    // ============ Sync Items ============

    fn loadSyncItems(self: *Database) !void {
        const content = try self.readFile(self.sync_items_path);
        defer self.allocator.free(content);

        const parsed = try std.json.parseFromSlice([]const SyncItemRecord, self.allocator, content, .{});
        defer parsed.deinit();

        for (parsed.value) |record| {
            const record_copy = try self.cloneSyncItemRecord(record);
            try self.sync_items.put(record_copy.id, record_copy);
        }
    }

    fn saveSyncItems(self: *Database) !void {
        var records = std.ArrayList(SyncItemRecord).init(self.allocator);
        defer records.deinit();

        var it = self.sync_items.iterator();
        while (it.next()) |entry| {
            try records.append(entry.value_ptr.*);
        }

        const content = try std.json.stringifyAlloc(self.allocator, records.items, .{
            .whitespace = .indent_tab,
        });
        defer self.allocator.free(content);

        try self.writeFileAtomic(self.sync_items_path, content);
    }

    pub fn createSyncItem(self: *Database, record: SyncItemRecord) !void {
        if (self.sync_items.contains(record.id)) {
            return DbError.ItemAlreadyExists;
        }
        const record_copy = try self.cloneSyncItemRecord(record);
        errdefer self.freeSyncItemRecord(record_copy);
        try self.sync_items.put(record_copy.id, record_copy);
        try self.saveSyncItems();
    }

    pub fn getSyncItem(self: *Database, id: []const u8) ?*const SyncItemRecord {
        return self.sync_items.get(id);
    }

    pub fn updateSyncItem(self: *Database, record: SyncItemRecord) !void {
        if (!self.sync_items.contains(record.id)) {
            return DbError.ItemNotFound;
        }
        const existing = self.sync_items.getPtr(record.id).?;
        self.freeSyncItemRecord(existing.*);
        existing.* = try self.cloneSyncItemRecord(record);
        try self.saveSyncItems();
    }

    pub fn deleteSyncItem(self: *Database, id: []const u8) !void {
        if (self.sync_items.fetchRemove(id)) |entry| {
            self.freeSyncItemRecord(entry.value);
            try self.saveSyncItems();
        }
    }

    pub fn listSyncItems(self: *Database) []SyncItemRecord {
        var result = std.ArrayList(SyncItemRecord).init(self.allocator);
        var it = self.sync_items.iterator();
        while (it.next()) |entry| {
            result.append(entry.value_ptr.*) catch {};
        }
        return result.toOwnedSlice();
    }

    fn cloneSyncItemRecord(self: *Database, record: SyncItemRecord) !SyncItemRecord {
        _ = self;
        return record;
    }

    fn freeSyncItemRecord(self: *Database, record: SyncItemRecord) void {
        _ = self;
        _ = record;
    }

    // ============ Global Config ============

    fn loadGlobalConfig(self: *Database) !void {
        const content = try self.readFile(self.config_file_path);
        defer self.allocator.free(content);

        const parsed = try std.json.parseFromSlice(GlobalConfig, self.allocator, content, .{});
        defer parsed.deinit();

        self.freeGlobalConfig(self.global_config);
        self.global_config = parsed.value;
    }

    fn saveGlobalConfig(self: *Database) !void {
        const content = try std.json.stringifyAlloc(self.allocator, self.global_config, .{
            .whitespace = .indent_tab,
        });
        defer self.allocator.free(content);

        try self.writeFileAtomic(self.config_file_path, content);
    }

    pub fn getGlobalConfig(self: *Database) *GlobalConfig {
        return &self.global_config;
    }

    pub fn updateGlobalConfig(self: *Database, config: GlobalConfig) !void {
        self.freeGlobalConfig(self.global_config);
        self.global_config = config;
        try self.saveGlobalConfig();
    }

    fn freeGlobalConfig(self: *Database, config: GlobalConfig) void {
        _ = self;
        _ = config;
    }

    // ============ Sessions (file-based) ============

    pub fn saveSession(self: *Database, session: *const Session) !void {
        const file_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}.json",
            .{ self.sessions_dir, session.id },
        );
        defer self.allocator.free(file_path);

        const content = try std.json.stringifyAlloc(self.allocator, session, .{
            .whitespace = .indent_tab,
        });
        defer self.allocator.free(content);

        try self.writeFileAtomic(file_path, content);
    }

    pub fn loadSession(self: *Database, id: []const u8) !Session {
        const file_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}.json",
            .{ self.sessions_dir, id },
        );
        defer self.allocator.free(file_path);

        const content = try self.readFile(file_path);
        defer self.allocator.free(content);

        return try std.json.parseFromSlice(Session, self.allocator, content, .{});
    }

    pub fn deleteSession(self: *Database, id: []const u8) !void {
        const file_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}.json",
            .{ self.sessions_dir, id },
        );
        defer self.allocator.free(file_path);

        std.fs.deleteFileAbsolute(file_path) catch {};
    }

    pub fn listSessions(self: *Database) ![]const []const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);
        errdefer result.deinit();

        const dir = try std.fs.cwd().openDir(self.sessions_dir, .{ .iterate = true });
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (std.mem.endsWith(u8, entry.name, ".json")) {
                const id = entry.name[0 .. entry.name.len - 5]; // Remove .json
                const id_copy = try self.allocator.dupe(u8, id);
                errdefer self.allocator.free(id_copy);
                try result.append(id_copy);
            }
        }

        return result.toOwnedSlice();
    }

    // ============ File Operations ============

    fn readFile(self: *Database, path: []const u8) ![]u8 {
        const file = std.fs.cwd().openFile(path, .{}) catch {
            return DbError.FileNotFound;
        };
        defer file.close();

        const stat = try file.stat();
        const content = try self.allocator.alloc(u8, @intCast(stat.size));
        errdefer self.allocator.free(content);

        const bytes_read = try file.readAll(content);
        if (bytes_read != stat.size) {
            return DbError.IoError;
        }

        return content;
    }

    fn writeFileAtomic(self: *Database, path: []const u8, content: []const u8) !void {
        if (!self.config.atomic_writes) {
            try self.writeFile(path, content);
            return;
        }

        // Atomic write: temp file + rename
        const temp_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}.tmp.{d}",
            .{ path, std.time.timestamp() },
        );
        defer self.allocator.free(temp_path);

        try self.writeFile(temp_path, content);

        // Atomic rename (fs.rename is atomic on POSIX)
        try std.fs.cwd().rename(temp_path, path);
    }

    fn writeFile(_: *Database, path: []const u8, content: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(content);

        if (true) { // TODO: check config.sync_on_write
            try file.sync();
        }
    }
};

// ============ Record Types ============

/// Provider configuration record (JSON-serializable)
pub const ProviderRecord = struct {
    id: []const u8,
    name: []const u8,
    provider_type: []const u8,
    base_url: []const u8,
    api_key: []const u8,
    enabled: bool = true,
    is_default: bool = false,
    created_at: i64,
    updated_at: i64,
    settings: ?[]const u8 = null, // Stored as raw JSON string
};

/// MCP Server record (JSON-serializable)
pub const McpServerRecord = struct {
    name: []const u8,
    command: []const u8,
    args: [][]const u8,
    env: []struct { key: []const u8, value: []const u8 }, // Serializable version
    enabled: bool = true,
    auto_start: bool = false,
    config_schema: ?[]const u8 = null,
};

/// Sync item record
pub const SyncItemRecord = struct {
    id: []const u8,
    name: []const u8,
    item_type: []const u8, // "skill" or "prompt"
    source_type: []const u8, // "local", "git", "webdav"
    source_url: []const u8,
    target_tools: [][]const u8,
    direction: []const u8, // "to_local", "to_remote", "bidirectional"
    auto_sync: bool = false,
    last_sync: ?i64 = null,
};

/// Global configuration
pub const GlobalConfig = struct {
    /// Default provider ID
    default_provider: ?[]const u8 = null,
    /// Active presets per CLI tool
    active_presets: std.json.Value = .null,
    /// Theme preference
    theme: []const u8 = "system",
    /// Language preference
    language: []const u8 = "en",
    /// Auto-start proxy on boot
    auto_start: bool = false,
    /// Check for updates automatically
    auto_update: bool = true,
    /// Last update check timestamp
    last_update_check: ?i64 = null,
};

test "database init and deinit" {
    const allocator = std.heap.page_allocator;
    const test_dir = "/tmp/llmlite-db-test";

    // Clean up any existing test directory
    std.fs.deleteDirRecursive(test_dir) catch {};

    var db = try Database.init(allocator, .{
        .base_path = test_dir,
        .atomic_writes = true,
    });
    defer db.deinit();

    // Should have empty initial state
    try std.testing.expectEqual(@as(usize, 0), db.providers.count());
    try std.testing.expectEqual(@as(usize, 0), db.mcp_servers.count());
    try std.testing.expectEqual(@as(usize, 0), db.sync_items.count());

    // Clean up
    std.fs.deleteDirRecursive(test_dir) catch {};
}

test "database providers CRUD" {
    const allocator = std.heap.page_allocator;
    const test_dir = "/tmp/llmlite-db-providers-test";

    std.fs.deleteDirRecursive(test_dir) catch {};

    var db = try Database.init(allocator, .{
        .base_path = test_dir,
    });
    defer db.deinit();

    // Create a provider
    const now = std.time.timestamp();
    try db.createProvider(.{
        .id = "openai-default",
        .name = "OpenAI",
        .provider_type = "openai",
        .base_url = "https://api.openai.com/v1",
        .api_key = "sk-test",
        .enabled = true,
        .is_default = true,
        .created_at = now,
        .updated_at = now,
    });

    // Verify it was created
    try std.testing.expectEqual(@as(usize, 1), db.providers.count());
    const provider = db.getProvider("openai-default").?;
    try std.testing.expectEqualStrings("OpenAI", provider.name);
    try std.testing.expectEqualStrings("openai", provider.provider_type);

    // Update the provider
    try db.updateProvider(.{
        .id = "openai-default",
        .name = "OpenAI Updated",
        .provider_type = "openai",
        .base_url = "https://api.openai.com/v1",
        .api_key = "sk-test-new",
        .enabled = true,
        .is_default = true,
        .created_at = now,
        .updated_at = now,
    });

    const updated = db.getProvider("openai-default").?;
    try std.testing.expectEqualStrings("OpenAI Updated", updated.name);

    // Delete the provider
    try db.deleteProvider("openai-default");
    try std.testing.expectEqual(@as(usize, 0), db.providers.count());

    // Clean up
    std.fs.deleteDirRecursive(test_dir) catch {};
}

test "database mcp servers CRUD" {
    const allocator = std.heap.page_allocator;
    const test_dir = "/tmp/llmlite-db-mcp-test";

    std.fs.deleteDirRecursive(test_dir) catch {};

    var db = try Database.init(allocator, .{
        .base_path = test_dir,
    });
    defer db.deinit();

    // Create an MCP server
    try db.createMcpServer(.{
        .name = "filesystem",
        .command = "npx",
        .args = &.{ "-y", "@modelcontextprotocol/server-filesystem" },
        .env = std.StringArrayHashMap([]const u8).init(allocator),
        .enabled = true,
        .auto_start = true,
    });

    // Verify
    try std.testing.expectEqual(@as(usize, 1), db.mcp_servers.count());
    const server = db.getMcpServer("filesystem").?;
    try std.testing.expectEqualStrings("npx", server.command);
    try std.testing.expectEqual(true, server.auto_start);

    // Delete
    try db.deleteMcpServer("filesystem");
    try std.testing.expectEqual(@as(usize, 0), db.mcp_servers.count());

    // Clean up
    std.fs.deleteDirRecursive(test_dir) catch {};
}

test "database global config" {
    const allocator = std.heap.page_allocator;
    const test_dir = "/tmp/llmlite-db-config-test";

    std.fs.deleteDirRecursive(test_dir) catch {};

    var db = try Database.init(allocator, .{
        .base_path = test_dir,
    });
    defer db.deinit();

    // Get default config
    const config = db.getGlobalConfig();
    try std.testing.expectEqualStrings("system", config.theme);
    try std.testing.expectEqualStrings("en", config.language);

    // Update config
    try db.updateGlobalConfig(.{
        .default_provider = "openai-default",
        .theme = "dark",
        .language = "zh",
        .auto_start = true,
    });

    // Reload and verify
    var db2 = try Database.init(allocator, .{
        .base_path = test_dir,
    });
    defer db2.deinit();

    const reloaded = db2.getGlobalConfig();
    try std.testing.expectEqualStrings("dark", reloaded.theme);
    try std.testing.expectEqualStrings("zh", reloaded.language);
    try std.testing.expectEqualStrings("openai-default", reloaded.default_provider.?);

    // Clean up
    std.fs.deleteDirRecursive(test_dir) catch {};
}
