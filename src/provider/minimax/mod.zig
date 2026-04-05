//! MiniMax Provider Module
//!
//! Provides access to MiniMax-specific APIs that are not OpenAI-compatible.

pub const tts = @import("tts.zig");
pub const video = @import("video.zig");
pub const image = @import("image.zig");
pub const music = @import("music.zig");
