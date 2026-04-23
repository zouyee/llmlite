//! MiniMax Video Generation API
//!
//! Supports multiple video generation modes:
//! - T2V (Text-to-Video): model + prompt
//! - I2V (Image-to-Video): model + first_frame_image (+ optional prompt)
//! - FL2V (First-Last Frame): model + first_frame_image + last_frame_image (+ optional prompt)
//! - S2V (Subject Reference): model + subject_reference (+ optional prompt)
//!
//! Reference: https://platform.minimax.io/docs/api-reference/video-generation-t2v

const std = @import("std");
const http = @import("http");

// ============================================================================
// Enums
// ============================================================================

pub const VideoResolution = enum {
    r512p,
    r720p,
    r768p,
    r1080p,

    pub fn toString(self: VideoResolution) []const u8 {
        return switch (self) {
            .r512p => "512P",
            .r720p => "720P",
            .r768p => "768P",
            .r1080p => "1080P",
        };
    }
};

/// Subject reference type for S2V mode
pub const SubjectReferenceType = enum {
    character,
};

/// Subject reference item for S2V mode
pub const SubjectReferenceItem = struct {
    ref_type: SubjectReferenceType,
    image: []const u8,
};

/// Video generation mode - determines which fields are required
pub const VideoMode = enum {
    /// Text-to-Video: requires prompt
    t2v,
    /// Image-to-Video: requires first_frame_image
    i2v,
    /// First-Last Frame-to-Video: requires first_frame_image and last_frame_image
    fl2v,
    /// Subject Reference-to-Video: requires subject_reference
    s2v,
};

/// Supported video models
pub const VideoModel = enum {
    // T2V models
    minimax_hailuo_2_3,
    minimax_hailuo_02,
    t2v_01_director,
    t2v_01,
    // I2V models
    minimax_hailuo_2_3_fast,
    i2v_01_director,
    i2v_01_live,
    i2v_01,
    // S2V model
    s2v_01,

    pub fn toString(self: VideoModel) []const u8 {
        return switch (self) {
            .minimax_hailuo_2_3 => "MiniMax-Hailuo-2.3",
            .minimax_hailuo_2_3_fast => "MiniMax-Hailuo-2.3-Fast",
            .minimax_hailuo_02 => "MiniMax-Hailuo-02",
            .t2v_01_director => "T2V-01-Director",
            .t2v_01 => "T2V-01",
            .i2v_01_director => "I2V-01-Director",
            .i2v_01_live => "I2V-01-live",
            .i2v_01 => "I2V-01",
            .s2v_01 => "S2V-01",
        };
    }

    /// Get the video mode this model belongs to
    pub fn getMode(self: VideoModel) VideoMode {
        return switch (self) {
            .minimax_hailuo_2_3, .minimax_hailuo_02, .t2v_01_director, .t2v_01 => .t2v,
            .minimax_hailuo_2_3_fast, .i2v_01_director, .i2v_01_live, .i2v_01 => .i2v,
            .s2v_01 => .s2v,
        };
    }
};

// ============================================================================
// Request/Response Types
// ============================================================================

pub const VideoGenerationRequest = struct {
    model: VideoModel,
    /// Text prompt (required for T2V, optional for others)
    prompt: ?[]const u8 = null,
    /// First frame image URL or base64 (required for I2V and FL2V)
    first_frame_image: ?[]const u8 = null,
    /// Last frame image URL or base64 (required for FL2V)
    last_frame_image: ?[]const u8 = null,
    /// Subject reference for S2V mode
    subject_references: ?[]const SubjectReferenceItem = null,
    /// Auto-optimize prompt (default: true)
    prompt_optimizer: ?bool = true,
    /// Fast pretreatment (default: false)
    fast_pretreatment: ?bool = false,
    /// Video duration in seconds (default: 6)
    duration: ?u32 = 6,
    /// Video resolution
    resolution: ?VideoResolution = null,
    /// Callback URL for async notifications
    callback_url: ?[]const u8 = null,
    /// Add AIGC watermark (default: false)
    aigc_watermark: ?bool = false,
};

