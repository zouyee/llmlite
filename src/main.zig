//! LLMLite - Lightweight OpenAI API Client (Zig Implementation)
//!
//! This module provides full support for OpenAI API, including:
//! - Chat Completions
//! - Embeddings
//! - Models

const std = @import("std");
const llmlite_version = @import("version.zig").version;

pub fn main() void {
    std.debug.print("LLMLite v{d}.{d}.{d} - OpenAI API Client (Zig)\n", .{
        llmlite_version.major,
        llmlite_version.minor,
        llmlite_version.patch,
    });
    std.debug.print("For usage, refer to examples/\n", .{});
}
