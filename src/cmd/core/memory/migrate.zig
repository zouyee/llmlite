//! History migration - convert text-based history.db to SQLite memory.db

const std = @import("std");
const types = @import("types.zig");
const db = @import("db.zig");
const utils = @import("utils.zig");

pub const Migrator = struct {
    allocator: std.mem.Allocator,
    memory_db: *db.MemoryDb,

    pub fn init(allocator: std.mem.Allocator, memory_db: *db.MemoryDb) Migrator {
        return Migrator{
            .allocator = allocator,
            .memory_db = memory_db,
        };
    }

    pub fn migrate(self: *Migrator) !MigrationResult {
        var result = MigrationResult{};

        const history_path = try self.getHistoryDbPath();
        defer self.allocator.free(history_path);

        const file = std.fs.openFileAbsolute(history_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("No history.db found, nothing to migrate.\n", .{});
                return result;
            }
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(content);

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0) continue;

            result.total_read += 1;

            const record = self.parseRecord(trimmed) catch |err| {
                if (err == error.InvalidFormat) {
                    result.failed += 1;
                    continue;
                }
                return err;
            };

            // Convert to MemoryEntry and insert
            self.migrateRecord(record) catch |err| {
                if (err == error.Duplicate) {
                    result.skipped_duplicates += 1;
                } else {
                    result.failed += 1;
                }
                continue;
            };

            result.migrated += 1;
        }

        return result;
    }

    fn getHistoryDbPath(self: *Migrator) ![]const u8 {
        const home_dir = std.process.getEnvVarOwned(self.allocator, "HOME") catch {
            return try std.fmt.allocPrint(self.allocator, "/tmp/llmlite_history.db", .{});
        };
        defer self.allocator.free(home_dir);
        return try std.fmt.allocPrint(self.allocator, "{s}/.local/share/llmlite/history.db", .{home_dir});
    }

    fn parseRecord(self: *Migrator, line: []const u8) !HistoryRecord {
        _ = self;
        var fields: [8][]const u8 = undefined;
        var field_count: usize = 0;

        var iter = std.mem.splitScalar(u8, line, '|');
        while (iter.next()) |field| {
            if (field_count >= 8) return error.InvalidFormat;
            fields[field_count] = field;
            field_count += 1;
        }

        if (field_count != 8) return error.InvalidFormat;

        return HistoryRecord{
            .timestamp = std.fmt.parseInt(i64, fields[0], 10) catch return error.InvalidFormat,
            .original_cmd = fields[1],
            .rtk_cmd = fields[2],
            .input_tokens = std.fmt.parseInt(u32, fields[3], 10) catch 0,
            .output_tokens = std.fmt.parseInt(u32, fields[4], 10) catch 0,
            .saved_tokens = std.fmt.parseInt(u32, fields[5], 10) catch 0,
            .savings_pct = std.fmt.parseFloat(f64, fields[6]) catch 0.0,
            .exit_code = std.fmt.parseInt(i32, fields[7], 10) catch 0,
        };
    }

    fn migrateRecord(self: *Migrator, record: HistoryRecord) !void {
        const session_id = try std.fmt.allocPrint(self.allocator, "migrated-{d}", .{record.timestamp});
        defer self.allocator.free(session_id);

        const summary = try std.fmt.allocPrint(self.allocator, "Ran: {s}", .{record.original_cmd});
        defer self.allocator.free(summary);

        const project = try utils.detectProject(self.allocator);
        defer self.allocator.free(project);

        const commands = try self.allocator.alloc([]const u8, 1);
        commands[0] = try self.allocator.dupe(u8, record.original_cmd);
        defer {
            for (commands) |c| self.allocator.free(c);
            self.allocator.free(commands);
        }

        const hash = utils.computeContentHash(session_id, summary, commands);

        // Check for duplicate (any time, not just within window)
        if (try self.memory_db.hasDuplicateHash(hash)) {
            return error.Duplicate;
        }

        const entry = types.MemoryEntry{
            .id = 0,
            .category = if (record.exit_code == 0) .other else .err,
            .summary = summary,
            .facts = &.{},
            .context = "",
            .tags = &.{},
            .commands = commands,
            .project = project,
            .session_id = session_id,
            .created_at = record.timestamp,
            .exit_code = record.exit_code,
            .content_hash = hash,
        };

        _ = try self.memory_db.insertMemory(entry);
    }
};

pub const MigrationResult = struct {
    total_read: u32 = 0,
    migrated: u32 = 0,
    skipped_duplicates: u32 = 0,
    failed: u32 = 0,
};

const HistoryRecord = struct {
    timestamp: i64,
    original_cmd: []const u8,
    rtk_cmd: []const u8,
    input_tokens: u32,
    output_tokens: u32,
    saved_tokens: u32,
    savings_pct: f64,
    exit_code: i32,
};
