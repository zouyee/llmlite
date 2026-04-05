//! Common Type Definitions

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const OpenAIError = error{
    InvalidUrl,
    InvalidApiKey,
    NetworkError,
    InvalidResponse,
    ApiError,
    RateLimitError,
    AuthenticationError,
    ParseError,
    RequiredFieldMissing,
};

pub fn openAIErrorFromStatus(status: u16, body: []const u8) OpenAIError {
    switch (status) {
        401 => return OpenAIError.AuthenticationError,
        429 => return OpenAIError.RateLimitError,
        400...499 => return OpenAIError.ApiError,
        500...599 => return OpenAIError.ApiError,
        else => return OpenAIError.InvalidResponse,
    }
}

// ============================================================================
// API Configuration
// ============================================================================

pub const Config = struct {
    api_key: []const u8,
    base_url: []const u8 = "https://api.openai.com/v1",
    organization: ?[]const u8 = null,
    project: ?[]const u8 = null,
    timeout_ms: u32 = 60000,
};

// ============================================================================
// Common Response Types
// ============================================================================

pub const Usage = struct {
    prompt_tokens: u32,
    completion_tokens: u32,
    total_tokens: u32,
};

pub const Model = struct {
    id: []const u8,
    object: []const u8 = "model",
    created: u64,
    owned_by: []const u8,
};

// ============================================================================
// Optional Field Wrapper (similar to Go's param.Opt[T])
// ============================================================================

pub fn Opt(comptime T: type) type {
    return struct {
        value: T,
        present: bool = true,

        pub fn none() @This() {
            return .{ .value = undefined, .present = false };
        }

        pub fn some(v: T) @This() {
            return .{ .value = v, .present = true };
        }

        pub fn isOmitted(self: @This()) bool {
            return !self.present;
        }
    };
}

// ============================================================================
// JSON Serialization Helpers
// ============================================================================

pub fn serializeOptionalField(buf: *std.ArrayList(u8), field_name: []const u8, value: anytype) !void {
    if (@TypeOf(value) == []const u8) {
        try buf.writer().print("\"{s}\":\"{s}\"", .{ field_name, value });
    } else if (@TypeOf(value) == f32 or @TypeOf(value) == f64) {
        try buf.writer().print("\"{s}\":{d}", .{ field_name, value });
    } else if (@TypeOf(value) == u32 or @TypeOf(value) == u64 or @TypeOf(value) == i32 or @TypeOf(value) == i64) {
        try buf.writer().print("\"{s}\":{d}", .{ field_name, value });
    } else if (@TypeOf(value) == bool) {
        try buf.writer().print("\"{s}\":{s}", .{ field_name, if (value) "true" else "false" });
    }
}
