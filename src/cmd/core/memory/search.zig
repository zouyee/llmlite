//! Memory search - FTS5 and metadata-based search

const std = @import("std");
const sqlite = @import("sqlite");
const types = @import("types.zig");
const db = @import("db.zig");

pub const Searcher = struct {
    memory_db: *db.MemoryDb,

    pub fn init(memory_db: *db.MemoryDb) Searcher {
        return Searcher{ .memory_db = memory_db };
    }

    /// Search memories with filter
    pub fn search(self: *Searcher, filter: types.MemoryFilter) ![]types.SearchResult {
        if (self.memory_db.has_fts5 and filter.query != null and filter.query.?.len > 0) {
            return try self.searchFts5(filter);
        } else {
            return try self.searchMetadata(filter);
        }
    }

    /// List recent memories (no query text)
    pub fn list(self: *Searcher, filter: types.MemoryFilter) ![]types.SearchResult {
        return try self.searchMetadata(filter);
    }

    /// Get timeline context around a specific memory
    pub fn timeline(self: *Searcher, id: u64, before: u32, after: u32) ![]types.SearchResult {
        _ = before;
        _ = after;

        // First get the target memory's session_id
        const target = try self.memory_db.getMemoryById(id);
        if (target == null) return &[_]types.SearchResult{};

        const RowType = struct {
            id: u64,
            category: sqlite.Text,
            summary: sqlite.Text,
            created_at: i64,
            project: sqlite.Text,
        };

        const stmt = self.memory_db.db.prepare(
            struct { session_id: sqlite.Text, id: u64 },
            RowType,
            \\SELECT id, category, summary, created_at, project FROM memories
            \\WHERE session_id = :session_id AND id != :id
            \\ORDER BY created_at DESC
        ) catch return &[_]types.SearchResult{};
        defer stmt.finalize();

        try stmt.bind(.{ .session_id = sqlite.text(target.?.session_id), .id = id });

        var results = std.ArrayList(types.SearchResult).empty;
        errdefer {
            for (results.items) |r| {
                self.memory_db.allocator.free(r.summary);
                self.memory_db.allocator.free(r.project);
            }
            results.deinit(self.memory_db.allocator);
        }

        while (try stmt.step()) |row| {
            try results.append(self.memory_db.allocator, types.SearchResult{
                .id = row.id,
                .category = types.MemoryCategory.fromString(row.category.data),
                .summary = try self.memory_db.allocator.dupe(u8, row.summary.data),
                .created_at = row.created_at,
                .project = try self.memory_db.allocator.dupe(u8, row.project.data),
                .relevance_score = 1.0,
            });
        }

        return results.toOwnedSlice(self.memory_db.allocator);
    }

    fn searchFts5(self: *Searcher, filter: types.MemoryFilter) ![]types.SearchResult {
        const RowType = struct {
            id: u64,
            category: sqlite.Text,
            summary: sqlite.Text,
            created_at: i64,
            project: sqlite.Text,
        };

        // Build SQL dynamically
        var sql_parts: [6][]const u8 = undefined;
        sql_parts[0] =
            \\SELECT m.id, m.category, m.summary, m.created_at, m.project
            \\FROM memories m
            \\JOIN memories_fts fts ON m.id = fts.rowid
            \\WHERE memories_fts MATCH :query
        ;

        var part_count: usize = 1;
        if (filter.category) |_| {
            sql_parts[part_count] = " AND m.category = :category";
            part_count += 1;
        }
        if (filter.project) |_| {
            sql_parts[part_count] = " AND m.project = :project";
            part_count += 1;
        }
        if (filter.date_start) |_| {
            sql_parts[part_count] = " AND m.created_at >= :date_start";
            part_count += 1;
        }
        if (filter.date_end) |_| {
            sql_parts[part_count] = " AND m.created_at <= :date_end";
            part_count += 1;
        }
        sql_parts[part_count] = " ORDER BY rank LIMIT :limit";
        part_count += 1;

        var total_len: usize = 0;
        for (sql_parts[0..part_count]) |part| total_len += part.len;

        const sql = try self.memory_db.allocator.alloc(u8, total_len);
        defer self.memory_db.allocator.free(sql);

        var pos: usize = 0;
        for (sql_parts[0..part_count]) |part| {
            @memcpy(sql[pos .. pos + part.len], part);
            pos += part.len;
        }

        const stmt = self.memory_db.db.prepare(
            struct {
                query: sqlite.Text,
                category: sqlite.Text,
                project: sqlite.Text,
                date_start: i64,
                date_end: i64,
                limit: u32,
            },
            RowType,
            sql,
        ) catch return &[_]types.SearchResult{};
        defer stmt.finalize();

        try stmt.bind(.{
            .query = sqlite.text(filter.query.?),
            .category = sqlite.text(if (filter.category) |c| c.asString() else ""),
            .project = sqlite.text(filter.project orelse ""),
            .date_start = filter.date_start orelse 0,
            .date_end = filter.date_end orelse 0,
            .limit = filter.limit,
        });

        return try self.collectResults(stmt);
    }

    fn searchMetadata(self: *Searcher, filter: types.MemoryFilter) ![]types.SearchResult {
        const RowType = struct {
            id: u64,
            category: sqlite.Text,
            summary: sqlite.Text,
            created_at: i64,
            project: sqlite.Text,
        };

        const sql =
            \\SELECT id, category, summary, created_at, project FROM memories
            \\WHERE category LIKE :category
            \\AND project LIKE :project
            \\AND created_at >= :date_start
            \\AND created_at <= :date_end
            \\AND (summary LIKE :query OR context LIKE :query OR tags LIKE :query)
            \\ORDER BY created_at DESC LIMIT :limit OFFSET :offset
        ;

        const Params = struct {
            category: sqlite.Text,
            project: sqlite.Text,
            date_start: i64,
            date_end: i64,
            query: sqlite.Text,
            limit: u32,
            offset: u32,
        };

        const stmt = self.memory_db.db.prepare(Params, RowType, sql) catch return &[_]types.SearchResult{};
        defer stmt.finalize();

        const category_pat = if (filter.category) |c|
            try std.fmt.allocPrint(self.memory_db.allocator, "{s}", .{c.asString()})
        else
            try self.memory_db.allocator.dupe(u8, "%");
        defer self.memory_db.allocator.free(category_pat);

        const project_pat = if (filter.project) |p|
            try std.fmt.allocPrint(self.memory_db.allocator, "{s}", .{p})
        else
            try self.memory_db.allocator.dupe(u8, "%");
        defer self.memory_db.allocator.free(project_pat);

        const query_pat = if (filter.query) |q|
            try std.fmt.allocPrint(self.memory_db.allocator, "%{s}%", .{q})
        else
            try self.memory_db.allocator.dupe(u8, "%");
        defer self.memory_db.allocator.free(query_pat);

        try stmt.bind(.{
            .category = sqlite.text(category_pat),
            .project = sqlite.text(project_pat),
            .date_start = filter.date_start orelse 0,
            .date_end = filter.date_end orelse std.math.maxInt(i64),
            .query = sqlite.text(query_pat),
            .limit = filter.limit,
            .offset = filter.offset,
        });

        return try self.collectResults(stmt);
    }

    fn collectResults(self: *Searcher, stmt: anytype) ![]types.SearchResult {
        var results = std.ArrayList(types.SearchResult).empty;
        errdefer {
            for (results.items) |r| {
                self.memory_db.allocator.free(r.summary);
                self.memory_db.allocator.free(r.project);
            }
            results.deinit(self.memory_db.allocator);
        }

        while (try stmt.step()) |row| {
            try results.append(self.memory_db.allocator, types.SearchResult{
                .id = row.id,
                .category = types.MemoryCategory.fromString(row.category.data),
                .summary = try self.memory_db.allocator.dupe(u8, row.summary.data),
                .created_at = row.created_at,
                .project = try self.memory_db.allocator.dupe(u8, row.project.data),
                .relevance_score = 1.0,
            });
        }

        return results.toOwnedSlice(self.memory_db.allocator);
    }
};
