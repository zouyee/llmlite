//! WebDAV Client for llmlite Proxy
//!
//! Provides WebDAV client functionality for syncing files to remote servers.
//! Supports standard WebDAV operations: PROPFIND, GET, PUT, DELETE, MKCOL, MOVE.
//!
//! Supported servers: Nextcloud, ownCloud, Synology, QNAP, etc.

const std = @import("std");
const http = @import("http");

/// WebDAV error types
pub const WebDavError = error{
    ConnectionFailed,
    AuthenticationFailed,
    ResourceNotFound,
    ResourceConflict,
    ServerError,
    InvalidResponse,
    NotImplemented,
};

/// WebDAV property names
pub const WebDavProperty = struct {
    name: []const u8,
    value: []const u8,
};

/// File or directory info from WebDAV
pub const WebDavResource = struct {
    path: []const u8,
    is_directory: bool,
    content_length: u64,
    last_modified: ?i64,
    etag: ?[]const u8,
};

/// File version info for versioning
pub const FileVersion = struct {
    path: []const u8,
    version: u32,
    mtime: i64,
    size: u64,
    checksum: []const u8,
};

/// Sync version database entry
pub const VersionDbEntry = struct {
    local_path: []const u8,
    remote_path: []const u8,
    local_mtime: i64,
    remote_mtime: i64,
    local_version: u32,
    remote_version: u32,
    checksum: []const u8,
    last_sync: i64,
    status: VersionStatus,
};

/// Version status
pub const VersionStatus = enum {
    synced,
    local_newer,
    remote_newer,
    conflict,
};

/// Daily rollup entry
pub const DailyRollup = struct {
    date: []const u8, // YYYY-MM-DD format
    files: [][]const u8,
    created_at: i64,
};

/// WebDAV sync state with versioning
/// Convert Unix timestamp to date string (YYYY-MM-DD)
fn timestampToDateString(timestamp: i64, allocator: std.mem.Allocator) ![]u8 {
    // Days since epoch (1970-01-01)
    const days_since_epoch = @divTrunc(timestamp, 86400);

    // Calculate year using 400-year cycle
    // 400 years = 146097 days (365*400 + 97 leap days)
    const days_400 = 146097;
    const cycles_400 = @divTrunc(days_since_epoch, days_400);
    var remaining_days = @mod(days_since_epoch, days_400);

    var year: i64 = 1970 + cycles_400 * 400;

    // 100-year cycle (36524 days, but last day is leap day)
    const days_100 = 36524;
    if (remaining_days >= days_100) {
        remaining_days -= days_100;
        year += 100;
        if (remaining_days >= days_100) {
            remaining_days -= days_100;
            year += 100;
            if (remaining_days >= days_100) {
                remaining_days -= days_100;
                year += 100;
            }
        }
    }

    // 4-year cycle (1461 days)
    const days_4 = 1461;
    while (remaining_days >= days_4) {
        remaining_days -= days_4;
        year += 4;
    }

    // Single year (365 days)
    while (remaining_days >= 365) {
        remaining_days -= 365;
        year += 1;
    }

    // Account for leap year
    const is_leap = isLeapYear(year);

    // Days in each month
    const month_lengths = if (is_leap)
        [_]i64{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    else
        [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

    var month: i64 = 1;
    for (month_lengths) |days_in_month| {
        if (remaining_days < days_in_month) break;
        remaining_days -= days_in_month;
        month += 1;
    }

    const day = remaining_days + 1;

    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
        year, month, day,
    });
}

/// Check if year is leap year
fn isLeapYear(year: i64) bool {
    return (@mod(year, 4) == 0 and @mod(year, 100) != 0) or (@mod(year, 400) == 0);
}

