//! TUI (Terminal User Interface) for llmlite-proxy
//!
//! Pure ANSI-based TUI with no external dependencies.
//! Provides real-time dashboard for monitoring and managing the proxy.

const std = @import("std");
const provider_types = @import("types");
const latency_health = @import("latency_health");
const circuit_breaker = @import("circuit_breaker");
const logger = @import("proxy_logger");

// ANSI Escape Codes
const ESC = "\x1b[";
const CSI = "\x1b[";

pub const Ansi = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";
    pub const italic = "\x1b[3m";
    pub const underline = "\x1b[4m";

    // Colors
    pub const black = "\x1b[30m";
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const white = "\x1b[37m";

    // Bright colors
    pub const bright_black = "\x1b[90m";
    pub const bright_red = "\x1b[91m";
    pub const bright_green = "\x1b[92m";
    pub const bright_yellow = "\x1b[93m";
    pub const bright_blue = "\x1b[94m";
    pub const bright_magenta = "\x1b[95m";
    pub const bright_cyan = "\x1b[96m";
    pub const bright_white = "\x1b[97m";

    // Background colors
    pub const bg_black = "\x1b[40m";
    pub const bg_red = "\x1b[41m";
    pub const bg_green = "\x1b[42m";
    pub const bg_yellow = "\x1b[43m";
    pub const bg_blue = "\x1b[44m";
    pub const bg_magenta = "\x1b[45m";
    pub const bg_cyan = "\x1b[46m";
    pub const bg_white = "\x1b[47m";

    // Cursor control
    pub const hide_cursor = "\x1b[?25l";
    pub const show_cursor = "\x1b[?25h";
    pub const clear_screen = "\x1b[2J";
    pub const clear_eol = "\x1b[K";
    pub const home = "\x1b[H";

    // Box drawing (single line)
    pub const box_top_left = "┌";
    pub const box_top_right = "┐";
    pub const box_bottom_left = "└";
    pub const box_bottom_right = "┘";
    pub const box_horizontal = "─";
    pub const box_vertical = "│";
    pub const box_cross = "┼";
    pub const box_tee_up = "┴";
    pub const box_tee_down = "┬";
    pub const box_tee_right = "├";
    pub const box_tee_left = "┤";

    // Box drawing (double line)
    pub const dbox_top_left = "╔";
    pub const dbox_top_right = "╗";
    pub const dbox_bottom_left = "╚";
    pub const dbox_bottom_right = "╝";
    pub const dbox_horizontal = "═";
    pub const dbox_vertical = "║";

    // Status indicators
    pub const check = "✓";
    pub const cross = "✗";
    pub const bullet = "●";
    pub const circle = "○";
    pub const arrow_right = "→";
    pub const arrow_left = "←";
    pub const arrow_up = "↑";
    pub const arrow_down = "↓";
    pub const star = "★";
    pub const diamond = "◆";
    pub const dot = "•";
};

pub const Key = struct {
    pub const ctrl_c = "\x03";
    pub const ctrl_d = "\x04";
    pub const ctrl_q = "\x11";
    pub const ctrl_r = "\x12";
    pub const ctrl_l = "\x0c";
    pub const enter = "\r";
    pub const escape = "\x1b";
    pub const backspace = "\x7f";
    pub const arrow_up = "\x1b[A";
    pub const arrow_down = "\x1b[B";
    pub const arrow_right = "\x1b[C";
    pub const arrow_left = "\x1b[D";
    pub const home = "\x1b[H";
    pub const end = "\x1b[F";
    pub const page_up = "\x1b[5~";
    pub const page_down = "\x1b[6~";
    pub const insert = "\x1b[2~";
    pub const delete = "\x1b[3~";
    pub const tab = "\t";
};

