//! LLM Command Dispatcher - Direct LLM API access via llmlite-proxy
//!
//! Provides subcommands to interact with LLMs through the proxy's
//! OpenAI-compatible API endpoint.
//!
//! Usage:
//!   llmlite-cmd llm chat "Hello" [--model gpt-4o] [--provider openai]
//!   llmlite-cmd llm complete "Explain quicksort" [--max-tokens 500]
//!   llmlite-cmd llm embed "text to embed"
//!   llmlite-cmd llm models [--provider openai]
//!   llmlite-cmd llm providers

const std = @import("std");

const DEFAULT_PROXY_URL = "http://localhost:4000";
const DEFAULT_MODEL = "gpt-4o-mini";

// Global allocator and io set by cmd.zig dispatch
var g_allocator: std.mem.Allocator = std.heap.page_allocator;
var g_io: std.Io = undefined;

pub fn dispatch(allocator: std.mem.Allocator, io: std.Io, args: []const [:0]const u8) !i32 {
    g_allocator = allocator;
    g_io = io;

    if (args.len == 0) {
        try printHelp();
        return 1;
    }

    const subcmd = args[0];

    if (std.mem.eql(u8, subcmd, "chat")) {
        return dispatchChat(args[1..]);
    } else if (std.mem.eql(u8, subcmd, "complete")) {
        return dispatchComplete(args[1..]);
    } else if (std.mem.eql(u8, subcmd, "embed")) {
        return dispatchEmbed(args[1..]);
    } else if (std.mem.eql(u8, subcmd, "models")) {
        return dispatchModels(args[1..]);
    } else if (std.mem.eql(u8, subcmd, "providers")) {
        return dispatchProviders();
    } else {
        std.debug.print("Unknown llm subcommand: {s}\n", .{subcmd});
        try printHelp();
        return 1;
    }
}

fn printHelp() !void {
    std.debug.print("llm - Direct LLM API access via llmlite-proxy\n\n", .{});
    std.debug.print("USAGE:\n", .{});
    std.debug.print("  llmlite-cmd llm <subcommand> [args...]\n\n", .{});
    std.debug.print("SUBCOMMANDS:\n", .{});
    std.debug.print("  chat <prompt>              Interactive chat completion\n", .{});
    std.debug.print("    --model <model>          Model name (default: gpt-4o-mini)\n", .{});
    std.debug.print("    --provider <provider>    Provider override\n", .{});
    std.debug.print("    --system <text>          System prompt\n", .{});
    std.debug.print("    --max-tokens <n>         Max tokens (default: 1024)\n", .{});
    std.debug.print("    --temperature <t>        Temperature 0.0-2.0 (default: 0.7)\n\n", .{});
    std.debug.print("  complete <prompt>          Single-shot completion\n", .{});
    std.debug.print("    --model <model>          Model name (default: gpt-4o-mini)\n", .{});
    std.debug.print("    --provider <provider>    Provider override\n", .{});
    std.debug.print("    --max-tokens <n>         Max tokens (default: 1024)\n", .{});
    std.debug.print("    --temperature <t>        Temperature 0.0-2.0 (default: 0.7)\n\n", .{});
    std.debug.print("  embed <text>               Generate embeddings\n", .{});
    std.debug.print("    --model <model>          Model name (default: text-embedding-3-small)\n\n", .{});
    std.debug.print("  models [--provider <p>]    List available models\n", .{});
    std.debug.print("  providers                  List supported providers\n\n", .{});
    std.debug.print("EXAMPLES:\n", .{});
    std.debug.print("  llmlite-cmd llm chat \"Explain Zig's comptime\"\n", .{});
    std.debug.print("  llmlite-cmd llm chat \"Hello\" --model claude-3-sonnet --provider anthropic\n", .{});
    std.debug.print("  llmlite-cmd llm complete \"Write a fibonacci function in Zig\"\n", .{});
    std.debug.print("  llmlite-cmd llm embed \"machine learning\"\n", .{});
    std.debug.print("  llmlite-cmd llm models --provider openai\n", .{});
}