pub const WebDavSyncState = struct {
    allocator: std.mem.Allocator,
    base_path: []const u8,
    version_db: std.StringArrayHashMap(VersionDbEntry),
    daily_rollups: std.StringArrayHashMap(DailyRollup),

    pub fn init(allocator: std.mem.Allocator, base_path: []const u8) !WebDavSyncState {
        return .{
            .allocator = allocator,
            .base_path = try allocator.dupe(u8, base_path),
            .version_db = std.StringArrayHashMap(VersionDbEntry).init(allocator),
            .daily_rollups = std.StringArrayHashMap(DailyRollup).init(allocator),
        };
    }

    pub fn deinit(self: *WebDavSyncState) void {
        self.version_db.deinit();
        self.daily_rollups.deinit();
        self.allocator.free(self.base_path);
    }

    /// Get current date string
    fn getDateStr(self: *WebDavSyncState) []u8 {
        const now = std.time.timestamp();
        return timestampToDateString(now, self.allocator) catch return "";
    }

    /// Check if local file needs sync (incremental sync)
    pub fn needsSync(self: *WebDavSyncState, local_path: []const u8, local_mtime: i64, remote_mtime: i64) bool {
        if (self.version_db.get(local_path)) |entry| {
            return entry.local_mtime != local_mtime or entry.remote_mtime != remote_mtime;
        }
        return true; // New file
    }

    /// Detect conflict between local and remote
    pub fn detectConflict(self: *WebDavSyncState, local_path: []const u8, local_mtime: i64, remote_mtime: i64) bool {
        if (self.version_db.get(local_path)) |entry| {
            // Conflict if both changed since last sync
            return (entry.local_mtime != local_mtime and entry.remote_mtime != remote_mtime and
                entry.local_mtime != entry.remote_mtime);
        }
        return false;
    }

    /// Update version database after sync
    pub fn updateEntry(self: *WebDavSyncState, entry: VersionDbEntry) !void {
        const key = try self.allocator.dupe(u8, entry.local_path);
        try self.version_db.put(key, entry);
    }

    /// Create versioned backup name with daily rollup
    pub fn createVersionedPath(self: *WebDavSyncState, remote_path: []const u8, is_conflict: bool) ![]u8 {
        const date_str = self.getDateStr();
        const basename = std.fs.path.basename(remote_path);
        const ext = std.fs.path.extension(basename);
        const stem = basename[0 .. basename.len - ext.len];

        if (is_conflict) {
            // Conflict: save as {date}_{path}_{version}.conflict
            return std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}_{d}.conflict", .{
                self.base_path, date_str, stem, std.time.timestamp(),
            });
        } else {
            // Normal: save as {date}/{path}
            return std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}", .{
                self.base_path, date_str, basename,
            });
        }
    }

    /// Get version info for a path
    pub fn getVersion(self: *WebDavSyncState, path: []const u8) ?u32 {
        if (self.version_db.get(path)) |entry| {
            return entry.local_version;
        }
        return null;
    }
};

/// WebDAV client configuration
pub const WebDavConfig = struct {
    /// Base URL of the WebDAV server
    url: []const u8,
    /// Username for authentication
    username: []const u8,
    /// Password for authentication
    password: []const u8,
    /// Base path on the server
    base_path: []const u8 = "/",
    /// Timeout in milliseconds
    timeout_ms: u32 = 30000,
};

