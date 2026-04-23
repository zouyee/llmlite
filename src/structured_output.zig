//! Structured Outputs - JSON Schema constrained responses
//!
//! Reference: https://platform.openai.com/docs/guides/structured-outputs
//!
//! Structured Outputs ensures that the model's response follows a JSON schema,
//! enabling type-safe integration with LLM applications.

const std = @import("std");
const json = std.json;

// ============================================================================
// JSON Schema Types
// ============================================================================

pub const JsonSchema = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    schema: Schema,
};

pub const Schema = struct {
    type: ?[]const u8 = null,
    description: ?[]const u8 = null,
    enum_values: ?[]const []const u8 = null,
    properties: ?std.StringHashMap(Schema) = null,
    items: ?*const Schema = null,
    required: ?[]const []const u8 = null,
    const_value: ?[]const u8 = null,
};

/// Generate JSON schema string from a Schema struct
pub fn schemaToJson(allocator: std.mem.Allocator, s: Schema) ![]u8 {
    var parts = std.ArrayListUnmanaged(u8){};
    errdefer parts.deinit(allocator);

    try parts.appendSlice(allocator, "{");

    var first = true;

    if (s.type) |t| {
        if (!first) try parts.appendSlice(allocator, ",");
        first = false;
        try parts.appendSlice(allocator, "\"type\":\"");
        try parts.appendSlice(allocator, t);
        try parts.appendSlice(allocator, "\"");
    }

    if (s.description) |d| {
        if (!first) try parts.appendSlice(allocator, ",");
        first = false;
        try parts.appendSlice(allocator, "\"description\":\"");
        try parts.appendSlice(allocator, d);
        try parts.appendSlice(allocator, "\"");
    }

    if (s.enum_values) |e| {
        if (!first) try parts.appendSlice(allocator, ",");
        first = false;
        try parts.appendSlice(allocator, "\"enum\":[");
        for (e, 0..) |val, i| {
            if (i > 0) try parts.appendSlice(allocator, ",");
            try parts.appendSlice(allocator, "\"");
            try parts.appendSlice(allocator, val);
            try parts.appendSlice(allocator, "\"");
        }
        try parts.appendSlice(allocator, "]");
    }

    if (s.properties) |props| {
        if (!first) try parts.appendSlice(allocator, ",");
        first = false;
        try parts.appendSlice(allocator, "\"properties\":{");

        var prop_iter = props.iterator();
        var prop_first = true;
        while (prop_iter.next()) |entry| {
            if (!prop_first) try parts.appendSlice(allocator, ",");
            prop_first = false;
            try parts.appendSlice(allocator, "\"");
            try parts.appendSlice(allocator, entry.key_ptr.*);
            try parts.appendSlice(allocator, "\":");
            try parts.appendSlice(allocator, try schemaToJson(allocator, entry.value_ptr.*));
        }
        try parts.appendSlice(allocator, "}");
    }

    if (s.items) |item| {
        if (!first) try parts.appendSlice(allocator, ",");
        first = false;
        try parts.appendSlice(allocator, "\"items\":");
        try parts.appendSlice(allocator, try schemaToJson(allocator, item.*));
    }

    if (s.required) |req| {
        if (!first) try parts.appendSlice(allocator, ",");
        first = false;
        try parts.appendSlice(allocator, "\"required\":[");
        for (req, 0..) |r, i| {
            if (i > 0) try parts.appendSlice(allocator, ",");
            try parts.appendSlice(allocator, "\"");
            try parts.appendSlice(allocator, r);
            try parts.appendSlice(allocator, "\"");
        }
        try parts.appendSlice(allocator, "]");
    }

    try parts.appendSlice(allocator, "}");

    return try parts.toOwnedSlice(allocator);
}

