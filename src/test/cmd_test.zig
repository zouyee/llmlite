//! Cmd Tests - Unit tests for llmlite-cmd RTK-inspired commands
//!
//! Tests JSON parsing and structure extraction for the json command.

const std = @import("std");
const testing = std.testing;

test "json.parseFromSlice - simple object" {
    const input = "{\"name\": \"test\", \"count\": 42}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, input, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .object);
    const obj = parsed.value.object;
    try testing.expectEqual(@as(usize, 2), obj.count());

    const name_field = obj.get("name");
    try testing.expect(name_field != null);
    try testing.expect(name_field.? == .string);
    try testing.expectEqualStrings("test", name_field.?.string);

    const count_field = obj.get("count");
    try testing.expect(count_field != null);
    try testing.expect(count_field.? == .integer);
    try testing.expectEqual(@as(i64, 42), count_field.?.integer);
}

test "json.parseFromSlice - nested object" {
    const input = "{\"user\": {\"name\": \"Alice\", \"age\": 30}, \"active\": true}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, input, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .object);
    const obj = parsed.value.object;

    const user_field = obj.get("user");
    try testing.expect(user_field != null);
    try testing.expect(user_field.? == .object);

    const active_field = obj.get("active");
    try testing.expect(active_field != null);
    try testing.expect(active_field.? == .bool);
    try testing.expectEqual(true, active_field.?.bool);
}

test "json.parseFromSlice - array" {
    const input = "[\"apple\", \"banana\", \"cherry\"]";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, input, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .array);
    const arr = parsed.value.array;
    try testing.expectEqual(@as(usize, 3), arr.items.len);

    try testing.expect(arr.items[0] == .string);
    try testing.expectEqualStrings("apple", arr.items[0].string);
}

test "json.parseFromSlice - mixed types" {
    const input = "{\"string\": \"hello\", \"number\": 123, \"float\": 3.14, \"bool\": false, \"null\": null}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, input, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .object);
    const obj = parsed.value.object;

    const str = obj.get("string");
    try testing.expect(str != null);
    try testing.expect(str.? == .string);

    const num = obj.get("number");
    try testing.expect(num != null);
    try testing.expect(num.? == .integer);

    const flt = obj.get("float");
    try testing.expect(flt != null);
    try testing.expect(flt.? == .float);

    const bool_val = obj.get("bool");
    try testing.expect(bool_val != null);
    try testing.expect(bool_val.? == .bool);

    const null_val = obj.get("null");
    try testing.expect(null_val != null);
    try testing.expect(null_val.? == .null);
}

test "json.parseFromSlice - empty object" {
    const input = "{}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, input, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .object);
    const obj = parsed.value.object;
    try testing.expectEqual(@as(usize, 0), obj.count());
}

test "json.parseFromSlice - empty array" {
    const input = "[]";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, input, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .array);
    const arr = parsed.value.array;
    try testing.expectEqual(@as(usize, 0), arr.items.len);
}

test "json.parseFromSlice - invalid JSON" {
    const input = "{invalid json}";
    const result = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, input, .{});
    // Zig 0.15+ and 0.16.0+ returns error.SyntaxError for invalid JSON
    try testing.expectError(error.SyntaxError, result);
}

test "json.parseFromSlice - deeply nested" {
    const input = "{\"a\": {\"b\": {\"c\": {\"d\": \"deep\"}}}}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, input, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .object);
    const a = parsed.value.object.get("a");
    try testing.expect(a != null);
    try testing.expect(a.? == .object);

    const b = a.?.object.get("b");
    try testing.expect(b != null);
    try testing.expect(b.? == .object);

    const c = b.?.object.get("c");
    try testing.expect(c != null);
    try testing.expect(c.? == .object);

    const d = c.?.object.get("d");
    try testing.expect(d != null);
    try testing.expect(d.? == .string);
    try testing.expectEqualStrings("deep", d.?.string);
}

test "json.object.iterator - iterate over keys" {
    const input = "{\"z\": 1, \"a\": 2, \"m\": 3}";
    const parsed = try std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, input, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .object);
    const obj = parsed.value.object;

    var count: usize = 0;
    var it = obj.iterator();
    while (it.next()) |entry| {
        count += 1;
        try testing.expect(entry.key_ptr.len > 0);
        try testing.expect(entry.value_ptr.* == .integer);
    }
    try testing.expectEqual(@as(usize, 3), count);
}
