//! MiniMax Integration Test - Provider-based API (Vercel AI SDK Style)
//! Uses: OpenAI.create(allocator, api_key, "minimax/MiniMax-M2.7")

const std = @import("std");
const OpenAI = @import("main").OpenAI;
const chat_mod = @import("chat");

pub fn main() void {
    const allocator = std.heap.c_allocator;
    const api_key = std.process.getEnvVarOwned(allocator, "MINIMAX_API_KEY") catch null;

    if (api_key) |key| {
        defer allocator.free(key);
        runTest(key) catch |e| {
            std.debug.print("[Test] Error: {}\n", .{e});
        };
    } else {
        std.debug.print("Error: MINIMAX_API_KEY not set\n", .{});
    }
}

fn runTest(api_key: []const u8) !void {
    std.debug.print("=== MiniMax Provider-based API Test ===\n\n", .{});

    // Using provider-based API: "minimax/MiniMax-M2.7"
    var client = try OpenAI.create(
        std.heap.c_allocator,
        api_key,
        "minimax/MiniMax-M2.7",
    );
    defer client.deinit();

    std.debug.print("[Test] Provider: {s}\n", .{client.getProvider().toString()});
    std.debug.print("[Test] Model: {s}\n\n", .{client.getModel()});

    // New Vercel AI SDK style API: client.complete(messages)
    const messages = &[1]chat_mod.Message{
        .{ .role = .user, .content = "Hello" },
    };

    const response = try client.complete(messages);

    if (response.choices[0].message.content) |c| {
        std.debug.print("Response: {s}\n", .{c});
    } else {
        std.debug.print("Response: (empty)\n", .{});
    }
}
