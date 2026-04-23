//! Unified Handler - GET /analytics/unified
//!
//! Aggregates API cost (from tracking store) and cmd savings data.

const std = @import("std");
const shared = @import("shared_analytics");
const savings_store_mod = @import("proxy_savings_store");

pub const UnifiedHandler = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    savings_store: *savings_store_mod.SavingsStore,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, savings_store: *savings_store_mod.SavingsStore) UnifiedHandler {
        return .{
            .allocator = allocator,
            .io = io,
            .savings_store = savings_store,
        };
    }

    /// Handle GET /analytics/unified?days=N&team_id=X
    pub fn handleGet(self: *UnifiedHandler, stream: std.Io.net.Stream, request_text: []const u8) !void {
        // Parse query parameters from request line
        const days = parseQueryParamU32(request_text, "days=");
        _ = parseQueryParam(request_text, "team_id="); // reserved for future use

        // Get cmd savings from savings store
        const cmd_savings = self.savings_store.aggregate(days, null);

        // TODO: Get api_cost from usage tracker once integrated into Server
        // For now, return zero-valued api_cost summary
        const api_cost = shared.ApiCostSummary{};

        // Net cost = API cost minus estimated savings value
        // Rough estimate: 1 token ≈ $0.000002 (2e-6) for average model
        const savings_value_usd = @as(f64, @floatFromInt(cmd_savings.total_saved_tokens)) * 0.000002;
        const net_cost = api_cost.total_cost_usd - savings_value_usd;

        const response_data = shared.UnifiedResponse{
            .api_cost = api_cost,
            .cmd_savings = cmd_savings,
            .net_cost = net_cost,
        };

        const json_response = shared.serializeUnifiedResponse(self.allocator, response_data) catch {
            try self.writeJsonResponse(stream, 500, "{\"error\":\"Failed to serialize response\"}");
            return;
        };
        defer self.allocator.free(json_response);
        try self.writeJsonResponse(stream, 200, json_response);
    }
    fn writeJsonResponse(self: *UnifiedHandler, stream: std.Io.net.Stream, status: u16, body: []const u8) !void {
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

fn parseQueryParam(request_text: []const u8, prefix: []const u8) ?[]const u8 {
    const path_end = std.mem.find(u8, request_text, " HTTP/1.") orelse return null;
    const path = request_text[0..path_end];
    const query_start = std.mem.find(u8, path, "?") orelse return null;
    const query = path[query_start + 1 ..];

    var it = std.mem.splitScalar(u8, query, '&');
    while (it.next()) |param| {
        if (std.mem.startsWith(u8, param, prefix)) {
            return param[prefix.len..];
        }
    }
    return null;
}

fn parseQueryParamU32(request_text: []const u8, prefix: []const u8) ?u32 {
    const value = parseQueryParam(request_text, prefix) orelse return null;
    return std.fmt.parseInt(u32, value, 10) catch null;
}


