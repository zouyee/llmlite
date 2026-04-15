//! Error Mapper for llmlite Proxy
//!
//! Maps ProxyError to HTTP status codes and user-friendly error messages.

const std = @import("std");

/// Proxy error types
pub const ProxyError = error {
    /// Upstream provider returned an error
    UpstreamError,
    /// Request timeout
    Timeout,
    /// Forward/fallback failed
    ForwardFailed,
    /// No provider available
    NoAvailableProvider,
    /// All providers circuit open
    AllProvidersCircuitOpen,
    /// No providers configured
    NoProvidersConfigured,
    /// Max retries exceeded
    MaxRetriesExceeded,
    /// Provider unhealthy
    ProviderUnhealthy,
    /// Database error
    DatabaseError,
    /// Transform error
    TransformError,
    /// Unknown error
    Unknown,
};

/// Map ProxyError to HTTP status code
///
/// Mapping rules:
/// - Timeout: 504 Gateway Timeout
/// - Connection failed: 502 Bad Gateway
/// - No available provider: 503 Service Unavailable
/// - Retry exhausted: 503 Service Unavailable
/// - Other errors: 500 Internal Server Error
pub fn mapProxyErrorToStatus(error: ProxyError) u16 {
    switch (error) {
        .Timeout => 504,
        .ForwardFailed => 502,
        .NoAvailableProvider => 503,
        .AllProvidersCircuitOpen => 503,
        .NoProvidersConfigured => 503,
        .MaxRetriesExceeded => 503,
        .ProviderUnhealthy => 503,
        .DatabaseError => 500,
        .TransformError => 500,
        .UpstreamError => 500,
        .Unknown => 500,
    }
}

/// Get user-friendly error message
pub fn getErrorMessage(error: ProxyError) []const u8 {
    switch (error) {
        .Timeout => "Request timeout",
        .ForwardFailed => "Forward failed",
        .NoAvailableProvider => "No available provider",
        .AllProvidersCircuitOpen => "All providers circuit open",
        .NoProvidersConfigured => "No providers configured",
        .MaxRetriesExceeded => "Max retries exceeded",
        .ProviderUnhealthy => "Provider unhealthy",
        .DatabaseError => "Database error",
        .TransformError => "Transform error",
        .UpstreamError => "Upstream error",
        .Unknown => "Unknown error",
    }
}

// ============================================================================
// TESTS
// ============================================================================

test "error_mapper - timeout returns 504" {
    const error = ProxyError.Timeout;
    try std.testing.expectEqual(@as(u16, 504), mapProxyErrorToStatus(error));
}

test "error_mapper - forward failed returns 502" {
    const error = ProxyError.ForwardFailed;
    try std.testing.expectEqual(@as(u16, 502), mapProxyErrorToStatus(error));
}

test "error_mapper - no available provider returns 503" {
    const error = ProxyError.NoAvailableProvider;
    try std.testing.expectEqual(@as(u16, 503), mapProxyErrorToStatus(error));
}

test "error_mapper - database error returns 500" {
    const error = ProxyError.DatabaseError;
    try std.testing.expectEqual(@as(u16, 500), mapProxyErrorToStatus(error));
}

test "error_mapper - upstream error returns 500" {
    const error = ProxyError.UpstreamError;
    try std.testing.expectEqual(@as(u16, 500), mapProxyErrorToStatus(error));
}

test "error_mapper - get error message for timeout" {
    const error = ProxyError.Timeout;
    try std.testing.expectEqualStrings("Request timeout", getErrorMessage(error));
}

test "error_mapper - get error message for no available provider" {
    const error = ProxyError.NoAvailableProvider;
    try std.testing.expectEqualStrings("No available provider", getErrorMessage(error));
}

test "error_mapper - get error message for upstream error" {
    const error = ProxyError.UpstreamError;
    try std.testing.expectEqualStrings("Upstream error", getErrorMessage(error));
}
