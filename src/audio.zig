//! Audio API

const std = @import("std");
const http = @import("http");

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

    /// Transcribes audio into written text.
    pub fn createTranscription(self: *Service, params: TranscriptionParams) !Transcription {
        const form_data = try self.buildTranscriptionFormData(params);
        defer self.allocator.free(form_data);

        const response = try self.http_client.postForm("/audio/transcriptions", form_data);
        defer self.allocator.free(response);

        return try self.parseTranscriptionResponse(response, params.response_format);
    }

    /// Translates audio into English text.
    pub fn createTranslation(self: *Service, params: TranslationParams) !Translation {
        const form_data = try self.buildTranslationFormData(params);
        defer self.allocator.free(form_data);

        const response = try self.http_client.postForm("/audio/translations", form_data);
        defer self.allocator.free(response);

        return try self.parseTranslationResponse(response);
    }

    /// Generates audio from text.
    pub fn createSpeech(self: *Service, params: SpeechParams) ![]u8 {
        const json_str = try self.serializeSpeechParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.postBinary("/audio/speech", json_str);
        defer self.allocator.free(response);

        return response;
    }

    fn buildTranscriptionFormData(self: *Service, params: TranscriptionParams) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8).empty;
        errdefer buf.deinit(self.allocator);

        // Add file
        try buf.appendSlice(self.allocator, "--form\n");
        try buf.appendSlice(self.allocator, "Content-Disposition: form-data; name=\"file\"; filename=\"audio.mp3\"\r\n");
        try buf.appendSlice(self.allocator, "Content-Type: application/octet-stream\r\n\r\n");
        try buf.appendSlice(self.allocator, params.file);
        try buf.appendSlice(self.allocator, "\r\n");

        // Add model
        try buf.appendSlice(self.allocator, "--form\n");
        try buf.appendSlice(self.allocator, "Content-Disposition: form-data; name=\"model\"\r\n\r\n");
        try buf.appendSlice(self.allocator, params.model.toString());
        try buf.appendSlice(self.allocator, "\r\n");

        if (params.language) |v| {
            try buf.appendSlice(self.allocator, "--form\n");
            try buf.appendSlice(self.allocator, "Content-Disposition: form-data; name=\"language\"\r\n\r\n");
            try buf.appendSlice(self.allocator, v);
            try buf.appendSlice(self.allocator, "\r\n");
        }

        if (params.prompt) |v| {
            try buf.appendSlice(self.allocator, "--form\n");
            try buf.appendSlice(self.allocator, "Content-Disposition: form-data; name=\"prompt\"\r\n\r\n");
            try buf.appendSlice(self.allocator, v);
            try buf.appendSlice(self.allocator, "\r\n");
        }

        if (params.response_format) |v| {
            try buf.appendSlice(self.allocator, "--form\n");
            try buf.appendSlice(self.allocator, "Content-Disposition: form-data; name=\"response_format\"\r\n\r\n");
            try buf.appendSlice(self.allocator, v.toString());
            try buf.appendSlice(self.allocator, "\r\n");
        }

        if (params.temperature) |v| {
            try buf.appendSlice(self.allocator, "--form\n");
            try buf.appendSlice(self.allocator, "Content-Disposition: form-data; name=\"temperature\"\r\n\r\n");
            try buf.writer(self.allocator).print("{d}\r\n", .{v});
        }

        if (params.timestamp_granularities) |v| {
            try buf.appendSlice(self.allocator, "--form\n");
            try buf.appendSlice(self.allocator, "Content-Disposition: form-data; name=\"timestamp_granularities[]\"\r\n\r\n");
            try buf.appendSlice(self.allocator, v);
            try buf.appendSlice(self.allocator, "\r\n");
        }

        try buf.appendSlice(self.allocator, "--form--\r\n");

        return try buf.toOwnedSlice(self.allocator);
    }

    fn buildTranslationFormData(self: *Service, params: TranslationParams) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8).empty;
        errdefer buf.deinit(self.allocator);

        // Add file
        try buf.appendSlice(self.allocator, "--form\n");
        try buf.appendSlice(self.allocator, "Content-Disposition: form-data; name=\"file\"; filename=\"audio.mp3\"\r\n");
        try buf.appendSlice(self.allocator, "Content-Type: application/octet-stream\r\n\r\n");
        try buf.appendSlice(self.allocator, params.file);
        try buf.appendSlice(self.allocator, "\r\n");

        // Add model
        try buf.appendSlice(self.allocator, "--form\n");
        try buf.appendSlice(self.allocator, "Content-Disposition: form-data; name=\"model\"\r\n\r\n");
        try buf.appendSlice(self.allocator, params.model.toString());
        try buf.appendSlice(self.allocator, "\r\n");

        if (params.prompt) |v| {
            try buf.appendSlice(self.allocator, "--form\n");
            try buf.appendSlice(self.allocator, "Content-Disposition: form-data; name=\"prompt\"\r\n\r\n");
            try buf.appendSlice(self.allocator, v);
            try buf.appendSlice(self.allocator, "\r\n");
        }

        if (params.response_format) |v| {
            try buf.appendSlice(self.allocator, "--form\n");
            try buf.appendSlice(self.allocator, "Content-Disposition: form-data; name=\"response_format\"\r\n\r\n");
            try buf.appendSlice(self.allocator, v.toString());
            try buf.appendSlice(self.allocator, "\r\n");
        }

        if (params.temperature) |v| {
            try buf.appendSlice(self.allocator, "--form\n");
            try buf.appendSlice(self.allocator, "Content-Disposition: form-data; name=\"temperature\"\r\n\r\n");
            try buf.writer(self.allocator).print("{d}\r\n", .{v});
        }

        try buf.appendSlice(self.allocator, "--form--\r\n");

        return try buf.toOwnedSlice(self.allocator);
    }

    fn serializeSpeechParams(self: *Service, params: SpeechParams) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8).empty;
        errdefer buf.deinit(self.allocator);

        try buf.append(self.allocator, '{');
        try buf.appendSlice(self.allocator, "\"model\":\"");
        try buf.appendSlice(self.allocator, params.model.toString());
        try buf.appendSlice(self.allocator, "\",\"input\":\"");
        try escapeJsonString(self.allocator, &buf, params.input);
        try buf.appendSlice(self.allocator, "\",\"voice\":\"");
        try buf.appendSlice(self.allocator, params.voice.toString());
        try buf.append(self.allocator, '"');

        if (params.response_format) |v| {
            try buf.appendSlice(self.allocator, ",\"response_format\":\"");
            try buf.appendSlice(self.allocator, v.toString());
            try buf.append(self.allocator, '"');
        }

        if (params.speed) |v| {
            try buf.appendSlice(self.allocator, ",\"speed\":");
            try buf.writer(self.allocator).print("{d}", .{v});
        }

        try buf.append(self.allocator, '}');
        return try buf.toOwnedSlice(self.allocator);
    }

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

    fn parseTranscriptionResponse(_: *Service, response: []u8, format: ?AudioResponseFormat) !Transcription {
        // If verbose_json, parse as TranscriptionVerbose, otherwise simple text
        _ = format;
        // Simple transcription parsing - just extract text field
        const text = parseJsonField(response, "text") orelse {
            // If no text field, return entire response as text (for non-JSON formats)
            return Transcription{ .text = response };
        };
        return Transcription{ .text = text };
    }

    fn parseTranslationResponse(_: *Service, response: []u8) !Translation {
        const text = parseJsonField(response, "text") orelse {
            return Translation{ .text = response };
        };
        return Translation{ .text = text };
    }

    fn parseJsonField(json_str: []const u8, field_name: []const u8) ?[]const u8 {
        const search_pattern_len = field_name.len + 3;
        if (search_pattern_len >= 128) return null;

        var buf: [128]u8 = undefined;
        @memcpy(buf[0..field_name.len], field_name);
        buf[field_name.len] = '"';
        buf[field_name.len + 1] = ':';
        buf[field_name.len + 2] = ' ';

        const start_idx = std.mem.indexOf(u8, json_str, buf[0..search_pattern_len]) orelse return null;
        const value_start = start_idx + search_pattern_len;

        var i = value_start;
        while (i < json_str.len and (json_str[i] == ' ' or json_str[i] == '\n' or json_str[i] == '\t')) {
            i += 1;
        }

        if (i >= json_str.len) return null;

        if (json_str[i] == '"') {
            i += 1;
            const str_start = i;
            while (i < json_str.len and json_str[i] != '"') {
                if (json_str[i] == '\\') i += 1;
                i += 1;
            }
            return json_str[str_start..i];
        } else if (json_str[i] == '{' or json_str[i] == '[') {
            var depth: u32 = 1;
            const start_char = json_str[i];
            i += 1;
            while (i < json_str.len and depth > 0) {
                if (json_str[i] == start_char) depth += 1;
                if (json_str[i] == '}') depth -= 1;
                if (json_str[i] == ']') depth -= 1;
                i += 1;
            }
            return json_str[value_start..i];
        } else {
            const num_start = i;
            while (i < json_str.len and (std.ascii.isDigit(json_str[i]) or json_str[i] == '.' or json_str[i] == '-' or json_str[i] == 'e' or json_str[i] == 'E')) {
                i += 1;
            }
            return json_str[num_start..i];
        }
    }
};

