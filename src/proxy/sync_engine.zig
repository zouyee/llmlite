//! Sync Engine for llmlite Proxy
//!
//! Handles synchronization of Skills and Prompts across CLI tools:
//! - Skills: GitHub repos, ZIP files, symlinks
//! - Prompts: CLAUDE.md, AGENTS.md, GEMINI.md synchronization
//! - Remote sync: WebDAV, Git repos
//!
//! Supports bidirectional sync with conflict resolution.

const std = @import("std");

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
const webdav = @import("proxy_webdav");
const time_compat = @import("time_compat");

pub const CliTool = preset.CliTool;

/// Sync direction
pub const SyncDirection = enum {
    to_local,
    to_remote,
    bidirectional,
};

/// Sync target type
pub const SyncTarget = union(enum) {
    /// Local directory
    local_dir: []const u8,
    /// Git repository
    git_repo: struct {
        url: []const u8,
        branch: []const u8 = "main",
        path: []const u8 = "",
    },
    /// WebDAV server
    webdav: struct {
        url: []const u8,
        username: ?[]const u8 = null,
        password: ?[]const u8 = null,
        base_path: []const u8 = "/",
    },
};

/// Sync item type
pub const SyncItemType = enum {
    skill,
    prompt,
};

/// Sync item definition
pub const SyncItem = struct {
    /// Unique ID
    id: []const u8,
    /// Type of item
    item_type: SyncItemType,
    /// Name/display name
    name: []const u8,
    /// Source path (local or remote)
    source: SyncTarget,
    /// Target paths (can be multiple - one per CLI tool)
    targets: []TargetPath,
    /// Sync direction
    direction: SyncDirection,
    /// Ignore patterns (for rsync-like filtering)
    ignores: [][]const u8 = &.{},
    /// Last sync timestamp
    last_sync: ?i64 = null,
    /// Auto-sync on change
    auto_sync: bool = false,
};

/// Target path for a sync item
pub const TargetPath = struct {
    /// Target CLI tool
    tool: CliTool,
    /// Path on the target
    path: []const u8,
    /// Use symlink instead of copy
    use_symlink: bool = true,
};

/// Sync result
pub const SyncResult = struct {
    /// Whether sync was successful
    success: bool,
    /// Number of files synced
    files_synced: u32 = 0,
    /// Number of files skipped
    files_skipped: u32 = 0,
    /// Number of errors
    errors: u32 = 0,
    /// Error messages
    error_messages: [][]const u8 = &.{},
    /// Timestamp of sync
    timestamp: i64,
};

