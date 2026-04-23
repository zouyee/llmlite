//! Images API

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

    /// Creates an image given a prompt.
    pub fn generateImage(self: *Service, params: ImageGenerateParams) !ImagesResponse {
        const json_str = try self.serializeImageGenerateParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/images/generations", json_str);
        defer self.allocator.free(response);

        return try self.parseImagesResponse(response);
    }

    /// Creates a edited or extended image given an original image and a prompt.
    pub fn editImage(self: *Service, params: ImageEditParams) !ImagesResponse {
        // For edit, we use JSON (simpler than multipart)
        const json_str = try self.serializeImageEditParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/images/edits", json_str);
        defer self.allocator.free(response);

        return try self.parseImagesResponse(response);
    }

    /// Creates a variation of a given image.
    pub fn createImageVariation(self: *Service, params: ImageVariationParams) !ImagesResponse {
        // For variation, we use JSON
        const json_str = try self.serializeImageVariationParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/images/variations", json_str);
        defer self.allocator.free(response);

        return try self.parseImagesResponse(response);
    }

    fn serializeImageGenerateParams(self: *Service, params: ImageGenerateParams) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8).empty;
        errdefer buf.deinit(self.allocator);

        try buf.append(self.allocator, '{');
        try buf.appendSlice(self.allocator, "\"prompt\":\"");
        try escapeJsonString(self.allocator, &buf, params.prompt);
        try buf.append(self.allocator, '"');

        if (params.model) |v| {
            try buf.appendSlice(self.allocator, ",\"model\":\"");
            try buf.appendSlice(self.allocator, v);
            try buf.append(self.allocator, '"');
        }

        if (params.quality) |v| {
            try buf.appendSlice(self.allocator, ",\"quality\":\"");
            try buf.appendSlice(self.allocator, v.toString());
            try buf.append(self.allocator, '"');
        }

        if (params.response_format) |v| {
            try buf.appendSlice(self.allocator, ",\"response_format\":\"");
            try buf.appendSlice(self.allocator, v.toString());
            try buf.append(self.allocator, '"');
        }

        if (params.size) |v| {
            try buf.appendSlice(self.allocator, ",\"size\":\"");
            try buf.appendSlice(self.allocator, v.toString());
            try buf.append(self.allocator, '"');
        }

        if (params.style) |v| {
            try buf.appendSlice(self.allocator, ",\"style\":\"");
            try buf.appendSlice(self.allocator, v.toString());
            try buf.append(self.allocator, '"');
        }

        if (params.user) |v| {
            try buf.appendSlice(self.allocator, ",\"user\":\"");
            try buf.appendSlice(self.allocator, v);
            try buf.append(self.allocator, '"');
        }

        try buf.append(self.allocator, '}');
        return try buf.toOwnedSlice(self.allocator);
    }

    fn serializeImageEditParams(self: *Service, params: ImageEditParams) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8).empty;
        errdefer buf.deinit(self.allocator);

        try buf.append(self.allocator, '{');
        try buf.appendSlice(self.allocator, "\"prompt\":\"");
        try escapeJsonString(self.allocator, &buf, params.prompt);
        try buf.append(self.allocator, '"');

        // For edit, image is provided as URL or base64 - using URL approach
        if (params.model) |v| {
            try buf.appendSlice(self.allocator, ",\"model\":\"");
            try buf.appendSlice(self.allocator, v);
            try buf.append(self.allocator, '"');
        }

        if (params.n) |v| {
            try buf.appendSlice(self.allocator, ",\"n\":");
            try buf.writer(self.allocator).print("{}", .{v});
        }

        if (params.size) |v| {
            try buf.appendSlice(self.allocator, ",\"size\":\"");
            try buf.appendSlice(self.allocator, v.toString());
            try buf.append(self.allocator, '"');
        }

        if (params.response_format) |v| {
            try buf.appendSlice(self.allocator, ",\"response_format\":\"");
            try buf.appendSlice(self.allocator, v.toString());
            try buf.append(self.allocator, '"');
        }

        if (params.user) |v| {
            try buf.appendSlice(self.allocator, ",\"user\":\"");
            try buf.appendSlice(self.allocator, v);
            try buf.append(self.allocator, '"');
        }

        try buf.append(self.allocator, '}');
        return try buf.toOwnedSlice(self.allocator);
    }

    fn serializeImageVariationParams(self: *Service, params: ImageVariationParams) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8).empty;
        errdefer buf.deinit(self.allocator);

        try buf.append(self.allocator, '{');

        if (params.model) |v| {
            try buf.appendSlice(self.allocator, "\"model\":\"");
            try buf.appendSlice(self.allocator, v);
            try buf.append(self.allocator, '"');
        }

        if (params.n) |v| {
            if (params.model != null) try buf.append(self.allocator, ',');
            try buf.appendSlice(self.allocator, "\"n\":");
            try buf.writer(self.allocator).print("{}", .{v});
        }

        if (params.size) |v| {
            if (params.model != null or params.n != null) try buf.append(self.allocator, ',');
            try buf.appendSlice(self.allocator, "\"size\":\"");
            try buf.appendSlice(self.allocator, v.toString());
            try buf.append(self.allocator, '"');
        }

        if (params.response_format) |v| {
            if (params.model != null or params.n != null or params.size != null) try buf.append(self.allocator, ',');
            try buf.appendSlice(self.allocator, "\"response_format\":\"");
            try buf.appendSlice(self.allocator, v.toString());
            try buf.append(self.allocator, '"');
        }

        if (params.user) |v| {
            if (params.model != null or params.n != null or params.size != null or params.response_format != null) try buf.append(self.allocator, ',');
            try buf.appendSlice(self.allocator, "\"user\":\"");
            try buf.appendSlice(self.allocator, v);
            try buf.append(self.allocator, '"');
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

    fn parseImagesResponse(self: *Service, response: []const u8) !ImagesResponse {
        const created_str = parseJsonField(response, "created") orelse "0";
        const created = std.fmt.parseInt(u64, created_str, 10) catch 0;

        const data_str = parseJsonField(response, "data") orelse return error.ParseError;

        // Count images in data array
        var image_count: usize = 0;
        var search_pos: usize = 0;
        while (std.mem.findPos(u8, data_str, search_pos, "\"url\":")) |_| {
            image_count += 1;
            search_pos += 1;
        }
        search_pos = 0;
        while (std.mem.findPos(u8, data_str, search_pos, "\"b64_json\":")) |_| {
            image_count += 1;
            search_pos += 1;
        }

        if (image_count == 0) return error.ParseError;

        var images = try self.allocator.alloc(Image, image_count);
        errdefer self.allocator.free(images);

        var parsed: usize = 0;
        search_pos = 0;

        while (parsed < image_count) {
            // Find next image object
            const obj_start = std.mem.findPos(u8, data_str, search_pos, "{") orelse break;
            var depth: u32 = 1;
            var i = obj_start + 1;
            while (i < data_str.len and depth > 0) {
                if (data_str[i] == '{') depth += 1;
                if (data_str[i] == '}') depth -= 1;
                i += 1;
            }
            const obj_str = data_str[obj_start..i];

            // Parse url
            const url = parseJsonField(obj_str, "url");
            // Parse b64_json
            const b64_json = parseJsonField(obj_str, "b64_json");
            // Parse revised_prompt
            const revised_prompt = parseJsonField(obj_str, "revised_prompt");

            images[parsed] = Image{
                .url = if (url) |v| try self.allocator.dupe(u8, v) else null,
                .b64_json = if (b64_json) |v| try self.allocator.dupe(u8, v) else null,
                .revised_prompt = if (revised_prompt) |v| try self.allocator.dupe(u8, v) else null,
            };

            parsed += 1;
            search_pos = i;
        }

        return ImagesResponse{
            .created = created,
            .data = images,
        };
    }

    fn parseJsonField(json_str: []const u8, field_name: []const u8) ?[]const u8 {
        const search_pattern_len = field_name.len + 3;
        if (search_pattern_len >= 128) return null;

        var buf: [128]u8 = undefined;
        @memcpy(buf[0..field_name.len], field_name);
        buf[field_name.len] = '"';
        buf[field_name.len + 1] = ':';
        buf[field_name.len + 2] = ' ';

        const start_idx = std.mem.find(u8, json_str, buf[0..search_pattern_len]) orelse return null;
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
                if (json_str[i] == '\\') i += 1; // Skip escaped char
                i += 1;
            }
            return json_str[str_start..i];
        } else if (json_str[i] == '{') {
            var depth: u32 = 1;
            i += 1;
            while (i < json_str.len and depth > 0) {
                if (json_str[i] == '{') depth += 1;
                if (json_str[i] == '}') depth -= 1;
                i += 1;
            }
            return json_str[value_start..i];
        } else if (json_str[i] == '[') {
            var depth: u32 = 1;
            i += 1;
            while (i < json_str.len and depth > 0) {
                if (json_str[i] == '[') depth += 1;
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
// Image Model
// ============================================================================

pub const ImageModel = enum {
    dall_e_2,
    dall_e_3,
    dall_e_3_hd,

    pub fn toString(self: ImageModel) []const u8 {
        return switch (self) {
            .dall_e_2 => "dall-e-2",
            .dall_e_3 => "dall-e-3",
            .dall_e_3_hd => "dall-e-3-hd",
        };
    }
};

// ============================================================================
// Image Response Format
// ============================================================================

pub const ImageResponseFormat = enum {
    url,
    b64_json,

    pub fn toString(self: ImageResponseFormat) []const u8 {
        return switch (self) {
            .url => "url",
            .b64_json => "b64_json",
        };
    }
};

// ============================================================================
// Image Size
// ============================================================================

pub const ImageSize = enum {
    s256x256,
    s512x512,
    s1024x1024,

    pub fn toString(self: ImageSize) []const u8 {
        return switch (self) {
            .s256x256 => "256x256",
            .s512x512 => "512x512",
            .s1024x1024 => "1024x1024",
        };
    }
};

// ============================================================================
// Image Style
// ============================================================================

pub const ImageStyle = enum {
    vivid,
    natural,

    pub fn toString(self: ImageStyle) []const u8 {
        return switch (self) {
            .vivid => "vivid",
            .natural => "natural",
        };
    }
};

// ============================================================================
// Image Quality
// ============================================================================

pub const ImageQuality = enum {
    standard,
    hd,

    pub fn toString(self: ImageQuality) []const u8 {
        return switch (self) {
            .standard => "standard",
            .hd => "hd",
        };
    }
};

// ============================================================================
// Image Object
// ============================================================================

pub const Image = struct {
    url: ?[]const u8 = null,
    b64_json: ?[]const u8 = null,
    revised_prompt: ?[]const u8 = null,
};

// ============================================================================
// Images Response
// ============================================================================

pub const ImagesResponse = struct {
    created: u64,
    data: []Image,
};

// ============================================================================
// Image Edit Request Params
// ============================================================================

pub const ImageEditParams = struct {
    image: []const u8,
    prompt: []const u8,
    mask: ?[]const u8 = null,
    model: ?[]const u8 = null,
    n: ?u32 = 1,
    size: ?ImageSize = null,
    response_format: ?ImageResponseFormat = null,
    user: ?[]const u8 = null,
};

// ============================================================================
// Image Variation Request Params
// ============================================================================

pub const ImageVariationParams = struct {
    image: []const u8,
    model: ?[]const u8 = null,
    n: ?u32 = 1,
    response_format: ?ImageResponseFormat = null,
    size: ?ImageSize = null,
    user: ?[]const u8 = null,
};

// ============================================================================
// Image Generate Request Params
// ============================================================================

pub const ImageGenerateParams = struct {
    prompt: []const u8,
    model: ?[]const u8 = null,
    quality: ?ImageQuality = null,
    response_format: ?ImageResponseFormat = null,
    size: ?ImageSize = null,
    style: ?ImageStyle = null,
    user: ?[]const u8 = null,
};
