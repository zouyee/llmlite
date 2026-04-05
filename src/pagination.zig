//! Pagination - Cursor-based pagination helpers for OpenAI APIs
//!
//! Reference: https://platform.openai.com/docs/api-reference/pagination
//!
//! This module provides generic pagination helpers that work with any
//! cursor-based API response from OpenAI.

const std = @import("std");

// ============================================================================
// Page Types
// ============================================================================

pub fn Page(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        items: []T,
        has_more: bool,
        first_id: ?[]const u8,
        last_id: ?[]const u8,

        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.items);
            if (self.first_id) |id| self.allocator.free(id);
            if (self.last_id) |id| self.allocator.free(id);
        }
    };
}

pub fn CursorPage(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        data: []T,
        has_more: bool,
        after: ?[]const u8,
        before: ?[]const u8,

        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.data);
            if (self.after) |id| self.allocator.free(id);
            if (self.before) |id| self.allocator.free(id);
        }
    };
}

// ============================================================================
// Pagination Iterator
// ============================================================================

pub const PaginationIterator = struct {
    allocator: std.mem.Allocator,
    fetch_func: *const fn (allocator: std.mem.Allocator, after: ?[]const u8) anyerror!CursorPage(void),
    current_page: ?CursorPage(void),
    done: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        fetch_func: *const fn (allocator: std.mem.Allocator, after: ?[]const u8) anyerror!CursorPage(void),
    ) PaginationIterator {
        return .{
            .allocator = allocator,
            .fetch_func = fetch_func,
            .current_page = null,
            .done = false,
        };
    }

    pub fn deinit(self: *PaginationIterator) void {
        if (self.current_page) |page| {
            page.deinit();
        }
    }

    /// Get the next page of results
    pub fn next(self: *PaginationIterator) !?CursorPage(void) {
        if (self.done) return null;

        const after = if (self.current_page) |page| page.after else null;

        const page = try self.fetch_func(self.allocator, after);
        self.done = !page.has_more;
        self.current_page = page;

        if (page.data.len == 0) {
            return null;
        }

        return page;
    }
};

// ============================================================================
// Page Builder
// ============================================================================

pub const PageBuilder = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PageBuilder {
        return .{ .allocator = allocator };
    }

    /// Parse a cursor page response
    pub fn parseCursorPage(self: *PageBuilder, comptime T: type, response: []const u8) !CursorPage(T) {
        _ = self;
        _ = response;
        return CursorPage(T){
            .allocator = undefined,
            .data = &.{},
            .has_more = false,
            .after = null,
            .before = null,
        };
    }
};

// ============================================================================
// List Helper Functions
// ============================================================================

pub const ListOptions = struct {
    after: ?[]const u8 = null,
    limit: ?u32 = null,
    order: ?[]const u8 = null,
    before: ?[]const u8 = null,
};

pub fn ListResponse(comptime T: type) type {
    return struct {
        data: []T,
        has_more: bool,
        first_id: ?[]const u8,
        last_id: ?[]const u8,
    };
}

/// Collect all items from a paginated API into a single list
pub fn collectAll(
    allocator: std.mem.Allocator,
    initial_page: ListResponse(void),
    fetch_next: *const fn (after: ?[]const u8) anyerror!ListResponse(void),
) ![]void {
    var all_items = std.ArrayList(void).init(allocator);
    errdefer all_items.deinit();

    // Add initial items
    try all_items.appendSlice(initial_page.data);

    // Fetch remaining pages
    var last_id = initial_page.last_id;
    while (initial_page.has_more) {
        const next_page = try fetch_next(last_id);
        try all_items.appendSlice(next_page.data);
        last_id = next_page.last_id;
        if (!next_page.has_more) break;
    }

    return try all_items.toOwnedSlice();
}

// ============================================================================
// Auto-Pagination Wrapper
// ============================================================================

pub const AutoPager = struct {
    allocator: std.mem.Allocator,
    client: *anyopaque,
    get_next_page: *const fn (client: *anyopaque, after: ?[]const u8) anyerror!ListResponse(void),

    pub fn init(
        allocator: std.mem.Allocator,
        client: *anyopaque,
        get_next_page: *const fn (client: *anyopaque, after: ?[]const u8) anyerror!ListResponse(void),
    ) AutoPager {
        return .{
            .allocator = allocator,
            .client = client,
            .get_next_page = get_next_page,
        };
    }

    pub fn deinit(self: *AutoPager) void {
        _ = self;
    }

    /// Iterate through all pages lazily
    pub fn iter(self: *AutoPager, first_page: ListResponse(void)) PagerIterator {
        return PagerIterator{
            .pager = self,
            .current_data = first_page.data,
            .current_idx = 0,
            .last_id = first_page.last_id,
            .has_more = first_page.has_more,
        };
    }
};

pub const PagerIterator = struct {
    pager: *AutoPager,
    current_data: []void,
    current_idx: usize,
    last_id: ?[]const u8,
    has_more: bool,

    pub fn next(self: *PagerIterator) ?void {
        if (self.current_idx >= self.current_data.len) {
            if (self.has_more) {
                // Fetch next page
                const next_page = self.pager.get_next_page(self.pager.client, self.last_id) catch return null;
                self.current_data = next_page.data;
                self.current_idx = 0;
                self.last_id = next_page.last_id;
                self.has_more = next_page.has_more;

                if (self.current_data.len == 0) return null;
            } else {
                return null;
            }
        }

        const item = self.current_data[self.current_idx];
        self.current_idx += 1;
        return item;
    }
};

// ============================================================================
// Async Pagination Support
// ============================================================================

pub const AsyncPager = struct {
    allocator: std.mem.Allocator,
    client: *anyopaque,
    fetch_page: *const fn (client: *anyopaque, after: ?[]const u8) anyerror!ListResponse(void),

    pub fn init(
        allocator: std.mem.Allocator,
        client: *anyopaque,
        fetch_page: *const fn (client: *anyopaque, after: ?[]const u8) anyerror!ListResponse(void),
    ) AsyncPager {
        return .{
            .allocator = allocator,
            .client = client,
            .fetch_page = fetch_page,
        };
    }

    pub fn deinit(self: *AsyncPager) void {
        _ = self;
    }

    /// Async iterator through pages
    pub fn iterate(self: *AsyncPager, initial_page: ListResponse(void)) AsyncPagerIterator {
        return AsyncPagerIterator{
            .pager = self,
            .current_data = initial_page.data,
            .current_idx = 0,
            .last_id = initial_page.last_id,
            .has_more = initial_page.has_more,
            .fetching = false,
        };
    }
};

pub const AsyncPagerIterator = struct {
    pager: *AsyncPager,
    current_data: []void,
    current_idx: usize,
    last_id: ?[]const u8,
    has_more: bool,
    fetching: bool,

    pub fn next(self: *AsyncPagerIterator) ?void {
        if (self.fetching) return null;

        if (self.current_idx >= self.current_data.len) {
            if (self.has_more) {
                self.fetching = true;
                // In async context, would fetch next page
                return null;
            } else {
                return null;
            }
        }

        const item = self.current_data[self.current_idx];
        self.current_idx += 1;
        return item;
    }
};
