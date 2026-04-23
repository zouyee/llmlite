//! Azure OpenAI API Support
//!
//! Reference: https://learn.microsoft.com/en-us/azure/ai-services/openai/
//!
//! Azure OpenAI has a different endpoint structure:
//! - Uses deployment-based URLs
//! - Requires API version query parameter
//! - Uses Azure AD authentication

const std = @import("std");
const http = @import("http");

// ============================================================================
// Azure Client
// ============================================================================

pub const AzureClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    api_version: []const u8,
    auth_type: AzureAuthType,
    api_key: ?[]const u8 = null,
    azure_ad_token: ?[]const u8 = null,

    pub const AzureAuthType = enum {
        api_key,
        azure_ad_token,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        resource: []const u8,
        deployment: []const u8,
        api_version: []const u8,
        auth_type: AzureAuthType,
        credentials: []const u8,
    ) !AzureClient {
        // Build base URL: https://{resource}.openai.azure.com/openai/deployments/{deployment}
        const base_url = try std.fmt.allocPrint(allocator, "https://{s}.openai.azure.com/openai/deployments/{s}", .{ resource, deployment });

        return AzureClient{
            .allocator = allocator,
            .base_url = base_url,
            .api_version = api_version,
            .auth_type = auth_type,
            .api_key = if (auth_type == .api_key) try allocator.dupe(u8, credentials) else null,
            .azure_ad_token = if (auth_type == .azure_ad_token) try allocator.dupe(u8, credentials) else null,
        };
    }

    pub fn deinit(self: *AzureClient) void {
        self.allocator.free(self.base_url);
        if (self.api_key) |k| self.allocator.free(k);
        if (self.azure_ad_token) |t| self.allocator.free(t);
    }

    /// Build full URL with API version
    pub fn buildUrl(self: *const AzureClient, path: []const u8) ![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}{s}?api-version={s}", .{
            self.base_url, path, self.api_version,
        });
    }

    /// Get authorization header value
    pub fn getAuthHeader(self: *const AzureClient) []const u8 {
        return switch (self.auth_type) {
            .api_key => if (self.api_key) |k| k else "",
            .azure_ad_token => if (self.azure_ad_token) |t| t else "",
        };
    }
};

// ============================================================================
// Azure Service Wrapper
// ============================================================================

