//! HTTP Header Case Preserver
//!
//! Captures and preserves the original casing of HTTP header names from raw TCP bytes.
//! Some upstream providers are sensitive to header name casing, while Zig's std.http
//! normalizes header names to lowercase.
//!
//! Usage:
//!   var preserver = HeaderCasePreserver.init(allocator);
//!   defer preserver.deinit();
//!   try preserver.captureFromRawBytes(raw_request);
//!   const original = preserver.getOriginalCase("content-type"); // "Content-Type"

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

pub const HeaderCasePreserver = struct {
    allocator: std.mem.Allocator,
    /// Maps lowercase header name → original casing
    original_cases: StringArrayHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) HeaderCasePreserver {
        return .{
            .allocator = allocator,
            .original_cases = StringArrayHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *HeaderCasePreserver) void {
        var it = self.original_cases.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.original_cases.deinit();
    }

    /// Parse raw HTTP request bytes to extract header name casing.
    /// Skips the request line (first \r\n), then parses each "Header-Name: value\r\n",
    /// storing lowercase(name) → name mapping.
    pub fn captureFromRawBytes(self: *HeaderCasePreserver, raw_request: []const u8) !void {
        // Find end of request line
        const header_start = std.mem.find(u8, raw_request, "\r\n") orelse return;
        var pos = header_start + 2;

        while (pos < raw_request.len) {
            // End of headers
            if (pos + 1 < raw_request.len and raw_request[pos] == '\r' and raw_request[pos + 1] == '\n') {
                break;
            }

            const line_end = std.mem.findPos(u8, raw_request, pos, "\r\n") orelse raw_request.len;
            const line = raw_request[pos..line_end];

            if (std.mem.findScalar(u8, line, ':')) |colon_idx| {
                const original_name = line[0..colon_idx];
                if (original_name.len > 0) {
                    const lower_key = try self.allocator.alloc(u8, original_name.len);
                    errdefer self.allocator.free(lower_key);
                    for (original_name, 0..) |c, i| {
                        lower_key[i] = std.ascii.toLower(c);
                    }

                    const original_dupe = try self.allocator.dupe(u8, original_name);
                    errdefer self.allocator.free(original_dupe);

                    const maybe_old = try self.original_cases.fetchPut(lower_key, original_dupe);
                    if (maybe_old) |old| {
                        self.allocator.free(old.key);
                        self.allocator.free(old.value);
                    }
                }
            }

            pos = if (line_end + 2 <= raw_request.len) line_end + 2 else raw_request.len;
        }
    }

    /// Return the original casing for a lowercase header name, or null if not captured.
    pub fn getOriginalCase(self: *const HeaderCasePreserver, lowercase_name: []const u8) ?[]const u8 {
        return self.original_cases.get(lowercase_name);
    }

    /// Write a header using original case if available, otherwise use the provided name.
    pub fn writeHeaderWithOriginalCase(
        self: *const HeaderCasePreserver,
        writer: anytype,
        name: []const u8,
        value: []const u8,
    ) !void {
        const header_name = self.getOriginalCase(name) orelse name;
        try writer.writeAll(header_name);
        try writer.writeAll(": ");
        try writer.writeAll(value);
        try writer.writeAll("\r\n");
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "header_case - init and deinit" {
    var preserver = HeaderCasePreserver.init(std.testing.allocator);
    defer preserver.deinit();
    try std.testing.expectEqual(@as(usize, 0), preserver.original_cases.count());
}

test "header_case - captureFromRawBytes basic" {
    var preserver = HeaderCasePreserver.init(std.testing.allocator);
    defer preserver.deinit();

    const raw =
        "GET /v1/messages HTTP/1.1\r\n" ++
        "Content-Type: application/json\r\n" ++
        "X-Api-Key: sk-test\r\n" ++
        "Authorization: Bearer token\r\n" ++
        "\r\n";

    try preserver.captureFromRawBytes(raw);

    try std.testing.expectEqualStrings("Content-Type", preserver.getOriginalCase("content-type").?);
    try std.testing.expectEqualStrings("X-Api-Key", preserver.getOriginalCase("x-api-key").?);
    try std.testing.expectEqualStrings("Authorization", preserver.getOriginalCase("authorization").?);
}

test "header_case - getOriginalCase unknown header returns null" {
    var preserver = HeaderCasePreserver.init(std.testing.allocator);
    defer preserver.deinit();

    const raw =
        "POST /v1/messages HTTP/1.1\r\n" ++
        "Content-Type: application/json\r\n" ++
        "\r\n";

    try preserver.captureFromRawBytes(raw);
    try std.testing.expect(preserver.getOriginalCase("x-unknown-header") == null);
}

test "header_case - preserves mixed case" {
    var preserver = HeaderCasePreserver.init(std.testing.allocator);
    defer preserver.deinit();

    const raw =
        "GET / HTTP/1.1\r\n" ++
        "X-Custom-HEADER: value1\r\n" ++
        "aNtHrOpIc-VeRsIoN: 2024-01-01\r\n" ++
        "\r\n";

    try preserver.captureFromRawBytes(raw);

    try std.testing.expectEqualStrings("X-Custom-HEADER", preserver.getOriginalCase("x-custom-header").?);
    try std.testing.expectEqualStrings("aNtHrOpIc-VeRsIoN", preserver.getOriginalCase("anthropic-version").?);
}

test "header_case - writeHeaderWithOriginalCase uses original case" {
    var preserver = HeaderCasePreserver.init(std.testing.allocator);
    defer preserver.deinit();

    const raw =
        "GET / HTTP/1.1\r\n" ++
        "Content-Type: application/json\r\n" ++
        "\r\n";

    try preserver.captureFromRawBytes(raw);

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try preserver.writeHeaderWithOriginalCase(writer, "content-type", "text/plain");
    try std.testing.expectEqualStrings("Content-Type: text/plain\r\n", fbs.getWritten());
}

test "header_case - writeHeaderWithOriginalCase falls back to provided name" {
    var preserver = HeaderCasePreserver.init(std.testing.allocator);
    defer preserver.deinit();

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try preserver.writeHeaderWithOriginalCase(writer, "x-new-header", "value");
    try std.testing.expectEqualStrings("x-new-header: value\r\n", fbs.getWritten());
}

test "header_case - duplicate header names keep last occurrence" {
    var preserver = HeaderCasePreserver.init(std.testing.allocator);
    defer preserver.deinit();

    const raw =
        "GET / HTTP/1.1\r\n" ++
        "X-Custom: first\r\n" ++
        "x-custom: second\r\n" ++
        "\r\n";

    try preserver.captureFromRawBytes(raw);
    try std.testing.expectEqualStrings("x-custom", preserver.getOriginalCase("x-custom").?);
}

test "header_case - empty request no crash" {
    var preserver = HeaderCasePreserver.init(std.testing.allocator);
    defer preserver.deinit();

    try preserver.captureFromRawBytes("GET / HTTP/1.1");
    try std.testing.expectEqual(@as(usize, 0), preserver.original_cases.count());
}

test "header_case - request line only" {
    var preserver = HeaderCasePreserver.init(std.testing.allocator);
    defer preserver.deinit();

    try preserver.captureFromRawBytes("GET / HTTP/1.1\r\n\r\n");
    try std.testing.expectEqual(@as(usize, 0), preserver.original_cases.count());
}
