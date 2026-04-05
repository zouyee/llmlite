//! MiniMax Music Generation API
//!
//! Reference: https://platform.minimaxi.com/docs/api-reference/music-generation

const std = @import("std");
const http = @import("http");

// ============================================================================
// Models
// ============================================================================

pub const MusicModel = enum {
    music_2_5_plus,
    music_2_5,

    pub fn toString(self: MusicModel) []const u8 {
        return switch (self) {
            .music_2_5_plus => "music-2.5+",
            .music_2_5 => "music-2.5",
        };
    }
};

pub const MusicAudioFormat = enum {
    mp3,
    wav,
    pcm,

    pub fn toString(self: MusicAudioFormat) []const u8 {
        return switch (self) {
            .mp3 => "mp3",
            .wav => "wav",
            .pcm => "pcm",
        };
    }
};

// ============================================================================
// Request/Response Types
// ============================================================================

pub const MusicAudioSetting = struct {
    sample_rate: ?u32 = 44100,
    bitrate: ?u32 = 256000,
    format: MusicAudioFormat = .mp3,
};

pub const MusicGenerateRequest = struct {
    model: []const u8,
    prompt: []const u8,
    lyrics: ?[]const u8 = null,
    stream: bool = false,
    output_format: []const u8 = "hex",
    audio_setting: ?MusicAudioSetting = null,
    aigc_watermark: ?bool = false,
    lyrics_optimizer: ?bool = false,
    is_instrumental: ?bool = false,
};

pub const MusicGenerateResponse = struct {
    audio: ?[]const u8,
    status: u32,
    music_duration: ?u64 = null,
    music_sample_rate: ?u32 = null,
    music_channel: ?u32 = null,
    bitrate: ?u32 = null,
    status_code: u32,
    status_msg: ?[]const u8,
};

// ============================================================================
// Service
// ============================================================================

pub const Service = struct {
    allocator: std.mem.Allocator,
    http_client: *http.HttpClient,

    pub fn init(allocator: std.mem.Allocator, http_client: *http.HttpClient) Service {
        return .{
            .allocator = allocator,
            .http_client = http_client,
        };
    }

    pub fn deinit(self: *Service) void {
        _ = self;
    }

    /// Generate music from text prompt and optional lyrics
    pub fn generate(self: *Service, params: MusicGenerateRequest) !MusicGenerateResponse {
        const json_str = try self.serializeRequest(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/music_generation", json_str);
        defer self.allocator.free(response);

        return try self.parseResponse(response);
    }

    fn serializeRequest(self: *Service, params: MusicGenerateRequest) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8).empty;
        errdefer buf.deinit(self.allocator);

        try buf.append(self.allocator, '{');

        // model
        try buf.appendSlice(self.allocator, "\"model\":\"");
        try buf.appendSlice(self.allocator, params.model);
        try buf.append(self.allocator, '"');

        // prompt
        try buf.appendSlice(self.allocator, ",\"prompt\":");
        try escapeJsonString(self.allocator, &buf, params.prompt);

        // lyrics
        if (params.lyrics) |lyrics| {
            try buf.appendSlice(self.allocator, ",\"lyrics\":");
            try escapeJsonString(self.allocator, &buf, lyrics);
        }

        // stream
        try buf.appendSlice(self.allocator, ",\"stream\":");
        try buf.appendSlice(self.allocator, if (params.stream) "true" else "false");

        // output_format
        try buf.appendSlice(self.allocator, ",\"output_format\":\"");
        try buf.appendSlice(self.allocator, params.output_format);
        try buf.append(self.allocator, '"');

        // audio_setting
        if (params.audio_setting) |audio| {
            try buf.appendSlice(self.allocator, ",\"audio_setting\":{");
            var first = true;

            if (audio.sample_rate) |sr| {
                try buf.appendSlice(self.allocator, "\"sample_rate\":");
                try buf.writer(self.allocator).print("{}", .{sr});
                first = false;
            }
            if (audio.bitrate) |br| {
                if (!first) try buf.append(self.allocator, ',');
                try buf.appendSlice(self.allocator, "\"bitrate\":");
                try buf.writer(self.allocator).print("{}", .{br});
                first = false;
            }
            if (!first) try buf.append(self.allocator, ',');
            try buf.appendSlice(self.allocator, "\"format\":\"");
            try buf.appendSlice(self.allocator, audio.format.toString());
            try buf.append(self.allocator, '"');
            try buf.append(self.allocator, '}');
        }

        // aigc_watermark
        if (params.aigc_watermark) |v| {
            try buf.appendSlice(self.allocator, ",\"aigc_watermark\":");
            try buf.appendSlice(self.allocator, if (v) "true" else "false");
        }

        // lyrics_optimizer
        if (params.lyrics_optimizer) |v| {
            try buf.appendSlice(self.allocator, ",\"lyrics_optimizer\":");
            try buf.appendSlice(self.allocator, if (v) "true" else "false");
        }

        // is_instrumental
        if (params.is_instrumental) |v| {
            try buf.appendSlice(self.allocator, ",\"is_instrumental\":");
            try buf.appendSlice(self.allocator, if (v) "true" else "false");
        }

        try buf.append(self.allocator, '}');
        return try buf.toOwnedSlice(self.allocator);
    }

    fn parseResponse(self: *Service, response: []const u8) !MusicGenerateResponse {
        _ = self;
        // Response format: {"data":{"audio":"...","status":2},"extra_info":{...},"base_resp":{...}}
        const data_obj = extractJsonObject(response, "data");
        var audio: ?[]const u8 = null;
        var status: u32 = 0;
        if (data_obj) |d| {
            audio = parseJsonField(d, "audio");
            const status_str = parseJsonField(d, "status") orelse "0";
            status = std.fmt.parseInt(u32, status_str, 10) catch 0;
        }

        const base_resp = extractJsonObject(response, "base_resp");
        var status_code: u32 = 0;
        var status_msg: ?[]const u8 = null;
        if (base_resp) |br| {
            const status_code_str = parseJsonField(br, "status_code") orelse "0";
            status_code = std.fmt.parseInt(u32, status_code_str, 10) catch 0;
            status_msg = parseJsonField(br, "status_msg");
        }

        return MusicGenerateResponse{
            .audio = audio,
            .status = status,
            .music_duration = null,
            .music_sample_rate = null,
            .music_channel = null,
            .bitrate = null,
            .status_code = status_code,
            .status_msg = status_msg,
        };
    }
};