/// WebDAV client
pub const WebDavClient = struct {
    allocator: std.mem.Allocator,
    config: WebDavConfig,
    http_client: http.HttpClient,

    pub fn init(allocator: std.mem.Allocator, config: WebDavConfig) WebDavClient {
        return .{
            .allocator = allocator,
            .config = config,
            .http_client = http.HttpClient.init(
                allocator,
                config.url,
                config.password,
                null,
                config.timeout_ms,
            ),
        };
    }

    pub fn deinit(self: *WebDavClient) void {
        self.http_client.deinit();
    }

    /// Build full URL from path
    fn buildUrl(self: *WebDavClient, path: []const u8) ![]u8 {
        return std.fmt.allocPrint(
            self.allocator,
            "{s}{s}{s}",
            .{
                self.config.url,
                self.config.base_path,
                path,
            },
        );
    }

    /// Make WebDAV PROPFIND request to list directory contents
    pub fn listDirectory(self: *WebDavClient, path: []const u8) ![]WebDavResource {
        const url = try self.buildUrl(path);
        defer self.allocator.free(url);

        const body = "<?xml version=\"1.0\" encoding=\"utf-8\"?><d:propfind xmlns:d=\"DAV:\"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/><d:getetag/></d:prop></d:propfind>";

        // PROPFIND request
        const response = self.propfindRequest(url, body) catch |e| {
            if (e == error.ServerError) {
                return error.ResourceNotFound;
            }
            return e;
        };
        defer self.allocator.free(response);

        // Parse XML response
        return self.parsePropfindResponse(response);
    }

    /// Make a PROPFIND request using std.http.Client
    fn propfindRequest(self: *WebDavClient, url: []const u8, body: []const u8) ![]u8 {
        const uri = try std.Uri.parse(url);
        defer self.allocator.free(url);

        const host = uri.host orelse return error.InvalidUrl;
        const port: u16 = uri.port orelse 443;
        const use_https = std.mem.startsWith(u8, url, "https");

        // Create HTTP client
        var http_client = std.http.Client{ .allocator = self.allocator };
        defer http_client.deinit();

        // Connect to server
        const stream = try http_client.connect(host, port, .{
            .protocol = if (use_https) .https else .http,
        });
        defer stream.close();

        // Build auth header
        const auth_value = try makeBasicAuth(self.allocator, self.config.username, self.config.password);
        defer self.allocator.free(auth_value);

        // Build headers
        const headers = .{
            .Host = host,
            .Authorization = auth_value,
            .Content_Type = "application/xml",
            .Depth = "1",
        };

        // Make PROPFIND request
        const response = try stream.sendRequest(.PROPFIND, .{
            .headers = headers,
            .body = .{ .string = body },
        });
        defer response.deinit();

        // Read response body
        const response_body = try response.body.readAllAlloc(self.allocator, 10_000_000);
        return response_body;
    }

    /// Parse PROPFIND XML response
    fn parsePropfindResponse(self: *WebDavClient, xml: []const u8) ![]WebDavResource {
        var results = std.ArrayList(WebDavResource).init(self.allocator);

        // Simple XML parsing for WebDAV responses
        // Look for <d:href> and <d:collection> tags
        var i: usize = 0;
        while (i < xml.len) {
            // Find href tags
            if (std.mem.startsWith(u8, xml[i..], "<d:href>")) {
                i += 9; // skip "<d:href>"
                const end = std.mem.indexOf(u8, xml[i..], "</d:href>") orelse {
                    i += 1;
                    continue;
                };
                const path = xml[i .. i + end];
                i += end + 10; // skip "</d:href>"

                // Check if next tag is collection (directory)
                var is_dir = false;
                const remaining = xml[i..];
                if (std.mem.indexOf(u8, remaining, "<d:collection") != null or
                    std.mem.indexOf(u8, remaining, "<d:resourcetype><d:collection") != null)
                {
                    is_dir = true;
                }

                try results.append(.{
                    .path = path,
                    .is_directory = is_dir,
                    .content_length = 0,
                    .last_modified = null,
                    .etag = null,
                });
            } else {
                i += 1;
            }
        }

        return results.toOwnedSlice();
    }

    /// Upload file with versioning (creates daily rollup)
    /// Returns the versioned path where file was stored
    pub fn uploadFileVersioned(
        self: *WebDavClient,
        local_path: []const u8,
        content: []const u8,
        mtime: i64,
    ) ![]u8 {
        _ = mtime; // mtime stored in version db, not on remote
        // Create daily path: {base_path}/{YYYY-MM-DD}/{filename}
        const now = std.time.timestamp();
        const date_str = try timestampToDateString(now, self.allocator);
        defer self.allocator.free(date_str);

        const basename = std.fs.path.basename(local_path);
        const versioned_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}", .{
            self.config.base_path, date_str, basename,
        });
        defer self.allocator.free(versioned_path);

        // Create daily directory first
        self.createDirectory(date_str) catch {};

        // Upload with versioning
        try self.uploadFile(versioned_path, content);

        return versioned_path;
    }

    /// Upload file with conflict resolution
    /// If conflict detected, stores local version with .conflict extension
    /// Returns the path used and conflict status
    pub const UploadConflictResult = struct {
        path: []const u8,
        is_conflict: bool,
        conflict_backup_path: ?[]const u8,
    };

    pub fn uploadWithConflictResolution(
        self: *WebDavClient,
        local_path: []const u8,
        content: []const u8,
        local_mtime: i64,
        remote_mtime: i64,
        has_local_changes: bool,
        has_remote_changes: bool,
    ) !UploadConflictResult {
        // Check if conflict (both changed)
        const is_conflict = has_local_changes and has_remote_changes and (local_mtime != remote_mtime);

        if (is_conflict) {
            // Conflict: upload local as .conflict, then upload new
            const now = std.time.timestamp();
            const basename = std.fs.path.basename(local_path);
            const ext = std.fs.path.extension(basename);
            const stem = basename[0 .. basename.len - ext.len];

            // Create conflict backup with timestamp
            const conflict_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.{d}.conflict", .{
                self.config.base_path, stem, now,
            });
            errdefer self.allocator.free(conflict_path);

            // Upload current local as conflict backup
            try self.uploadFile(conflict_path, content);

            // Upload new version (don't overwrite - create new daily version)
            const new_path = try self.uploadFileVersioned(local_path, content, local_mtime);
            errdefer self.allocator.free(new_path);

            return .{
                .path = new_path,
                .is_conflict = true,
                .conflict_backup_path = conflict_path,
            };
        } else {
            // No conflict: normal upload with versioning
            const new_path = try self.uploadFileVersioned(local_path, content, local_mtime);
            return .{
                .path = new_path,
                .is_conflict = false,
                .conflict_backup_path = null,
            };
        }
    }

    /// Download a file
    pub fn downloadFile(self: *WebDavClient, remote_path: []const u8) ![]u8 {
        const url = try self.buildUrl(remote_path);
        defer self.allocator.free(url);

        // Use basic auth
        const auth_value = try std.fmt.allocPrint(
            self.allocator,
            "Basic {s}",
            .{
                try makeBasicAuth(self.allocator, self.config.username, self.config.password),
            },
        );
        defer self.allocator.free(auth_value);

        // Create HTTP client for download
        var download_client = http.HttpClient.initWithAuthType(
            self.allocator,
            self.config.url,
            auth_value,
            null,
            self.config.timeout_ms,
            .api_key,
        );
        defer download_client.deinit();

        const path_with_base = try std.fmt.allocPrint(
            self.allocator,
            "{s}{s}",
            .{ self.config.base_path, remote_path },
        );
        defer self.allocator.free(path_with_base);

        return try download_client.get(path_with_base);
    }

    /// Upload a file
    pub fn uploadFile(self: *WebDavClient, remote_path: []const u8, content: []const u8) !void {
        const url = try self.buildUrl(remote_path);
        defer self.allocator.free(url);

        // Use basic auth
        const auth_value = try std.fmt.allocPrint(
            self.allocator,
            "Basic {s}",
            .{
                try makeBasicAuth(self.allocator, self.config.username, self.config.password),
            },
        );
        defer self.allocator.free(auth_value);

        // Create HTTP client for upload
        var upload_client = http.HttpClient.initWithAuthType(
            self.allocator,
            self.config.url,
            auth_value,
            null,
            self.config.timeout_ms,
            .api_key,
        );
        defer upload_client.deinit();

        const path_with_base = try std.fmt.allocPrint(
            self.allocator,
            "{s}{s}",
            .{ self.config.base_path, remote_path },
        );
        defer self.allocator.free(path_with_base);

        _ = try upload_client.post(path_with_base, content);
    }

    /// Delete a file or directory
    pub fn delete(self: *WebDavClient, path: []const u8) !void {
        const url = try self.buildUrl(path);
        defer self.allocator.free(url);

        // Use basic auth
        const auth_value = try std.fmt.allocPrint(
            self.allocator,
            "Basic {s}",
            .{
                try makeBasicAuth(self.allocator, self.config.username, self.config.password),
            },
        );
        defer self.allocator.free(auth_value);

        var client = http.HttpClient.initWithAuthType(
            self.allocator,
            self.config.url,
            auth_value,
            null,
            self.config.timeout_ms,
            .api_key,
        );
        defer client.deinit();

        _ = try client.delete(url);
    }

    /// Create a directory (MKCOL)
    pub fn createDirectory(self: *WebDavClient, path: []const u8) !void {
        const url = try self.buildUrl(path);
        defer self.allocator.free(url);

        // Use basic auth
        const auth_value = try std.fmt.allocPrint(
            self.allocator,
            "Basic {s}",
            .{
                try makeBasicAuth(self.allocator, self.config.username, self.config.password),
            },
        );
        defer self.allocator.free(auth_value);

        var client = http.HttpClient.initWithAuthType(
            self.allocator,
            self.config.url,
            auth_value,
            null,
            self.config.timeout_ms,
            .api_key,
        );
        defer client.deinit();

        // MKCOL is a PUT-like operation with empty body
        _ = try client.sendRequest("MKCOL", url, "", "application/xml");
    }

    /// Move a resource
    pub fn move(self: *WebDavClient, source: []const u8, destination: []const u8) !void {
        const source_url = try self.buildUrl(source);
        defer self.allocator.free(source_url);

        const dest_url = try self.buildUrl(destination);
        defer self.allocator.free(dest_url);

        // Use basic auth
        const auth_value = try std.fmt.allocPrint(
            self.allocator,
            "Basic {s}",
            .{
                try makeBasicAuth(self.allocator, self.config.username, self.config.password),
            },
        );
        defer self.allocator.free(auth_value);

        var client = http.HttpClient.initWithAuthType(
            self.allocator,
            self.config.url,
            auth_value,
            null,
            self.config.timeout_ms,
            .api_key,
        );
        defer client.deinit();

        // Build MOVE request with Destination header
        var headers: [3]http.Http.Header = undefined;
        headers[0] = .{ .name = "Authorization", .value = auth_value };
        headers[1] = .{ .name = "Destination", .value = dest_url };
        headers[2] = .{ .name = "Content-Type", .value = "application/xml" };

        // For MOVE, we need a custom request - use sendRequest directly
        var url_full: []u8 = undefined;
        url_full = try std.mem.concat(self.allocator, u8, &.{ self.config.url, source_url });
        defer self.allocator.free(url_full);

        // Build the MOVE request manually since we need the Destination header
        _ = try client.sendRequest("MOVE", url_full, "", "application/xml");
    }

    /// Check if server supports WebDAV
    pub fn checkServer(self: *WebDavClient) !bool {
        if (self.buildUrl("/")) |url| {
            self.allocator.free(url);
        }
        // TODO: Send OPTIONS request and check for DAV header
        return true;
    }

    /// Make Basic Authentication header value
    fn makeBasicAuth(allocator: std.mem.Allocator, username: []const u8, password: []const u8) ![]u8 {
        const credentials = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ username, password });
        defer allocator.free(credentials);

        // Base64 encode
        const encoded = try base64Encode(allocator, credentials);
        return encoded;
    }

    /// Simple Base64 encoder
    fn base64Encode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        const charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

        var result = try std.ArrayList(u8).initCapacity(allocator, 0);
        errdefer result.deinit(allocator);

        var i: usize = 0;
        while (i < input.len) : (i += 3) {
            const b1 = input[i];
            const b2 = if (i + 1 < input.len) input[i + 1] else 0;
            const b3 = if (i + 2 < input.len) input[i + 2] else 0;

            try result.append(allocator, charset[b1 >> 2]);
            try result.append(allocator, charset[((b1 & 0x03) << 4) | (b2 >> 4)]);

            if (i + 1 < input.len) {
                try result.append(allocator, charset[((b2 & 0x0f) << 2) | (b3 >> 6)]);
            } else {
                try result.append(allocator, '=');
            }

            if (i + 2 < input.len) {
                try result.append(allocator, charset[b3 & 0x3f]);
            } else {
                try result.append(allocator, '=');
            }
        }

        return result.toOwnedSlice(allocator);
    }
};

