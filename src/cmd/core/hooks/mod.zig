//! Hook System - Module Exports
//!
//! Central module that exports all hook system components.

pub const permissions = @import("permissions.zig");
pub const integrity = @import("integrity.zig");
pub const hook_check = @import("hook_check.zig");
pub const hook_cmd = @import("hook_cmd.zig");
pub const trust = @import("trust.zig");

// Re-export commonly used types
pub const HookStatus = hook_check.HookStatus;
pub const HookFormat = hook_cmd.HookFormat;
pub const TrustStatus = trust.TrustStatus;
pub const TrustEntry = trust.TrustEntry;
pub const IntegrityStatus = integrity.IntegrityStatus;
pub const PermissionVerdict = permissions.PermissionVerdict;