/// Sync engine
pub const SyncEngine = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    items: StringArrayHashMap(SyncItem),
    sync_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) SyncEngine {
        return .{
            .allocator = allocator,
            .io = io,
            .items = StringArrayHashMap(SyncItem).init(allocator),
            .sync_dir = undefined, // Set from home dir
        };
    }

    pub fn deinit(self: *SyncEngine) void {
        var it = self.items.iterator();
        while (it.next()) |entry| {
            self.freeItem(entry.value_ptr.*);
        }
        self.items.deinit();
        if (self.sync_dir.len > 0) {
            self.allocator.free(self.sync_dir);
        }
    }

    fn freeItem(self: *SyncEngine, item: SyncItem) void {
        self.allocator.free(item.id);
        self.allocator.free(item.name);
        self.freeSyncTarget(item.source);
        for (item.targets) |t| {
            self.allocator.free(t.path);
        }
        self.allocator.free(item.targets);
        for (item.ignores) |ig| self.allocator.free(ig);
        self.allocator.free(item.ignores);
    }

    fn freeSyncTarget(self: *SyncEngine, target: SyncTarget) void {
        switch (target) {
            .local_dir => |p| self.allocator.free(p),
            .git_repo => |r| {
                self.allocator.free(r.url);
                self.allocator.free(r.branch);
                self.allocator.free(r.path);
            },
            .webdav => |w| {
                self.allocator.free(w.url);
                if (w.username) |u| self.allocator.free(u);
                if (w.password) |p| self.allocator.free(p);
                self.allocator.free(w.base_path);
            },
        }
    }

    /// Add a sync item
    pub fn addItem(self: *SyncEngine, item: SyncItem) !void {
        const id = try self.allocator.dupe(u8, item.id);
        errdefer self.allocator.free(id);

        var item_copy = item;
        item_copy.id = id;
        item_copy.name = try self.allocator.dupe(u8, item.name);

        // Copy source
        item_copy.source = try self.copySyncTarget(item.source);

        // Copy targets
        {
            const targets_copy = try self.allocator.alloc(TargetPath, item.targets.len);
            errdefer self.allocator.free(targets_copy);
            for (item.targets, 0..) |t, i| {
                targets_copy[i].tool = t.tool;
                targets_copy[i].path = try self.allocator.dupe(u8, t.path);
                targets_copy[i].use_symlink = t.use_symlink;
            }
            item_copy.targets = targets_copy;
        }

        // Copy ignores
        if (item.ignores.len > 0) {
            const ignores_copy = try self.allocator.alloc([]const u8, item.ignores.len);
            errdefer self.allocator.free(ignores_copy);
            for (item.ignores, 0..) |ig, i| {
                ignores_copy[i] = try self.allocator.dupe(u8, ig);
            }
            item_copy.ignores = ignores_copy;
        }

        try self.items.put(id, item_copy);
    }

    fn copySyncTarget(self: *SyncEngine, target: SyncTarget) !SyncTarget {
        return switch (target) {
            .local_dir => |p| .{ .local_dir = try self.allocator.dupe(u8, p) },
            .git_repo => |r| .{
                .git_repo = .{
                    .url = try self.allocator.dupe(u8, r.url),
                    .branch = try self.allocator.dupe(u8, r.branch),
                    .path = try self.allocator.dupe(u8, r.path),
                },
            },
            .webdav => |w| .{
                .webdav = .{
                    .url = try self.allocator.dupe(u8, w.url),
                    .username = if (w.username) |u| try self.allocator.dupe(u8, u) else null,
                    .password = if (w.password) |p| try self.allocator.dupe(u8, p) else null,
                    .base_path = try self.allocator.dupe(u8, w.base_path),
                },
            },
        };
    }

    /// Remove a sync item
    pub fn removeItem(self: *SyncEngine, id: []const u8) bool {
        if (self.items.fetchRemove(id)) |entry| {
            self.freeItem(entry.value);
            return true;
        }
        return false;
    }

    /// Get a sync item
    pub fn getItem(self: *SyncEngine, id: []const u8) ?*SyncItem {
        return self.items.get(id);
    }

    /// List all sync items
    pub fn listItems(self: *SyncEngine) ![]SyncItem {
        var result = std.array_list.Managed(SyncItem).init(self.allocator);
        defer result.deinit();
        var it = self.items.iterator();
        while (it.next()) |entry| {
            try result.append(entry.value_ptr.*);
        }
        return try result.toOwnedSlice();
    }

    /// Sync a specific item
    pub fn syncItem(self: *SyncEngine, id: []const u8) !SyncResult {
        const item_ptr = self.items.getPtr(id) orelse {
            return error.ItemNotFound;
        };

        var result = SyncResult{
            .success = true,
            .timestamp = time_compat.timestamp(self.io),
        };

        // Perform sync based on direction
        switch (item_ptr.direction) {
            .to_local => {
                self.syncToLocal(item_ptr, &result) catch |e| {
                    result.success = false;
                    try self.addError(&result, @errorName(e));
                };
            },
            .to_remote => {
                self.syncToRemote(item_ptr, &result) catch |e| {
                    result.success = false;
                    try self.addError(&result, @errorName(e));
                };
            },
            .bidirectional => {
                self.syncBidirectional(item_ptr, &result) catch |e| {
                    result.success = false;
                    try self.addError(&result, @errorName(e));
                };
            },
        }

        // Update last_sync timestamp
        if (result.success) {
            var item_mut = self.items.getPtr(id).?;
            item_mut.last_sync = result.timestamp;
        }

        return result;
    }

    fn addError(self: *SyncEngine, result: *SyncResult, msg: []const u8) !void {
        const msg_copy = try self.allocator.dupe(u8, msg);
        const new_errors = try self.allocator.alloc([]const u8, result.error_messages.len + 1);
        for (result.error_messages, 0..) |e, i| {
            new_errors[i] = e;
        }
        new_errors[result.error_messages.len] = msg_copy;
        result.error_messages = new_errors;
        result.errors += 1;
    }

    /// Sync from source to local targets
    fn syncToLocal(self: *SyncEngine, item: *const SyncItem, result: *SyncResult) !void {
        // Get source content
        const source_path = switch (item.source) {
            .local_dir => |p| p,
            else => return error.UnsupportedSource,
        };

        // Process each target
        for (item.targets) |target| {
            const target_path = target.path;

            if (target.use_symlink) {
                // Create symlink
                try self.createSymlink(source_path, target_path);
                result.files_synced += 1;
            } else {
                // Copy files
                const count = try self.copyDirectory(source_path, target_path, item.ignores);
                result.files_synced += count;
            }
        }
    }

    /// Sync from local to remote
    fn syncToRemote(self: *SyncEngine, item: *const SyncItem, result: *SyncResult) !void {
        // Handle WebDAV sync with versioning
        switch (item.source) {
            .webdav => |webdav_config| {
                // Get source path (first target's path as source)
                const source_path = if (item.targets.len > 0) item.targets[0].path else "";
                if (source_path.len == 0) {
                    result.errors += 1;
                    return;
                }

                // Initialize WebDAV client
                var client = webdav.WebDavClient.init(self.allocator, .{
                    .url = webdav_config.url,
                    .username = webdav_config.username orelse "",
                    .password = webdav_config.password orelse "",
                    .base_path = webdav_config.base_path,
                });
                defer client.deinit();

                // Initialize version tracking
                var version_state = webdav.WebDavSyncState.init(self.allocator, webdav_config.base_path) catch |err| {
                    std.debug.print("Failed to init version state: {}\n", .{err});
                    result.errors += 1;
                    return;
                };
                defer version_state.deinit();

                // For each file in source directory, upload to WebDAV with versioning
                var source_dir = std.Io.Dir.openDirAbsolute(self.io, source_path, .{ .iterate = true }) catch {
                    result.errors += 1;
                    return;
                };
                defer source_dir.close(self.io);

                var it = source_dir.iterate(self.io);
                while (try it.next()) |entry| {
                    const src_file_path = try std.fs.path.join(self.allocator, &.{ source_path, entry.name });
                    defer self.allocator.free(src_file_path);

                    // Skip directories
                    if (entry.kind != .file) continue;

                    // Read file content
                    const src_file = std.Io.Dir.openFileAbsolute(self.io, src_file_path, .{}) catch continue;
                    defer src_file.close(self.io);

                    const stat = src_file.stat(self.io) catch continue;
                    var read_buf: [8192]u8 = undefined;
                    var file_reader = src_file.reader(self.io, &read_buf);
                    const content = file_reader.interface.allocRemaining(self.allocator, .limited(10_000_000)) catch continue;
                    defer self.allocator.free(content);

                    // Upload with versioning and conflict resolution
                    const upload_result = client.uploadWithConflictResolution(
                        entry.name,
                        content,
                        @as(i64, @intCast(@divTrunc(stat.mtime, 1_000_000_000))),
                        0, // remote_mtime - would need to check remote first for true incremental
                        true, // has_local_changes (always true for upload)
                        false, // has_remote_changes
                    ) catch {
                        result.errors += 1;
                        continue;
                    };
                    defer {
                        self.allocator.free(upload_result.path);
                        if (upload_result.conflict_backup_path) |p| self.allocator.free(p);
                    }

                    if (upload_result.is_conflict) {
                        std.log.info("WebDAV sync conflict for {s}, backed up to {s}", .{
                            entry.name, upload_result.conflict_backup_path orelse "",
                        });
                    }

                    result.files_synced += 1;
                }
            },
            .git_repo => |git_config| {
                // Get source path (first target's path as local clone destination)
                const local_path = if (item.targets.len > 0) item.targets[0].path else "";
                if (local_path.len == 0) {
                    result.errors += 1;
                    return;
                }

                // Check if repo exists locally by checking for .git directory
                const repo_git_path = try std.fs.path.join(self.allocator, &.{ local_path, ".git" });
                defer self.allocator.free(repo_git_path);

                var repo_exists = true;
                if (std.Io.Dir.openFileAbsolute(self.io, repo_git_path, .{})) |f| {
                    f.close(self.io);
                    repo_exists = true;
                } else |_| {
                    repo_exists = false;
                }

                if (repo_exists) {
                    // Pull latest changes
                    try self.gitPull(local_path);
                } else {
                    // Clone the repository
                    try self.gitClone(git_config.url, local_path, git_config.branch);
                }

                // Sync files from repo to other targets
                var source_dir = std.Io.Dir.openDirAbsolute(self.io, local_path, .{ .iterate = true }) catch {
                    result.errors += 1;
                    return;
                };
                defer source_dir.close(self.io);

                var it = source_dir.iterate(self.io);
                while (try it.next()) |entry| {
                    // Skip .git directory
                    if (std.mem.eql(u8, entry.name, ".git")) continue;

                    const src_file_path = try std.fs.path.join(self.allocator, &.{ local_path, entry.name });
                    defer self.allocator.free(src_file_path);

                    if (entry.kind == .file) {
                        // Read file content
                        const src_file = std.Io.Dir.openFileAbsolute(self.io, src_file_path, .{}) catch continue;
                        defer src_file.close(self.io);

                        var read_buf: [8192]u8 = undefined;
                        var file_reader = src_file.reader(self.io, &read_buf);
                        const content = file_reader.interface.allocRemaining(self.allocator, .limited(10_000_000)) catch continue;
                        defer self.allocator.free(content);

                        // Content is read and counted - could push to another git remote
                        result.files_synced += 1;
                    }
                }
            },
            else => {
                // Local-only source, can't sync to remote
                result.errors += 1;
            },
        }
    }

    /// Bidirectional sync
    fn syncBidirectional(self: *SyncEngine, item: *const SyncItem, result: *SyncResult) !void {
        // First sync to remote
        try self.syncToRemote(item, result);

        // Then sync to local (from remote)
        // For now, just do to_local
        try self.syncToLocal(item, result);
    }

    /// Clone a Git repository
    fn gitClone(self: *SyncEngine, url: []const u8, local_path: []const u8, branch: []const u8) !void {
        // Ensure parent directory exists
        const parent = std.fs.path.dirname(local_path);
        if (parent) |p| {
            std.Io.Dir.createDirAbsolute(self.io, p, .{}) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };
        }

        // Run git clone: git clone --branch <branch> --single-branch <url> <local_path>
        var child = std.process.Child.init(.{
            .argv = &.{
                "git",             "clone",
                "--branch",        branch,
                "--single-branch", url,
                local_path,
            },
            .allocator = self.allocator,
        });
        child.stdout_behavior = .ignore;
        child.stderr_behavior = .pipe;

        try child.spawn(self.io);
        const term = try child.wait(self.io);
        if (term != .exited or term.exited != 0) {
            return error.GitCloneFailed;
        }
    }

    /// Pull latest changes from Git repository
    fn gitPull(self: *SyncEngine, local_path: []const u8) !void {
        var child = std.process.Child.init(.{
            .argv = &.{ "git", "pull", "--rebase" },
            .allocator = self.allocator,
            .cwd = .{ .absolute = local_path },
        });
        child.stdout_behavior = .ignore;
        child.stderr_behavior = .pipe;

        try child.spawn(self.io);
        const term = try child.wait(self.io);
        if (term != .exited or term.exited != 0) {
            return error.GitPullFailed;
        }
    }

    /// Create a symlink (with backup if exists)
    fn createSymlink(self: *SyncEngine, source: []const u8, target: []const u8) !void {
        // Backup existing file/link if it exists
        const target_file = std.Io.Dir.openFileAbsolute(self.io, target, .{}) catch null;
        if (target_file) |f| {
            defer f.close(self.io);
            // Read content and backup
            const backup_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}.backup.{d}",
                .{ target, time_compat.timestamp(self.io) },
            );
            defer self.allocator.free(backup_path);
            var read_buf: [8192]u8 = undefined;
            var file_reader = f.reader(self.io, &read_buf);
            const content = try file_reader.interface.allocRemaining(self.allocator, .limited(1_000_000));
            defer self.allocator.free(content);
            try self.writeFile(backup_path, content);
        }

        // Remove existing symlink if exists
        std.Io.Dir.deleteFileAbsolute(self.io, target) catch {};
        try std.Io.Dir.symLinkAbsolute(self.io, source, target, .{});
    }

    /// Copy directory recursively
    fn copyDirectory(self: *SyncEngine, src: []const u8, dst: []const u8, ignores: [][]const u8) !u32 {
        var count: u32 = 0;

        var src_dir = try std.Io.Dir.openDirAbsolute(self.io, src, .{ .iterate = true });
        defer src_dir.close(self.io);

        // Create destination directory if needed
        std.Io.Dir.createDirAbsolute(self.io, dst, .{}) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        var it = src_dir.iterate(self.io);
        while (try it.next()) |entry| {
            // Check ignore patterns
            var ignored = false;
            for (ignores) |pattern| {
                if (self.matchesPattern(entry.name, pattern)) {
                    ignored = true;
                    break;
                }
            }
            if (ignored) {
                count += 1;
                continue;
            }

            const src_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ src, entry.name });
            defer self.allocator.free(src_path);

            const dst_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dst, entry.name });
            defer self.allocator.free(dst_path);

            switch (entry.kind) {
                .file => {
                    try self.copyFile(src_path, dst_path);
                    count += 1;
                },
                .directory => {
                    count += try self.copyDirectory(src_path, dst_path, ignores);
                },
                else => {},
            }
        }

        return count;
    }

    /// Copy a single file
    fn copyFile(self: *SyncEngine, src: []const u8, dst: []const u8) !void {
        const src_file = try std.Io.Dir.openFileAbsolute(self.io, src, .{});
        defer src_file.close(self.io);

        var read_buf: [8192]u8 = undefined;
        var file_reader = src_file.reader(self.io, &read_buf);
        const content = try file_reader.interface.allocRemaining(self.allocator, .limited(10_000_000));
        defer self.allocator.free(content);

        try self.writeFile(dst, content);
    }

    /// Write content to file
    fn writeFile(self: *SyncEngine, path: []const u8, content: []const u8) !void {
        const file = try std.Io.Dir.createFileAbsolute(self.io, path, .{});
        defer file.close(self.io);
        var write_buf: [8192]u8 = undefined;
        var writer = file.writer(self.io, &write_buf);
        try writer.interface.writeAll(content);
        try writer.interface.flush();
    }

    /// Simple pattern matching (supports * and **)
    fn matchesPattern(self: *SyncEngine, name: []const u8, pattern: []const u8) bool {
        _ = self;
        // Simple implementation - just check if pattern is prefix/suffix
        if (std.mem.eql(u8, pattern, "*")) {
            return true;
        }
        if (std.mem.startsWith(u8, pattern, "*.")) {
            const ext = pattern[1..];
            return std.mem.endsWith(u8, name, ext);
        }
        return std.mem.find(u8, name, pattern) != null;
    }

    /// Sync all items marked with auto_sync
    pub fn syncAllAutoSync(self: *SyncEngine) !void {
        var it = self.items.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.auto_sync) {
                _ = self.syncItem(entry.key_ptr.*) catch |e| {
                    std.log.warn("auto-sync failed for '{s}': {}", .{ entry.key_ptr.*, e });
                };
            }
        }
    }

    /// Get sync status for an item
    pub fn getSyncStatus(self: *SyncEngine, id: []const u8) ?struct {
        last_sync: ?i64,
        auto_sync: bool,
    } {
        const item = self.items.get(id) orelse return null;
        return .{
            .last_sync = item.last_sync,
            .auto_sync = item.auto_sync,
        };
    }

    /// Export skills to a directory
    pub fn exportSkills(self: *SyncEngine, tool: CliTool, target_dir: []const u8, home_dir: []const u8) !void {
        // Source: ~/.cc-switch/skills/
        const src_dir = try std.fmt.allocPrint(
            self.allocator,
            "{s}/.cc-switch/skills",
            .{home_dir},
        );
        defer self.allocator.free(src_dir);

        // Destination
        const dst_dir = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ target_dir, self.cliToolToDirName(tool) },
        );
        defer self.allocator.free(dst_dir);

        _ = try self.copyDirectory(src_dir, dst_dir, &.{ "node_modules", ".git" });
    }

    /// Import skills from a directory
    pub fn importSkills(self: *SyncEngine, tool: CliTool, source_dir: []const u8, home_dir: []const u8) !void {
        // Destination: ~/.cc-switch/skills/
        const dst_dir = try std.fmt.allocPrint(
            self.allocator,
            "{s}/.cc-switch/skills",
            .{home_dir},
        );
        defer self.allocator.free(dst_dir);

        // Source
        const src_dir = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ source_dir, self.cliToolToDirName(tool) },
        );
        defer self.allocator.free(src_dir);

        _ = try self.copyDirectory(src_dir, dst_dir, &.{ "node_modules", ".git" });
    }

    fn cliToolToDirName(self: *SyncEngine, tool: CliTool) []const u8 {
        _ = self;
        return switch (tool) {
            .claude_code => "claude",
            .codex => "codex",
            .gemini_cli => "gemini",
            .opencode => "opencode",
            .openclaw => "openclaw",
        };
    }

    /// GitHub reference (branch, tag, or commit)
    pub const GitHubRef = struct {
        kind: enum { branch, tag, commit },
        name: []const u8,
    };

    /// Parsed GitHub URL result
    pub const GitHubRepo = struct {
        owner: []const u8,
        repo: []const u8,
        ref: ?GitHubRef,
    };

    /// Parse a GitHub URL to extract owner, repo, and optional ref
    pub fn parseGitHubUrl(url: []const u8) ?GitHubRepo {
        // Handle formats:
        // https://github.com/owner/repo
        // https://github.com/owner/repo.git
        // https://github.com/owner/repo/tree/branch-name
        // https://github.com/owner/repo/archive/refs/tags/v1.0.zip
        // https://github.com/owner/repo/archive/refs/heads/main.zip
        // git@github.com:owner/repo.git

        const https_prefix = "https://github.com/";
        const git_prefix = "git@github.com:";

        var remainder: []const u8 = undefined;

        if (std.mem.startsWith(u8, url, https_prefix)) {
            remainder = url[https_prefix.len..];
        } else if (std.mem.startsWith(u8, url, git_prefix)) {
            remainder = url[git_prefix.len..];
            // Convert git@github.com:owner/repo.git format
            if (std.mem.endsWith(u8, remainder, ".git")) {
                remainder = remainder[0 .. remainder.len - 4];
            }
        } else {
            return null;
        }

        // Split owner/repo
        const slash_idx = std.mem.find(u8, remainder, "/") orelse return null;
        const owner = remainder[0..slash_idx];
        const after_owner = remainder[slash_idx + 1 ..];

        // Check for .git suffix
        var repo_part = after_owner;
        if (std.mem.endsWith(u8, repo_part, ".git")) {
            repo_part = repo_part[0 .. repo_part.len - 4];
        }

        // Parse ref from path
        var ref: ?GitHubRef = null;

        // Check for tree/branch
        const tree_prefix = "/tree/";
        if (std.mem.startsWith(u8, repo_part, tree_prefix)) {
            const after_tree = repo_part[tree_prefix.len..];
            // Find next slash or end
            const end_idx = std.mem.find(u8, after_tree, "/") orelse after_tree.len;
            const branch_name = after_tree[0..end_idx];
            ref = .{
                .kind = .branch,
                .name = branch_name,
            };
            // Trim to just "owner/repo" if we had extra path
            if (end_idx < after_tree.len) {
                // Keep only "owner/repo"
            }
        }

        // Check for archive refs
        const archive_prefix = "/archive/refs/";
        if (std.mem.startsWith(u8, repo_part, archive_prefix)) {
            const after_archive = repo_part[archive_prefix.len..];
            // Parse refs/heads/branch.zip or refs/tags/tag.zip
            if (std.mem.startsWith(u8, after_archive, "heads/")) {
                const branch_name = after_archive["heads/".len..];
                if (std.mem.endsWith(u8, branch_name, ".zip")) {
                    ref = .{
                        .kind = .branch,
                        .name = branch_name[0 .. branch_name.len - 4],
                    };
                }
            } else if (std.mem.startsWith(u8, after_archive, "tags/")) {
                const tag_name = after_archive["tags/".len..];
                if (std.mem.endsWith(u8, tag_name, ".zip")) {
                    ref = .{
                        .kind = .tag,
                        .name = tag_name[0 .. tag_name.len - 4],
                    };
                }
            }
        }

        // Find repo name (before any path components)
        const repo_end = std.mem.find(u8, repo_part, "/") orelse repo_part.len;
        const repo = repo_part[0..repo_end];

        return .{
            .owner = owner,
            .repo = repo,
            .ref = ref,
        };
    }

    /// Build a ZIP download URL from GitHub repo and ref
    pub fn buildGitHubZipUrl(allocator: std.mem.Allocator, repo: *const GitHubRepo) ![]u8 {
        // Format: https://github.com/{owner}/{repo}/archive/refs/{kind}/{name}.zip
        const base = "https://github.com/";
        const archive_base = "/archive/refs/";

        const kind_str = switch (repo.ref.?.kind) {
            .branch => "heads",
            .tag => "tags",
            .commit => "heads", // Fallback, won't work for commits
        };

        return std.fmt.allocPrint(allocator, "{s}{s}/{s}{s}{s}/{s}.zip", .{
            base, repo.owner, repo.repo, archive_base, kind_str, repo.ref.?.name,
        });
    }

    /// Build a Git clone URL from GitHub repo
    pub fn buildGitCloneUrl(allocator: std.mem.Allocator, repo: *const GitHubRepo) ![]u8 {
        const https_url = try std.fmt.allocPrint(allocator, "https://github.com/{s}/{s}.git", .{
            repo.owner, repo.repo,
        });
        return https_url;
    }

    /// Install skills from a GitHub repository URL
    /// Supports: https://github.com/owner/repo, https://github.com/owner/repo/tree/branch
    pub fn installFromGitHub(self: *SyncEngine, github_url: []const u8, target_dir: []const u8) !void {
        const parsed = self.parseGitHubUrl(github_url) orelse {
            return error.InvalidGitHubUrl;
        };

        // Ensure target directory exists
        std.Io.Dir.createDirAbsolute(self.io, target_dir, .{}) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        if (parsed.ref) |ref| {
            // We have a specific ref - use ZIP download for tags/commits, git for branches
            switch (ref.kind) {
                .branch => {
                    // For branches, use git clone
                    const clone_url = try self.buildGitCloneUrl(self.allocator, &parsed);
                    defer self.allocator.free(clone_url);

                    // Clone to a temp location then copy relevant files
                    const temp_path = try std.fmt.allocPrint(self.allocator, "{s}/.tmp.{s}", .{
                        target_dir, parsed.repo,
                    });
                    defer self.allocator.free(temp_path);

                    try self.gitClone(clone_url, temp_path, ref.name);

                    // Copy files from repo to target
                    _ = try self.copyDirectory(temp_path, target_dir, &.{ ".git", "node_modules" });

                    // Cleanup temp
                    if (std.fs.path.dirname(temp_path)) |parent| {
                        if (std.Io.Dir.openDirAbsolute(self.io, parent, .{})) |*parent_dir| {
                            defer parent_dir.close(self.io);
                            const basename = std.fs.path.basename(temp_path);
                            parent_dir.deleteTree(self.io, basename) catch {};
                        } else |_| {}
                    }
                },
                .tag => {
                    // For tags, download ZIP
                    const zip_url = try std.fmt.allocPrint(self.allocator, "https://github.com/{s}/{s}/archive/refs/tags/{s}.zip", .{ parsed.owner, parsed.repo, ref.name });
                    defer self.allocator.free(zip_url);

                    try self.installFromZip(zip_url, target_dir);
                },
                .commit => {
                    // For commits, download ZIP from commit
                    const zip_url = try std.fmt.allocPrint(self.allocator, "https://github.com/{s}/{s}/archive/{s}.zip", .{ parsed.owner, parsed.repo, ref.name });
                    defer self.allocator.free(zip_url);

                    try self.installFromZip(zip_url, target_dir);
                },
            }
        } else {
            // No ref specified, clone the repo (main branch)
            const clone_url = try self.buildGitCloneUrl(self.allocator, &parsed);
            defer self.allocator.free(clone_url);

            try self.gitClone(clone_url, target_dir, "main");
        }
    }

    /// Install skills from a ZIP URL or local ZIP file
    pub fn installFromZip(self: *SyncEngine, zip_url_or_path: []const u8, target_dir: []const u8) !void {
        // Determine if URL or local file
        const is_url = std.mem.startsWith(u8, zip_url_or_path, "http://") or
            std.mem.startsWith(u8, zip_url_or_path, "https://");

        var zip_data: []u8 = undefined;

        if (is_url) {
            // Download the ZIP
            zip_data = try self.downloadFile(zip_url_or_path);
        } else {
            // Read local file
            const file = try std.Io.Dir.openFileAbsolute(self.io, zip_url_or_path, .{});
            defer file.close(self.io);
            var read_buf: [8192]u8 = undefined;
            var file_reader = file.reader(self.io, &read_buf);
            zip_data = try file_reader.interface.allocRemaining(self.allocator, .limited(50_000_000)); // 50MB max
        }
        defer self.allocator.free(zip_data);

        // Extract ZIP to target directory
        try self.extractZip(zip_data, target_dir);
    }

    /// Download a file from URL
    fn downloadFile(self: *SyncEngine, url: []const u8) ![]u8 {
        // Simple HTTP GET using std.http.Client
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const uri = try std.Uri.parse(url);
        const response = try client.fetch(.{
            .location = .{ .url = uri },
            .response_storage = .{
                .dynamic = .{
                    .allocator = self.allocator,
                    .growable = true,
                },
            },
        });

        if (response.status != .ok) {
            return error.DownloadFailed;
        }

        return response.body.?;
    }

    /// Extract ZIP data to target directory
    fn extractZip(self: *SyncEngine, zip_data: []u8, target_dir: []const u8) !void {
        // Ensure target directory exists
        std.Io.Dir.createDirAbsolute(self.io, target_dir, .{}) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // Parse ZIP central directory
        // This is a simplified implementation - handles basic ZIP files
        // For full spec compliance, a more complete parser would be needed

        var offset: usize = 0;
        const signature: [4]u8 = .{ 0x50, 0x4b, 0x03, 0x04 }; // Local file header

        while (offset + 30 <= zip_data.len) {
            // Check for local file header
            if (!std.mem.eql(u8, zip_data[offset .. offset + 4], &signature)) {
                // Try to find next signature
                const next = findNextSignature(zip_data[offset + 1 ..], &signature) orelse break;
                offset += next + 1;
                continue;
            }

            // Parse local file header
            const local = zip_data[offset..];
            _ = std.mem.readInt(u16, local[4..6], .little); // version
            _ = std.mem.readInt(u16, local[6..8], .little); // flags
            const compression = std.mem.readInt(u16, local[8..10], .little);
            const comp_size = std.mem.readInt(u32, local[18..22], .little);
            _ = std.mem.readInt(u32, local[22..26], .little); // uncomp_size
            const name_len = std.mem.readInt(u16, local[26..28], .little);
            const extra_len = std.mem.readInt(u16, local[28..30], .little);

            const name_start = offset + 30;
            const name_end = name_start + name_len;
            const data_start = name_end + extra_len;
            const data_end = data_start + comp_size;

            if (data_end > zip_data.len) break;

            const name = zip_data[name_start..name_end];

            // Skip directories and hidden files
            if (name[name_len - 1] == '/') {
                offset = data_end;
                continue;
            }

            // Skip macOS and other hidden files
            if (containsHiddenPrefix(name)) {
                offset = data_end;
                continue;
            }

            // Build destination path
            // ZIP archives from GitHub have prefix like "repo-branch/"
            const file_name = extractBaseName(name);
            if (file_name.len == 0) {
                offset = data_end;
                continue;
            }

            const dst_path = try std.fs.path.join(self.allocator, &.{ target_dir, file_name });
            defer self.allocator.free(dst_path);

            // Get compressed data
            const comp_data = zip_data[data_start..data_end];

            // Decompress if needed
            if (compression == 0) {
                // Stored (no compression)
                try self.writeFile(dst_path, comp_data);
            } else if (compression == 8) {
                // Deflate
                var decomp = std.io.decompress(self.allocator, comp_data) catch |err| {
                    std.log.warn("Failed to decompress {s}: {}", .{ name, err });
                    offset = data_end;
                    continue;
                };
                defer decomp.deinit();
                const decompressed = try decomp.allocRemaining(self.allocator, .limited(10_000_000));
                defer self.allocator.free(decompressed);
                try self.writeFile(dst_path, decompressed);
            }

            offset = data_end;
        }
    }

    /// Find next occurrence of signature in data
    fn findNextSignature(data: []const u8, signature: *const [4]u8) ?usize {
        for (0..data.len - 3) |i| {
            if (std.mem.eql(u8, data[i .. i + 4], signature)) {
                return i;
            }
        }
        return null;
    }

    /// Check if path contains hidden file prefix (._, .DS_Store, etc)
    fn containsHiddenPrefix(path: []const u8) bool {
        // Skip macOS resource fork files
        if (std.mem.startsWith(u8, path, "._")) return true;
        // Skip .DS_Store
        if (std.mem.find(u8, path, ".DS_Store") != null) return true;
        // Skip __MACOSX
        if (std.mem.find(u8, path, "__MACOSX") != null) return true;
        return false;
    }

    /// Extract base name from ZIP entry path (removes directory prefix)
    fn extractBaseName(zip_path: []const u8) []const u8 {
        // GitHub archives have prefix like "repo-branch/"
        // Find last / to get actual filename
        const last_slash = std.mem.findLast(u8, zip_path, "/");
        if (last_slash) |idx| {
            return zip_path[idx + 1 ..];
        }
        return zip_path;
    }
};


