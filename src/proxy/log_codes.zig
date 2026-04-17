//! Log Codes for llmlite Proxy
//!
//! Format: [Module-Number] Message
//! - CB: Circuit Breaker
//! - SRV: Server
//! - FWD: Forwarder
//! - FO: Failover
//! - RECT: Rectifier
//! - RSP: Response
//! - USG: Usage

const std = @import("std");

/// Circuit Breaker log codes
pub const cb = struct {
    /// CB-001: Circuit breaker opened to half-open
    pub const OPEN_TO_HALF_OPEN: []const u8 = "CB-001";
    /// CB-002: Circuit breaker half-open to closed
    pub const HALF_OPEN_TO_CLOSED: []const u8 = "CB-002";
    /// CB-003: Half-open probe failed
    pub const HALF_OPEN_PROBE_FAILED: []const u8 = "CB-003";
    /// CB-004: Triggered by failures
    pub const TRIGGERED_FAILURES: []const u8 = "CB-004";
    /// CB-005: Triggered by error rate
    pub const TRIGGERED_ERROR_RATE: []const u8 = "CB-005";
    /// CB-006: Manual reset
    pub const MANUAL_RESET: []const u8 = "CB-006";
};

/// Server log codes
pub const srv = struct {
    /// SRV-001: Server started
    pub const STARTED: []const u8 = "SRV-001";
    /// SRV-002: Server stopped
    pub const STOPPED: []const u8 = "SRV-002";
    /// SRV-003: Stop timeout
    pub const STOP_TIMEOUT: []const u8 = "SRV-003";
    /// SRV-004: Task error
    pub const TASK_ERROR: []const u8 = "SRV-004";
    /// SRV-005: Accept error
    pub const ACCEPT_ERR: []const u8 = "SRV-005";
    /// SRV-006: Connection error
    pub const CONN_ERR: []const u8 = "SRV-006";
};

/// Forwarder log codes
pub const fwd = struct {
    /// FWD-001: Provider failed, retrying
    pub const PROVIDER_FAILED_RETRY: []const u8 = "FWD-001";
    /// FWD-002: All providers failed
    pub const ALL_PROVIDERS_FAILED: []const u8 = "FWD-002";
    /// FWD-003: Single provider failed
    pub const SINGLE_PROVIDER_FAILED: []const u8 = "FWD-003";
};

/// Failover log codes
pub const fo = struct {
    /// FO-001: Switch success
    pub const SWITCH_SUCCESS: []const u8 = "FO-001";
    /// FO-002: Config read error
    pub const CONFIG_READ_ERROR: []const u8 = "FO-002";
    /// FO-003: Live backup error
    pub const LIVE_BACKUP_ERROR: []const u8 = "FO-003";
    /// FO-004: All circuits open
    pub const ALL_CIRCUIT_OPEN: []const u8 = "FO-004";
    /// FO-005: No providers
    pub const NO_PROVIDERS: []const u8 = "FO-005";
};

/// Rectifier log codes
pub const rect = struct {
    /// RECT-001: Signature rectifier triggered
    pub const SIGNATURE_TRIGGERED: []const u8 = "RECT-001";
    /// RECT-002: Budget rectifier triggered
    pub const BUDGET_TRIGGERED: []const u8 = "RECT-002";
    /// RECT-003: Rectification succeeded
    pub const RECTIFY_OK: []const u8 = "RECT-003";
    /// RECT-004: Rectification failed
    pub const RECTIFY_FAIL: []const u8 = "RECT-004";
    /// RECT-005: Rectifier already triggered, skip retry
    pub const ALREADY_TRIGGERED: []const u8 = "RECT-005";
    /// RECT-006: Signature rectifier triggered but no rectifiable content
    pub const NO_RECTIFIABLE_CONTENT: []const u8 = "RECT-006";
};

/// Response log codes
pub const rsp = struct {
    /// RSP-001: Build stream error
    pub const BUILD_STREAM_ERROR: []const u8 = "RSP-001";
    /// RSP-002: Read body error
    pub const READ_BODY_ERROR: []const u8 = "RSP-002";
    /// RSP-003: Build response error
    pub const BUILD_RESPONSE_ERROR: []const u8 = "RSP-003";
    /// RSP-004: Stream timeout
    pub const STREAM_TIMEOUT: []const u8 = "RSP-004";
    /// RSP-005: Stream error
    pub const STREAM_ERROR: []const u8 = "RSP-005";
};

/// Usage log codes
pub const usg = struct {
    /// USG-001: Log failed
    pub const LOG_FAILED: []const u8 = "USG-001";
    /// USG-002: Pricing not found
    pub const PRICING_NOT_FOUND: []const u8 = "USG-002";
};

// ============================================================================
// TESTS
// ============================================================================

test "log_codes - circuit breaker codes" {
    try std.testing.expectEqualStrings("CB-001", cb.OPEN_TO_HALF_OPEN);
    try std.testing.expectEqualStrings("CB-002", cb.HALF_OPEN_TO_CLOSED);
    try std.testing.expectEqualStrings("CB-006", cb.MANUAL_RESET);
}

test "log_codes - server codes" {
    try std.testing.expectEqualStrings("SRV-001", srv.STARTED);
    try std.testing.expectEqualStrings("SRV-002", srv.STOPPED);
}

test "log_codes - forwarder codes" {
    try std.testing.expectEqualStrings("FWD-001", fwd.PROVIDER_FAILED_RETRY);
    try std.testing.expectEqualStrings("FWD-002", fwd.ALL_PROVIDERS_FAILED);
}

test "log_codes - failover codes" {
    try std.testing.expectEqualStrings("FO-001", fo.SWITCH_SUCCESS);
    try std.testing.expectEqualStrings("FO-005", fo.NO_PROVIDERS);
}

test "log_codes - response codes" {
    try std.testing.expectEqualStrings("RSP-001", rsp.BUILD_STREAM_ERROR);
    try std.testing.expectEqualStrings("RSP-005", rsp.STREAM_ERROR);
}

test "log_codes - rectifier codes" {
    try std.testing.expectEqualStrings("RECT-001", rect.SIGNATURE_TRIGGERED);
    try std.testing.expectEqualStrings("RECT-002", rect.BUDGET_TRIGGERED);
    try std.testing.expectEqualStrings("RECT-003", rect.RECTIFY_OK);
    try std.testing.expectEqualStrings("RECT-004", rect.RECTIFY_FAIL);
    try std.testing.expectEqualStrings("RECT-005", rect.ALREADY_TRIGGERED);
    try std.testing.expectEqualStrings("RECT-006", rect.NO_RECTIFIABLE_CONTENT);
}

test "log_codes - usage codes" {
    try std.testing.expectEqualStrings("USG-001", usg.LOG_FAILED);
    try std.testing.expectEqualStrings("USG-002", usg.PRICING_NOT_FOUND);
}
