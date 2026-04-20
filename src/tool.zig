//! Tool Calling - Function calling support for OpenAI APIs
//!
//! This module provides:
//! - Tool/Function definitions (JSON Schema based)
//! - Tool execution framework
//! - Automatic function call parsing
//!
//! Reference: https://platform.openai.com/docs/guides/function-calling

const std = @import("std");
const json = std.json;

// ============================================================================
// Tool Definition
// ============================================================================

pub const Tool = struct {
    name: []const u8,
    description: []const u8,
    parameters: ToolParameters,
};

pub const ToolParameters = struct {
    type: []const u8 = "object",
    properties: std.StringHashMap(ToolProperty),
    required: ?[]const []const u8 = null,
};

pub const ToolProperty = struct {
    type: []const u8,
    description: ?[]const u8 = null,
    @"enum": ?[]const []const u8 = null,
};

/// Converts a Tool to JSON string for API requests
pub fn toolToJson(allocator: std.mem.Allocator, tool: Tool) ![]u8 {
    var properties_json = std.ArrayListUnmanaged(u8){};
    errdefer properties_json.deinit(allocator);

    // Build properties object
    var props_iter = tool.parameters.properties.iterator();
    var first = true;
    while (props_iter.next()) |entry| {
        if (!first) try properties_json.appendSlice(allocator, ",");
        first = false;

        try properties_json.appendSlice(allocator, "\"");
        try properties_json.appendSlice(allocator, entry.key_ptr.*);
        try properties_json.appendSlice(allocator, "\":{");
        try properties_json.appendSlice(allocator, "\"type\":\"");
        try properties_json.appendSlice(allocator, entry.value_ptr.type);
        try properties_json.appendSlice(allocator, "\"");

        if (entry.value_ptr.description) |desc| {
            try properties_json.appendSlice(allocator, ",\"description\":\"");
            try properties_json.appendSlice(allocator, desc);
            try properties_json.appendSlice(allocator, "\"");
        }

        if (entry.value_ptr.@"enum") |enum_vals| {
            try properties_json.appendSlice(allocator, ",\"enum\":[");
            for (enum_vals, 0..) |val, i| {
                if (i > 0) try properties_json.appendSlice(allocator, ",");
                try properties_json.appendSlice(allocator, "\"");
                try properties_json.appendSlice(allocator, val);
                try properties_json.appendSlice(allocator, "\"");
            }
            try properties_json.appendSlice(allocator, "]");
        }

        try properties_json.appendSlice(allocator, "}");
    }

    // Build required array
    var required_json = std.ArrayListUnmanaged(u8){};
    errdefer required_json.deinit(allocator);

    if (tool.parameters.required) |req| {
        for (req, 0..) |r, i| {
            if (i > 0) try required_json.appendSlice(allocator, ",");
            try required_json.appendSlice(allocator, "\"");
            try required_json.appendSlice(allocator, r);
            try required_json.appendSlice(allocator, "\"");
        }
    }

    // Build final JSON
    return std.fmt.allocPrint(allocator,
        \\{{"type":"function","name":"{s}","description":"{s}","parameters":{{"type":"object","properties":{{{s}}},"required":[{s}]}}}}
    , .{
        tool.name,
        tool.description,
        try properties_json.toOwnedSlice(allocator),
        try required_json.toOwnedSlice(allocator),
    });
}

// ============================================================================
// Tool Execution
// ============================================================================

pub const ToolResult = struct {
    call_id: []const u8,
    output: []const u8,
};

