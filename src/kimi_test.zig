//! Kimi Integration Test - Provider-based API (Vercel AI SDK Style)
//! Uses: OpenAI.create(allocator, api_key, "moonshot/kimi-k2.5")
//!
//! Supported models:
//! - kimi-k2.5 (multimodal, supports vision)
//! - kimi-k2-turbo-preview
//! - kimi-k2-thinking
//! - moonshot-v1-8k/32k/128k
//! - moonshot-v1-8k/32k/128k-vision-preview
//!
//! API Docs: https://platform.moonshot.cn/docs/api/chat

const std = @import("std");

// Zig 0.16.0 compat: replacement for removed _getEnvVarOwned
fn _getEnvVarOwned(allocator: std.mem.Allocator, key: [*:0]const u8) error{EnvironmentVariableNotFound, OutOfMemory}![]u8 {
    const ptr = std.c.getenv(key) orelse return error.EnvironmentVariableNotFound;
    const slice = std.mem.sliceTo(ptr, 0);
    return allocator.dupe(u8, slice);
}
const OpenAI = @import("main").OpenAI;
const chat_mod = @import("chat");

pub fn main(init: std.process.Init) void {
    const allocator = std.heap.c_allocator;
    const io = init.io;

    // Try KIMI_API_KEY first, then fall back to MOONSHOT_API_KEY
    const api_key = _getEnvVarOwned(allocator, "KIMI_API_KEY") catch blk: {
        const fallback = _getEnvVarOwned(allocator, "MOONSHOT_API_KEY") catch {
            std.debug.print("Error: KIMI_API_KEY or MOONSHOT_API_KEY environment variable not set\n", .{});
            std.debug.print("Please set it in your .env file or export it:\n", .{});
            std.debug.print("  export KIMI_API_KEY=your_api_key_here\n", .{});
            std.debug.print("  export MOONSHOT_API_KEY=your_api_key_here\n", .{});
            break :blk null;
        };
        break :blk fallback;
    };

    if (api_key) |key| {
        defer allocator.free(key);
        runTest(io, key) catch |e| {
            std.debug.print("[Test] Error: {}\n", .{e});
        };
    }
}

fn runTest(io: std.Io, api_key: []const u8) !void {
    std.debug.print("=== Kimi Provider-based API Test ===\n\n", .{});

    // Using provider-based API: "moonshot/kimi-k2.5"
    var client = try OpenAI.create(
        std.heap.c_allocator,
        io,
        api_key,
        "moonshot/kimi-k2.5",
    );
    defer client.deinit();

    std.debug.print("[Test] Provider: {s}\n", .{client.getProvider().toString()});
    std.debug.print("[Test] Model: {s}\n\n", .{client.getModel()});

    // New Vercel AI SDK style API: client.complete(messages)
    const messages = &[1]chat_mod.Message{
        .{ .role = .user, .content = "Hello, who are you?" },
    };

    const response = try client.complete(messages);

    if (response.choices[0].message.content) |c| {
        std.debug.print("Response: {s}\n", .{c});
    } else {
        std.debug.print("Response: (empty)\n", .{});
    }
}