// ============================================================================
// Audio Model
// ============================================================================

pub const AudioModel = enum {
    whisper_1,
    gpt_4o_transcribe,
    gpt_4o_mini_transcribe,

    pub fn toString(self: AudioModel) []const u8 {
        return switch (self) {
            .whisper_1 => "whisper-1",
            .gpt_4o_transcribe => "gpt-4o-transcribe",
            .gpt_4o_mini_transcribe => "gpt-4o-mini-transcribe",
        };
    }
};

// ============================================================================
// Audio Response Format
// ============================================================================

pub const AudioResponseFormat = enum {
    json,
    text,
    srt,
    verbose_json,
    vtt,

    pub fn toString(self: AudioResponseFormat) []const u8 {
        return switch (self) {
            .json => "json",
            .text => "text",
            .srt => "srt",
            .verbose_json => "verbose_json",
            .vtt => "vtt",
        };
    }
};

// ============================================================================
// Transcription Word
// ============================================================================

pub const TranscriptionWord = struct {
    word: []const u8,
    start_ms: u32,
    end_ms: u32,
};

// ============================================================================
// Transcription Segment
// ============================================================================

pub const TranscriptionSegment = struct {
    id: u32,
    seek: u32,
    start_ms: u32,
    end_ms: u32,
    text: []const u8,
    tokens: []u32,
    temperature: f32,
    avg_logprob: f32,
    compression_ratio: f32,
    no_speech_prob: f32,
    pause_duration: ?f32 = null,
};