pub const ToolExecutor = struct {
    allocator: std.mem.Allocator,
    tools: std.StringHashMap(ToolHandler),

    pub fn init(allocator: std.mem.Allocator) ToolExecutor {
        return .{
            .allocator = allocator,
            .tools = std.StringHashMap(ToolHandler).init(allocator),
        };
    }

    pub fn deinit(self: *ToolExecutor) void {
        var it = self.tools.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.tools.deinit();
    }

    /// Register a tool handler
    pub fn register(self: *ToolExecutor, tool: Tool, handler: ToolHandlerFunc) !void {
        const name = try self.allocator.dupe(u8, tool.name);
        errdefer self.allocator.free(name);
        try self.tools.put(name, handler);
    }

    /// Execute a tool call by name with arguments
    pub fn execute(self: *ToolExecutor, name: []const u8, call_id: []const u8, arguments: []const u8) !ToolResult {
        const handler = self.tools.get(name) orelse return error.UnknownTool;

        // Parse arguments JSON
        const parsed = try json.parseFromSlice(std.json.Value, self.allocator, arguments, .{});
        defer parsed.deinit();

        // Execute handler
        const result = try handler(self.allocator, parsed.value);

        return ToolResult{
            .call_id = try self.allocator.dupe(u8, call_id),
            .output = result,
        };
    }
};

pub const ToolHandler = struct {
    func: ToolHandlerFunc,
};

pub const ToolHandlerFunc = fn (allocator: std.mem.Allocator, arguments: std.json.Value) anyerror![]const u8;

/// Create a tool handler from a typed function
/// Note: This uses std.json.parseFromValue for type-safe JSON deserialization.
pub fn createHandler(comptime T: type, func: *const fn (std.mem.Allocator, T) anyerror![]const u8) ToolHandlerFunc {
    return struct {
        fn handler(allocator: std.mem.Allocator, args: std.json.Value) anyerror![]const u8 {
            const parsed = try json.parseFromValue(T, allocator, args, .{});
            defer parsed.deinit();
            return try func(allocator, parsed.value);
        }
    }.handler;
}

// ============================================================================
// Built-in Tool Templates
// ============================================================================

/// Creates a weather tool definition
/// Caller must provide an allocator for the properties HashMap.
pub fn weatherTool(allocator: std.mem.Allocator) Tool {
    return Tool{
        .name = "get_weather",
        .description = "Get the current weather in a given location",
        .parameters = .{
            .type = "object",
            .properties = std.StringHashMap(ToolProperty).init(allocator),
            .required = &.{"location"},
        },
    };
}

/// Helper to build a tool with properties
pub fn buildTool(name: []const u8, description: []const u8) ToolBuilder {
    return .{
        .name = name,
        .description = description,
    };
}

pub const ToolBuilder = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    description: []const u8,
    properties: std.StringHashMap(ToolProperty),
    required: std.ArrayListUnmanaged([]const u8),

    pub fn init(allocator: std.mem.Allocator) ToolBuilder {
        return .{
            .allocator = allocator,
            .name = undefined,
            .description = undefined,
            .properties = std.StringHashMap(ToolProperty).init(allocator),
            .required = std.ArrayListUnmanaged([]const u8){},
        };
    }

    pub fn deinit(self: *ToolBuilder) void {
        self.properties.deinit();
        self.required.deinit(self.allocator);
    }

    pub fn addProperty(self: *ToolBuilder, key: []const u8, prop: ToolProperty, required: bool) !*ToolBuilder {
        try self.properties.put(key, prop);
        if (required) {
            try self.required.append(self.properties.allocator, key);
        }
        return self;
    }

    pub fn addStringProperty(self: *ToolBuilder, key: []const u8, description: []const u8, required: bool) !*ToolBuilder {
        return self.addProperty(key, .{ .type = "string", .description = description }, required);
    }

    pub fn addIntegerProperty(self: *ToolBuilder, key: []const u8, description: []const u8, required: bool) !*ToolBuilder {
        return self.addProperty(key, .{ .type = "integer", .description = description }, required);
    }

    pub fn addNumberProperty(self: *ToolBuilder, key: []const u8, description: []const u8, required: bool) !*ToolBuilder {
        return self.addProperty(key, .{ .type = "number", .description = description }, required);
    }

    pub fn addBooleanProperty(self: *ToolBuilder, key: []const u8, description: []const u8, required: bool) !*ToolBuilder {
        return self.addProperty(key, .{ .type = "boolean", .description = description }, required);
    }

    pub fn addEnumProperty(self: *ToolBuilder, key: []const u8, description: []const u8, enum_vals: [][]const u8, required: bool) !*ToolBuilder {
        return self.addProperty(key, .{ .type = "string", .description = description, .@"enum" = enum_vals }, required);
    }

    pub fn finish(self: *ToolBuilder) !Tool {
        return Tool{
            .name = self.name,
            .description = self.description,
            .parameters = .{
                .type = "object",
                .properties = self.properties,
                .required = if (self.required.items.len > 0) try self.required.toOwnedSlice(self.allocator) else null,
            },
        };
    }
};