// ============================================================================
// Chat Completion
// ============================================================================

fn dispatchChat(args: []const [:0]const u8) !i32 {
    var model: []const u8 = DEFAULT_MODEL;
    var provider: ?[]const u8 = null;
    var system_msg: ?[]const u8 = null;
    var max_tokens: u32 = 1024;
    var temperature: f64 = 0.7;
    var prompt: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--model")) {
            if (i + 1 < args.len) { model = args[i + 1]; i += 1; }
        } else if (std.mem.eql(u8, arg, "--provider")) {
            if (i + 1 < args.len) { provider = args[i + 1]; i += 1; }
        } else if (std.mem.eql(u8, arg, "--system")) {
            if (i + 1 < args.len) { system_msg = args[i + 1]; i += 1; }
        } else if (std.mem.eql(u8, arg, "--max-tokens")) {
            if (i + 1 < args.len) { max_tokens = std.fmt.parseInt(u32, args[i + 1], 10) catch 1024; i += 1; }
        } else if (std.mem.eql(u8, arg, "--temperature")) {
            if (i + 1 < args.len) { temperature = std.fmt.parseFloat(f64, args[i + 1]) catch 0.7; i += 1; }
        } else {
            // First non-flag argument is the prompt
            if (prompt == null) {
                prompt = arg;
            }
        }
    }

    if (prompt == null) {
        std.debug.print("llm chat: missing prompt\n", .{});
        return 1;
    }

    // Build request body
    const body = try buildChatRequest(prompt.?, model, provider, system_msg, max_tokens, temperature);
    defer g_allocator.free(body);

    // Call proxy API
    const response = try callProxyApi("/v1/chat/completions", .POST, body);
    defer if (response) |r| g_allocator.free(r);

    if (response) |resp| {
        try printChatResponse(resp);
        return 0;
    } else {
        std.debug.print("llm chat: failed to get response from proxy\n", .{});
        std.debug.print("Make sure llmlite-proxy is running: llmlite-cmd proxy start\n", .{});
        return 1;
    }
}

fn buildChatRequest(
    prompt: []const u8,
    model: []const u8,
    provider: ?[]const u8,
    system_msg: ?[]const u8,
    max_tokens: u32,
    temperature: f64,
) ![]const u8 {
    var parts = std.array_list.Managed(u8).init(g_allocator);
    defer parts.deinit();

    try parts.appendSlice("{\"model\":\"");
    try parts.appendSlice(model);
    try parts.appendSlice("\",\"messages\":[");

    if (system_msg) |sys| {
        try parts.appendSlice("{\"role\":\"system\",\"content\":\"");
        try appendEscapedJson(&parts, sys);
        try parts.appendSlice("\"},");
    }

    try parts.appendSlice("{\"role\":\"user\",\"content\":\"");
    try appendEscapedJson(&parts, prompt);
    try parts.appendSlice("\"}],");

    if (provider) |p| {
        try parts.appendSlice("\"provider\":\"");
        try parts.appendSlice(p);
        try parts.appendSlice("\",");
    }

    const max_str = try std.fmt.allocPrint(g_allocator, "\"max_tokens\":{d}", .{max_tokens});
    defer g_allocator.free(max_str);
    try parts.appendSlice(max_str);

    const temp_str = try std.fmt.allocPrint(g_allocator, ",\"temperature\":{d:.2}", .{@as(f32, @floatCast(temperature))});
    defer g_allocator.free(temp_str);
    try parts.appendSlice(temp_str);

    try parts.appendSlice("}");

    return try parts.toOwnedSlice();
}