// ============================================================================
// Transcription
// ============================================================================

pub const Transcription = struct {
    text: []const u8,
};

// ============================================================================
// Transcription Verbose
// ============================================================================

pub const TranscriptionVerbose = struct {
    text: []const u8,
    language: ?[]const u8 = null,
    duration: ?[]const u8 = null,
    segments: ?[]TranscriptionSegment = null,
    words: ?[]TranscriptionWord = null,
};

// ============================================================================
// Translation
// ============================================================================

pub const Translation = struct {
    text: []const u8,
};

// ============================================================================
// Speech Model
// ============================================================================

pub const SpeechModel = enum {
    tts_1,
    tts_1_hd,
    gpt_4o_mini_tts,

    pub fn toString(self: SpeechModel) []const u8 {
        return switch (self) {
            .tts_1 => "tts-1",
            .tts_1_hd => "tts-1-hd",
            .gpt_4o_mini_tts => "gpt-4o-mini-tts",
        };
    }
};

// ============================================================================
// Speech Voice
// ============================================================================

pub const SpeechVoice = enum {
    alloy,
    ash,
    ballad,
    coral,
    echo,
    fable,
    nova,
    onyx,
    sage,
    shimmer,
    verse,
    marin,
    cedar,

    pub fn toString(self: SpeechVoice) []const u8 {
        return switch (self) {
            .alloy => "alloy",
            .ash => "ash",
            .ballad => "ballad",
            .coral => "coral",
            .echo => "echo",
            .fable => "fable",
            .nova => "nova",
            .onyx => "onyx",
            .sage => "sage",
            .shimmer => "shimmer",
            .verse => "verse",
            .marin => "marin",
            .cedar => "cedar",
        };
    }
};

// ============================================================================
// Speech Request Params
// ============================================================================

pub const SpeechParams = struct {
    input: []const u8,
    voice: SpeechVoice,
    model: SpeechModel,
    response_format: ?AudioResponseFormat = null,
    speed: ?f32 = null,
};

// ============================================================================
// Transcription Request Params
// ============================================================================

pub const TranscriptionParams = struct {
    file: []const u8,
    model: AudioModel,
    language: ?[]const u8 = null,
    prompt: ?[]const u8 = null,
    response_format: ?AudioResponseFormat = null,
    temperature: ?f32 = null,
    timestamp_granularities: ?[]const u8 = null,
};

// ============================================================================
// Translation Request Params
// ============================================================================

pub const TranslationParams = struct {
    file: []const u8,
    model: AudioModel,
    prompt: ?[]const u8 = null,
    response_format: ?AudioResponseFormat = null,
    temperature: ?f32 = null,
};
