//! Proxy Middleware
//!
//! Authentication, rate limiting, and model access control middleware

const std = @import("std");
const virtual_key = @import("virtual_key");
const rate_limit = @import("proxy_rate_limit");

pub const VirtualKeyStore = virtual_key.VirtualKeyStore;
pub const VirtualKey = virtual_key.VirtualKey;
pub const RateLimiter = rate_limit.RateLimiter;

pub const ProxyError = error{
    MissingAuthHeader,
    InvalidAuthFormat,
    InvalidApiKey,
    RateLimitExceeded,
    ModelNotAllowed,
    ProviderNotAllowed,
    InternalError,
};

pub fn formatProxyError(err: ProxyError) struct { code: u16, message: []const u8 } {
    return switch (err) {
        .MissingAuthHeader => .{ .code = 401, .message = "Missing authorization header" },
        .InvalidAuthFormat => .{ .code = 401, .message = "Invalid authorization format" },
        .InvalidApiKey => .{ .code = 401, .message = "Invalid API key" },
        .RateLimitExceeded => .{ .code = 429, .message = "Rate limit exceeded" },
        .ModelNotAllowed => .{ .code = 403, .message = "Model not allowed for this key" },
        .ProviderNotAllowed => .{ .code = 403, .message = "Provider not allowed for this key" },
        .InternalError => .{ .code = 500, .message = "Internal server error" },
    };
}

/// Authenticate request using Bearer token
pub fn authMiddleware(request_text: []const u8, key_store: *VirtualKeyStore) !void {
    const auth_header_start = std.mem.find(u8, request_text, "Authorization: Bearer ");
    if (auth_header_start == null) {
        return ProxyError.MissingAuthHeader;
    }

    const auth_start = auth_header_start.? + 19;
    const auth_end = std.mem.find(u8, request_text[auth_start..], "\r\n");
    if (auth_end == null) {
        return ProxyError.InvalidAuthFormat;
    }

    const api_key = request_text[auth_start .. auth_start + auth_end.?];

    try key_store.validate(api_key);
}

/// Check rate limit for virtual key
pub fn rateLimitMiddleware(key_store: *VirtualKeyStore, rate_limiter: *RateLimiter, api_key: []const u8) !void {
    const vk = key_store.keys.get(api_key) orelse {
        return ProxyError.InvalidApiKey;
    };

    if (vk.rate_limit) |limit| {
        if (!try rate_limiter.check(api_key, limit)) {
            return ProxyError.RateLimitExceeded;
        }
    }
}

/// Check if model is allowed for virtual key
pub fn modelRestrictionMiddleware(vk: *const VirtualKey, model: []const u8) !void {
    if (vk.allowed_models) |allowed| {
        var found = false;
        for (allowed) |m| {
            if (std.mem.eql(u8, m, model)) {
                found = true;
                break;
            }
        }
        if (!found) {
            return ProxyError.ModelNotAllowed;
        }
    }
}

/// Check if provider is allowed for virtual key
pub fn providerRestrictionMiddleware(vk: *const VirtualKey, provider: anytype) !void {
    if (vk.allowed_providers) |allowed| {
        var found = false;
        for (allowed) |p| {
            if (p == provider) {
                found = true;
                break;
            }
        }
        if (!found) {
            return ProxyError.ProviderNotAllowed;
        }
    }
}
