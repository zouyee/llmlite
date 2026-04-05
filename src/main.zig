//! LLMLite - Lightweight OpenAI API Client (Zig Implementation)
//!
//! This module provides full support for OpenAI API, including:
//! - Chat Completions
//! - Embeddings
//! - Models

const std = @import("std");

// Re-export main API
pub const OpenAI = @import("client.zig").OpenAI;

pub fn main() void {
    std.debug.print("LLMLite - OpenAI API Client (Zig)\n", .{});
    std.debug.print("For usage, refer to examples/\n", .{});
}
