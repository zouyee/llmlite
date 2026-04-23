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
    if (args.len == 0) {
        std.debug.print("llm chat: missing prompt\n", .{});
        return 1;
    }

    const prompt: []const u8 = args[0];
    var model: []const u8 = DEFAULT_MODEL;
    var provider: ?[]const u8 = null;
    var system_msg: ?[]const u8 = null;
    var max_tokens: u32 = 1024;
    var temperature: f64 = 0.7;

    var i: usize = 1;
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
        }
    }

    // Build request body
    const body = try buildChatRequest(prompt, model, provider, system_msg, max_tokens, temperature);
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
    // Simple JSON extraction: find "content":"..." in choices[0].message
    const choices_key = "\"choices\"";
    const content_key = "\"content\"";

    const choices_idx = std.mem.find(u8, resp, choices_key) orelse {
        std.debug.print("{s}\n", .{resp});
        return;
    };

    const after_choices = resp[choices_idx + choices_key.len ..];
    const content_idx = std.mem.find(u8, after_choices, content_key) orelse {
        std.debug.print("{s}\n", .{resp});
        return;
    };

    const after_content = after_choices[content_idx + content_key.len ..];
    const quote_start = std.mem.find(u8, after_content, "\"") orelse {
        std.debug.print("{s}\n", .{resp});
        return;
    };

    const after_quote = after_content[quote_start + 1 ..];
    const quote_end = std.mem.find(u8, after_quote, "\"");

    if (quote_end) |end| {
        const content = after_quote[0..end];
        // Print unescaped content
        var j: usize = 0;
        while (j < content.len) : (j += 1) {
            if (content[j] == '\\' and j + 1 < content.len) {
                switch (content[j + 1]) {
                    'n' => { std.debug.print("\n", .{}); j += 1; },
                    't' => { std.debug.print("\t", .{}); j += 1; },
                    'r' => { j += 1; },
                    '\\' => { std.debug.print("\\", .{}); j += 1; },
                    '"' => { std.debug.print("\"", .{}); j += 1; },
                    else => std.debug.print("{c}", .{content[j]}),
                }
            } else {
                std.debug.print("{c}", .{content[j]});
            }
        }
        std.debug.print("\n", .{});
    } else {
        std.debug.print("{s}\n", .{resp});
    }
}

// ============================================================================
// Single-shot Completion
// ============================================================================

fn dispatchComplete(args: []const [:0]const u8) !i32 {
    if (args.len == 0) {
        std.debug.print("llm complete: missing prompt\n", .{});
        return 1;
    }

    const prompt: []const u8 = args[0];
    var model: []const u8 = DEFAULT_MODEL;
    var provider: ?[]const u8 = null;
    var max_tokens: u32 = 1024;
    var temperature: f64 = 0.7;

    var i: usize = 1;
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
        }
    }

    // Complete is just chat with a single user message
    const body = try buildChatRequest(prompt, model, provider, null, max_tokens, temperature);
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
    const url = try std.fmt.allocPrint(g_allocator, "{s}{s}", .{ DEFAULT_PROXY_URL, path });
    defer g_allocator.free(url);

    const uri = std.Uri.parse(url) catch return null;

    var client = std.http.Client{ .allocator = g_allocator, .io = g_io };
    defer client.deinit();

    var response_writer = std.Io.Writer.Allocating.init(g_allocator);
    defer response_writer.deinit();

    const extra_headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
    };

    const response = client.fetch(.{
        .location = .{ .uri = uri },
        .method = method,
        .extra_headers = extra_headers,
        .response_writer = &response_writer.writer,
        .payload = body,
    }) catch return null;

    if (response.status != .ok) {
        const err_body = response_writer.written();
        if (err_body.len > 0) {
            std.debug.print("Proxy error (HTTP {}): {s}\n", .{ response.status, err_body });
        }
        return null;
    }

    const resp_body = response_writer.written();
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
