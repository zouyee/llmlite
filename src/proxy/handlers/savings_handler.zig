//! Savings Handler - POST /tracking/savings and POST /tracking/savings/batch

const std = @import("std");
const shared = @import("shared_analytics");
const savings_store_mod = @import("proxy_savings_store");

pub const SavingsHandler = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *savings_store_mod.SavingsStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *savings_store_mod.SavingsStore) SavingsHandler {
        return .{
            .allocator = allocator,
            .io = io,
            .store = store,
        };
    }

    /// Handle POST /tracking/savings
    pub fn handlePost(self: *SavingsHandler, stream: std.Io.net.Stream, request_text: []const u8) !void {
        const body_start = std.mem.find(u8, request_text, "\r\n\r\n");
        if (body_start == null) {
            try self.writeJsonResponse(stream, 400, "{\"error\":\"Missing request body\"}");
            return;
        }
        const body = request_text[body_start.? + 4 ..];

        const report = shared.parseSavingsReport(self.allocator, body) catch |err| {
            const msg = switch (err) {
                error.SyntaxError => "invalid JSON",
                error.MissingField => "missing required field",
                else => "parse error",
            };
            const response = try std.fmt.allocPrint(self.allocator, "{{\"error\":\"{s}\"}}", .{msg});
            defer self.allocator.free(response);
            try self.writeJsonResponse(stream, 400, response);
            return;
        };
        defer {
            self.allocator.free(report.original_cmd);
            self.allocator.free(report.hostname);
        }

        // Store the report (store makes its own deep copy)
        self.store.addReport(report) catch {
            try self.writeJsonResponse(stream, 500, "{\"error\":\"Failed to store report\"}");
            return;
        };

        try self.writeJsonResponse(stream, 200, "{\"status\":\"ok\"}");
    }

    /// Handle POST /tracking/savings/batch
    pub fn handleBatchPost(self: *SavingsHandler, stream: std.Io.net.Stream, request_text: []const u8) !void {
        const body_start = std.mem.find(u8, request_text, "\r\n\r\n");
        if (body_start == null) {
            try self.writeJsonResponse(stream, 400, "{\"error\":\"Missing request body\"}");
            return;
        }
        const body = request_text[body_start.? + 4 ..];

        // Parse as array of SavingsReport
        const parsed = std.json.parseFromSlice([]shared.SavingsReport, self.allocator, body, .{}) catch {
            try self.writeJsonResponse(stream, 400, "{\"error\":\"Invalid JSON array\"}");
            return;
        };
        defer parsed.deinit();

        var accepted: usize = 0;
        var rejected: usize = 0;

        for (parsed.value) |report| {
            self.store.addReport(report) catch {
                rejected += 1;
                continue;
            };
            accepted += 1;
        }

        const response = try std.json.Stringify.valueAlloc(self.allocator, .{
            .accepted = accepted,
            .rejected = rejected,
        }, .{});
        defer self.allocator.free(response);
        try self.writeJsonResponse(stream, 200, response);
    }

    fn writeJsonResponse(self: *SavingsHandler, stream: std.Io.net.Stream, status: u16, body: []const u8) !void {
        var buf: [32]u8 = undefined;
        const status_line = try std.fmt.bufPrint(&buf, "HTTP/1.1 {d} OK\r\n", .{status});
        var write_buf: [4096]u8 = undefined;
        var writer = stream.writer(self.io, &write_buf);
        try writer.interface.writeAll(status_line);
        try writer.interface.writeAll("Content-Type: application/json\r\n");
        try writer.interface.writeAll("\r\n");
        try writer.interface.writeAll(body);
        try writer.interface.flush();
    }
};
