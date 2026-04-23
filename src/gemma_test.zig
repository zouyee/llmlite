//! Google AI (Gemma) Integration Test
//!
//! Uses the new elegant API: model string auto-detects provider
//! Format: "provider/model" e.g., "google/gemini-2.0-flash"

const std = @import("std");

// Zig 0.16.0 compat: replacement for removed _getEnvVarOwned
fn _getEnvVarOwned(allocator: std.mem.Allocator, key: [*:0]const u8) error{EnvironmentVariableNotFound, OutOfMemory}![]u8 {
    const ptr = std.c.getenv(key) orelse return error.EnvironmentVariableNotFound;
    const slice = std.mem.sliceTo(ptr, 0);
    return allocator.dupe(u8, slice);
}
const OpenAI = @import("main").OpenAI;
const chat = @import("chat");

// Model string contains provider info, auto-selects base_url and auth_type
const MODEL = "google/gemini-2.0-flash";

pub fn main(init: std.process.Init) void {
    const allocator = std.heap.c_allocator;
    const io = init.io;
    const api_key = _getEnvVarOwned(allocator, "GOOGLE_AI_API_KEY") catch null;

    if (api_key) |key| {
        defer allocator.free(key);
        runTest(io, key) catch |e| {
            std.debug.print("[Test] Error: {}\n", .{e});
        };
    } else {
        std.debug.print("Error: GOOGLE_AI_API_KEY environment variable not set\n", .{});
    }
}

fn runTest(io: std.Io, api_key: []const u8) !void {
    std.debug.print("=== Google AI (Gemma) Integration Test ===\n", .{});
    std.debug.print("Model: {s}\n\n", .{MODEL});

    // Use the new elegant API: Client.create(model_str)
    // Auto-detects provider (google) and configures base_url and auth_type
    var client = try OpenAI.create(
        std.heap.c_allocator,
        io,
        api_key,
        MODEL,
    );
    defer client.deinit();

    std.debug.print("[Test] Provider: {s}\n", .{client.getProvider().toString()});
    std.debug.print("[Test] Model: {s}\n\n", .{client.getModel()});

    std.debug.print("[Test] Sending chat completion request...\n", .{});

    const messages = &[1]chat.Message{
        .{ .role = .user, .content = "Hello, who are you?" },
    };

    const response = try client.complete(messages);

    std.debug.print("[Test] Response:\n", .{});
    std.debug.print("  Model: {s}\n", .{response.model});
    if (response.choices[0].message.content) |c| {
        std.debug.print("  Content: {s}\n", .{c});
    } else {
        std.debug.print("  Content: (empty)\n", .{});
    }
}