fn escapeJsonString(allocator: std.mem.Allocator, buf: *std.ArrayListUnmanaged(u8), str: []const u8) !void {
    try buf.append(allocator, '"');
    for (str) |c| {
        switch (c) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            else => try buf.append(allocator, c),
        }
    }
    try buf.append(allocator, '"');
}

fn parseJsonField(json_str: []const u8, field_name: []const u8) ?[]const u8 {
    const search_pattern_len = field_name.len + 3;
    if (search_pattern_len >= 128) return null;

    var buf: [128]u8 = undefined;
    @memcpy(buf[0..field_name.len], field_name);
    buf[field_name.len] = '"';
    buf[field_name.len + 1] = ':';
    buf[field_name.len + 2] = ' ';

    const pattern = buf[0..search_pattern_len];
    const start_idx = std.mem.indexOf(u8, json_str, pattern) orelse return null;
    const value_start = start_idx + search_pattern_len;

    if (value_start >= json_str.len) return null;
    if (json_str[value_start] != '"') return null;

    const value_start_inner = value_start + 1;
    const end_idx = std.mem.indexOfPos(u8, json_str, value_start_inner, "\"") orelse return null;

    return json_str[value_start_inner..end_idx];
}

/// Extract a JSON object field value (for nested objects like "data":{...})
fn extractJsonObject(json_str: []const u8, field_name: []const u8) ?[]const u8 {
    // Build pattern: "field_name":
    if (field_name.len + 4 > 128) return null;

    var buf: [128]u8 = undefined;
    @memcpy(buf[0..field_name.len], field_name);
    buf[field_name.len] = '"';
    buf[field_name.len + 1] = ':';
    buf[field_name.len + 2] = ' ';
    buf[field_name.len + 3] = '\x00'; // null terminator for string

    const pattern = buf[0 .. field_name.len + 3];

    const start_idx = std.mem.indexOf(u8, json_str, pattern) orelse return null;
    const colon_pos = start_idx + pattern.len;

    // Skip whitespace and find the opening brace
    var i = colon_pos;
    while (i < json_str.len) : (i += 1) {
        const c = json_str[i];
        if (c == '{') break;
        if (c != ' ' and c != '\n' and c != '\t' and c != '\r') return null;
    }

    if (i >= json_str.len or json_str[i] != '{') return null;
    const obj_start = i;

    // Find matching closing brace
    var depth: u32 = 1;
    i = obj_start + 1;
    while (i < json_str.len) : (i += 1) {
        if (json_str[i] == '{') {
            depth += 1;
        } else if (json_str[i] == '}') {
            depth -= 1;
            if (depth == 0) {
                return json_str[obj_start..i];
            }
        }
    }
    return null;
}
