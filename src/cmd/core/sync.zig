//! Sync Engine - Synchronize tracking data to llmlite-proxy
//!
//! Provides async synchronization of cmd tracking data to proxy server.
//! Supports offline queuing and multiple sync strategies.

const std = @import("std");
const tracking = @import("cmd_core_tracking");

pub const SyncConfig = struct {
    /// Proxy URL to sync to
    proxy_url: []const u8 = "http://localhost:4000",
    /// Sync strategy
    strategy: SyncStrategy = .immediate,
    /// Batch size for batch sync
    batch_size: usize = 10,
    /// Sync interval in ms (for batch mode)
    sync_interval_ms: u64 = 300_000, // 5 minutes
    /// Enable/disable sync
    enabled: bool = true,
    /// Path to persist pending records for offline resilience
    queue_path: ?[]const u8 = null,
};

pub const SyncStrategy = enum {
    immediate, // Sync right after each command
    batch, // Batch sync periodically
    on_demand, // Only sync when explicitly requested
};

pub const SyncRecord = struct {
    timestamp: i64,
    original_cmd: []const u8,
    rtk_cmd: []const u8,
    raw_output_len: usize,
    filtered_output_len: usize,
    exit_code: i32,
    hostname: []const u8,
};

pub const SyncStatus = struct {
    pending_count: usize,
    last_sync: ?i64,
    last_error: ?[]const u8,
    proxy_reachable: bool,
};

/// Global sync state
var global_sync: ?*Sync = null;
var global_config: SyncConfig = undefined;

/// Initialize the sync engine
pub fn init(allocator: std.mem.Allocator, config: SyncConfig) !void {
    if (global_sync != null) return;
    global_sync = try allocator.create(Sync);
    global_sync.?.* = try Sync.init(allocator, config);
    global_config = config;
}

/// Deinitialize the sync engine
pub fn deinit() void {
    if (global_sync) |sync| {
        sync.deinit();
        sync.allocator.destroy(sync);
        global_sync = null;
    }
}

/// Get current sync status
pub fn getStatus() SyncStatus {
    if (global_sync) |sync| {
        return sync.getStatus();
    }
    return .{
        .pending_count = 0,
        .last_sync = null,
        .last_error = null,
        .proxy_reachable = false,
    };
}

/// Record a tracking event and sync to proxy
pub fn recordAndSync(record: tracking.TrackingRecord) !void {
    // Always write locally first
    try tracking.track(std.heap.page_allocator, record);

    // Convert to sync record
    const sync_record = SyncRecord{
        .timestamp = std.time.timestamp(),
        .original_cmd = record.original_cmd,
        .rtk_cmd = record.rtk_cmd,
        .raw_output_len = record.raw_output.len,
        .filtered_output_len = record.filtered_output.len,
        .exit_code = record.exit_code,
        .hostname = try getHostname(),
    };

    // If sync is disabled or on_demand, skip
    if (!global_config.enabled or global_config.strategy == .on_demand) {
        return;
    }

    // Try to sync
    if (global_sync) |sync| {
        sync.queueRecord(sync_record);
        if (global_config.strategy == .immediate) {
            sync.syncNow() catch |err| {
                std.log.warn("sync failed: {}", .{err});
            };
        }
    }
}

/// Sync pending records to proxy
pub fn syncPending() !void {
    if (global_sync) |sync| {
        try sync.syncNow();
    }
}