/// Generate JSON schema string from a JsonSchema struct
pub fn jsonSchemaToJson(allocator: std.mem.Allocator, js: JsonSchema) ![]u8 {
    var parts = std.ArrayListUnmanaged(u8){};
    defer parts.deinit(allocator);

    try parts.appendSlice(allocator, "{\"type\":\"json_schema\",\"name\":\"");
    try parts.appendSlice(allocator, js.name);
    try parts.appendSlice(allocator, "\",\"schema\":");
    try parts.appendSlice(allocator, try schemaToJson(allocator, js.schema));
    try parts.appendSlice(allocator, "}");

    return try parts.toOwnedSlice(allocator);
}

// ============================================================================
// Schema Builder - Fluent API for building schemas
// ============================================================================

pub const SchemaBuilder = struct {
    allocator: std.mem.Allocator,
    root: *Schema,

    pub fn init(allocator: std.mem.Allocator) !SchemaBuilder {
        const root = try allocator.create(Schema);
        root.* = Schema{};
        return .{ .allocator = allocator, .root = root };
    }

    pub fn deinit(self: *SchemaBuilder) void {
        self.deinitRecursive(self.root);
        self.allocator.destroy(self.root);
    }

    fn deinitRecursive(self: *SchemaBuilder, s: *Schema) void {
        if (s.properties) |props| {
            var iter = props.iterator();
            while (iter.next()) |entry| {
                self.deinitRecursive(entry.value_ptr);
            }
            props.deinit();
        }
        if (s.items) |item| {
            self.deinitRecursive(item);
            self.allocator.destroy(item);
        }
    }

    pub fn withType(self: *SchemaBuilder, type_name: []const u8) *SchemaBuilder {
        self.root.type = type_name;
        return self;
    }

    pub fn withDescription(self: *SchemaBuilder, desc: []const u8) *SchemaBuilder {
        self.root.description = desc;
        return self;
    }

    pub fn withEnum(self: *SchemaBuilder, values: []const []const u8) *SchemaBuilder {
        self.root.enum_values = values;
        return self;
    }

    pub fn withProperties(self: *SchemaBuilder, props: std.StringHashMap(Schema)) *SchemaBuilder {
        self.root.properties = props;
        return self;
    }

    pub fn addProperty(self: *SchemaBuilder, name: []const u8, schema: Schema) !*SchemaBuilder {
        if (self.root.properties == null) {
            self.root.properties = std.StringHashMap(Schema).init(self.allocator);
        }
        try self.root.properties.?.put(name, schema);
        return self;
    }

    pub fn withRequired(self: *SchemaBuilder, fields: []const []const u8) *SchemaBuilder {
        self.root.required = fields;
        return self;
    }

    pub fn withItems(self: *SchemaBuilder, item_schema: *Schema) !*SchemaBuilder {
        self.root.items = item_schema;
        return self;
    }

    pub fn build(self: *SchemaBuilder) *Schema {
        return self.root;
    }
};

// ============================================================================
// Typed Response Parser - Parse JSON response into typed struct
// ============================================================================

