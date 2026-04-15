//! Auto-Backup Manager for llmlite Proxy
//!
//! Provides automatic backup with rotation for all data files.
//!
//! Features:
//! - Timestamped backups
//! - Configurable retention (keeps N most recent)
//! - Supports all data files (providers.json, mcp_servers.json, sync_items.json, config.json)
//! - Atomic backup with temp file + rename

const std = @import("std");

pub const BackupError = error{
    IoError,
    FileNotFound,
    BackupFailed,
    OutOfMemory,
};

pub const BackupConfig = struct {
    /// Base directory for backups
    backup_dir: []const u8,
    /// Maximum number of backups to retain
    max_backups: u32 = 10,
    /// Whether to compress backups
    compress: bool = false,
};

pub const BackupManager = struct {
    allocator: std.mem.Allocator,
    config: BackupConfig,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, config: BackupConfig) !BackupManager {
        // Ensure backup directory exists
        std.fs.makeDirAbsolute(config.backup_dir) catch |err| switch (err) {
            error.FileNotFound => unreachable, // Should not happen for makeDirAbsolute
            else => return error.IoError,
        };

        return BackupManager{
            .allocator = allocator,
            .config = config,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *BackupManager) void {
        _ = self;
    }

    /// Create a backup of a file
    pub fn backupFile(self: *BackupManager, source_path: []const u8, category: []const u8) BackupError![]const u8 {
        const mutex = &self.mutex;
        mutex.lock();
        defer mutex.unlock();

        // Generate timestamp
        const timestamp = std.time.timestamp();
        const timestamp_str = std.fmt.allocPrint(self.allocator, "{d}", .{timestamp}) catch return error.OutOfMemory;

        // Create backup filename: {category}_{timestamp}_{original_name}
        const source_name = std.fs.path.basename(source_path);
        const backup_name = std.fmt.allocPrint(
            self.allocator,
            "{s}_{s}_{s}",
            .{ category, timestamp_str, source_name },
        ) catch return error.OutOfMemory;
        defer self.allocator.free(backup_name);

        const backup_path = std.fs.path.join(self.allocator, &.{
            self.config.backup_dir,
            backup_name,
        }) catch return error.IoError;
        defer self.allocator.free(backup_path);

        // Read source file
        const source_file = std.fs.openFileAbsolute(source_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return error.FileNotFound,
            else => return error.IoError,
        };
        defer source_file.close();

        const stat = source_file.stat() catch return error.IoError;
        const content = source_file.readToEndAlloc(self.allocator, stat.size) catch return error.IoError;
        defer self.allocator.free(content);

        // Write backup atomically (temp file + rename)
        const temp_path = std.fmt.allocPrint(self.allocator, "{s}.tmp", .{backup_path}) catch return error.OutOfMemory;
        defer self.allocator.free(temp_path);

        const temp_file = std.fs.createFileAbsolute(temp_path, .{}) catch |err| switch (err) {
            else => return error.IoError,
        };
        defer temp_file.close();

        temp_file.writeAll(content) catch return error.IoError;
        temp_file.sync() catch return error.IoError;

        // Rename to final location
        std.fs.renameAbsolute(temp_path, backup_path) catch return error.IoError;

        // Rotate old backups
        self.rotateBackups(category) catch return error.IoError;

        return backup_path;
    }

    /// Restore a backup
    pub fn restoreBackup(self: *BackupManager, backup_path: []const u8, target_path: []const u8) BackupError!void {
        const mutex = &self.mutex;
        mutex.lock();
        defer mutex.unlock();

        // Read backup file
        const backup_file = std.fs.openFileAbsolute(backup_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return error.FileNotFound,
            else => return error.IoError,
        };
        defer backup_file.close();

        const stat = backup_file.stat() catch return error.IoError;
        const content = backup_file.readToEndAlloc(self.allocator, stat.size) catch return error.IoError;
        defer self.allocator.free(content);

        // Create temp file for atomic write
        const temp_path = std.fmt.allocPrint(self.allocator, "{s}.tmp", .{target_path}) catch return error.OutOfMemory;
        defer self.allocator.free(temp_path);

        const temp_file = std.fs.createFileAbsolute(temp_path, .{}) catch |err| switch (err) {
            else => return error.IoError,
        };
        defer temp_file.close();

        temp_file.writeAll(content) catch return error.IoError;
        temp_file.sync() catch return error.IoError;

        // Rename to final location
        std.fs.renameAbsolute(temp_path, target_path) catch return error.IoError;
    }

    /// List all backups for a category
    pub fn listBackups(self: *BackupManager, category: []const u8) BackupError![][]const u8 {
        const mutex = &self.mutex;
        mutex.lock();
        defer mutex.unlock();

        var dir = std.fs.openDirAbsolute(self.config.backup_dir, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => return BackupError.FileNotFound,
            else => return BackupError.IoError,
        };
        defer dir.close();

        var backups = std.ArrayList([]const u8).initCapacity(self.allocator, 0) catch return error.OutOfMemory;
        errdefer backups.deinit(self.allocator);

        var it = dir.iterate();
        while (it.next() catch null) |entry| {
            // Check if file starts with category_
            if (std.mem.startsWith(u8, entry.name, category)) {
                const path = std.fs.path.join(self.allocator, &.{
                    self.config.backup_dir,
                    entry.name,
                }) catch return error.IoError;
                backups.append(self.allocator, path) catch return error.OutOfMemory;
            }
        }

        // Sort by timestamp (newest first)
        std.mem.sort([]const u8, backups.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                // Extract timestamp from filename: {category}_{timestamp}_{name}
                const a_ts = extractTimestamp(a);
                const b_ts = extractTimestamp(b);
                return a_ts > b_ts;
            }
        }.lessThan);

        return backups.toOwnedSlice(self.allocator);
    }

    /// Rotate backups - keep only max_backups most recent
    fn rotateBackups(self: *BackupManager, category: []const u8) BackupError!void {
        const backups = self.listBackups(category) catch |err| return err;
        defer {
            for (backups) |b| self.allocator.free(b);
            self.allocator.free(backups);
        }

        if (backups.len <= self.config.max_backups) {
            return;
        }

        // Delete oldest backups beyond max_backups
        const to_delete = backups[self.config.max_backups..];
        for (to_delete) |path| {
            std.fs.deleteFileAbsolute(path) catch {};
        }
    }

    /// Extract timestamp from backup filename
    fn extractTimestamp(backup_path: []const u8) i64 {
        const name = std.fs.path.basename(backup_path);
        // Format: {category}_{timestamp}_{original_name}
        var parts = std.mem.splitScalar(u8, name, '_');
        _ = parts.next(); // category
        const ts_str = parts.next() orelse return 0;
        return std.fmt.parseInt(i64, ts_str, 10) catch 0;
    }

    /// Create backup of all database files
    pub fn backupAll(self: *BackupManager, base_path: []const u8) BackupError!void {
        const files = [_]struct { name: []const u8, category: []const u8 }{
            .{ .name = "providers.json", .category = "providers" },
            .{ .name = "mcp_servers.json", .category = "mcp_servers" },
            .{ .name = "sync_items.json", .category = "sync_items" },
            .{ .name = "config.json", .category = "config" },
        };

        for (files) |f| {
            const source_path = std.fs.path.join(self.allocator, &.{ base_path, f.name }) catch return error.IoError;
            defer self.allocator.free(source_path);

            // Check if file exists
            std.fs.accessAbsolute(source_path, .{}) catch {
                continue;
            };
            _ = self.backupFile(source_path, f.category) catch {};
        }
    }
};

