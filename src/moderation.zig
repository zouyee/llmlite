//! Moderations API

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

    /// Classifies if text violate OpenAI's content policy.
    pub fn createModeration(self: *Service, params: ModerationParams) !Moderation {
        const json_str = try self.serializeModerationParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/moderations", json_str);
        defer self.allocator.free(response);

        return try self.parseModerationResponse(response);
    }

    fn serializeModerationParams(self: *Service, params: ModerationParams) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8).empty;
        errdefer buf.deinit(self.allocator);

        try buf.append(self.allocator, '{');
        try buf.appendSlice(self.allocator, "\"input\":\"");
        try escapeJsonString(self.allocator, &buf, params.input);
        try buf.append(self.allocator, '"');

        if (params.model) |v| {
            try buf.appendSlice(self.allocator, ",\"model\":\"");
            try buf.appendSlice(self.allocator, v.toString());
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

    fn parseModerationResponse(self: *Service, response: []const u8) !Moderation {
        const id = parseJsonField(response, "id") orelse "unknown";
        const model = parseJsonField(response, "model") orelse "unknown";

        const results_str = parseJsonField(response, "results") orelse return error.ParseError;

        var results = try self.allocator.alloc(ModerationInputResult, 1);
        errdefer self.allocator.free(results);

        results[0] = try self.parseModerationInputResult(results_str);

        return Moderation{
            .id = try self.allocator.dupe(u8, id),
            .model = try self.allocator.dupe(u8, model),
            .results = results,
        };
    }

    fn parseModerationInputResult(self: *Service, json_str: []const u8) !ModerationInputResult {
        const flagged_str = parseJsonField(json_str, "flagged") orelse "false";
        const flagged = std.mem.eql(u8, flagged_str, "true");

        const categories_str = parseJsonField(json_str, "categories") orelse return error.ParseError;
        const categories = try self.parseModerationCategories(categories_str);

        const category_scores_str = parseJsonField(json_str, "category_scores") orelse return error.ParseError;
        const category_scores = try self.parseModerationCategoryScores(category_scores_str);

        return ModerationInputResult{
            .flagged = flagged,
            .categories = categories,
            .category_scores = category_scores,
        };
    }

    fn parseModerationCategories(self: *Service, json_str: []const u8) !ModerationCategories {
        return ModerationCategories{
            .hate = try self.parseModerationCategory(json_str, "hate"),
            .harassment = try self.parseModerationCategory(json_str, "harassment"),
            .violence = try self.parseModerationCategory(json_str, "violence"),
            .sexual = try self.parseModerationCategory(json_str, "sexual"),
            .self_harm = try self.parseModerationCategory(json_str, "self_harm"),
            .weapons = try self.parseModerationCategory(json_str, "weapons"),
            .copyright = try self.parseModerationCategory(json_str, "copyright"),
            .self_harm_intent = try self.parseModerationCategory(json_str, "self_harm_intent"),
            .self_harm_instructions = try self.parseModerationCategory(json_str, "self_harm_instructions"),
            .hate_threatening = try self.parseModerationCategory(json_str, "hate_threatening"),
            .violence_graphic = try self.parseModerationCategory(json_str, "violence_graphic"),
            .harassment_threatening = try self.parseModerationCategory(json_str, "harassment_threatening"),
        };
    }

    fn parseModerationCategory(_: *Service, json_str: []const u8, field: []const u8) !ModerationCategory {
        const field_str = parseJsonField(json_str, field) orelse return error.ParseError;
        const flagged_str = parseJsonField(field_str, "flagged") orelse "false";
        const flagged = std.mem.eql(u8, flagged_str, "true");

        const score_str = parseJsonField(field_str, "score") orelse "0";
        const score = std.fmt.parseFloat(f32, score_str) catch 0;

        return ModerationCategory{
            .flagged = flagged,
            .confidence = score,
        };
    }

    fn parseModerationCategoryScores(self: *Service, json_str: []const u8) !ModerationCategoryScores {
        return ModerationCategoryScores{
            .hate = try self.parseScore(json_str, "hate"),
            .harassment = try self.parseScore(json_str, "harassment"),
            .violence = try self.parseScore(json_str, "violence"),
            .sexual = try self.parseScore(json_str, "sexual"),
            .self_harm = try self.parseScore(json_str, "self_harm"),
            .weapons = try self.parseScore(json_str, "weapons"),
            .copyright = try self.parseScore(json_str, "copyright"),
            .self_harm_intent = try self.parseScore(json_str, "self_harm_intent"),
            .self_harm_instructions = try self.parseScore(json_str, "self_harm_instructions"),
            .hate_threatening = try self.parseScore(json_str, "hate_threatening"),
            .violence_graphic = try self.parseScore(json_str, "violence_graphic"),
            .harassment_threatening = try self.parseScore(json_str, "harassment_threatening"),
        };
    }

    fn parseScore(_: *Service, json_str: []const u8, field: []const u8) !f32 {
        const field_str = parseJsonField(json_str, field) orelse return error.ParseError;
        const score_str = parseJsonField(field_str, "score") orelse "0";
        return std.fmt.parseFloat(f32, score_str) catch 0;
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
                if (json_str[i] == '\\') i += 1;
                i += 1;
            }
            return json_str[str_start..i];
        } else if (json_str[i] == '{' or json_str[i] == '[') {
            var depth: u32 = 1;
            i += 1;
            while (i < json_str.len and depth > 0) {
                if (json_str[i] == '{' or json_str[i] == '[') depth += 1;
                if (json_str[i] == '}' or json_str[i] == ']') depth -= 1;
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
// Moderation Model
// ============================================================================

pub const ModerationModel = enum {
    text_moderation_latest,
    text_moderation_stable,

    pub fn toString(self: ModerationModel) []const u8 {
        return switch (self) {
            .text_moderation_latest => "text-moderation-latest",
            .text_moderation_stable => "text-moderation-stable",
        };
    }
};

// ============================================================================
// Moderation Category
// ============================================================================

pub const ModerationCategory = struct {
    flagged: bool,
    flagged_reason: ?[]const u8 = null,
    confidence: f32,
};

// ============================================================================
// Moderation Categories
// ============================================================================

pub const ModerationCategories = struct {
    hate: ModerationCategory,
    harassment: ModerationCategory,
    violence: ModerationCategory,
    sexual: ModerationCategory,
    self_harm: ModerationCategory,
    weapons: ModerationCategory,
    copyright: ModerationCategory,
    self_harm_intent: ModerationCategory,
    self_harm_instructions: ModerationCategory,
    hate_threatening: ModerationCategory,
    violence_graphic: ModerationCategory,
    harassment_threatening: ModerationCategory,
};

// ============================================================================
// Moderation Input Result
// ============================================================================

pub const ModerationInputResult = struct {
    flagged: bool,
    categories: ModerationCategories,
    category_scores: ModerationCategoryScores,
};

// ============================================================================
// Moderation Category Scores
// ============================================================================

pub const ModerationCategoryScores = struct {
    hate: f32,
    harassment: f32,
    violence: f32,
    sexual: f32,
    self_harm: f32,
    weapons: f32,
    copyright: f32,
    self_harm_intent: f32,
    self_harm_instructions: f32,
    hate_threatening: f32,
    violence_graphic: f32,
    harassment_threatening: f32,
};

// ============================================================================
// Moderation
// ============================================================================

pub const Moderation = struct {
    id: []const u8,
    model: []const u8,
    results: []ModerationInputResult,
};

// ============================================================================
// Moderation Request Params
// ============================================================================

pub const ModerationParams = struct {
    input: []const u8,
    model: ?ModerationModel = null,
};