pub const VideoGenerationResponse = struct {
    task_id: ?[]const u8,
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

    /// Generate video (supports T2V, I2V, FL2V, S2V modes)
    pub fn generate(self: *Service, params: VideoGenerationRequest) !VideoGenerationResponse {
        const json_str = try self.serializeRequest(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/video_generation", json_str);
        defer self.allocator.free(response);

        return try self.parseResponse(response);
    }

    fn serializeRequest(self: *Service, params: VideoGenerationRequest) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8).empty;
        errdefer buf.deinit(self.allocator);

        try buf.append(self.allocator, '{');

        // model (required)
        try buf.appendSlice(self.allocator, "\"model\":\"");
        try buf.appendSlice(self.allocator, params.model.toString());
        try buf.append(self.allocator, '"');

        // prompt (required for T2V, optional for others)
        if (params.prompt) |p| {
            try buf.appendSlice(self.allocator, ",\"prompt\":");
            try escapeJsonString(self.allocator, &buf, p);
        }

        // first_frame_image (required for I2V and FL2V)
        if (params.first_frame_image) |img| {
            try buf.appendSlice(self.allocator, ",\"first_frame_image\":");
            try escapeJsonString(self.allocator, &buf, img);
        }

        // last_frame_image (required for FL2V)
        if (params.last_frame_image) |img| {
            try buf.appendSlice(self.allocator, ",\"last_frame_image\":");
            try escapeJsonString(self.allocator, &buf, img);
        }

        // subject_references (required for S2V)
        if (params.subject_references) |refs| {
            try buf.appendSlice(self.allocator, ",\"subject_reference\":[");
            for (refs, 0..) |ref, i| {
                if (i > 0) try buf.append(self.allocator, ',');
                try buf.appendSlice(self.allocator, "{\"type\":\"");
                try buf.appendSlice(self.allocator, switch (ref.ref_type) {
                    .character => "character",
                });
                try buf.appendSlice(self.allocator, "\",\"image\":[\"");
                try escapeJsonString(self.allocator, &buf, ref.image);
                try buf.appendSlice(self.allocator, "\"]}");
            }
            try buf.append(self.allocator, ']');
        }

        // prompt_optimizer
        if (params.prompt_optimizer) |v| {
            try buf.appendSlice(self.allocator, ",\"prompt_optimizer\":");
            try buf.appendSlice(self.allocator, if (v) "true" else "false");
        }

        // fast_pretreatment
        if (params.fast_pretreatment) |v| {
            try buf.appendSlice(self.allocator, ",\"fast_pretreatment\":");
            try buf.appendSlice(self.allocator, if (v) "true" else "false");
        }

        // duration
        if (params.duration) |v| {
            try buf.appendSlice(self.allocator, ",\"duration\":");
            try buf.print(self.allocator, "{}", .{v});
        }

        // resolution
        if (params.resolution) |r| {
            try buf.appendSlice(self.allocator, ",\"resolution\":\"");
            try buf.appendSlice(self.allocator, r.toString());
            try buf.append(self.allocator, '"');
        }

        // callback_url
        if (params.callback_url) |url| {
            try buf.appendSlice(self.allocator, ",\"callback_url\":\"");
            try buf.appendSlice(self.allocator, url);
            try buf.append(self.allocator, '"');
        }

        // aigc_watermark
        if (params.aigc_watermark) |v| {
            try buf.appendSlice(self.allocator, ",\"aigc_watermark\":");
            try buf.appendSlice(self.allocator, if (v) "true" else "false");
        }

        try buf.append(self.allocator, '}');
        return try buf.toOwnedSlice(self.allocator);
    }

    fn escapeJsonString(allocator: std.mem.Allocator, buf: *std.ArrayListUnmanaged(u8), str: []const u8) !void {
        // Simple JSON string escaping
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

    fn parseResponse(self: *Service, response: []const u8) !VideoGenerationResponse {
        _ = self;
        const task_id = parseJsonField(response, "task_id");
        // Response: {"task_id":"...","base_resp":{"status_code":0,"status_msg":"success"}}
        const base_resp = extractJsonObject(response, "base_resp");
        var status_code: u32 = 0;
        var status_msg: ?[]const u8 = null;
        if (base_resp) |br| {
            const status_code_str = parseJsonField(br, "status_code") orelse "0";
            status_code = std.fmt.parseInt(u32, status_code_str, 10) catch 0;
            status_msg = parseJsonField(br, "status_msg");
        }

        return VideoGenerationResponse{
            .task_id = task_id,
            .status_code = status_code,
            .status_msg = status_msg,
        };
    }
};

fn parseJsonField(json_str: []const u8, field_name: []const u8) ?[]const u8 {
    const search_pattern_len = field_name.len + 3;
    if (search_pattern_len >= 128) return null;

    var buf: [128]u8 = undefined;
    @memcpy(buf[0..field_name.len], field_name);
    buf[field_name.len] = '"';
    buf[field_name.len + 1] = ':';
    buf[field_name.len + 2] = ' ';

    const pattern = buf[0..search_pattern_len];
    const start_idx = std.mem.find(u8, json_str, pattern) orelse return null;
    const value_start = start_idx + search_pattern_len;

    if (value_start >= json_str.len) return null;
    if (json_str[value_start] != '"') return null;

    const value_start_inner = value_start + 1;
    const end_idx = std.mem.findPos(u8, json_str, value_start_inner, "\"") orelse return null;

    return json_str[value_start_inner..end_idx];
}

/// Extract a JSON object field value (for nested objects like "base_resp":{...})
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

    const start_idx = std.mem.find(u8, json_str, pattern) orelse return null;
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
