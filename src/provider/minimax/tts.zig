//! MiniMax Text-to-Audio API
//!
//! Reference: https://platform.minimaxi.com/docs/api-reference/speech-t2a-http

const std = @import("std");
const http = @import("http");

// ============================================================================
// Models
// ============================================================================

pub const T2AModel = enum {
    speech_2_8_hd,
    speech_2_8_turbo,
    speech_2_6_hd,
    speech_2_6_turbo,
    speech_02_hd,
    speech_02_turbo,
    speech_01_hd,
    speech_01_turbo,

    pub fn toString(self: T2AModel) []const u8 {
        return switch (self) {
            .speech_2_8_hd => "speech-2.8-hd",
            .speech_2_8_turbo => "speech-2.8-turbo",
            .speech_2_6_hd => "speech-2.6-hd",
            .speech_2_6_turbo => "speech-2.6-turbo",
            .speech_02_hd => "speech-02-hd",
            .speech_02_turbo => "speech-02-turbo",
            .speech_01_hd => "speech-01-hd",
            .speech_01_turbo => "speech-01-turbo",
        };
    }
};

pub const Emotion = enum {
    happy,
    sad,
    angry,
    fearful,
    disgusted,
    surprised,
    calm,
    fluent,
    whisper,

    pub fn toString(self: Emotion) []const u8 {
        return switch (self) {
            .happy => "happy",
            .sad => "sad",
            .angry => "angry",
            .fearful => "fearful",
            .disgusted => "disgusted",
            .surprised => "surprised",
            .calm => "calm",
            .fluent => "fluent",
            .whisper => "whisper",
        };
    }
};

pub const AudioFormat = enum {
    mp3,
    pcm,
    flac,
    wav,

    pub fn toString(self: AudioFormat) []const u8 {
        return switch (self) {
            .mp3 => "mp3",
            .pcm => "pcm",
            .flac => "flac",
            .wav => "wav",
        };
    }
};

// ============================================================================
// Request/Response Types
// ============================================================================

pub const VoiceSetting = struct {
    voice_id: []const u8,
    speed: ?f32 = 1.0,
    vol: ?f32 = 1.0,
    pitch: ?i32 = 0,
    emotion: ?Emotion = null,
};

pub const AudioSetting = struct {
    sample_rate: ?u32 = 32000,
    bitrate: ?u32 = 128000,
    format: AudioFormat = .mp3,
    channel: ?u32 = 1,
};

pub const T2ARequest = struct {
    model: []const u8,
    text: []const u8,
    stream: bool = false,
    voice_setting: VoiceSetting,
    audio_setting: ?AudioSetting = null,
    output_format: []const u8 = "hex",
};

pub const T2AResponse = struct {
    audio: ?[]const u8,
    status: u32,
    extra_info: ?struct {
        audio_length: u64,
        audio_sample_rate: u32,
        audio_size: u64,
        bitrate: u32,
        audio_format: []const u8,
        audio_channel: u32,
    } = null,
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

    /// Synthesize speech from text
    pub fn synthesize(self: *Service, params: T2ARequest) !T2AResponse {
        const json_str = try self.serializeT2ARequest(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/t2a_v2", json_str);
        defer self.allocator.free(response);

        return try self.parseT2AResponse(response);
    }

    fn serializeT2ARequest(self: *Service, params: T2ARequest) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8).empty;
        errdefer buf.deinit(self.allocator);

        try buf.append(self.allocator, '{');

        // model
        try buf.appendSlice(self.allocator, "\"model\":\"");
        try buf.appendSlice(self.allocator, params.model);
        try buf.append(self.allocator, '"');

        // text
        try buf.appendSlice(self.allocator, ",\"text\":\"");
        try escapeJsonString(self.allocator, &buf, params.text);
        try buf.append(self.allocator, '"');

        // stream
        try buf.appendSlice(self.allocator, ",\"stream\":");
        try buf.appendSlice(self.allocator, if (params.stream) "true" else "false");

        // voice_setting
        try buf.appendSlice(self.allocator, ",\"voice_setting\":{");
        try buf.appendSlice(self.allocator, "\"voice_id\":\"");
        try buf.appendSlice(self.allocator, params.voice_setting.voice_id);
        try buf.append(self.allocator, '"');

        if (params.voice_setting.speed) |v| {
            try buf.appendSlice(self.allocator, ",\"speed\":");
            try buf.writer(self.allocator).print("{d}", .{v});
        }
        if (params.voice_setting.vol) |v| {
            try buf.appendSlice(self.allocator, ",\"vol\":");
            try buf.writer(self.allocator).print("{d}", .{v});
        }
        if (params.voice_setting.pitch) |v| {
            try buf.appendSlice(self.allocator, ",\"pitch\":");
            try buf.writer(self.allocator).print("{d}", .{v});
        }
        if (params.voice_setting.emotion) |emotion| {
            try buf.appendSlice(self.allocator, ",\"emotion\":\"");
            try buf.appendSlice(self.allocator, emotion.toString());
            try buf.append(self.allocator, '"');
        }
        try buf.append(self.allocator, '}');

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

            if (audio.channel) |ch| {
                try buf.appendSlice(self.allocator, ",\"channel\":");
                try buf.writer(self.allocator).print("{}", .{ch});
            }
            try buf.append(self.allocator, '}');
        }

        // output_format
        try buf.appendSlice(self.allocator, ",\"output_format\":\"");
        try buf.appendSlice(self.allocator, params.output_format);
        try buf.append(self.allocator, '"');

        try buf.append(self.allocator, '}');
        return try buf.toOwnedSlice(self.allocator);
    }

    fn parseT2AResponse(self: *Service, response: []const u8) !T2AResponse {
        _ = self;
        // Response format: {"data":{"audio":"...","status":2},"extra_info":{...},"base_resp":{...}}
        // First extract the data object, then get audio from it

        var status: u32 = 0;
        var audio: ?[]const u8 = null;

        const data_obj = extractJsonObject(response, "data");
        if (data_obj) |data_str| {
            audio = parseJsonField(data_str, "audio");
            const status_str = parseJsonField(data_str, "status") orelse "0";
            status = std.fmt.parseInt(u32, status_str, 10) catch 0;
        } else {
            // Fallback: try to find audio at top level (legacy format)
            audio = parseJsonField(response, "audio");
            const status_str = parseJsonField(response, "status") orelse "0";
            status = std.fmt.parseInt(u32, status_str, 10) catch 0;
        }

        // Check base_resp for error status if status is not 0
        if (status != 0) {
            if (extractJsonObject(response, "base_resp")) |base_resp| {
                const base_status_str = parseJsonField(base_resp, "status_code") orelse "0";
                const base_status = std.fmt.parseInt(u32, base_status_str, 10) catch 0;
                // If base_resp has a non-zero status, use that
                if (base_status != 0) {
                    status = base_status;
                }
            }
        }

        return T2AResponse{
            .audio = audio,
            .status = status,
            .extra_info = null,
        };
    }
};

fn escapeJsonString(allocator: std.mem.Allocator, buf: *std.ArrayListUnmanaged(u8), str: []const u8) !void {
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