pub const AzureService = struct {
    allocator: std.mem.Allocator,
    azure_client: AzureClient,

    pub fn init(
        allocator: std.mem.Allocator,
        resource: []const u8,
        deployment: []const u8,
        api_version: []const u8,
        auth_type: AzureClient.AzureAuthType,
        credentials: []const u8,
    ) !AzureService {
        return .{
            .allocator = allocator,
            .azure_client = try AzureClient.init(allocator, resource, deployment, api_version, auth_type, credentials),
        };
    }

    pub fn deinit(self: *AzureService) void {
        self.azure_client.deinit();
    }

    // ============================================================================
    // Chat Completions
    // ============================================================================

    /// Creates a chat completion using Azure OpenAI
    pub fn createChatCompletion(self: *AzureService, params: AzureChatCompletionParams) !AzureChatCompletionResponse {
        const url = try self.azure_client.buildUrl("/chat/completions");
        defer self.allocator.free(url);

        const json_str = try self.serializeChatParams(params);
        defer self.allocator.free(json_str);

        const response = try self.httpPost(url, json_str);
        defer self.allocator.free(response);

        return try self.parseChatCompletion(response);
    }

    fn httpPost(self: *const AzureService, url: []const u8, body: []const u8) ![]u8 {
        // Build headers
        const auth_header = self.azure_client.getAuthHeader();
        const content_type = "Content-Type: application/json";

        var headers = std.array_list.Managed(u8).init(self.allocator);
        defer headers.deinit();

        try headers.appendSlice(content_type);
        try headers.append('\n');

        switch (self.azure_client.auth_type) {
            .api_key => {
                try headers.appendSlice("Authorization: ");
                try headers.appendSlice(auth_header);
                try headers.append('\n');
            },
            .azure_ad_token => {
                try headers.appendSlice("Authorization: Bearer ");
                try headers.appendSlice(auth_header);
                try headers.append('\n');
            },
        }

        // For now, we use the standard HTTP client
        // In a full implementation, this would use a custom HTTP client
        _ = url;
        _ = body;
        return error.NotImplemented;
    }

    // ============================================================================
    // Embeddings
    // ============================================================================

    /// Creates an embedding using Azure OpenAI
    pub fn createEmbedding(self: *AzureService, params: AzureEmbeddingParams) !AzureEmbeddingResponse {
        const url = try self.azure_client.buildUrl("/embeddings");
        defer self.allocator.free(url);

        const json_str = try self.serializeEmbeddingParams(params);
        defer self.allocator.free(json_str);

        const response = try self.httpPost(url, json_str);
        defer self.allocator.free(response);

        return try self.parseEmbedding(response);
    }

    // ============================================================================
    // Serialization
    // ============================================================================

    fn serializeChatParams(self: *AzureService, params: AzureChatCompletionParams) ![]u8 {
        _ = self;
        var parts = std.ArrayListUnmanaged(u8){};
        defer parts.deinit(self.allocator);

        try parts.appendSlice(self.allocator, "{\"messages\":[");
        for (params.messages, 0..) |msg, i| {
            if (i > 0) try parts.appendSlice(self.allocator, ",");
            try parts.appendSlice(self.allocator, "{\"role\":\"");
            try parts.appendSlice(self.allocator, msg.role);
            try parts.appendSlice(self.allocator, "\",\"content\":\"");
            try parts.appendSlice(self.allocator, msg.content);
            try parts.appendSlice(self.allocator, "\"}");
        }
        try parts.appendSlice(self.allocator, "]}");

        return try parts.toOwnedSlice(self.allocator);
    }

    fn serializeEmbeddingParams(self: *AzureService, params: AzureEmbeddingParams) ![]u8 {
        _ = self;
        return std.fmt.allocPrint(self.allocator,
            \\{{"input":"{s}","model":"{s}"}}
        , .{ params.input, params.model });
    }

    // ============================================================================
    // Parsing
    // ============================================================================

    fn parseChatCompletion(self: *AzureService, response: []const u8) !AzureChatCompletionResponse {
        _ = self;
        // Simplified parsing - just extract key fields
        const id = parseJsonField(response, "id") orelse return error.ParseError;
        const content = parseJsonField(response, "content") orelse return error.ParseError;

        return AzureChatCompletionResponse{
            .id = id,
            .content = content,
        };
    }

    fn parseEmbedding(self: *AzureService, response: []const u8) !AzureEmbeddingResponse {
        _ = self;
        const embedding = parseJsonField(response, "embedding") orelse return error.ParseError;

        return AzureEmbeddingResponse{
            .embedding = embedding,
        };
    }
};

// ============================================================================
// Azure Request/Response Types
// ============================================================================

pub const AzureChatCompletionParams = struct {
    messages: []const AzureMessage,
    temperature: ?f32 = null,
    max_tokens: ?u32 = null,
};

pub const AzureMessage = struct {
    role: []const u8,
    content: []const u8,
};

pub const AzureChatCompletionResponse = struct {
    id: []const u8,
    content: []const u8,
};

pub const AzureEmbeddingParams = struct {
    input: []const u8,
    model: []const u8,
};

pub const AzureEmbeddingResponse = struct {
    embedding: []const u8,
};

// ============================================================================
// Azure Resource/Deployment Helpers
// ============================================================================

pub const AzureConfig = struct {
    resource: []const u8,
    deployment: []const u8,
    api_version: []const u8,
};

/// Common Azure API versions
pub const AzureApiVersion = struct {
    pub const v2024_06_01 = "2024-06-01";
    pub const v2024_05_01_preview = "2024-05-01-preview";
    pub const v2024_04_01_preview = "2024-04-01-preview";
    pub const v2024_02_01 = "2024-02-01";
    pub const v2023_12_01_preview = "2023-12-01-preview";
    pub const v2023_05_15 = "2023-05-15";
};

// ============================================================================
// JSON Field Parser (copied from other modules for independence)
// ============================================================================

fn parseJsonField(json_str: []const u8, field_name: []const u8) ?[]const u8 {
    const search_pattern_len = field_name.len + 3;
    var search_pattern_buf: [128]u8 = undefined;
    if (search_pattern_len >= search_pattern_buf.len) return null;

    var buf = search_pattern_buf[0..search_pattern_len];
    buf[0] = '"';
    @memcpy(buf[1..][0..field_name.len], field_name);
    buf[field_name.len + 1] = '"';
    buf[field_name.len + 2] = ':';

    const start_idx = std.mem.find(u8, json_str, buf) orelse return null;
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