pub const ResponseParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ResponseParser {
        return .{ .allocator = allocator };
    }

    /// Parse a JSON string into a typed struct
    pub fn parse(self: *ResponseParser, comptime T: type, json_str: []const u8) !T {
        const parsed = try json.parseFromSlice(T, self.allocator, json_str, .{
            .ignore_unknown_fields = true,
        });
        return parsed.value;
    }

    /// Parse and validate against a JSON schema
    pub fn parseWithSchema(self: *ResponseParser, json_str: []const u8, schema: JsonSchema) !json.Value {
        // First parse the JSON
        const parsed = try json.parseFromSlice(json.Value, self.allocator, json_str, .{});

        // Then validate against schema
        try self.validateValue(parsed.value, schema.schema);

        return parsed.value;
    }

    fn validateValue(self: *ResponseParser, value: json.Value, schema: Schema) !void {
        _ = self;
        switch (value) {
            .null => if (schema.type) |t| if (!std.mem.eql(u8, t, "null")) return error.TypeMismatch,
            .bool => if (schema.type) |t| if (!std.mem.eql(u8, t, "boolean")) return error.TypeMismatch,
            .integer, .float => if (schema.type) |t| {
                if (!std.mem.eql(u8, t, "number") and !std.mem.eql(u8, t, "integer")) {
                    return error.TypeMismatch;
                }
            },
            .string => if (schema.type) |t| if (!std.mem.eql(u8, t, "string")) return error.TypeMismatch,
            .array => |arr| {
                if (schema.type) |t| if (!std.mem.eql(u8, t, "array")) return error.TypeMismatch;
                if (schema.items) |item_schema| {
                    for (arr.items) |item| {
                        try self.validateValue(item, item_schema.*);
                    }
                }
            },
            .object => |obj| {
                if (schema.type) |t| if (!std.mem.eql(u8, t, "object")) return error.TypeMismatch;
                if (schema.properties) |props| {
                    var iter = props.iterator();
                    while (iter.next()) |entry| {
                        if (obj.getEntry(entry.key_ptr.*)) |e| {
                            try self.validateValue(e.value_ptr.*, entry.value_ptr.*);
                        }
                    }
                }
            },
        }
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Create a simple object schema with string properties
pub fn objectSchema(properties: []const []const u8, required: []const []const u8) Schema {
    var props = std.StringHashMap(Schema).init(std.heap.page_allocator);
    for (properties) |name| {
        props.put(name, Schema{ .type = "string" }) catch unreachable;
    }
    return Schema{
        .type = "object",
        .properties = props,
        .required = required,
    };
}

/// Create a schema for a typed struct at compile time
pub fn schemaFromTyped(comptime T: type) Schema {
    return switch (@typeInfo(T)) {
        .@"struct" => |info| schemaFromStructInfo(info),
        .@"enum" => Schema{ .type = "string", .enum_values = &getEnumNames(T) },
        .@"union" => |info| schemaFromUnionInfo(info),
        else => Schema{ .type = "string" },
    };
}

fn schemaFromStructInfo(comptime info: std.builtin.Type.Struct) Schema {
    var props = std.StringHashMap(Schema).init(std.heap.page_allocator);
    var required_fields: []const []const u8 = &.{};

    for (info.fields) |field| {
        const is_optional = field.default_value_ptr != null;
        const field_schema = schemaFromFieldType(field.type, is_optional);
        props.put(field.name, field_schema) catch unreachable;
        if (!is_optional) {
            // Would need to grow this properly in real impl
        }
    }

    return Schema{
        .type = "object",
        .properties = props,
        .required = required_fields,
    };
}

fn schemaFromFieldType(comptime T: type, comptime is_optional: bool) Schema {
    _ = is_optional;
    return switch (@typeInfo(T)) {
        .int, .comptime_int => Schema{ .type = "integer" },
        .float, .comptime_float => Schema{ .type = "number" },
        .bool => Schema{ .type = "boolean" },
        .pointer => |ptr| if (ptr.child == u8) Schema{ .type = "string" } else schemaFromTyped(ptr.child),
        .array => |arr| blk: {
            const schema_ptr = std.heap.page_allocator.create(Schema) catch unreachable;
            schema_ptr.* = schemaFromFieldType(arr.child, false);
            break :blk Schema{ .type = "array", .items = schema_ptr };
        },
        .@"struct" => |info| schemaFromStructInfo(info),
        else => Schema{ .type = "string" },
    };
}

fn schemaFromUnionInfo(comptime info: std.builtin.Type.Union) Schema {
    var props = std.StringHashMap(Schema).init(std.heap.page_allocator);
    for (info.fields) |field| {
        const inner_schema = schemaFromFieldType(field.type, false);
        props.put(field.name, inner_schema) catch unreachable;
    }
    return Schema{
        .type = "object",
        .properties = props,
    };
}

fn getEnumNames(comptime T: type) [][]const u8 {
    const info = @typeInfo(T).@"enum";
    var names: [info.fields.len][]const u8 = undefined;
    for (info.fields, 0..) |field, i| {
        names[i] = field.name;
    }
    return &names;
}
