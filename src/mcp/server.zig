//! MCP Server Implementation - JSON-RPC 2.0 Protocol Handler
//!
//! Handles MCP protocol requests and dispatches to registered tools

const std = @import("std");
const types = @import("mcp_types");
const tools = @import("mcp_tools");

pub const Server = struct {
    allocator: std.mem.Allocator,
    initialized: bool = false,
    protocol_version: []const u8 = "2024-11-05",
    server_name: []const u8,
    server_version: []const u8,

    io: std.Io,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, name: []const u8, version: []const u8) Server {
        return .{
            .allocator = allocator,
            .io = io,
            .server_name = name,
            .server_version = version,
        };
    }

    /// Handle an incoming JSON-RPC request
    pub fn handleRequest(self: *Server, request_json: []const u8) ![]u8 {
        const request = std.json.parseFromSlice(types.JsonRpcRequest, self.allocator, request_json, .{}) catch {
            return self.errorResponse(null, types.ErrorCodes.ParseError, "Invalid JSON");
        };
        defer request.deinit();
        return self.dispatch(request.value);
    }

    fn dispatch(self: *Server, request: types.JsonRpcRequest) ![]u8 {
        const method = request.method;

        if (std.mem.eql(u8, method, types.Methods.Initialize)) {
            return self.handleInitialize(request);
        }

        if (!self.initialized) {
            return self.errorResponse(request.id, types.ErrorCodes.ServerNotInitialized, "Server not initialized");
        }

        if (std.mem.eql(u8, method, types.Methods.ToolsList)) {
            return self.handleToolsList(request);
        }

        if (std.mem.eql(u8, method, types.Methods.ToolsCall)) {
            return self.handleToolsCall(request);
        }

        if (std.mem.eql(u8, method, types.Methods.ResourcesList)) {
            return self.handleResourcesList(request);
        }

        if (std.mem.eql(u8, method, types.Methods.Ping)) {
            return self.successResponse(request.id, "true");
        }

        if (std.mem.eql(u8, method, types.Methods.Shutdown)) {
            self.initialized = false;
            return self.successResponse(request.id, "true");
        }

        return self.errorResponse(request.id, types.ErrorCodes.MethodNotFound, "Unknown method");
    }

    fn successResponse(self: *Server, id: ?std.json.Value, result: []const u8) ![]u8 {
        const id_str = if (id) |v| try self.idToJson(v) else "null";
        return try std.fmt.allocPrint(self.allocator, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":{s}}}", .{ id_str, result });
    }

    fn errorResponse(self: *Server, id: ?std.json.Value, code: i32, message: []const u8) ![]u8 {
        const id_str = if (id) |v| try self.idToJson(v) else "null";
        return try std.fmt.allocPrint(self.allocator, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"error\":{{\"code\":{},\"message\":\"{s}\"}}}}", .{ id_str, code, message });
    }

    fn idToJson(self: *Server, id: std.json.Value) ![]u8 {
        return switch (id) {
            .string => |s| try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{s}),
            .integer => |i| try std.fmt.allocPrint(self.allocator, "{}", .{i}),
            .float => |f| try std.fmt.allocPrint(self.allocator, "{}", .{f}),
            else => try self.allocator.dupe(u8, "null"),
        };
    }

    fn handleInitialize(self: *Server, request: types.JsonRpcRequest) ![]u8 {
        self.initialized = true;
        const response = try std.fmt.allocPrint(self.allocator, "{{\"protocol_version\":\"2024-11-05\",\"capabilities\":{{\"tools\":{{}},\"resources\":{{\"subscribe\":false,\"list_changed\":false}},\"prompts\":{{\"list_changed\":false}}}},\"server_info\":{{\"name\":\"{s}\",\"version\":\"{s}\"}}}}", .{ self.server_name, self.server_version });
        return self.successResponse(request.id, response);
    }

    fn handleToolsList(self: *Server, request: types.JsonRpcRequest) ![]u8 {
        const tool_list = tools.listTools();
        var tools_json = std.array_list.Managed(u8).init(self.allocator);
        defer tools_json.deinit();
        
        // Build JSON string manually for Zig 0.16.0 compatibility
        try tools_json.appendSlice("[");
        for (tool_list.tools, 0..) |tool, i| {
            if (i > 0) try tools_json.appendSlice(",");
            const tool_json = try std.fmt.allocPrint(self.allocator, "{{\"name\":\"{s}\",\"description\":\"{s}\",\"inputSchema\":{{}}}}", .{ tool.name, tool.description });
            defer self.allocator.free(tool_json);
            try tools_json.appendSlice(tool_json);
        }
        try tools_json.appendSlice("]");
        const result = try std.fmt.allocPrint(self.allocator, "{{\"tools\":{s}}}", .{tools_json.items});
        return self.successResponse(request.id, result);
    }

    fn handleToolsCall(self: *Server, request: types.JsonRpcRequest) ![]u8 {
        const params = request.params orelse {
            return self.errorResponse(request.id, types.ErrorCodes.InvalidParams, "Missing params");
        };
        const tool_name = extractToolName(params) orelse {
            return self.errorResponse(request.id, types.ErrorCodes.InvalidParams, "Missing tool name");
        };
        const tool_result = tools.callTool(self.allocator, self.io, tool_name, request.params) catch {
            return self.errorResponse(request.id, types.ErrorCodes.InternalError, "Tool execution failed");
        };

        // Build content manually with string concatenation
        var content_parts = std.ArrayListUnmanaged([]const u8).empty;
        defer content_parts.deinit(self.allocator);

        for (tool_result.content) |block| {
            // Escape the text content for JSON
            const escaped = try self.escapeJsonString(block.text);
            const entry = try std.fmt.allocPrint(self.allocator, "{{\"type\":\"{s}\",\"text\":{s}}}", .{ block.type, escaped });
            try content_parts.append(self.allocator, entry);
        }

        // Join content parts with commas
        var content_json: std.ArrayListUnmanaged(u8) = .empty;
        for (content_parts.items, 0..) |part, i| {
            if (i > 0) try content_json.appendSlice(self.allocator, ",");
            try content_json.appendSlice(self.allocator, part);
        }

        // Free individual parts
        for (content_parts.items) |part| {
            self.allocator.free(part);
        }
        // Note: We don't free block.text or destroy blocks because
        // text might be a static string literal. For stdio-based MCP
        // servers that exit after each request, leaking is acceptable.

        const is_err: []const u8 = if (tool_result.is_error) "true" else "false";
        const result = try std.fmt.allocPrint(self.allocator, "{{\"content\":[{s}],\"isError\":{s}}}", .{ try content_json.toOwnedSlice(self.allocator), is_err });
        return self.successResponse(request.id, result);
    }

    /// Escape a string for JSON embedding
    fn escapeJsonString(self: *Server, str: []const u8) ![]u8 {
        var result: std.ArrayListUnmanaged(u8) = .empty;
        errdefer result.deinit(self.allocator);

        try result.appendSlice(self.allocator, "\"");
        for (str) |byte| {
            switch (byte) {
                '"' => try result.appendSlice(self.allocator, "\\\""),
                '\\' => try result.appendSlice(self.allocator, "\\\\"),
                '\n' => try result.appendSlice(self.allocator, "\\n"),
                '\r' => try result.appendSlice(self.allocator, "\\r"),
                '\t' => try result.appendSlice(self.allocator, "\\t"),
                0x08 => try result.appendSlice(self.allocator, "\\b"),
                0x0C => try result.appendSlice(self.allocator, "\\f"),
                else => {
                    if (byte < 0x20) {
                        var buf: [6]u8 = undefined;
                        const slice = try std.fmt.bufPrint(&buf, "\\u{X:0>4}", .{byte});
                        try result.appendSlice(self.allocator, slice);
                    } else {
                        try result.append(self.allocator, byte);
                    }
                },
            }
        }
        try result.appendSlice(self.allocator, "\"");

        return try result.toOwnedSlice(self.allocator);
    }

    fn extractToolName(params: std.json.Value) ?[]const u8 {
        if (params != .object) return null;
        const obj = params.object;
        const name = obj.get("name") orelse return null;
        if (name != .string) return null;
        return name.string;
    }

    fn handleResourcesList(self: *Server, request: types.JsonRpcRequest) ![]u8 {
        return self.successResponse(request.id, "{}");
    }
};