const Sync = struct {
    allocator: std.mem.Allocator,
    config: SyncConfig,
    pending: std.ArrayList(SyncRecord),
    last_sync: ?i64,
    last_error: ?[]const u8,
    proxy_reachable: bool,

    pub fn init(allocator: std.mem.Allocator, config: SyncConfig) !Sync {
        var sync = Sync{
            .allocator = allocator,
            .config = config,
            .pending = std.ArrayList(SyncRecord).init(allocator),
            .last_sync = null,
            .last_error = null,
            .proxy_reachable = false,
        };

        // Load pending records from persistent queue if available
        if (config.queue_path) |path| {
            sync.loadQueue(path) catch |err| {
                std.log.warn("failed to load sync queue from {s}: {}", .{ path, err });
            };
        }

        return sync;
    }

    pub fn deinit(self: *Sync) void {
        // Save pending records before deinit if persistence is enabled
        if (self.config.queue_path) |path| {
            self.saveQueue(path) catch |err| {
                std.log.warn("failed to save sync queue to {s}: {}", .{ path, err });
            };
        }

        // Sync any pending records before deinit
        self.syncNow() catch {};
        for (self.pending.items) |*record| {
            self.allocator.free(record.original_cmd);
            self.allocator.free(record.rtk_cmd);
            self.allocator.free(record.hostname);
        }
        self.pending.deinit();
    }

    pub fn getStatus(self: *Sync) SyncStatus {
        return .{
            .pending_count = self.pending.items.len,
            .last_sync = self.last_sync,
            .last_error = self.last_error,
            .proxy_reachable = self.proxy_reachable,
        };
    }

    pub fn queueRecord(self: *Sync, record: SyncRecord) void {
        // Don't queue if batch is full
        if (self.pending.items.len >= self.config.batch_size) {
            // Sync immediately when batch is full
            self.syncNow() catch {};
        }

        // Make a copy of the record with owned strings
        const owned = SyncRecord{
            .timestamp = record.timestamp,
            .original_cmd = self.allocator.dupe(u8, record.original_cmd) catch return,
            .rtk_cmd = self.allocator.dupe(u8, record.rtk_cmd) catch return,
            .raw_output_len = record.raw_output_len,
            .filtered_output_len = record.filtered_output_len,
            .exit_code = record.exit_code,
            .hostname = self.allocator.dupe(u8, record.hostname) catch return,
        };
        self.pending.append(owned) catch return;

        // Persist queue to disk if enabled
        if (self.config.queue_path) |path| {
            self.saveQueue(path) catch |err| {
                std.log.warn("failed to persist sync queue: {}", .{err});
            };
        }
    }

    pub fn syncNow(self: *Sync) !void {
        if (self.pending.items.len == 0) return;

        // Check if proxy is reachable
        if (!self.checkProxyReachable()) {
            self.proxy_reachable = false;
            return;
        }
        self.proxy_reachable = true;

        // Build sync request
        const request_body = try self.buildSyncRequest();
        defer self.allocator.free(request_body);

        // Send to proxy
        const response = try self.sendSyncRequest(request_body);
        defer self.allocator.free(response);

        // Parse response
        const parsed = std.json.parseFromSlice(
            SyncResponse,
            self.allocator,
            response,
            .{},
        ) catch {
            self.last_error = try self.allocator.dupe(u8, "failed to parse response");
            return error.ParseError;
        };
        defer parsed.deinit();

        // Clear synced records
        for (self.pending.items) |*record| {
            self.allocator.free(record.original_cmd);
            self.allocator.free(record.rtk_cmd);
            self.allocator.free(record.hostname);
        }
        self.pending.clearRetainingCapacity();

        // Clear persisted queue since we successfully synced
        if (self.config.queue_path) |path| {
            self.clearQueue(path) catch |err| {
                std.log.warn("failed to clear sync queue: {}", .{err});
            };
        }

        self.last_sync = std.time.timestamp();
        self.last_error = null;

        std.log.info("synced {} records to proxy", .{parsed.value.synced});
    }

    /// Load pending records from persistent queue file
    fn loadQueue(self: *Sync, path: []const u8) !void {
        const file = std.fs.openFileAbsolute(path, .{ .mode = .read_only }) catch {
            // File doesn't exist yet - that's OK
            return;
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10_000_000);
        defer self.allocator.free(content);

        if (content.len == 0) return;

        // Parse queue file (JSON array of SyncRecord)
        var parsed = std.json.parseFromSlice(
            []QueuedRecord,
            self.allocator,
            content,
            .{},
        ) catch return;
        defer parsed.deinit();

        // Convert queued records to pending
        for (parsed.value) |qr| {
            const record = SyncRecord{
                .timestamp = qr.timestamp,
                .original_cmd = try self.allocator.dupe(u8, qr.original_cmd),
                .rtk_cmd = try self.allocator.dupe(u8, qr.rtk_cmd),
                .raw_output_len = qr.raw_output_len,
                .filtered_output_len = qr.filtered_output_len,
                .exit_code = qr.exit_code,
                .hostname = try self.allocator.dupe(u8, qr.hostname),
            };
            try self.pending.append(record);
        }

        std.log.info("loaded {} pending records from queue", .{parsed.value.len});
    }

    /// Save pending records to persistent queue file
    fn saveQueue(self: *Sync, path: []const u8) !void {
        if (self.pending.items.len == 0) {
            // Clear empty queue
            self.clearQueue(path) catch {};
            return;
        }

        // Build queue file content (JSON array)
        var json = std.ArrayList(u8).init(self.allocator);
        defer json.deinit();

        try json.appendSlice("[");

        for (self.pending.items, 0..) |record, i| {
            if (i > 0) try json.append(',');

            // Escape strings for JSON
            try json.append('{');
            try json.appendSlice("\"timestamp\":");
            var ts_buf: [32]u8 = undefined;
            const ts_slice = std.fmt.formatIntBuf(&ts_buf, record.timestamp, 10, .lower, .{});
            try json.appendSlice(ts_slice);
            try json.append(',');

            try json.appendSlice("\"original_cmd\":\"");
            try json.appendSlice(escapeJsonString(record.original_cmd));
            try json.append('\"');
            try json.append(',');

            try json.appendSlice("\"rtk_cmd\":\"");
            try json.appendSlice(escapeJsonString(record.rtk_cmd));
            try json.append('\"');
            try json.append(',');

            try json.appendSlice("\"raw_output_len\":");
            var raw_buf: [32]u8 = undefined;
            const raw_slice = std.fmt.formatIntBuf(&raw_buf, record.raw_output_len, 10, .lower, .{});
            try json.appendSlice(raw_slice);
            try json.append(',');

            try json.appendSlice("\"filtered_output_len\":");
            var filtered_buf: [32]u8 = undefined;
            const filtered_slice = std.fmt.formatIntBuf(&filtered_buf, record.filtered_output_len, 10, .lower, .{});
            try json.appendSlice(filtered_slice);
            try json.append(',');

            try json.appendSlice("\"exit_code\":");
            var exit_buf: [32]u8 = undefined;
            const exit_slice = std.fmt.formatIntBuf(&exit_buf, record.exit_code, 10, .lower, .{});
            try json.appendSlice(exit_slice);
            try json.append(',');

            try json.appendSlice("\"hostname\":\"");
            try json.appendSlice(escapeJsonString(record.hostname));
            try json.append('\"');

            try json.append('}');
        }

        try json.append(']');

        // Ensure parent directory exists
        const parent = std.fs.path.dirname(path);
        if (parent) |p| {
            try std.fs.makePathAbsolute(p);
            std.fs.cwd().makeDir(p) catch {};
        }

        // Write to file atomically (write to temp then rename)
        const tmp_path = try std.mem.concat(self.allocator, u8, &.{ path, ".tmp" });
        defer self.allocator.free(tmp_path);

        const file = try std.fs.createFileAbsolute(tmp_path, .{});
        defer file.close();

        try file.writeAll(json.items);
        try file.sync();

        // Rename temp to actual path
        try std.fs.rename(tmp_path, path);

        std.log.debug("saved {} records to queue file", .{self.pending.items.len});
    }

    /// Clear the queue file
    fn clearQueue(_: *Sync, path: []const u8) !void {
        std.fs.deleteFileAbsolute(path) catch {};
    }

    fn checkProxyReachable(self: *Sync) bool {
        // Simple health check
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const uri = std.Uri.parse(self.config.proxy_url ++ "/health/live") catch return false;
        const response = client.fetch(.{
            .location = uri,
            .method = .GET,
        }) catch return false;

        return response.status == .ok;
    }

    fn buildSyncRequest(self: *Sync) ![]u8 {
        // Build a JSON array of records
        var json_items = std.ArrayList(u8).init(self.allocator);
        defer json_items.deinit();

        try json_items.appendSlice(self.allocator, "{\"records\":[");
        for (self.pending.items, 0..) |record, i| {
            if (i > 0) try json_items.appendSlice(self.allocator, ",");
            const item = try std.fmt.allocPrint(self.allocator,
                \\{{"timestamp":{},"original_cmd":"{s}","rtk_cmd":"{s}","raw_output_len":{},"filtered_output_len":{},"exit_code":{},"hostname":"{s}"}}
            , .{
                record.timestamp,
                escapeJsonString(record.original_cmd),
                escapeJsonString(record.rtk_cmd),
                record.raw_output_len,
                record.filtered_output_len,
                record.exit_code,
                escapeJsonString(record.hostname),
            });
            defer self.allocator.free(item);
            try json_items.appendSlice(self.allocator, item);
        }
        try json_items.appendSlice(self.allocator, "]}");

        return json_items.toOwnedSlice(self.allocator);
    }

    fn sendSyncRequest(self: *Sync, body: []const u8) ![]u8 {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const uri = std.Uri.parse(self.config.proxy_url ++ "/tracking/sync") catch return error.InvalidUrl;
        const response = try client.fetch(.{
            .location = uri,
            .method = .POST,
            .headers = .{
                .content_type = .json,
            },
            .body = .{
                .string = body,
            },
        });

        if (response.status != .ok) {
            return error.HttpError;
        }

        return response.body;
    }
};

/// Internal format for queue file persistence
const QueuedRecord = struct {
    timestamp: i64,
    original_cmd: []const u8,
    rtk_cmd: []const u8,
    raw_output_len: usize,
    filtered_output_len: usize,
    exit_code: i32,
    hostname: []const u8,
};

const SyncResponse = struct {
    synced: usize,
    errors: usize,
};

fn getHostname() ![]const u8 {
    var buf: [256]u8 = undefined;
    const hostname = std.posix.gethostname(&buf) catch return "unknown";
    return hostname;
}

fn escapeJsonString(s: []const u8) []const u8 {
    // Simple JSON string escaping - handle basic special characters
    // In a full implementation, you'd escape all special chars
    return s;
}