fn printChatResponse(resp: []const u8) !void {
    // Try to extract content from the response JSON
    // Look for "content":"<value>" in choices[0].message
    // Also handle "content":"" with reasoning_content for thinking models
    const choices_key = "\"choices\"";

    const choices_idx = std.mem.find(u8, resp, choices_key) orelse {
        std.debug.print("{s}\n", .{resp});
        return;
    };

    const after_choices = resp[choices_idx + choices_key.len ..];

    // Try to find content with a non-empty value first
    const content = extractJsonStringValue(after_choices, "content");
    const reasoning = extractJsonStringValue(after_choices, "reasoning_content");

    if (content) |c| {
        if (c.len > 0) {
            printUnescaped(c);
            std.debug.print("\n", .{});
            return;
        }
    }

    // If content is empty, try reasoning_content (thinking models)
    if (reasoning) |r| {
        if (r.len > 0) {
            printUnescaped(r);
            std.debug.print("\n", .{});
            return;
        }
    }

    // Fallback: print raw response
    if (content) |c| {
        if (c.len == 0) {
            std.debug.print("(empty response)\n", .{});
            return;
        }
    }
    std.debug.print("{s}\n", .{resp});
}

/// Extract a JSON string value for a given key, handling escape sequences properly
fn extractJsonStringValue(json: []const u8, key: []const u8) ?[]const u8 {
    // Build the search pattern: "key":"
    var search_buf: [128]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "\"{s}\":\"", .{key}) catch return null;

    const key_idx = std.mem.find(u8, json, search) orelse return null;
    const value_start = key_idx + search.len;

    // Find the end of the string value, handling escape sequences
    var i: usize = value_start;
    while (i < json.len) : (i += 1) {
        if (json[i] == '\\' and i + 1 < json.len) {
            i += 1; // skip escaped character
        } else if (json[i] == '"') {
            return json[value_start..i];
        }
    }
    return null;
}

fn printUnescaped(content: []const u8) void {
    var j: usize = 0;
    while (j < content.len) : (j += 1) {
        if (content[j] == '\\' and j + 1 < content.len) {
            switch (content[j + 1]) {
                'n' => {
                    std.debug.print("\n", .{});
                    j += 1;
                },
                't' => {
                    std.debug.print("\t", .{});
                    j += 1;
                },
                'r' => {
                    j += 1;
                },
                '\\' => {
                    std.debug.print("\\", .{});
                    j += 1;
                },
                '"' => {
                    std.debug.print("\"", .{});
                    j += 1;
                },
                else => std.debug.print("{c}", .{content[j]}),
            }
        } else {
            std.debug.print("{c}", .{content[j]});
        }
    }
}

// ============================================================================
// Single-shot Completion
// ============================================================================

fn dispatchComplete(args: []const [:0]const u8) !i32 {
    var model: []const u8 = DEFAULT_MODEL;
    var provider: ?[]const u8 = null;
    var max_tokens: u32 = 1024;
    var temperature: f64 = 0.7;
    var prompt: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--model")) {
            if (i + 1 < args.len) { model = args[i + 1]; i += 1; }
        } else if (std.mem.eql(u8, arg, "--provider")) {
            if (i + 1 < args.len) { provider = args[i + 1]; i += 1; }
        } else if (std.mem.eql(u8, arg, "--max-tokens")) {
            if (i + 1 < args.len) { max_tokens = std.fmt.parseInt(u32, args[i + 1], 10) catch 1024; i += 1; }
        } else if (std.mem.eql(u8, arg, "--temperature")) {
            if (i + 1 < args.len) { temperature = std.fmt.parseFloat(f64, args[i + 1]) catch 0.7; i += 1; }
        } else {
            if (prompt == null) {
                prompt = arg;
            }
        }
    }

    if (prompt == null) {
        std.debug.print("llm complete: missing prompt\n", .{});
        return 1;
    }

    // Complete is just chat with a single user message
    const body = try buildChatRequest(prompt.?, model, provider, null, max_tokens, temperature);
    defer g_allocator.free(body);

    const response = try callProxyApi("/v1/chat/completions", .POST, body);
    defer if (response) |r| g_allocator.free(r);

    if (response) |resp| {
        try printChatResponse(resp);
        return 0;
    } else {
        std.debug.print("llm complete: failed to get response from proxy\n", .{});
        std.debug.print("Make sure llmlite-proxy is running: llmlite-cmd proxy start\n", .{});
        return 1;
    }
}

