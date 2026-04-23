//! Error Handler for llmlite Proxy
//!
//! Normalizes errors from all providers into a consistent format
//!
//! Error response format (inspired by DeepSeek API):
//! {{
//!     "error": {{
//!         "code": "{code}",
//!         "message": "{message}",
//!         "reason": "{reason}",
//!         "provider_code": "{provider_code}"
//!     }}
//! }}

const std = @import("std");

pub const ProxyErrorCode = enum {
    invalid_request,
    authentication_error,
    permission_denied,
    not_found,
    rate_limit_exceeded,
    internal_error,
    service_unavailable,
    model_not_found,
    provider_error,
};

pub const NormalizedError = struct {
    code: ProxyErrorCode,
    message: []const u8,
    reason: []const u8,
    provider_code: ?[]const u8 = null,
    status: u16,
};

/// Convert any error to a normalized proxy error
pub fn normalizeError(err: anyerror, provider_code: ?[]const u8) NormalizedError {
    return switch (err) {
        error.MissingAuthHeader => .{
            .code = .authentication_error,
            .message = "Missing authorization header",
            .reason = "The request is missing the Authorization header. Please include 'Authorization: Bearer <API_KEY>' in your request.",
            .provider_code = provider_code,
            .status = 401,
        },
        error.InvalidAuthFormat => .{
            .code = .authentication_error,
            .message = "Invalid authorization format",
            .reason = "The Authorization header format is invalid. Expected format: 'Bearer <API_KEY>'.",
            .provider_code = provider_code,
            .status = 401,
        },
        error.InvalidApiKey => .{
            .code = .authentication_error,
            .message = "Invalid API key",
            .reason = "The provided API key is invalid or has been revoked. Please check your API key and ensure it has not expired.",
            .provider_code = provider_code,
            .status = 401,
        },
        error.RateLimitExceeded => .{
            .code = .rate_limit_exceeded,
            .message = "Rate limit exceeded",
            .reason = "You are sending requests too quickly. Please pace your requests reasonably and implement exponential backoff for retries.",
            .provider_code = provider_code,
            .status = 429,
        },
        error.ModelNotAllowed => .{
            .code = .permission_denied,
            .message = "Model not allowed for this key",
            .reason = "Your API key does not have permission to access this model. Please check your key's allowed models list or upgrade your plan.",
            .provider_code = provider_code,
            .status = 403,
        },
        error.ProviderNotAllowed => .{
            .code = .permission_denied,
            .message = "Provider not allowed for this key",
            .reason = "Your API key does not have permission to access this provider. Please check your key's allowed providers list.",
            .provider_code = provider_code,
            .status = 403,
        },
        error.ModelNotFound => .{
            .code = .model_not_found,
            .message = "Model not found",
            .reason = "The specified model does not exist or is not available. Please check the model name and try again.",
            .provider_code = provider_code,
            .status = 404,
        },
        error.InvalidJson,
        error.InvalidRequest,
        => .{
            .code = .invalid_request,
            .message = "Invalid request",
            .reason = "The request body format is invalid. Please modify your request body according to the API documentation.",
            .provider_code = provider_code,
            .status = 400,
        },
        error.ConnectionRefused,
        error.ConnectionReset,
        error.NetworkUnreachable,
        error.HostUnreachable,
        error.ConnectionTimedOut,
        error.TemporaryServerBusy,
        => .{
            .code = .service_unavailable,
            .message = "Provider service unavailable",
            .reason = "The provider's server is temporarily unavailable. Please retry your request after a brief wait.",
            .provider_code = provider_code,
            .status = 503,
        },
        error.ApiError => .{
            .code = .provider_error,
            .message = "Provider returned an error",
            .reason = "The upstream provider returned an error. Please check the provider_code for more details and retry if needed.",
            .provider_code = provider_code,
            .status = 502,
        },
        else => .{
            .code = .internal_error,
            .message = "Internal server error",
            .reason = "An unexpected error occurred on our server. Please contact support if the issue persists.",
            .provider_code = provider_code,
            .status = 500,
        },
    };
}

/// Format error as JSON response body (DeepSeek-compatible format)
pub fn formatErrorJson(err: NormalizedError, allocator: std.mem.Allocator) ![]u8 {
    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);

    // Start: {"error":{"code":STATUS,
    try result.appendSlice(allocator, "{\"error\":{\"code\":");
    try result.print(allocator, "{d}", .{err.status});
    try result.appendSlice(allocator, ",\"message\":\"");
    try result.appendSlice(allocator, err.message);
    try result.appendSlice(allocator, "\",\"reason\":\"");
    try result.appendSlice(allocator, err.reason);
    try result.appendSlice(allocator, "\"");

    // Add provider_code if present
    if (err.provider_code) |pc| {
        try result.appendSlice(allocator, ",\"provider_code\":\"");
        try result.appendSlice(allocator, pc);
        try result.appendSlice(allocator, "\"");
    }

    // End: }}
    try result.appendSlice(allocator, "}}");

    return result.toOwnedSlice(allocator);
}

/// Get HTTP status text for error
pub fn getStatusText(status: u16) []const u8 {
    return switch (status) {
        400 => "Bad Request",
        401 => "Unauthorized",
        402 => "Payment Required",
        403 => "Forbidden",
        404 => "Not Found",
        422 => "Unprocessable Entity",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        502 => "Bad Gateway",
        503 => "Service Unavailable",
        else => "Unknown Error",
    };
}