/// Sync status for a single item
pub const SyncStatus = struct {
    success: bool,
    bytes_transferred: u64,
    error_message: ?[]const u8,
    timestamp: i64,
};

/// WebDAV Sync Engine
pub const WebDavSyncEngine = struct {
    allocator: std.mem.Allocator,
    client: WebDavClient,
    local_base_path: []const u8,
    remote_base_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, client: WebDavClient, local_base_path: []const u8, remote_base_path: []const u8) WebDavSyncEngine {
        return .{
            .allocator = allocator,
            .client = client,
            .local_base_path = local_base_path,
            .remote_base_path = remote_base_path,
        };
    }

    pub fn deinit(self: *WebDavSyncEngine) void {
        _ = self;
    }

    /// Sync a file from local to remote
    pub fn uploadFile(self: *WebDavSyncEngine, relative_path: []const u8) !SyncStatus {
        const local_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ self.local_base_path, relative_path },
        );
        defer self.allocator.free(local_path);

        const remote_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ self.remote_base_path, relative_path },
        );
        defer self.allocator.free(remote_path);

        // Read local file
        const file = std.fs.openFileAbsolute(local_path, .{}) catch {
            return SyncStatus{
                .success = false,
                .bytes_transferred = 0,
                .error_message = "Local file not found",
                .timestamp = std.time.timestamp(),
            };
        };
        defer file.close();

        const content = file.readToEndAlloc(self.allocator, 10_000_000) catch {
            return SyncStatus{
                .success = false,
                .bytes_transferred = 0,
                .error_message = "Failed to read local file",
                .timestamp = std.time.timestamp(),
            };
        };
        defer self.allocator.free(content);

        // Upload to remote
        self.client.uploadFile(remote_path, content) catch |e| {
            return SyncStatus{
                .success = false,
                .bytes_transferred = 0,
                .error_message = @errorName(e),
                .timestamp = std.time.timestamp(),
            };
        };

        return SyncStatus{
            .success = true,
            .bytes_transferred = @intCast(content.len),
            .error_message = null,
            .timestamp = std.time.timestamp(),
        };
    }

    /// Sync a file from remote to local
    pub fn downloadFile(self: *WebDavSyncEngine, relative_path: []const u8) !SyncStatus {
        const local_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ self.local_base_path, relative_path },
        );
        defer self.allocator.free(local_path);

        const remote_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ self.remote_base_path, relative_path },
        );
        defer self.allocator.free(remote_path);

        // Download from remote
        const content = self.client.downloadFile(remote_path) catch |e| {
            return SyncStatus{
                .success = false,
                .bytes_transferred = 0,
                .error_message = @errorName(e),
                .timestamp = std.time.timestamp(),
            };
        };
        defer self.allocator.free(content);

        // Write to local file
        const file = std.fs.createFileAbsolute(local_path, .{}) catch {
            return SyncStatus{
                .success = false,
                .bytes_transferred = 0,
                .error_message = "Failed to create local file",
                .timestamp = std.time.timestamp(),
            };
        };
        defer file.close();

        file.writeAll(content) catch {
            return SyncStatus{
                .success = false,
                .bytes_transferred = 0,
                .error_message = "Failed to write local file",
                .timestamp = std.time.timestamp(),
            };
        };

        return SyncStatus{
            .success = true,
            .bytes_transferred = @intCast(content.len),
            .error_message = null,
            .timestamp = std.time.timestamp(),
        };
    }

    /// Sync all files in a directory recursively
    pub fn syncDirectory(self: *WebDavSyncEngine, relative_path: []const u8, direction: enum { upload, download }) ![]SyncStatus {
        var results = try std.ArrayList(SyncStatus).initCapacity(self.allocator, 0);
        errdefer results.deinit();

        const local_dir = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ self.local_base_path, relative_path },
        );
        defer self.allocator.free(local_dir);

        // List local directory
        const dir = std.fs.openDirAbsolute(local_dir, .{ .iterate = true }) catch {
            return results.toOwnedSlice();
        };
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            const entry_rel_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}/{s}",
                .{ relative_path, entry.name },
            );
            defer self.allocator.free(entry_rel_path);

            switch (entry.kind) {
                .file => {
                    const status = switch (direction) {
                        .upload => self.uploadFile(entry_rel_path),
                        .download => self.downloadFile(entry_rel_path),
                    } catch |e| {
                        results.append(SyncStatus{
                            .success = false,
                            .bytes_transferred = 0,
                            .error_message = @errorName(e),
                            .timestamp = std.time.timestamp(),
                        }) catch {};
                        continue;
                    };
                    results.append(status) catch {};
                },
                .directory => {
                    // Recursively sync subdirectories
                    const sub_results = self.syncDirectory(entry_rel_path, direction) catch |e| {
                        _ = e;
                        continue;
                    };
                    defer self.allocator.free(sub_results);
                    for (sub_results) |status| {
                        results.append(status) catch {};
                    }
                },
                else => {},
            }
        }

        return results.toOwnedSlice();
    }
};

test "webdav client init" {
    const allocator = std.heap.page_allocator;
    const client = WebDavClient.init(allocator, .{
        .url = "https://example.com/remote.php/webdav",
        .username = "user",
        .password = "pass",
        .base_path = "/",
    });
    defer client.deinit();

    try std.testing.expect(client.config.timeout_ms == 30000);
}

test "webdav sync engine init" {
    const allocator = std.heap.page_allocator;
    const client = WebDavClient.init(allocator, .{
        .url = "https://example.com/remote.php/webdav",
        .username = "user",
        .password = "pass",
        .base_path = "/",
    });
    defer client.deinit();

    const engine = WebDavSyncEngine.init(
        allocator,
        client,
        "/tmp/local",
        "/remote",
    );
    defer engine.deinit();

    try std.testing.expect(engine.local_base_path.len > 0);
    try std.testing.expect(engine.remote_base_path.len > 0);
}

test "base64 encoding" {
    const allocator = std.heap.page_allocator;
    const encoded = try WebDavClient.base64Encode(allocator, "user:pass");
    defer allocator.free(encoded);

    try std.testing.expectEqualStrings("dXNlcjpwYXNz", encoded);
}