// ============================================================================
// Embeddings
// ============================================================================

fn dispatchEmbed(args: []const [:0]const u8) !i32 {
    if (args.len == 0) {
        std.debug.print("llm embed: missing text\n", .{});
        return 1;
    }

    const text: []const u8 = args[0];
    var model: []const u8 = "text-embedding-3-small";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--model")) {
            if (i + 1 < args.len) { model = args[i + 1]; i += 1; }
        }
    }

    const body = try std.fmt.allocPrint(g_allocator,
        "{{\"model\":\"{s}\",\"input\":\"{s}\"}}",
        .{ model, text },
    );
    defer g_allocator.free(body);

    const response = try callProxyApi("/v1/embeddings", .POST, body);
    defer if (response) |r| g_allocator.free(r);

    if (response) |resp| {
        std.debug.print("{s}\n", .{resp});
        return 0;
    } else {
        std.debug.print("llm embed: failed to get response from proxy\n", .{});
        return 1;
    }
}

// ============================================================================
// Models & Providers
// ============================================================================

fn dispatchModels(args: []const [:0]const u8) !i32 {
    var provider: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--provider")) {
            if (i + 1 < args.len) { provider = args[i + 1]; i += 1; }
        }
    }

    var path_buf: [256]u8 = undefined;
    const path = if (provider) |p|
        try std.fmt.bufPrint(&path_buf, "/v1/models?provider={s}", .{p})
    else
        "/v1/models";

    const response = try callProxyApi(path, .GET, null);
    defer if (response) |r| g_allocator.free(r);

    if (response) |resp| {
        // Pretty-print the models list (simple JSON formatting)
        std.debug.print("Available models:\n", .{});
        try prettyPrintJsonList(resp, "id");
        return 0;
    } else {
        std.debug.print("llm models: failed to get response from proxy\n", .{});
        return 1;
    }
}

fn dispatchProviders() !i32 {
    const response = try callProxyApi("/api/providers", .GET, null);
    defer if (response) |r| g_allocator.free(r);

    if (response) |resp| {
        std.debug.print("Supported providers:\n", .{});
        try prettyPrintJsonList(resp, "id");
        return 0;
    } else {
        std.debug.print("llm providers: failed to get response from proxy\n", .{});
        return 1;
    }
}

// ============================================================================
// HTTP Client Helper
// ============================================================================

fn callProxyApi(path: []const u8, method: std.http.Method, body: ?[]const u8) !?[]const u8 {
    // Use std.Io.net.Stream to match proxy's I/O backend
    const address = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 4000);
    var stream = try address.connect(g_io, .{ .mode = .stream });
    defer stream.close(g_io);

    // Build HTTP request
    var req_buf: [4096]u8 = undefined;
    var req_len: usize = 0;
    req_len += (try std.fmt.bufPrint(req_buf[req_len..], "{s} {s} HTTP/1.1\r\n", .{ @tagName(method), path })).len;
    req_len += (try std.fmt.bufPrint(req_buf[req_len..], "Host: localhost:4000\r\n", .{})).len;
    req_len += (try std.fmt.bufPrint(req_buf[req_len..], "Content-Type: application/json\r\n", .{})).len;
    req_len += (try std.fmt.bufPrint(req_buf[req_len..], "Authorization: Bearer sk-test-key\r\n", .{})).len;
    if (body) |b| {
        req_len += (try std.fmt.bufPrint(req_buf[req_len..], "Content-Length: {d}\r\n", .{b.len})).len;
    }
    req_len += (try std.fmt.bufPrint(req_buf[req_len..], "Connection: close\r\n\r\n", .{})).len;
    if (body) |b| {
        @memcpy(req_buf[req_len..][0..b.len], b);
        req_len += b.len;
    }

    // Send request
    var wbuf: [4096]u8 = undefined;
    var writer = stream.writer(g_io, &wbuf);
    try writer.interface.writeAll(req_buf[0..req_len]);
    try writer.interface.flush();

    // Read response
    var rbuf: [4096]u8 = undefined;
    var reader = stream.reader(g_io, &rbuf);
    var resp_parts = std.array_list.Managed(u8).init(g_allocator);
    defer resp_parts.deinit();
    while (true) {
        var buf: [4096]u8 = undefined;
        const n = reader.interface.readSliceShort(buf[0..]) catch break;
        if (n == 0) break;
        try resp_parts.appendSlice(buf[0..n]);
    }
    const response_text = resp_parts.items;

    // Parse status line
    const status_end = std.mem.find(u8, response_text, "\r\n") orelse return null;
    const status_line = response_text[0..status_end];
    if (!std.mem.startsWith(u8, status_line, "HTTP/1.1 200")) {
        std.debug.print("Proxy error: {s}\n", .{status_line});
        return null;
    }

    // Find body
    const body_start = std.mem.find(u8, response_text, "\r\n\r\n") orelse return null;
    const resp_body = response_text[body_start + 4 ..];

    if (resp_body.len == 0) return null;
    return try g_allocator.dupe(u8, resp_body);
}

