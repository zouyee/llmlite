//! AppState - Centralized application state for llmlite-proxy TUI
//!
//! Pattern from llmfit-tui: tui_app.rs holds all state and filtering logic.
//! Pattern from cc-switch: enum-driven view routing with centralized state.

const std = @import("std");
const provider_types = @import("types");
const latency_health = @import("latency_health");
const circuit_breaker = @import("circuit_breaker");
const logger = @import("proxy_logger");
const time_compat = @import("time_compat");

/// View enum - cc-switch pattern: enum-driven view routing
pub const View = enum {
    dashboard, // Main monitoring view (providers, metrics, details)
    logs, // Request log view
    help, // Keyboard shortcuts help

    pub fn toString(self: View) []const u8 {
        return switch (self) {
            .dashboard => "Dashboard",
            .logs => "Logs",
            .help => "Help",
        };
    }

    pub fn keyHint(self: View) []const u8 {
        return switch (self) {
            .dashboard => "[1]",
            .logs => "[2]",
            .help => "[?]",
        };
    }
};

/// InputMode state machine - llmfit-tui pattern
/// Only event handler mutates state; renderer is stateless.
pub const InputMode = enum {
    normal, // Navigation, view switching, actions
    confirm, // Confirmation dialog active (e.g., disable provider)

    pub fn toString(self: InputMode) []const u8 {
        return switch (self) {
            .normal => "NORMAL",
            .confirm => "CONFIRM",
        };
    }
};

/// Dialog type for overlay rendering
pub const Dialog = struct {
    title: []const u8,
    message: []const u8,
    confirm_label: []const u8 = "Yes",
    cancel_label: []const u8 = "No",
    on_confirm: *const fn (*AppState) void,
    on_cancel: *const fn (*AppState) void,
};

/// Centralized application state
pub const AppState = struct {
    // ── Core navigation ──
    current_view: View = .dashboard,
    input_mode: InputMode = .normal,
    running: bool = true,
    should_refresh: bool = true,

    // ── Terminal dimensions ──
    width: u16 = 80,
    height: u16 = 24,

    // ── Dashboard state ──
    selected_index: usize = 0,
    providers: []const provider_types.ProviderType = &.{
        .openai, .anthropic, .google, .deepseek, .moonshot, .minimax,
    },
    enabled_providers: [6]bool = .{ true, true, true, true, true, true },

    // ── Data references (immutable after init) ──
    io: std.Io,
    latency_tracker: ?*latency_health.LatencyTracker = null,
    health_checker: ?*latency_health.HealthChecker = null,
    circuit_breaker: ?*circuit_breaker.CircuitBreaker = null,
    metrics: ?*logger.MetricsCollector = null,

    // ── Service state ──
    is_service_running: bool = false,
    listen_address: []const u8 = "0.0.0.0",
    listen_port: u16 = 4000,
    logging_enabled: bool = true,

    // ── Time tracking ──
    start_time: i64 = 0,

    // ── Dialog overlay ──
    dialog: ?Dialog = null,

    // ── Callbacks ──
    refresh_callback: ?*const fn (?*anyopaque) void = null,
    refresh_context: ?*anyopaque = null,
    logger_toggle_callback: ?*const fn (?*anyopaque, bool) void = null,
    logger_toggle_context: ?*anyopaque = null,

    // ── Buffers ──
    uptime_buf: [32]u8 = undefined,
    address_buf: [32]u8 = undefined,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) AppState {
        _ = allocator;
        return .{
            .io = io,
            .start_time = time_compat.timestamp(io),
        };
    }

    pub fn deinit(self: *AppState, tty: anytype) void {
        _ = self;
        _ = tty;
        // Cleanup handled by caller (restore raw mode, etc.)
    }

    /// Mark for refresh on next frame
    pub fn markRefresh(self: *AppState) void {
        self.should_refresh = true;
    }

    /// Detect terminal size via ioctl
    pub fn detectSize(self: *AppState) void {
        const builtin = @import("builtin");
        if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
            var ws: std.posix.winsize = undefined;
            const rc = std.posix.system.ioctl(
                std.posix.STDOUT_FILENO,
                std.posix.T.IOCGWINSZ,
                @intFromPtr(&ws),
            );
            if (rc == 0 and ws.col > 0 and ws.row > 0) {
                self.width = ws.col;
                self.height = ws.row;
                self.should_refresh = true;
                return;
            }
        }
        self.width = 80;
        self.height = 24;
        self.should_refresh = true;
    }

    /// Format uptime string into internal buffer
    pub fn getUptime(self: *AppState) []const u8 {
        const elapsed = time_compat.timestamp(self.io) - self.start_time;
        const hours = @divTrunc(elapsed, 3600);
        const minutes = @divTrunc(@mod(elapsed, 3600), 60);

        if (hours > 0) {
            return std.fmt.bufPrint(&self.uptime_buf, "{}h {}m", .{ hours, minutes }) catch "-";
        } else if (minutes > 0) {
            return std.fmt.bufPrint(&self.uptime_buf, "{}m", .{minutes}) catch "-";
        } else {
            return std.fmt.bufPrint(&self.uptime_buf, "{}s", .{elapsed}) catch "-";
        }
    }

    /// Format service address string
    pub fn getAddress(self: *AppState) []const u8 {
        return std.fmt.bufPrint(&self.address_buf, "http://{s}:{d}", .{ self.listen_address, self.listen_port }) catch "-";
    }

    /// Navigate to a specific view
    pub fn switchView(self: *AppState, view: View) void {
        if (self.current_view != view) {
            self.current_view = view;
            self.should_refresh = true;
        }
    }

    /// Show confirmation dialog
    pub fn showConfirm(self: *AppState, dlg: Dialog) void {
        self.dialog = dlg;
        self.input_mode = .confirm;
        self.should_refresh = true;
    }

    /// Dismiss dialog
    pub fn dismissDialog(self: *AppState) void {
        self.dialog = null;
        self.input_mode = .normal;
        self.should_refresh = true;
    }

    pub fn isRunning(self: *const AppState) bool {
        return self.running;
    }

    pub fn stop(self: *AppState) void {
        self.running = false;
    }
};