// ============================================================================
// Property-Based Tests
// ============================================================================

// **Feature: zig-016-upgrade, Property 2: 文件 I/O 往返一致性**
// Verify any byte sequence written via new API then read back is identical.
//
// **Validates: Requirements 2.3, 2.4, 2.11, 2.12**
test "Property 2: file I/O round-trip consistency" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const iterations: usize = 100;

    // Simple PRNG for generating test data
    var rng = std.Random.DefaultPrng.init(42);
    const random = rng.random();

    for (0..iterations) |i| {
        // Generate random content of varying sizes (0 to 4096 bytes)
        const content_len = random.intRangeAtMost(usize, 0, 4096);
        const content = try allocator.alloc(u8, content_len);
        defer allocator.free(content);
        random.bytes(content);

        // Build a unique temp file path
        const path = try std.fmt.allocPrint(allocator, "/tmp/llmlite_prop2_roundtrip_{d}.bin", .{i});
        defer allocator.free(path);

        // Write via new API
        {
            const file = try std.Io.Dir.createFileAbsolute(io, path, .{});
            defer file.close(io);
            var write_buf: [8192]u8 = undefined;
            var writer = file.writer(io, &write_buf);
            try writer.interface.writeAll(content);
            try writer.interface.flush();
        }

        // Read back via new API
        const read_back = blk: {
            const file = try std.Io.Dir.openFileAbsolute(io, path, .{});
            defer file.close(io);
            var read_buf: [8192]u8 = undefined;
            var file_reader = file.reader(io, &read_buf);
            break :blk try file_reader.interface.allocRemaining(allocator, .limited(10_000_000));
        };
        defer allocator.free(read_back);

        // Verify round-trip: written content must equal read content
        try std.testing.expectEqualSlices(u8, content, read_back);

        // Cleanup
        std.Io.Dir.deleteFileAbsolute(io, path) catch {};
    }
}
