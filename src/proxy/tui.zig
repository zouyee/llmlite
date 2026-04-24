//! TUI (Terminal User Interface) for llmlite-proxy
//!
//! Redesigned architecture inspired by:
//! - cc-switch: Enum-driven view routing, centralized state, contextual shortcuts
//! - llmfit-tui: Event loop (poll+read), InputMode state machine, strict
//!   separation of AppState / Renderer / EventHandler
//!
//! File layout:
//!   tui.zig       - Public API, terminal setup, SIGWINCH
//!   tui/app.zig   - AppState, View, InputMode
//!   tui/input.zig - KeyEvent parser (escape sequences)
//!   tui/event.zig - Event loop & handler (sole state mutator)
//!   tui/render.zig- Stateless renderer

const std = @import("std");
const builtin = @import("builtin");

// Re-export public types
pub const app = @import("tui/app.zig");
pub const input = @import("tui/input.zig");
pub const event = @import("tui/event.zig");
const render_mod = @import("tui/render.zig");
pub const render = render_mod;

pub const AppState = app.AppState;
pub const View = app.View;
pub const InputMode = app.InputMode;
pub const KeyEvent = input.KeyEvent;
pub const Ansi = render.Ansi;

// Re-export resize handlers from event module
pub const handleSigwinch = event.handleSigwinch;
pub const checkResize = event.checkResize;

// ============================================================================
// Backwards-compatible Tui struct (wraps new AppState)
// ============================================================================

/// Wrapper struct that maintains the old Tui API for proxy_main.zig
pub const Tui = struct {
    state: AppState,
    termios_backup: ?if (builtin.os.tag == .windows) u8 else std.posix.termios = null,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) Tui {
        return .{
            .state = AppState.init(allocator, io),
        };
    }

    pub fn deinit(self: *Tui, tty: anytype) void {
        self.disableRawMode(tty);
        self.state.deinit(tty);
    }

    /// Enable raw mode for terminal input
    pub fn enableRawMode(self: *Tui, tty: anytype) !void {
        if (builtin.os.tag == .windows) {
            try tty.writeAll(Ansi.hide_cursor);
            try tty.writeAll(Ansi.clear_screen);
            try tty.writeAll(Ansi.home);
            return;
        }

        if (std.c.isatty(std.posix.STDIN_FILENO) == 0) {
            try tty.writeAll(Ansi.hide_cursor);
            try tty.writeAll(Ansi.clear_screen);
            try tty.writeAll(Ansi.home);
            return;
        }

        const original = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch {
            try tty.writeAll(Ansi.hide_cursor);
            try tty.writeAll(Ansi.clear_screen);
            try tty.writeAll(Ansi.home);
            return;
        };

        self.termios_backup = original;

        var raw = original;
        raw.lflag.ICANON = false;
        raw.lflag.ECHO = false;
        raw.lflag.ISIG = false;
        raw.iflag.ICRNL = false;
        raw.iflag.IXON = false;
        raw.cc[16] = 0; // VMIN
        raw.cc[17] = 0; // VTIME

        std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, raw) catch {};

        self.state.detectSize();

        try tty.writeAll(Ansi.hide_cursor);
        try tty.writeAll(Ansi.clear_screen);
        try tty.writeAll(Ansi.home);
    }

    /// Disable raw mode and restore original terminal settings
    pub fn disableRawMode(self: *Tui, tty: anytype) void {
        if (builtin.os.tag != .windows) {
            if (self.termios_backup) |original| {
                std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, original) catch {};
                self.termios_backup = null;
            }
        }
        tty.writeAll(Ansi.show_cursor) catch {};
    }

    pub fn showCursor(self: *Tui, tty: anytype) void {
        tty.writeAll(Ansi.show_cursor) catch {};
        _ = self;
    }

    pub fn detectSize(self: *Tui) void {
        self.state.detectSize();
    }

    pub fn markRefresh(self: *Tui) void {
        self.state.markRefresh();
    }

    pub fn render(self: *Tui, tty: anytype) !void {
        try render_mod.render(&self.state, tty);
    }

    pub fn handleInput(self: *Tui, input_bytes: []const u8) void {
        // Parse and handle all keys in the buffer
        var offset: usize = 0;
        while (offset < input_bytes.len) {
            const result = input.parseKey(input_bytes[offset..]);
            if (result.event) |evt| {
                event.handle(&self.state, evt) catch {};
                offset += result.consumed;
            } else {
                break;
            }
        }
    }

    pub fn isRunning(self: *Tui) bool {
        return self.state.isRunning();
    }

    pub fn stop(self: *Tui) void {
        self.state.stop();
    }

    // Data reference setters (for proxy_main.zig)
    pub fn setLatencyTracker(self: *Tui, lt: anytype) void {
        self.state.latency_tracker = lt;
    }

    pub fn setHealthChecker(self: *Tui, hc: anytype) void {
        self.state.health_checker = hc;
    }

    pub fn setCircuitBreaker(self: *Tui, cb: anytype) void {
        self.state.circuit_breaker = cb;
    }

    pub fn setMetrics(self: *Tui, m: anytype) void {
        self.state.metrics = m;
    }

    pub fn setServiceRunning(self: *Tui, running: bool) void {
        self.state.is_service_running = running;
    }

    // Backwards-compatible field access
    pub fn getSelectedIndex(self: *Tui) usize {
        return self.state.selected_index;
    }

    pub fn setSelectedIndex(self: *Tui, idx: usize) void {
        self.state.selected_index = idx;
    }
};

// ============================================================================
// New event-loop entry point (recommended for new code)
// ============================================================================

/// Run the TUI with the new event loop.
/// This replaces the old while+sleep loop in proxy_main.zig.
pub fn runEventLoop(state: *AppState, tty: anytype) !void {
    try event.run(state, tty);
}