// ============================================================================
// Tool Call Parsing
// ============================================================================

pub const FunctionCall = struct {
    name: []const u8,
    arguments: []const u8,
};

pub const ToolCall = struct {
    id: []const u8,
    function: FunctionCall,
};

/// Parse a tool call from Chat Completion message content
pub fn parseToolCalls(allocator: std.mem.Allocator, content: []const u8) ![]ToolCall {
    var calls = std.ArrayListUnmanaged(ToolCall){};
    errdefer calls.deinit(allocator);

    // Find all tool_call objects in the content
    var search_idx: usize = 0;
    while (true) {
        const call_start = std.mem.indexOf(u8, content[search_idx..], "\"tool_calls\":[") orelse break;
        var after_calls = content[search_idx + call_start + 13 ..];

        // Parse each tool call
        while (after_calls.len > 0 and after_calls[0] != ']') {
            // Skip whitespace
            while (after_calls.len > 0 and (after_calls[0] == ' ' or after_calls[0] == '\n' or after_calls[0] == ',')) {
                after_calls = after_calls[1..];
            }

            if (after_calls.len == 0 or after_calls[0] == ']') break;

            // Find the tool call object (look for "id" field)
            const id_start = std.mem.indexOf(u8, after_calls, "\"id\":\"") orelse break;
            const id_value_start = after_calls[id_start + 6 ..];
            const id_end = std.mem.indexOf(u8, id_value_start, "\"") orelse break;
            const id = id_value_start[0..id_end];

            // Find function name
            const name_start = std.mem.indexOf(u8, after_calls[id_start..], "\"function\":{\"name\":\"") orelse break;
            const name_value_start = after_calls[id_start + name_start + 17 ..];
            const name_end = std.mem.indexOf(u8, name_value_start, "\"") orelse break;
            const name = name_value_start[0..name_end];

            // Find arguments
            const args_start = std.mem.indexOf(u8, after_calls[name_start..], "\"arguments\":\"") orelse break;
            const args_value_start = after_calls[name_start + args_start + 14 ..];
            const args_end = std.mem.indexOf(u8, args_value_start, "\"") orelse break;
            const args = args_value_start[0..args_end];

            try calls.append(allocator, ToolCall{
                .id = try allocator.dupe(u8, id),
                .function = .{
                    .name = try allocator.dupe(u8, name),
                    .arguments = try allocator.dupe(u8, args),
                },
            });

            after_calls = after_calls[id_start + name_start + args_start + args_end + 15 ..];
        }

        search_idx += call_start + 13;
    }

    return try calls.toOwnedSlice(allocator);
}

/// Build a tool message for continuing the conversation after tool execution
pub fn buildToolMessage(allocator: std.mem.Allocator, call_id: []const u8, output: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator,
        \\{{"role":"tool","tool_call_id":"{s}","content":"{s}"}}
    , .{ call_id, output });
}

/// Build multiple tool messages
pub fn buildToolMessages(allocator: std.mem.Allocator, results: []const ToolResult) ![]u8 {
    var result_json = std.ArrayListUnmanaged(u8){};
    defer result_json.deinit(allocator);

    try result_json.appendSlice(allocator, "[");
    for (results, 0..) |result, i| {
        if (i > 0) try result_json.appendSlice(allocator, ",");
        try result_json.appendSlice(allocator, try buildToolMessage(allocator, result.call_id, result.output));
    }
    try result_json.appendSlice(allocator, "]");

    return try result_json.toOwnedSlice(allocator);
}