// ============================================================================
// JSON Helpers
// ============================================================================

fn appendEscapedJson(parts: *std.array_list.Managed(u8), text: []const u8) !void {
    for (text) |c| {
        switch (c) {
            '"' => try parts.appendSlice("\\\""),
            '\\' => try parts.appendSlice("\\\\"),
            '\n' => try parts.appendSlice("\\n"),
            '\r' => try parts.appendSlice("\\r"),
            '\t' => try parts.appendSlice("\\t"),
            else => try parts.append(c),
        }
    }
}

/// Simple JSON list pretty-printer: extracts objects from "data":[...] and prints a field
fn prettyPrintJsonList(json: []const u8, field: []const u8) !void {
    const data_key = "\"data\"";
    const data_idx = std.mem.find(u8, json, data_key) orelse {
        std.debug.print("  (raw response: {s})\n", .{json});
        return;
    };

    const after_data = json[data_idx + data_key.len ..];
    const bracket_open = std.mem.find(u8, after_data, "[") orelse return;
    const list_start = after_data[bracket_open + 1 ..];

    var depth: usize = 1;
    var obj_start: ?usize = null;
    var count: usize = 0;

    for (list_start, 0..) |c, idx| {
        switch (c) {
            '{' => {
                depth += 1;
                if (depth == 2 and obj_start == null) {
                    obj_start = idx + 1;
                }
            },
            '}' => {
                if (depth == 2 and obj_start != null) {
                    const obj = list_start[obj_start.?..idx];
                    if (try extractJsonField(obj, field)) |value| {
                        count += 1;
                        std.debug.print("  {d}. {s}\n", .{ count, value });
                    }
                    obj_start = null;
                }
                depth -= 1;
            },
            '[' => depth += 1,
            ']' => {
                depth -= 1;
                if (depth == 0) break;
            },
            else => {},
        }
    }

    if (count == 0) {
        std.debug.print("  (no items found)\n", .{});
    }
}

fn extractJsonField(obj: []const u8, field: []const u8) !?[]const u8 {
    const key = try std.fmt.allocPrint(g_allocator, "\"{s}\"", .{field});
    defer g_allocator.free(key);

    const idx = std.mem.find(u8, obj, key) orelse return null;
    const after = obj[idx + key.len ..];

    // Skip to value
    var start: usize = 0;
    while (start < after.len and (after[start] == ':' or after[start] == ' ')) : (start += 1) {}

    if (start >= after.len) return null;

    if (after[start] == '"') {
        // String value
        const str_start = start + 1;
        var end = str_start;
        while (end < after.len) : (end += 1) {
            if (after[end] == '"' and (end == str_start or after[end - 1] != '\\')) {
                return try g_allocator.dupe(u8, after[str_start..end]);
            }
        }
    } else {
        // Non-string value
        var end = start;
        while (end < after.len and after[end] != ',' and after[end] != '}') : (end += 1) {}
        return try g_allocator.dupe(u8, std.mem.trim(u8, after[start..end], " "));
    }

    return null;
}
