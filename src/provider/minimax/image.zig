//! MiniMax Image Generation API
//!
//! Reference: https://platform.minimaxi.com/docs/api-reference/image-generation-t2i

const std = @import("std");
const http = @import("http");

// ============================================================================
// Models
// ============================================================================

pub const ImageModel = enum {
    image_01,
    image_01_live,

    pub fn toString(self: ImageModel) []const u8 {
        return switch (self) {
            .image_01 => "image-01",
            .image_01_live => "image-01-live",
        };
    }
};

pub const AspectRatio = enum {
    ratio_1_1,
    ratio_16_9,
    ratio_4_3,
    ratio_3_2,
    ratio_2_3,
    ratio_3_4,
    ratio_9_16,
    ratio_21_9,

    pub fn toString(self: AspectRatio) []const u8 {
        return switch (self) {
            .ratio_1_1 => "1:1",
            .ratio_16_9 => "16:9",
            .ratio_4_3 => "4:3",
            .ratio_3_2 => "3:2",
            .ratio_2_3 => "2:3",
            .ratio_3_4 => "3:4",
            .ratio_9_16 => "9:16",
            .ratio_21_9 => "21:9",
        };
    }
};

pub const ResponseFormat = enum {
    url,
    base64,

    pub fn toString(self: ResponseFormat) []const u8 {
        return switch (self) {
            .url => "url",
            .base64 => "base64",
        };
    }
};

pub const StyleType = enum {
    cartoon,
    energetic,
    medieval,
    watercolor,

    pub fn toString(self: StyleType) []const u8 {
        return switch (self) {
            .cartoon => "漫画",
            .energetic => "元气",
            .medieval => "中世纪",
            .watercolor => "水彩",
        };
    }
};

// ============================================================================
// Request/Response Types
// ============================================================================

pub const StyleObject = struct {
    style_type: StyleType,
    style_weight: ?f32 = 0.8,
};

pub const ImageGenerateRequest = struct {
    model: []const u8,
    prompt: []const u8,
    style: ?StyleObject = null,
    aspect_ratio: ?AspectRatio = null,
    width: ?u32 = null,
    height: ?u32 = null,
    response_format: ResponseFormat = .url,
    seed: ?u64 = null,
    n: ?u32 = 1,
    prompt_optimizer: ?bool = false,
    aigc_watermark: ?bool = false,
};

pub const ImageGenerateResponse = struct {
    id: ?[]const u8,
    image_urls: ?[][]const u8,
    image_base64: ?[][]const u8,
    success_count: u32,
    failed_count: u32,
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

    /// Generate image from text prompt
    pub fn generate(self: *Service, params: ImageGenerateRequest) !ImageGenerateResponse {
        const json_str = try self.serializeRequest(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/image_generation", json_str);
        defer self.allocator.free(response);

        return try self.parseResponse(response);
    }

    fn serializeRequest(self: *Service, params: ImageGenerateRequest) ![]u8 {
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

        // style
        if (params.style) |style| {
            try buf.appendSlice(self.allocator, ",\"style\":{");
            try buf.appendSlice(self.allocator, "\"style_type\":\"");
            try buf.appendSlice(self.allocator, style.style_type.toString());
            try buf.append(self.allocator, '"');
            if (style.style_weight) |sw| {
                try buf.appendSlice(self.allocator, ",\"style_weight\":");
                try buf.writer(self.allocator).print("{d}", .{sw});
            }
            try buf.append(self.allocator, '}');
        }

        // aspect_ratio
        if (params.aspect_ratio) |ar| {
            try buf.appendSlice(self.allocator, ",\"aspect_ratio\":\"");
            try buf.appendSlice(self.allocator, ar.toString());
            try buf.append(self.allocator, '"');
        }

        // width and height
        if (params.width) |w| {
            try buf.appendSlice(self.allocator, ",\"width\":");
            try buf.writer(self.allocator).print("{}", .{w});
        }
        if (params.height) |h| {
            try buf.appendSlice(self.allocator, ",\"height\":");
            try buf.writer(self.allocator).print("{}", .{h});
        }

        // response_format
        try buf.appendSlice(self.allocator, ",\"response_format\":\"");
        try buf.appendSlice(self.allocator, params.response_format.toString());
        try buf.append(self.allocator, '"');

        // seed
        if (params.seed) |s| {
            try buf.appendSlice(self.allocator, ",\"seed\":");
            try buf.writer(self.allocator).print("{}", .{s});
        }

        // n
        if (params.n) |n| {
            try buf.appendSlice(self.allocator, ",\"n\":");
            try buf.writer(self.allocator).print("{}", .{n});
        }

        // prompt_optimizer
        if (params.prompt_optimizer) |v| {
            try buf.appendSlice(self.allocator, ",\"prompt_optimizer\":");
            try buf.appendSlice(self.allocator, if (v) "true" else "false");
        }

        // aigc_watermark
        if (params.aigc_watermark) |v| {
            try buf.appendSlice(self.allocator, ",\"aigc_watermark\":");
            try buf.appendSlice(self.allocator, if (v) "true" else "false");
        }

        try buf.append(self.allocator, '}');
        return try buf.toOwnedSlice(self.allocator);
    }

    fn parseResponse(self: *Service, response: []const u8) !ImageGenerateResponse {
        _ = self;
        const id = parseJsonField(response, "id");
        const status_code_str = parseJsonField(response, "status_code") orelse "0";
        const status_code = std.fmt.parseInt(u32, status_code_str, 10) catch 0;
        const status_msg = parseJsonField(response, "status_msg");

        const success_count_str = parseJsonField(response, "success_count") orelse "0";
        const success_count = std.fmt.parseInt(u32, success_count_str, 10) catch 0;

        const failed_count_str = parseJsonField(response, "failed_count") orelse "0";
        const failed_count = std.fmt.parseInt(u32, failed_count_str, 10) catch 0;

        // Parse image URLs or base64
        var image_urls: ?[][]const u8 = null;
        const image_base64: ?[][]const u8 = null;

        if (parseJsonField(response, "image_urls")) |urls_str| {
            _ = urls_str;
            // Simplified - would need proper JSON array parsing
            image_urls = null;
        }

        return ImageGenerateResponse{
            .id = id,
            .image_urls = image_urls,
            .image_base64 = image_base64,
            .success_count = success_count,
            .failed_count = failed_count,
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