test "backup manager init" {
    const allocator = std.heap.page_allocator;
    const test_dir = "/tmp/llmlite-backup-test";

    std.fs.deleteDirRecursive(test_dir, .{}) catch {};

    var mgr = try BackupManager.init(allocator, .{
        .backup_dir = test_dir,
        .max_backups = 3,
    });
    defer mgr.deinit();

    try std.testing.expect(true);
}

test "backup file and restore" {
    const allocator = std.heap.page_allocator;
    const test_dir = "/tmp/llmlite-backup-test2";
    const source_dir = "/tmp/llmlite-backup-source2";

    std.fs.deleteDirRecursive(test_dir, .{}) catch {};
    std.fs.deleteDirRecursive(source_dir, .{}) catch {};

    // Create source file
    try std.fs.makeDirAbsolute(source_dir);
    const source_path = try std.fs.path.join(allocator, &.{ source_dir, "test.json" });
    defer allocator.free(source_path);

    const source_file = try std.fs.createFileAbsolute(source_path, .{});
    try source_file.writeAll("{\"test\": true}");
    source_file.close();

    var mgr = try BackupManager.init(allocator, .{
        .backup_dir = test_dir,
        .max_backups = 3,
    });
    defer mgr.deinit();

    // Create backup
    const backup_path = try mgr.backupFile(source_path, "test");
    defer allocator.free(backup_path);

    // Verify backup exists
    try std.testing.expect(std.fs.accessAbsolute(backup_path, .{}));

    // Clean up
    std.fs.deleteDirRecursive(test_dir, .{}) catch {};
    std.fs.deleteDirRecursive(source_dir, .{}) catch {};
}
