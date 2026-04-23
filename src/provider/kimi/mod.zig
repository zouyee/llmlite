//! Kimi Provider Module
//!
//! Provides access to Kimi-specific APIs via Moonshot platform
//! Kimi API is OpenAI-compatible, so it uses the OpenAI transformation/parsing
//!
//! Supported models:
//! - kimi-k2.5 (multimodal, supports vision)
//! - kimi-k2-turbo-preview
//! - kimi-k2-thinking
//! - moonshot-v1-8k/32k/128k
//! - moonshot-v1-8k/32k/128k-vision-preview
//!
//! Kimi-specific APIs:
//! - Token Estimation: POST /v1/tokenizers/estimate-token-count
//! - Balance: GET /v1/users/me/balance
//!
//! API Docs: https://platform.moonshot.cn/docs/api/chat

const std = @import("std");
const http_mod = @import("http");
pub const chat = @import("chat");
pub const types = @import("types");

// ============================================================================
// Kimi HTTP Client - For direct API calls
// ============================================================================

pub const KimiClient = struct {
    allocator: std.mem.Allocator,
    http_client: *http_mod.HttpClient,

    pub fn init(allocator: std.mem.Allocator, http_client: *http_mod.HttpClient) KimiClient {
        return .{
            .allocator = allocator,
            .http_client = http_client,
        };
    }

    // =========================================================================
    // Token Estimation API
    // =========================================================================

    /// Estimate token count for a message sequence
    /// POST /v1/tokenizers/estimate-token-count
    pub fn estimateTokenCount(self: *KimiClient, params: EstimateTokenParams) !EstimateTokenResponse {
        const json_str = try self.serializeEstimateParams(params);
        defer self.allocator.free(json_str);

        const response = try self.http_client.post("/tokenizers/estimate-token-count", json_str);
        defer self.allocator.free(response);

        return try self.parseEstimateResponse(response);
    }

    fn serializeEstimateParams(_: *KimiClient, params: EstimateTokenParams) ![]u8 {
        // Build messages array first
        var messages_json: std.ArrayListUnmanaged(u8) = .empty;
        errdefer messages_json.deinit(std.heap.c_allocator);

        try messages_json.appendSlice(std.heap.c_allocator, "[");
        for (params.messages, 0..) |msg, i| {
            if (i > 0) try messages_json.appendSlice(std.heap.c_allocator, ",");
            try messages_json.appendSlice(std.heap.c_allocator, try serializeMessageToJson(std.heap.c_allocator, msg));
        }
        try messages_json.appendSlice(std.heap.c_allocator, "]");

        const result = try std.fmt.allocPrint(std.heap.c_allocator,
            \\{{"model":"{s}","messages":{s}}}
        , .{
            params.model,
            try messages_json.toOwnedSlice(std.heap.c_allocator),
        });
        return result;
    }

    fn serializeMessageToJson(allocator: std.mem.Allocator, msg: chat.Message) ![]u8 {
        if (msg.content) |c| {
            return std.fmt.allocPrint(allocator, "{{\"role\":\"{s}\",\"content\":\"{s}\"}}", .{ msg.role.toString(), c });
        } else {
            return std.fmt.allocPrint(allocator, "{{\"role\":\"{s}\"}}", .{msg.role.toString()});
        }
    }

    fn parseEstimateResponse(_: *KimiClient, response: []const u8) !EstimateTokenResponse {
        // Check for error
        if (std.mem.find(u8, response, "\"error\":")) |_| {
            return error.ApiError;
        }

        const data_start = std.mem.find(u8, response, "\"data\":{") orelse return error.ParseError;
        const data_str = response[data_start + 7 .. response.len - 1];

        const total_start = std.mem.find(u8, data_str, "\"total_tokens\":") orelse return error.ParseError;
        const total_str = data_str[total_start + 14 ..];
        const total = std.fmt.parseInt(u32, total_str[0..findNumEnd(total_str)], 10) catch return error.ParseError;

        return EstimateTokenResponse{
            .total_tokens = total,
        };
    }

    // =========================================================================
    // Balance API
    // =========================================================================

    /// Get account balance
    /// GET /v1/users/me/balance
    pub fn getBalance(self: *KimiClient) !BalanceResponse {
        const response = try self.http_client.get("/users/me/balance");
        defer self.allocator.free(response);

        return try self.parseBalanceResponse(response);
    }

    fn parseBalanceResponse(_: *KimiClient, response: []const u8) !BalanceResponse {
        // Check for error
        if (std.mem.find(u8, response, "\"error\":")) |_| {
            return error.ApiError;
        }

        const data_start = std.mem.find(u8, response, "\"data\":{") orelse return error.ParseError;
        const data_str = response[data_start + 7 .. response.len - 1];

        const available_start = std.mem.find(u8, data_str, "\"available_balance\":") orelse return error.ParseError;
        const available_str = data_str[available_start + 19 ..];
        const available = std.fmt.parseFloat(f64, available_str[0..findFloatEnd(available_str)]) catch return error.ParseError;

        const voucher_start = std.mem.find(u8, data_str, "\"voucher_balance\":") orelse return error.ParseError;
        const voucher_str = data_str[voucher_start + 17 ..];
        const voucher = std.fmt.parseFloat(f64, voucher_str[0..findFloatEnd(voucher_str)]) catch return error.ParseError;

        const cash_start = std.mem.find(u8, data_str, "\"cash_balance\":") orelse return error.ParseError;
        const cash_str = data_str[cash_start + 15 ..];
        const cash = std.fmt.parseFloat(f64, cash_str[0..findFloatEnd(cash_str)]) catch return error.ParseError;

        return BalanceResponse{
            .available_balance = available,
            .voucher_balance = voucher,
            .cash_balance = cash,
        };
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

fn findNumEnd(s: []const u8) usize {
    var i: usize = 0;
    while (i < s.len and (std.ascii.isDigit(s[i]) or s[i] == '.' or s[i] == 'e' or s[i] == 'E' or s[i] == '+' or s[i] == '-')) {
        i += 1;
    }
    return i;
}

fn findFloatEnd(s: []const u8) usize {
    var i: usize = 0;
    while (i < s.len and (std.ascii.isDigit(s[i]) or s[i] == '.' or s[i] == '-')) {
        i += 1;
    }
    return i;
}

// ============================================================================
// Types
// ============================================================================

/// Token estimation parameters
pub const EstimateTokenParams = struct {
    messages: []const chat.Message,
    model: []const u8,
};

/// Token estimation response
pub const EstimateTokenResponse = struct {
    total_tokens: u32,
};

/// Balance response
pub const BalanceResponse = struct {
    available_balance: f64,
    voucher_balance: f64,
    cash_balance: f64,
};

/// Kimi-specific chat completion parameters
pub const KimiChatParams = struct {
    messages: []const chat.Message,
    model: []const u8,
    temperature: ?f32 = null,
    max_completion_tokens: ?u32 = null,
    top_p: ?f32 = null,
    n: ?u32 = null,
    presence_penalty: ?f32 = null,
    frequency_penalty: ?f32 = null,
    stop: ?[]const u8 = null,
    stream: bool = false,
    thinking: ?KimiThinking = null,
};

pub const KimiThinking = struct {
    type: []const u8, // "enabled" or "disabled"
};

/// Kimi API error types
pub const KimiError = struct {
    type: []const u8,
    message: []const u8,
};

/// Parse Kimi error response
pub fn parseKimiError(response: []const u8) !KimiError {
    const err_start = std.mem.find(u8, response, "\"error\":{") orelse return error.ParseError;
    const obj_start_idx = err_start + 8;
    const obj_str = response[obj_start_idx..];

    const msg_key = "\"message\":\"";
    const msg_start = std.mem.find(u8, obj_str, msg_key) orelse return error.ParseError;
    const msg_value_start = msg_start + msg_key.len;
    const msg_end = std.mem.findPos(u8, obj_str, msg_value_start, "\"") orelse return error.ParseError;
    const message = obj_str[msg_value_start..msg_end];

    const type_key = "\"type\":\"";
    const type_start = std.mem.find(u8, obj_str, type_key) orelse return error.ParseError;
    const type_value_start = type_start + type_key.len;
    const type_end = std.mem.findPos(u8, obj_str, type_value_start, "\"") orelse return error.ParseError;
    const error_type = obj_str[type_value_start..type_end];

    return KimiError{
        .type = error_type,
        .message = message,
    };
}