pub const Tui = struct {
    allocator: std.mem.Allocator,
    width: u16 = 80,
    height: u16 = 24,
    selected_index: usize = 0,
    running: bool = true,
    should_refresh: bool = true,
    start_time: i64 = 0,
    termios_backup: ?std.posix.termios = null,

    // Data references (set externally)
    latency_tracker: ?*latency_health.LatencyTracker = null,
    health_checker: ?*latency_health.HealthChecker = null,
    circuit_breaker: ?*circuit_breaker.CircuitBreaker = null,
    metrics: ?*logger.MetricsCollector = null,

    // Service state (set externally)
    is_service_running: bool = false,
    listen_address: []const u8 = "0.0.0.0",
    listen_port: u16 = 4000,
    logging_enabled: bool = true,

    // Provider list
    providers: []const provider_types.ProviderType = &.{
        .openai,
        .anthropic,
        .google,
        .deepseek,
        .moonshot,
        .minimax,
    },

    // Enabled state for each provider (all enabled by default)
    enabled_providers: [6]bool = .{ true, true, true, true, true, true },

    // Buffer for uptime string
    uptime_buf: [32]u8 = undefined,

    // Buffer for address string
    address_buf: [32]u8 = undefined,

    // Callback for refresh action (set by caller)
    refresh_callback: ?*const fn (?*anyopaque) void = null,
    refresh_context: ?*anyopaque = null,

    // Callback for logging toggle (set by caller)
    logger_toggle_callback: ?*const fn (?*anyopaque, bool) void = null,
    logger_toggle_context: ?*anyopaque = null,

    pub fn init(allocator: std.mem.Allocator) Tui {
        return .{
            .allocator = allocator,
            .start_time = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *Tui) void {
        _ = self;
        // Note: showCursor requires a writer which we don't have in deinit
        // The caller should call disableRawMode before deinit
    }

    /// Enable raw mode for terminal input
    pub fn enableRawMode(self: *Tui, tty: anytype) !void {
        // Check if stdin is a TTY before trying to get terminal attributes
        if (!std.posix.isatty(std.posix.STDIN_FILENO)) {
            // Not a TTY (e.g., running in background) - skip raw mode setup
            tty.writeAll(Ansi.hide_cursor) catch {};
            tty.writeAll(Ansi.clear_screen) catch {};
            tty.writeAll(Ansi.home) catch {};
            return;
        }

        // Try to get terminal attributes
        const original = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch {
            // Failed to get attributes - skip raw mode setup
            tty.writeAll(Ansi.hide_cursor) catch {};
            tty.writeAll(Ansi.clear_screen) catch {};
            tty.writeAll(Ansi.home) catch {};
            return;
        };

        // Store original for restoration
        self.termios_backup = original;

        // Create raw mode settings
        var raw = original;
        raw.lflag.ICANON = false; // Disable canonical mode (no line buffering)
        raw.lflag.ECHO = false; // Disable echo
        raw.lflag.ISIG = false; // Disable INTR/QUIT/SUSP signals
        raw.iflag.ICRNL = false; // Disable CR-NL mapping on input
        raw.iflag.IXON = false; // Disable XON/XOFF flow control on output
        // VMIN=16, VTIME=17 on macOS - set to 0 for non-blocking read
        raw.cc[16] = 0; // VMIN
        raw.cc[17] = 0; // VTIME

        std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, raw) catch {};

        // Detect terminal size
        self.detectSize();

        // Hide cursor and clear screen
        tty.writeAll(Ansi.hide_cursor) catch {};
        tty.writeAll(Ansi.clear_screen) catch {};
        tty.writeAll(Ansi.home) catch {};
    }

    /// Disable raw mode and restore original terminal settings
    pub fn disableRawMode(self: *Tui, tty: anytype) void {
        if (self.termios_backup) |original| {
            std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, original) catch {};
            self.termios_backup = null;
        }
        self.showCursor(tty);
    }

    pub fn showCursor(self: *Tui, tty: anytype) void {
        tty.writeAll(Ansi.show_cursor) catch {};
        _ = self;
    }

    /// Set terminal size
    pub fn setSize(self: *Tui, width: u16, height: u16) void {
        self.width = width;
        self.height = height;
        self.should_refresh = true;
    }

    /// Detect and set terminal size - uses reasonable defaults
    /// TODO: implement proper SIGWINCH handling for dynamic resize
    pub fn detectSize(self: *Tui) void {
        // Default to 80x24 which is minimum for proper display
        self.width = 80;
        self.height = 24;
        self.should_refresh = true;
    }

    /// Truncate string to fit within max_width.
    /// Shows the END of the string (better for URLs where domain is informative).
    /// Returns a slice that, when ".." is prepended, fits in max_width.
    fn truncate(_: *Tui, text: []const u8, max_width: usize) []const u8 {
        if (text.len == 0) return text;
        if (max_width < 3) return text;
        if (text.len > max_width - 2) {
            // Keep the last (max_width - 2) characters - the ".." is added by caller
            const start_idx = text.len - (max_width - 2);
            return text[start_idx..text.len];
        }
        return text;
    }

    /// Write exactly n spaces (helper for padding)
    fn writeSpaces(_: *Tui, tty: anytype, count: usize) !void {
        var i: usize = 0;
        while (i < count) : (i += 1) {
            try tty.writeAll(" ");
        }
    }

    /// Write string with padding to fill exactly target_width
    fn writePadded(_: *Tui, tty: anytype, text: []const u8, target_width: usize) !void {
        try tty.writeAll(text);
        if (text.len < target_width) {
            var i: usize = 0;
            while (i < target_width - text.len) : (i += 1) {
                try tty.writeAll(" ");
            }
        }
    }

    /// Mark for refresh
    pub fn markRefresh(self: *Tui) void {
        self.should_refresh = true;
    }

    /// Clear the screen
    pub fn clear(self: *Tui, tty: anytype) !void {
        try tty.writeAll(Ansi.clear_screen);
        try tty.writeAll(Ansi.home);
        _ = self;
    }

    /// Render the full TUI
    pub fn render(self: *Tui, tty: anytype) !void {
        if (!self.should_refresh) return;

        // Clear entire screen first to prevent old content overlap
        try tty.writeAll(Ansi.clear_screen);
        try tty.writeAll(Ansi.home);

        // Header
        try self.renderHeader(tty);

        // Provider list
        try self.renderProviderList(tty);

        // Provider details for selected provider
        try self.renderSelectedProviderDetails(tty);

        // Metrics panel
        try self.renderMetrics(tty);

        // Footer
        try self.renderFooter(tty);

        try tty.writeAll(Ansi.home);
        try tty.flush();

        self.should_refresh = false;
    }

    /// Render details for the selected provider
    fn renderSelectedProviderDetails(self: *Tui, tty: anytype) !void {
        const selected_provider = self.providers[self.selected_index];
        const provider_name = selected_provider.toString();

        // Get detailed stats
        const is_healthy = if (self.health_checker) |hc| hc.isHealthy(selected_provider) else true;
        const latency_avg = if (self.latency_tracker) |lt| lt.getMovingAvg(selected_provider) else 0;
        const p50 = if (self.latency_tracker) |lt| lt.getPercentile(selected_provider, 50) else 0;
        const p95 = if (self.latency_tracker) |lt| lt.getPercentile(selected_provider, 95) else 0;
        const p99 = if (self.latency_tracker) |lt| lt.getPercentile(selected_provider, 99) else 0;
        const cb_state = if (self.circuit_breaker) |cb| cb.getState(selected_provider) else .closed;
        // last_check not available in HealthChecker - show 0 (never)
        const last_check: i64 = 0;

        // Calculate available width: total width minus borders (2)
        const avail_width: usize = if (self.width > 2) self.width - 2 else 10;
        _ = avail_width; // Track but don't use for calculation since we write directly

        // Section header - dynamic padding based on width
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll(Ansi.bright_black);
        try tty.writeAll(" ");
        try tty.writeAll(Ansi.bright_yellow);
        try tty.writeAll(Ansi.bold);
        try tty.writeAll("PROVIDER DETAILS");
        try tty.writeAll(Ansi.reset);
        try tty.writeAll(" ");
        try tty.writeAll(Ansi.bright_black);
        // Dynamic padding: self.width - 21 (vertical + space + header + space + vertical)
        const header_padding: usize = if (self.width > 21) self.width - 21 else 0;
        try self.writeSpaces(tty, header_padding);
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll(Ansi.clear_eol);
        try tty.writeAll("\n");

        // Separator
        try tty.writeAll(Ansi.box_tee_right);
        var sep_j: usize = 0;
        while (sep_j < 17) : (sep_j += 1) try tty.writeAll(Ansi.box_horizontal);
        try tty.writeAll(Ansi.box_cross);
        sep_j = 0;
        // remaining width: self.width - 21 (left_tee + 17 + cross + right_tee + borders)
        const sep_right: usize = if (self.width > 21) self.width - 21 else 0;
        while (sep_j < sep_right) : (sep_j += 1) try tty.writeAll(Ansi.box_horizontal);
        try tty.writeAll(Ansi.box_tee_left);
        try tty.writeAll(Ansi.clear_eol);
        try tty.writeAll("\n");

        // Details row - compute max widths to prevent overflow
        // Available: self.width - 2 (borders) - 1 (leading space) = self.width - 3
        // But we need at least 1 char between content and closing border
        const content_max: usize = if (self.width > 4) self.width - 3 else 1;

        // Calculate content lengths
        const base_url = selected_provider.getBaseUrl();
        const name_len: usize = provider_name.len;
        const url_len: usize = base_url.len;

        // Fixed label lengths: "Name:"=5, "  Endpoint:"=12, "  Status:"=10
        const label_len: usize = 27;
        const min_name_len: usize = 3; // Minimum to show before truncation
        const min_url_len: usize = 10; // Minimum URL to show

        // Calculate widths, prioritizing: name > url > status
        var name_display: usize = name_len;
        var url_display: usize = url_len;

        // First pass: calculate what we can fit
        const needed_fixed: usize = label_len + 2 + 2; // labels + ".." for name + ".." for url
        const remaining_after_fixed: usize = if (content_max > needed_fixed) content_max - needed_fixed else 0;

        // Distribute remaining space: give 40% to name, 60% to url
        if (remaining_after_fixed > 0) {
            name_display = @min(name_len, @max(min_name_len, remaining_after_fixed * 40 / 100));
            url_display = @min(url_len, @max(min_url_len, remaining_after_fixed * 60 / 100));
        } else {
            name_display = min_name_len;
            url_display = min_url_len;
        }

        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll(" ");

        // Name
        try tty.writeAll(Ansi.bright_cyan);
        try tty.writeAll("Name:");
        try tty.writeAll(Ansi.bright_white);
        if (name_display < name_len) {
            try tty.writeAll(provider_name[0..name_display]);
            try tty.writeAll("..");
        } else {
            try tty.writeAll(provider_name);
        }

        // Endpoint
        try tty.writeAll(Ansi.bright_cyan);
        try tty.writeAll("  Endpoint:");
        try tty.writeAll(Ansi.bright_black);
        if (url_display < url_len) {
            try tty.writeAll("..");
            // Show end of URL (domain is most important)
            const url_start = url_len - url_display;
            try tty.writeAll(base_url[url_start..url_len]);
        } else {
            try tty.writeAll(base_url);
        }

        // Status
        try tty.writeAll(Ansi.bright_cyan);
        try tty.writeAll("  Status:");
        if (is_healthy) {
            try tty.writeAll(Ansi.bright_green);
            try tty.writeAll("healthy");
        } else {
            try tty.writeAll(Ansi.bright_red);
            try tty.writeAll("unhealthy");
        }

        // Clear to end of line and close
        try tty.writeAll(Ansi.clear_eol);
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll("\n");

        // Second row - latency details
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll(" ");
        try tty.writeAll(Ansi.bright_cyan);
        try tty.writeAll("Latency:");
        if (latency_avg > 0) {
            try tty.writeAll(Ansi.bright_white);
            var avg_buf: [16]u8 = undefined;
            const avg_str = std.fmt.bufPrint(&avg_buf, "{d}ms (avg)", .{latency_avg}) catch "";
            try tty.writeAll(avg_str);
        } else {
            try tty.writeAll(Ansi.bright_black);
            try tty.writeAll("no data");
        }

        // Percentiles
        if (p50 > 0) {
            try tty.writeAll(" P50:");
            try tty.writeAll(Ansi.bright_white);
            var p50_buf: [12]u8 = undefined;
            const p50_str = std.fmt.bufPrint(&p50_buf, "{d}ms", .{p50}) catch "";
            try tty.writeAll(p50_str);

            try tty.writeAll(" P95:");
            try tty.writeAll(Ansi.bright_white);
            var p95_buf: [12]u8 = undefined;
            const p95_str = std.fmt.bufPrint(&p95_buf, "{d}ms", .{p95}) catch "";
            try tty.writeAll(p95_str);

            try tty.writeAll(" P99:");
            try tty.writeAll(Ansi.bright_white);
            var p99_buf: [12]u8 = undefined;
            const p99_str = std.fmt.bufPrint(&p99_buf, "{d}ms", .{p99}) catch "";
            try tty.writeAll(p99_str);
        }

        // Circuit breaker
        try tty.writeAll(Ansi.bright_cyan);
        try tty.writeAll("  CB:");
        const cb_color: []const u8 = switch (cb_state) {
            .closed => Ansi.bright_green,
            .half_open => Ansi.bright_yellow,
            .open => Ansi.bright_red,
        };
        const cb_str = switch (cb_state) {
            .closed => "CLOSED",
            .half_open => "HALF_OPEN",
            .open => "OPEN",
        };
        try tty.writeAll(cb_color);
        try tty.writeAll(cb_str);

        // Last check time
        try tty.writeAll(Ansi.bright_cyan);
        try tty.writeAll("  Last Check:");
        if (last_check > 0) {
            const now = std.time.timestamp();
            const seconds_ago = now - last_check;
            try tty.writeAll(Ansi.bright_black);
            if (seconds_ago < 60) {
                var buf: [16]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "{d}s ago", .{seconds_ago}) catch "";
                try tty.writeAll(str);
            } else if (seconds_ago < 3600) {
                var buf: [16]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "{d}m ago", .{@divTrunc(seconds_ago, 60)}) catch "";
                try tty.writeAll(str);
            } else {
                var buf: [16]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "{d}h ago", .{@divTrunc(seconds_ago, 3600)}) catch "";
                try tty.writeAll(str);
            }
        } else {
            try tty.writeAll(Ansi.bright_black);
            try tty.writeAll("never");
        }

        // Clear to end of line and close
        try tty.writeAll(Ansi.clear_eol);
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll("\n");
    }

    fn renderHeader(self: *Tui, tty: anytype) !void {
        const title = " llmlite-proxy ";
        const uptime = self.getUptime();

        try tty.writeAll(Ansi.bold);
        try tty.writeAll(Ansi.bright_cyan);
        try tty.writeAll(Ansi.box_top_left);
        var i: usize = 0;
        const top_len: usize = if (self.width > 2) self.width - 2 else 0;
        while (i < top_len) : (i += 1) {
            try tty.writeAll(Ansi.box_horizontal);
        }
        try tty.writeAll(Ansi.box_top_right);
        try tty.writeAll("\n");

        // Title line with uptime - dynamic padding
        // Structure: | <space> title <spaces> uptime: Xh Xm <spaces> |
        // title = " llmlite-proxy " = 16 chars
        // "uptime: " = 8 chars
        // uptime = variable (from getUptime())
        const title_len: usize = 16;
        const label_len: usize = 8; // "uptime: "

        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll(Ansi.bright_black);
        try tty.writeAll(" ");
        try tty.writeAll(Ansi.bright_cyan);
        try tty.writeAll(Ansi.bold);
        try tty.writeAll(title);
        try tty.writeAll(Ansi.reset);
        try tty.writeAll(Ansi.bright_black);

        // Calculate spaces: width - 1(border) - 1(space) - title_len - label_len - uptime.len - 1(border)
        // But we want spaces between title and label, so split: pad1 after title, pad2 after uptime
        const fixed_content: usize = 1 + 1 + title_len + label_len; // border + space + title + label
        const uptime_len: usize = uptime.len;
        const after_label: usize = 1 + uptime_len + 1; // space before label + uptime + border
        if (self.width > fixed_content + after_label) {
            const total_spaces = self.width - fixed_content - after_label;
            // Split spaces: half after title, half after uptime
            const pad_after_title = total_spaces / 2;
            const pad_after_uptime = total_spaces - pad_after_title;
            try self.writeSpaces(tty, pad_after_title);
            try tty.writeAll("uptime: ");
            try tty.writeAll(uptime);
            try self.writeSpaces(tty, pad_after_uptime);
        } else {
            // Not enough space, just put label after title
            try tty.writeAll("uptime: ");
            try tty.writeAll(uptime);
        }
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll("\n");

        // Separator
        try tty.writeAll(Ansi.box_vertical);
        i = 0;
        const sep_len: usize = if (self.width > 2) self.width - 2 else 0;
        while (i < sep_len) : (i += 1) {
            try tty.writeAll(" ");
        }
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll("\n");

        try tty.writeAll(Ansi.reset);
    }

    fn renderProviderList(self: *Tui, tty: anytype) !void {
        // Section header - dynamic padding based on width
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll(Ansi.bright_black);
        try tty.writeAll(" ");
        try tty.writeAll(Ansi.bright_yellow);
        try tty.writeAll(Ansi.bold);
        try tty.writeAll("PROVIDERS");
        try tty.writeAll(Ansi.reset);
        try tty.writeAll(" ");
        try tty.writeAll(Ansi.bright_black);
        // Dynamic: "PROVIDERS" (9 chars) + 2 spaces + borders = 12, so padding = width - 12
        const prov_header_pad: usize = if (self.width > 12) self.width - 12 else 0;
        try self.writeSpaces(tty, prov_header_pad);
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll("\n");

        // Separator with providers label
        try tty.writeAll(Ansi.box_tee_right);
        try tty.writeAll(Ansi.bright_black);
        var sep_i: usize = 0;
        while (sep_i < 10) : (sep_i += 1) try tty.writeAll(Ansi.box_horizontal);
        try tty.writeAll(Ansi.box_cross);
        // Right side: width - 14 for the remaining
        const sep_right_len: usize = if (self.width > 14) self.width - 14 else 0;
        sep_i = 0; // Reset counter for right side
        while (sep_i < sep_right_len) : (sep_i += 1) try tty.writeAll(Ansi.box_horizontal);
        try tty.writeAll(Ansi.box_tee_left);
        try tty.writeAll("\n");

        // Provider rows
        for (self.providers, 0..) |provider, idx| {
            try self.renderProviderRow(tty, provider, idx);
        }

        // Bottom border
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll(Ansi.bright_black);
        const bottom_pad: usize = if (self.width > 2) self.width - 2 else 0;
        sep_i = 0;
        while (sep_i < bottom_pad) : (sep_i += 1) {
            try tty.writeAll(" ");
        }
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll("\n");
    }

    fn renderProviderRow(self: *Tui, tty: anytype, provider: provider_types.ProviderType, index: usize) !void {
        const is_selected = (index == self.selected_index);
        const provider_name = provider.toString();

        // Get status
        const is_healthy = if (self.health_checker) |hc| hc.isHealthy(provider) else true;
        const latency_avg = if (self.latency_tracker) |lt| lt.getMovingAvg(provider) else 0;
        const cb_state = if (self.circuit_breaker) |cb| cb.getState(provider) else .closed;
        const cb_is_open = if (self.circuit_breaker) |cb| cb.isOpen(provider) else false;

        // Build latency string
        var latency_buf: [16]u8 = undefined;
        const latency_str = if (latency_avg > 0)
            std.fmt.bufPrint(&latency_buf, "{d}", .{latency_avg}) catch "0"
        else
            "";

        // Status indicator
        const status_color: []const u8 = if (!is_healthy or cb_is_open)
            Ansi.bright_red
        else if (latency_avg > 0)
            Ansi.bright_green
        else
            Ansi.bright_black;

        const status_icon: []const u8 = if (!is_healthy)
            Ansi.cross
        else if (cb_is_open)
            Ansi.bright_red ++ "⚡"
        else if (latency_avg > 0)
            Ansi.check
        else
            Ansi.circle;

        // Circuit state
        const cb_color: []const u8 = switch (cb_state) {
            .closed => Ansi.bright_black,
            .half_open => Ansi.bright_yellow,
            .open => Ansi.bright_red,
        };
        const cb_str = switch (cb_state) {
            .closed => "CLOSED",
            .half_open => "HALF_OPEN",
            .open => "OPEN",
        };

        // Calculate fixed content length for width enforcement
        // Format: | <arrow?> name padding status latency [cb] percentiles
        // Min: "| " + "  " + name + padding(12-name) + icon + space + latency(8) + " [CLOSED]" = 4 + name + 8 + 9 = 21 + name
        const min_content_len: usize = 4 + provider_name.len + 8 + 9; // borders + space + arrow + name + pad + status + latency + cb
        const avail_width: usize = if (self.width > 2) self.width - 2 else 0;
        // Assume percentiles take ~30 chars if available - we'll check at render time
        const percentiles_width: usize = 30;

        const total_content_len: usize = min_content_len + percentiles_width;
        const needs_truncation = total_content_len > avail_width;

        // Selected row background
        if (is_selected) {
            try tty.writeAll(Ansi.bright_blue ++ Ansi.bg_blue);
        }

        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll(" ");

        // Selection indicator
        if (is_selected) {
            try tty.writeAll(Ansi.bright_white ++ Ansi.bold ++ Ansi.arrow_right ++ " ");
        } else {
            try tty.writeAll("  ");
        }

        // Provider name (truncate if needed)
        try tty.writeAll(status_color);
        if (needs_truncation and provider_name.len > 10) {
            try tty.writeAll(provider_name[0..10]);
            try tty.writeAll("..");
        } else {
            try tty.writeAll(provider_name);
        }
        try tty.writeAll(Ansi.reset);

        // Padding
        const display_name_len: usize = if (needs_truncation and provider_name.len > 10) 12 else provider_name.len;
        var pad: usize = 12;
        while (pad > display_name_len) : (pad -= 1) try tty.writeAll(" ");

        // Status
        try tty.writeAll(status_color);
        try tty.writeAll(status_icon);
        try tty.writeAll(" ");
        try tty.writeAll(Ansi.reset);

        // Latency (skip percentiles if width is tight)
        try tty.writeAll(Ansi.bright_black);
        if (latency_avg > 0) {
            // Truncate latency string if needed
            const lat_len: usize = @min(latency_str.len, 6);
            try tty.writeAll(latency_str[0..lat_len]);
            try tty.writeAll("ms");
        } else {
            try tty.writeAll("     -  ");
        }
        try tty.writeAll(Ansi.reset);

        // Circuit breaker
        try tty.writeAll(" [");
        try tty.writeAll(cb_color);
        try tty.writeAll(cb_str);
        try tty.writeAll(Ansi.reset);
        try tty.writeAll("]");

        // Percentiles only if there's enough space
        const remaining_after_percentiles: usize = if (self.width > total_content_len + 2) self.width - total_content_len - 2 else 0;
        if (self.latency_tracker) |lt| {
            const p50 = lt.getPercentile(provider, 50);
            const p95 = lt.getPercentile(provider, 95);
            if (p50 > 0 and remaining_after_percentiles > 20) {
                try tty.writeAll("  P50:");
                try tty.writeAll(Ansi.bright_black);
                var p50_buf: [8]u8 = undefined;
                const p50_str = std.fmt.bufPrint(&p50_buf, "{d}", .{p50}) catch &p50_buf;
                try tty.writeAll(p50_str);
                try tty.writeAll("ms");

                if (remaining_after_percentiles > 30 and p95 > 0) {
                    try tty.writeAll(" P95:");
                    var p95_buf: [8]u8 = undefined;
                    const p95_str = std.fmt.bufPrint(&p95_buf, "{d}", .{p95}) catch &p95_buf;
                    try tty.writeAll(p95_str);
                    try tty.writeAll("ms");
                }
            }
        }

        // Clear selection background
        if (is_selected) {
            try tty.writeAll(Ansi.reset);
        }

        // Fill rest of line to enforce width bounds
        try tty.writeAll(Ansi.clear_eol);
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll("\n");
    }

    fn renderMetrics(self: *Tui, tty: anytype) !void {
        // Header - dynamic padding based on width
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll(Ansi.bright_black);
        try tty.writeAll(" ");
        try tty.writeAll(Ansi.bright_yellow);
        try tty.writeAll(Ansi.bold);
        try tty.writeAll("METRICS");
        try tty.writeAll(Ansi.reset);
        try tty.writeAll(" ");
        try tty.writeAll(Ansi.bright_black);
        // "METRICS" (8 chars) + 2 spaces + borders = 12, so padding = width - 12
        const metrics_pad: usize = if (self.width > 12) self.width - 12 else 0;
        try self.writeSpaces(tty, metrics_pad);
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll("\n");

        // Separator
        try tty.writeAll(Ansi.box_tee_right);
        try tty.writeAll(Ansi.bright_black);
        var sep_i: usize = 0;
        while (sep_i < 10) : (sep_i += 1) try tty.writeAll(Ansi.box_horizontal);
        try tty.writeAll(Ansi.box_cross);
        // Right side: width - 14 for the remaining
        const sep_right_len: usize = if (self.width > 14) self.width - 14 else 0;
        while (sep_i < 10 + sep_right_len) : (sep_i += 1) try tty.writeAll(Ansi.box_horizontal);
        try tty.writeAll(Ansi.box_tee_left);
        try tty.writeAll("\n");

        // Metrics row
        const total_req = if (self.metrics) |m| m.requests_total else 0;
        const active_conn = if (self.metrics) |m| m.active_connections else 0;
        const success_rate = if (self.metrics) |m| m.getSuccessRate() else 100.0;
        const uptime = self.getUptime();

        var req_buf: [32]u8 = undefined;
        const req_str = std.fmt.bufPrint(&req_buf, "{d}", .{total_req}) catch "0";
        var conn_buf: [32]u8 = undefined;
        const conn_str = std.fmt.bufPrint(&conn_buf, "{d}", .{active_conn}) catch "0";

        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll("  ");
        try tty.writeAll(Ansi.bright_cyan);
        try tty.writeAll("Requests:");
        try tty.writeAll(Ansi.bright_white);
        try tty.writeAll(req_str);
        try tty.writeAll("  ");

        try tty.writeAll(Ansi.bright_cyan);
        try tty.writeAll("Success:");
        if (success_rate > 90) {
            try tty.writeAll(Ansi.bright_green);
        } else if (success_rate > 70) {
            try tty.writeAll(Ansi.bright_yellow);
        } else {
            try tty.writeAll(Ansi.bright_red);
        }
        var rate_buf: [16]u8 = undefined;
        const rate_str = std.fmt.bufPrint(&rate_buf, "{d:.1f}%", .{success_rate}) catch "0.0%";
        try tty.writeAll(rate_str);
        try tty.writeAll(Ansi.bright_black);
        try tty.writeAll("  ");

        try tty.writeAll(Ansi.bright_cyan);
        try tty.writeAll("Conns:");
        try tty.writeAll(Ansi.bright_white);
        try tty.writeAll(conn_str);
        try tty.writeAll(Ansi.bright_black);
        try tty.writeAll("  ");

        try tty.writeAll(Ansi.bright_cyan);
        try tty.writeAll("Uptime:");
        try tty.writeAll(Ansi.bright_white);
        try tty.writeAll(uptime);

        // Fill rest
        try tty.writeAll(Ansi.clear_eol);
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll("\n");

        // Second row - Service info
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll("  ");
        try tty.writeAll(Ansi.bright_cyan);
        try tty.writeAll("Address:");
        try tty.writeAll(Ansi.bright_white);
        const addr = self.getAddress();
        try tty.writeAll(addr);
        try tty.writeAll(Ansi.bright_black);
        try tty.writeAll("  ");

        try tty.writeAll(Ansi.bright_cyan);
        try tty.writeAll("Status:");
        if (self.is_service_running) {
            try tty.writeAll(Ansi.bright_green);
            try tty.writeAll("running");
        } else {
            try tty.writeAll(Ansi.bright_red);
            try tty.writeAll("stopped");
        }
        try tty.writeAll(Ansi.bright_black);
        try tty.writeAll("  ");

        try tty.writeAll(Ansi.bright_cyan);
        try tty.writeAll("Logging:");
        if (self.logging_enabled) {
            try tty.writeAll(Ansi.bright_green);
            try tty.writeAll("ON");
        } else {
            try tty.writeAll(Ansi.bright_red);
            try tty.writeAll("OFF");
        }

        // Fill rest
        try tty.writeAll(Ansi.clear_eol);
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll("\n");
    }

    fn renderFooter(self: *Tui, tty: anytype) !void {
        // Bottom border
        try tty.writeAll(Ansi.box_bottom_left);
        try tty.writeAll(Ansi.bright_black);
        var i: u16 = 0;
        while (i < self.width - 2) : (i += 1) {
            try tty.writeAll(Ansi.box_horizontal);
        }
        try tty.writeAll(Ansi.box_bottom_right);
        try tty.writeAll("\n");

        // Help text
        try tty.writeAll(Ansi.bright_black);
        try tty.writeAll("  ");
        try tty.writeAll(Ansi.bold);
        try tty.writeAll("[q]");
        try tty.writeAll(Ansi.reset);
        try tty.writeAll(Ansi.bright_black);
        try tty.writeAll(" quit ");
        try tty.writeAll(Ansi.bold);
        try tty.writeAll("[r]");
        try tty.writeAll(Ansi.reset);
        try tty.writeAll(Ansi.bright_black);
        try tty.writeAll(" refresh ");
        try tty.writeAll(Ansi.bold);
        try tty.writeAll("[l]");
        try tty.writeAll(Ansi.reset);
        try tty.writeAll(Ansi.bright_black);
        try tty.writeAll(" logging ");
        try tty.writeAll(Ansi.bold);
        try tty.writeAll("[↑↓]");
        try tty.writeAll(Ansi.reset);
        try tty.writeAll(Ansi.bright_black);
        try tty.writeAll(" select ");
        try tty.writeAll(Ansi.bold);
        try tty.writeAll("[Enter]");
        try tty.writeAll(Ansi.reset);
        try tty.writeAll(Ansi.bright_black);
        try tty.writeAll(" toggle ");
        // Fill rest - reset i first
        i = 0;
        while (i < self.width - 85) : (i += 1) try tty.writeAll(" ");
        try tty.writeAll("\n");
    }

    fn getUptime(self: *Tui) []const u8 {
        const elapsed = std.time.timestamp() - self.start_time;
        const hours = @divTrunc(elapsed, 3600);
        const minutes = @divTrunc(@mod(elapsed, 3600), 60);

        if (hours > 0) {
            const len = std.fmt.bufPrint(&self.uptime_buf, "{}h {}m", .{ hours, minutes }) catch return "-";
            return len;
        } else if (minutes > 0) {
            const len = std.fmt.bufPrint(&self.uptime_buf, "{}m", .{minutes}) catch return "-";
            return len;
        } else {
            // Less than 1 minute - show seconds
            const len = std.fmt.bufPrint(&self.uptime_buf, "{}s", .{elapsed}) catch return "-";
            return len;
        }
    }

    /// Get formatted service address string
    fn getAddress(self: *Tui) []const u8 {
        const len = std.fmt.bufPrint(&self.address_buf, "http://{s}:{d}", .{ self.listen_address, self.listen_port }) catch return "-";
        return len;
    }

    /// Handle keyboard input
    pub fn handleInput(self: *Tui, input: []const u8) void {
        if (input.len == 0) return;

        // Single key checks
        if (std.mem.eql(u8, input, Key.ctrl_c) or std.mem.eql(u8, input, "q") or std.mem.eql(u8, input, "Q")) {
            self.running = false;
            return;
        }

        if (std.mem.eql(u8, input, Key.ctrl_r) or std.mem.eql(u8, input, "r") or std.mem.eql(u8, input, "R")) {
            // Trigger refresh callback if set (for manual health check)
            if (self.refresh_callback) |callback| {
                callback(self.refresh_context);
            }
            self.should_refresh = true;
            return;
        }

        if (std.mem.eql(u8, input, "l") or std.mem.eql(u8, input, "L")) {
            // Toggle logging
            self.logging_enabled = !self.logging_enabled;
            if (self.logger_toggle_callback) |callback| {
                callback(self.logger_toggle_context, self.logging_enabled);
            }
            std.log.info("Logging {s}", .{if (self.logging_enabled) "enabled" else "disabled"});
            self.should_refresh = true;
            return;
        }

        if (std.mem.eql(u8, input, Key.arrow_up) or std.mem.eql(u8, input, "k") or std.mem.eql(u8, input, "K")) {
            if (self.selected_index > 0) {
                self.selected_index -= 1;
                self.should_refresh = true;
            }
            return;
        }

        if (std.mem.eql(u8, input, Key.arrow_down) or std.mem.eql(u8, input, "j") or std.mem.eql(u8, input, "J")) {
            if (self.selected_index < self.providers.len - 1) {
                self.selected_index += 1;
                self.should_refresh = true;
            }
            return;
        }

        if (std.mem.eql(u8, input, Key.enter) or std.mem.eql(u8, input, " ")) {
            // Toggle selected provider enabled/disabled
            if (self.selected_index < self.enabled_providers.len) {
                self.enabled_providers[self.selected_index] = !self.enabled_providers[self.selected_index];
                const provider_name = self.providers[self.selected_index].toString();
                const state = if (self.enabled_providers[self.selected_index]) "enabled" else "disabled";
                std.log.info("Provider '{s}' {s}", .{ provider_name, state });
            }
            self.should_refresh = true;
            return;
        }

        if (std.mem.eql(u8, input, Key.home) or std.mem.eql(u8, input, "g")) {
            self.selected_index = 0;
            self.should_refresh = true;
            return;
        }

        if (std.mem.eql(u8, input, Key.end) or std.mem.eql(u8, input, "G")) {
            self.selected_index = self.providers.len - 1;
            self.should_refresh = true;
            return;
        }
    }

    pub fn isRunning(self: *Tui) bool {
        return self.running;
    }

    pub fn stop(self: *Tui) void {
        self.running = false;
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "tui - init and deinit" {
    const allocator = std.heap.page_allocator;
    var tui = Tui.init(allocator);
    defer tui.deinit();

    try std.testing.expect(tui.width == 80);
    try std.testing.expect(tui.height == 24);
    try std.testing.expect(tui.selected_index == 0);
    try std.testing.expect(tui.isRunning());
}

test "tui - handle input navigation" {
    const allocator = std.heap.page_allocator;
    var tui = Tui.init(allocator);
    defer tui.deinit();

    try std.testing.expectEqual(@as(usize, 0), tui.selected_index);

    // Arrow down
    tui.handleInput(Key.arrow_down);
    try std.testing.expectEqual(@as(usize, 1), tui.selected_index);

    // Arrow up
    tui.handleInput(Key.arrow_up);
    try std.testing.expectEqual(@as(usize, 0), tui.selected_index);

    // Vim-style j/k
    tui.handleInput("j");
    try std.testing.expectEqual(@as(usize, 1), tui.selected_index);

    tui.handleInput("k");
    try std.testing.expectEqual(@as(usize, 0), tui.selected_index);
}

test "tui - handle input quit" {
    const allocator = std.heap.page_allocator;
    var tui = Tui.init(allocator);
    defer tui.deinit();

    try std.testing.expect(tui.isRunning());

    tui.handleInput("q");
    try std.testing.expect(!tui.isRunning());
}

test "tui - handle input refresh" {
    const allocator = std.heap.page_allocator;
    var tui = Tui.init(allocator);
    defer tui.deinit();

    try std.testing.expect(!tui.should_refresh);

    tui.handleInput("r");
    try std.testing.expect(tui.should_refresh);

    // After refresh flag is set, it should be false until changed again
    tui.should_refresh = false;
    tui.handleInput(Key.ctrl_r);
    try std.testing.expect(tui.should_refresh);
}

test "tui - handle input boundaries" {
    const allocator = std.heap.page_allocator;
    var tui = Tui.init(allocator);
    defer tui.deinit();

    // Can't go below 0
    tui.handleInput(Key.arrow_up);
    try std.testing.expectEqual(@as(usize, 0), tui.selected_index);

    // Can't go above providers.len - 1
    tui.selected_index = tui.providers.len - 1;
    tui.handleInput(Key.arrow_down);
    try std.testing.expectEqual(@as(usize, tui.providers.len - 1), tui.selected_index);
}

test "tui - home and end" {
    const allocator = std.heap.page_allocator;
    var tui = Tui.init(allocator);
    defer tui.deinit();

    // Go to end
    tui.handleInput(Key.end);
    try std.testing.expectEqual(@as(usize, tui.providers.len - 1), tui.selected_index);

    // Go to home
    tui.handleInput(Key.home);
    try std.testing.expectEqual(@as(usize, 0), tui.selected_index);
}
