//! Renderer - Stateless rendering for llmlite-proxy TUI
//!
//! Pattern from llmfit-tui: tui_ui.rs is stateless -- reads from App, writes to Frame.
//! Pattern from cc-switch: switch(currentView) dispatch to per-view render functions.
//!
//! All rendering functions take `*AppState` (immutable) and a writer.

const std = @import("std");
const app = @import("app.zig");
const provider_types = @import("types");
const latency_health = @import("latency_health");
const circuit_breaker = @import("circuit_breaker");
const logger = @import("proxy_logger");
const time_compat = @import("time_compat");

const AppState = app.AppState;
const View = app.View;
const InputMode = app.InputMode;

// ============================================================================
// ANSI Escape Codes
// ============================================================================

pub const Ansi = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";
    pub const italic = "\x1b[3m";
    pub const underline = "\x1b[4m";

    // Foreground colors
    pub const black = "\x1b[30m";
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const white = "\x1b[37m";

    // Bright foreground
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
    pub const circle = "○";
    pub const arrow_right = "→";
    pub const arrow_left = "←";
    pub const arrow_up = "↑";
    pub const arrow_down = "↓";
    pub const bullet = "●";
};

// ============================================================================
// Helper functions
// ============================================================================

fn writeSpaces(tty: anytype, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        try tty.writeAll(" ");
    }
}

fn writePadded(tty: anytype, text: []const u8, target_width: usize) !void {
    try tty.writeAll(text);
    if (text.len < target_width) {
        try writeSpaces(tty, target_width - text.len);
    }
}

/// Truncate text to fit max_width, showing END of string.
fn truncate(text: []const u8, max_width: usize) []const u8 {
    if (text.len == 0) return text;
    if (max_width < 3) return text;
    if (text.len > max_width - 2) {
        const start_idx = text.len - (max_width - 2);
        return text[start_idx..text.len];
    }
    return text;
}

fn writeTruncated(tty: anytype, text: []const u8, max_width: usize) !void {
    if (text.len <= max_width) {
        try tty.writeAll(text);
        if (text.len < max_width) try writeSpaces(tty, max_width - text.len);
    } else if (max_width >= 2) {
        try tty.writeAll("..");
        try tty.writeAll(text[text.len - (max_width - 2) .. text.len]);
    }
}

// ============================================================================
// Main Render Entry Point
// ============================================================================

pub fn render(app_state: *AppState, tty: anytype) !void {
    // Clear and home
    try tty.writeAll(Ansi.clear_screen);
    try tty.writeAll(Ansi.home);

    // Shared header
    try renderHeader(app_state, tty);

    // View-specific content
    switch (app_state.current_view) {
        .dashboard => try renderDashboard(app_state, tty),
        .logs => try renderLogs(app_state, tty),
        .help => try renderHelp(app_state, tty),
    }

    // Dialog overlay (if any)
    if (app_state.dialog != null) {
        try renderDialogOverlay(app_state, tty);
    }

    try tty.flush();

    // Cast away const for the mutable field (render takes *const but needs to clear flag)
    const mutable: *AppState = @constCast(app_state);
    mutable.should_refresh = false;
}


// ============================================================================
// Header & Footer (shared across all views)
// ============================================================================

fn renderHeader(app_state: *AppState, tty: anytype) !void {
    const title = " llmlite-proxy ";
    const uptime = app_state.getUptime();

    // Top border
    try tty.writeAll(Ansi.bold);
    try tty.writeAll(Ansi.bright_cyan);
    try tty.writeAll(Ansi.box_top_left);
    const top_len = if (app_state.width > 2) app_state.width - 2 else 0;
    var i: usize = 0;
    while (i < top_len) : (i += 1) try tty.writeAll(Ansi.box_horizontal);
    try tty.writeAll(Ansi.box_top_right);
    try tty.writeAll("\n");

    // Title line with uptime
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll(Ansi.bright_black);
    try tty.writeAll(" ");
    try tty.writeAll(Ansi.bright_cyan);
    try tty.writeAll(Ansi.bold);
    try tty.writeAll(title);
    try tty.writeAll(Ansi.reset);
    try tty.writeAll(Ansi.bright_black);

    const title_len: usize = 16;
    const label_len: usize = 8; // "uptime: "
    const uptime_len = uptime.len;
    const fixed_content = 1 + 1 + title_len + label_len;
    const after_label = 1 + uptime_len + 1;
    if (app_state.width > fixed_content + after_label) {
        const total_spaces = app_state.width - fixed_content - after_label;
        const pad_after_title = total_spaces / 2;
        const pad_after_uptime = total_spaces - pad_after_title;
        try writeSpaces(tty, pad_after_title);
        try tty.writeAll("uptime: ");
        try tty.writeAll(uptime);
        try writeSpaces(tty, pad_after_uptime);
    } else {
        try tty.writeAll("uptime: ");
        try tty.writeAll(uptime);
    }
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll("\n");

    // Separator
    try tty.writeAll(Ansi.box_vertical);
    i = 0;
    const sep_len = if (app_state.width > 2) app_state.width - 2 else 0;
    while (i < sep_len) : (i += 1) try tty.writeAll(" ");
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll("\n");

    try tty.writeAll(Ansi.reset);
}

fn renderFooter(app_state: *AppState, tty: anytype) !void {
    const MIN_WIDTH: u16 = 40;
    const w = if (app_state.width >= MIN_WIDTH) app_state.width else MIN_WIDTH;

    // Bottom border
    try tty.writeAll(Ansi.box_bottom_left);
    try tty.writeAll(Ansi.bright_black);
    var i: u16 = 0;
    const border_len = if (w > 2) w - 2 else 0;
    while (i < border_len) : (i += 1) try tty.writeAll(Ansi.box_horizontal);
    try tty.writeAll(Ansi.box_bottom_right);
    try tty.writeAll("\n");

    // Help text - contextual based on view
    try tty.writeAll(Ansi.bright_black);

    // View indicator + mode
    try tty.writeAll("  ");
    try tty.writeAll(Ansi.bold);
    try tty.writeAll("[");
    try tty.writeAll(app_state.current_view.toString());
    try tty.writeAll("]");
    try tty.writeAll(Ansi.reset);
    try tty.writeAll(Ansi.bright_black);
    try tty.writeAll(" ");
    try tty.writeAll(app_state.input_mode.toString());
    try tty.writeAll("  ");

    // Contextual shortcuts
    switch (app_state.current_view) {
        .dashboard => {
            if (app_state.width >= 90) {
                try tty.writeAll(Ansi.bold); try tty.writeAll("[q]"); try tty.writeAll(Ansi.reset); try tty.writeAll(Ansi.bright_black); try tty.writeAll(" quit ");
                try tty.writeAll(Ansi.bold); try tty.writeAll("[r]"); try tty.writeAll(Ansi.reset); try tty.writeAll(Ansi.bright_black); try tty.writeAll(" refresh ");
                try tty.writeAll(Ansi.bold); try tty.writeAll("[l]"); try tty.writeAll(Ansi.reset); try tty.writeAll(Ansi.bright_black); try tty.writeAll(" logging ");
                try tty.writeAll(Ansi.bold); try tty.writeAll("[↑↓/jk]"); try tty.writeAll(Ansi.reset); try tty.writeAll(Ansi.bright_black); try tty.writeAll(" select ");
                try tty.writeAll(Ansi.bold); try tty.writeAll("[Enter/Space]"); try tty.writeAll(Ansi.reset); try tty.writeAll(Ansi.bright_black); try tty.writeAll(" toggle ");
                try tty.writeAll(Ansi.bold); try tty.writeAll("[?]"); try tty.writeAll(Ansi.reset); try tty.writeAll(Ansi.bright_black); try tty.writeAll(" help");
            } else if (app_state.width >= 60) {
                try tty.writeAll(Ansi.bold); try tty.writeAll("[q]"); try tty.writeAll(Ansi.reset); try tty.writeAll(Ansi.bright_black); try tty.writeAll(" quit ");
                try tty.writeAll(Ansi.bold); try tty.writeAll("[r]"); try tty.writeAll(Ansi.reset); try tty.writeAll(Ansi.bright_black); try tty.writeAll(" refresh ");
                try tty.writeAll(Ansi.bold); try tty.writeAll("[↑↓]"); try tty.writeAll(Ansi.reset); try tty.writeAll(Ansi.bright_black); try tty.writeAll(" select ");
                try tty.writeAll(Ansi.bold); try tty.writeAll("[?]"); try tty.writeAll(Ansi.reset); try tty.writeAll(Ansi.bright_black); try tty.writeAll(" help");
            } else {
                try tty.writeAll(Ansi.bold); try tty.writeAll("[q]"); try tty.writeAll(Ansi.reset); try tty.writeAll(Ansi.bright_black); try tty.writeAll(" quit ");
                try tty.writeAll(Ansi.bold); try tty.writeAll("[?]"); try tty.writeAll(Ansi.reset); try tty.writeAll(Ansi.bright_black); try tty.writeAll(" help");
            }
        },
        .logs => {
            try tty.writeAll(Ansi.bold); try tty.writeAll("[q]"); try tty.writeAll(Ansi.reset); try tty.writeAll(Ansi.bright_black); try tty.writeAll(" quit ");
            try tty.writeAll(Ansi.bold); try tty.writeAll("[Esc]"); try tty.writeAll(Ansi.reset); try tty.writeAll(Ansi.bright_black); try tty.writeAll(" dashboard ");
            try tty.writeAll(Ansi.bold); try tty.writeAll("[?]"); try tty.writeAll(Ansi.reset); try tty.writeAll(Ansi.bright_black); try tty.writeAll(" help");
        },
        .help => {
            try tty.writeAll(Ansi.bold); try tty.writeAll("[any]"); try tty.writeAll(Ansi.reset); try tty.writeAll(Ansi.bright_black); try tty.writeAll(" back");
        },
    }

    try tty.writeAll("\n");
}


// ============================================================================
// Dashboard View
// ============================================================================

fn renderDashboard(app_state: *AppState, tty: anytype) !void {
    try renderProviderList(app_state, tty);
    try renderProviderDetails(app_state, tty);
    try renderMetricsPanel(app_state, tty);
    try renderFooter(app_state, tty);
}

fn renderProviderList(app_state: *AppState, tty: anytype) !void {
    // Section header
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll(Ansi.bright_black);
    try tty.writeAll(" ");
    try tty.writeAll(Ansi.bright_yellow);
    try tty.writeAll(Ansi.bold);
    try tty.writeAll("PROVIDERS");
    try tty.writeAll(Ansi.reset);
    try tty.writeAll(" ");
    try tty.writeAll(Ansi.bright_black);
    const prov_header_pad: usize = if (app_state.width > 12) app_state.width - 12 else 0;
    try writeSpaces(tty, prov_header_pad);
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll("\n");

    // Separator
    try tty.writeAll(Ansi.box_tee_right);
    try tty.writeAll(Ansi.bright_black);
    var sep_i: usize = 0;
    while (sep_i < 10) : (sep_i += 1) try tty.writeAll(Ansi.box_horizontal);
    try tty.writeAll(Ansi.box_cross);
    const sep_right_len: usize = if (app_state.width > 14) app_state.width - 14 else 0;
    sep_i = 0;
    while (sep_i < sep_right_len) : (sep_i += 1) try tty.writeAll(Ansi.box_horizontal);
    try tty.writeAll(Ansi.box_tee_left);
    try tty.writeAll("\n");

    // Provider rows
    for (app_state.providers, 0..) |provider, idx| {
        try renderProviderRow(app_state, tty, provider, idx);
    }

    // Bottom border of provider section
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll(Ansi.bright_black);
    const bottom_pad: usize = if (app_state.width > 2) app_state.width - 2 else 0;
    sep_i = 0;
    while (sep_i < bottom_pad) : (sep_i += 1) try tty.writeAll(" ");
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll("\n");
}

fn renderProviderRow(app_state: *AppState, tty: anytype, provider: provider_types.ProviderType, index: usize) !void {
    const is_selected = (index == app_state.selected_index);
    const provider_name = provider.toString();

    const is_healthy = if (app_state.health_checker) |hc| hc.isHealthy(provider) else true;
    const latency_avg = if (app_state.latency_tracker) |lt| lt.getMovingAvg(provider) else 0;
    const cb_state = if (app_state.circuit_breaker) |cb| cb.getState(app_state.io, provider) else .closed;
    const cb_is_open = if (app_state.circuit_breaker) |cb| cb.isOpen(app_state.io, provider) else false;

    // Latency string
    var latency_buf: [16]u8 = undefined;
    const latency_str = if (latency_avg > 0)
        std.fmt.bufPrint(&latency_buf, "{d}", .{latency_avg}) catch "0"
    else
        "";

    // Status
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

    // Circuit breaker
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

    // Enabled/disabled indicator
    const enabled = if (index < app_state.enabled_providers.len) app_state.enabled_providers[index] else true;
    const enabled_icon: []const u8 = if (enabled) Ansi.bright_green ++ "●" else Ansi.bright_black ++ "○";

    // Width calculations
    const display_name_len = if (provider_name.len > 12) 12 else provider_name.len;
    const min_content_len: usize = 4 + display_name_len + 8 + 9 + 4; // borders + name + status + latency + cb + enabled

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

    // Enabled indicator
    try tty.writeAll(enabled_icon);
    try tty.writeAll(Ansi.reset);
    if (is_selected) try tty.writeAll(Ansi.bright_blue ++ Ansi.bg_blue);
    try tty.writeAll(" ");

    // Provider name
    try tty.writeAll(status_color);
    if (provider_name.len > 12) {
        try tty.writeAll(provider_name[0..10]);
        try tty.writeAll("..");
    } else {
        try tty.writeAll(provider_name);
    }
    try tty.writeAll(Ansi.reset);
    if (is_selected) try tty.writeAll(Ansi.bright_blue ++ Ansi.bg_blue);

    // Padding after name
    var pad: usize = 13;
    while (pad > display_name_len + 1) : (pad -= 1) try tty.writeAll(" ");

    // Status icon
    try tty.writeAll(status_color);
    try tty.writeAll(status_icon);
    try tty.writeAll(" ");
    try tty.writeAll(Ansi.reset);
    if (is_selected) try tty.writeAll(Ansi.bright_blue ++ Ansi.bg_blue);

    // Latency
    try tty.writeAll(Ansi.bright_black);
    if (latency_avg > 0) {
        const lat_len = @min(latency_str.len, 6);
        try tty.writeAll(latency_str[0..lat_len]);
        try tty.writeAll("ms");
    } else {
        try tty.writeAll("     -  ");
    }
    try tty.writeAll(Ansi.reset);
    if (is_selected) try tty.writeAll(Ansi.bright_blue ++ Ansi.bg_blue);

    // Circuit breaker
    try tty.writeAll(" [");
    try tty.writeAll(cb_color);
    try tty.writeAll(cb_str);
    try tty.writeAll(Ansi.reset);
    if (is_selected) try tty.writeAll(Ansi.bright_blue ++ Ansi.bg_blue);
    try tty.writeAll("]");

    // Percentiles if space available
    const percentiles_width: usize = 30;
    const total_content_len = min_content_len + percentiles_width;
    if (app_state.width > total_content_len + 2) {
        if (app_state.latency_tracker) |lt| {
            const p50 = lt.getPercentile(provider, 50);
            const p95 = lt.getPercentile(provider, 95);
            if (p50 > 0) {
                try tty.writeAll("  P50:");
                try tty.writeAll(Ansi.bright_black);
                var p50_buf: [8]u8 = undefined;
                const p50_str = std.fmt.bufPrint(&p50_buf, "{d}", .{p50}) catch "";
                try tty.writeAll(p50_str);
                try tty.writeAll("ms");

                if (app_state.width > total_content_len + 12 and p95 > 0) {
                    try tty.writeAll(" P95:");
                    var p95_buf: [8]u8 = undefined;
                    const p95_str = std.fmt.bufPrint(&p95_buf, "{d}", .{p95}) catch "";
                    try tty.writeAll(p95_str);
                    try tty.writeAll("ms");
                }
            }
        }
    }

    if (is_selected) {
        try tty.writeAll(Ansi.reset);
    }

    try tty.writeAll(Ansi.clear_eol);
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll("\n");
}


fn renderProviderDetails(app_state: *AppState, tty: anytype) !void {
    if (app_state.providers.len == 0) return;
    const selected_provider = app_state.providers[app_state.selected_index];
    const provider_name = selected_provider.toString();

    const is_healthy = if (app_state.health_checker) |hc| hc.isHealthy(selected_provider) else true;
    const latency_avg = if (app_state.latency_tracker) |lt| lt.getMovingAvg(selected_provider) else 0;
    const p50 = if (app_state.latency_tracker) |lt| lt.getPercentile(selected_provider, 50) else 0;
    const p95 = if (app_state.latency_tracker) |lt| lt.getPercentile(selected_provider, 95) else 0;
    const p99 = if (app_state.latency_tracker) |lt| lt.getPercentile(selected_provider, 99) else 0;
    const cb_state = if (app_state.circuit_breaker) |cb| cb.getState(app_state.io, selected_provider) else .closed;
    const last_check: i64 = 0;

    // Section header
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll(Ansi.bright_black);
    try tty.writeAll(" ");
    try tty.writeAll(Ansi.bright_yellow);
    try tty.writeAll(Ansi.bold);
    try tty.writeAll("PROVIDER DETAILS");
    try tty.writeAll(Ansi.reset);
    try tty.writeAll(" ");
    try tty.writeAll(Ansi.bright_black);
    const header_padding: usize = if (app_state.width > 21) app_state.width - 21 else 0;
    try writeSpaces(tty, header_padding);
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll(Ansi.clear_eol);
    try tty.writeAll("\n");

    // Separator
    try tty.writeAll(Ansi.box_tee_right);
    var sep_j: usize = 0;
    while (sep_j < 17) : (sep_j += 1) try tty.writeAll(Ansi.box_horizontal);
    try tty.writeAll(Ansi.box_cross);
    const sep_right: usize = if (app_state.width > 21) app_state.width - 21 else 0;
    sep_j = 0;
    while (sep_j < sep_right) : (sep_j += 1) try tty.writeAll(Ansi.box_horizontal);
    try tty.writeAll(Ansi.box_tee_left);
    try tty.writeAll(Ansi.clear_eol);
    try tty.writeAll("\n");

    // Row 1: Name + Status
    const content_max: usize = if (app_state.width > 4) app_state.width - 3 else 1;
    const name_len = provider_name.len;
    const label_len: usize = 16;
    const min_name_len: usize = 3;
    const needed_fixed: usize = label_len + 2;
    const remaining_after_fixed: usize = if (content_max > needed_fixed) content_max - needed_fixed else 0;
    const name_display: usize = if (remaining_after_fixed > 0)
        @min(name_len, @max(min_name_len, remaining_after_fixed))
    else
        min_name_len;

    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll(" ");

    try tty.writeAll(Ansi.bright_cyan);
    try tty.writeAll("Name:");
    try tty.writeAll(Ansi.bright_white);
    if (name_display < name_len) {
        try tty.writeAll(provider_name[0..name_display]);
        try tty.writeAll("..");
    } else {
        try tty.writeAll(provider_name);
    }

    try tty.writeAll(Ansi.bright_cyan);
    try tty.writeAll("  Status:");
    if (is_healthy) {
        try tty.writeAll(Ansi.bright_green);
        try tty.writeAll("healthy");
    } else {
        try tty.writeAll(Ansi.bright_red);
        try tty.writeAll("unhealthy");
    }

    try tty.writeAll(Ansi.clear_eol);
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll("\n");

    // Row 2: Latency + Circuit breaker
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

    if (p50 > 0) {
        try tty.writeAll(" P50:");
        try tty.writeAll(Ansi.bright_white);
        var p50_buf: [12]u8 = undefined;
        try tty.writeAll(std.fmt.bufPrint(&p50_buf, "{d}ms", .{p50}) catch "");

        if (p95 > 0) {
            try tty.writeAll(" P95:");
            var p95_buf: [12]u8 = undefined;
            try tty.writeAll(std.fmt.bufPrint(&p95_buf, "{d}ms", .{p95}) catch "");
        }

        if (p99 > 0) {
            try tty.writeAll(" P99:");
            var p99_buf: [12]u8 = undefined;
            try tty.writeAll(std.fmt.bufPrint(&p99_buf, "{d}ms", .{p99}) catch "");
        }
    }

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

    try tty.writeAll(Ansi.bright_cyan);
    try tty.writeAll("  Last Check:");
    if (last_check > 0) {
        const now = time_compat.timestamp(app_state.io);
        const seconds_ago = now - last_check;
        try tty.writeAll(Ansi.bright_black);
        if (seconds_ago < 60) {
            var buf: [16]u8 = undefined;
            try tty.writeAll(std.fmt.bufPrint(&buf, "{d}s ago", .{seconds_ago}) catch "");
        } else if (seconds_ago < 3600) {
            var buf: [16]u8 = undefined;
            try tty.writeAll(std.fmt.bufPrint(&buf, "{d}m ago", .{@divTrunc(seconds_ago, 60)}) catch "");
        } else {
            var buf: [16]u8 = undefined;
            try tty.writeAll(std.fmt.bufPrint(&buf, "{d}h ago", .{@divTrunc(seconds_ago, 3600)}) catch "");
        }
    } else {
        try tty.writeAll(Ansi.bright_black);
        try tty.writeAll("never");
    }

    try tty.writeAll(Ansi.clear_eol);
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll("\n");
}

fn renderMetricsPanel(app_state: *AppState, tty: anytype) !void {
    // Header
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll(Ansi.bright_black);
    try tty.writeAll(" ");
    try tty.writeAll(Ansi.bright_yellow);
    try tty.writeAll(Ansi.bold);
    try tty.writeAll("METRICS");
    try tty.writeAll(Ansi.reset);
    try tty.writeAll(" ");
    try tty.writeAll(Ansi.bright_black);
    const metrics_pad: usize = if (app_state.width > 12) app_state.width - 12 else 0;
    try writeSpaces(tty, metrics_pad);
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll("\n");

    // Separator
    try tty.writeAll(Ansi.box_tee_right);
    try tty.writeAll(Ansi.bright_black);
    var sep_i: usize = 0;
    while (sep_i < 10) : (sep_i += 1) try tty.writeAll(Ansi.box_horizontal);
    try tty.writeAll(Ansi.box_cross);
    const sep_right_len: usize = if (app_state.width > 14) app_state.width - 14 else 0;
    while (sep_i < 10 + sep_right_len) : (sep_i += 1) try tty.writeAll(Ansi.box_horizontal);
    try tty.writeAll(Ansi.box_tee_left);
    try tty.writeAll("\n");

    // Metrics row 1
    const total_req = if (app_state.metrics) |m| m.requests_total else 0;
    const errors = if (app_state.metrics) |m| m.requests_error else 0;
    const success_rate = if (app_state.metrics) |m| m.getSuccessRate() else 100.0;
    const uptime = app_state.getUptime();

    var req_buf: [32]u8 = undefined;
    const req_str = std.fmt.bufPrint(&req_buf, "{d}", .{total_req}) catch "0";
    var err_buf: [32]u8 = undefined;
    const err_str = std.fmt.bufPrint(&err_buf, "{d}", .{errors}) catch "0";

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
    const rate_str = std.fmt.bufPrint(&rate_buf, "{d:.1}%", .{success_rate}) catch "0.0%";
    try tty.writeAll(rate_str);
    try tty.writeAll(Ansi.bright_black);
    try tty.writeAll("  ");

    try tty.writeAll(Ansi.bright_cyan);
    try tty.writeAll("Errors:");
    try tty.writeAll(Ansi.bright_white);
    try tty.writeAll(err_str);
    try tty.writeAll(Ansi.bright_black);
    try tty.writeAll("  ");

    try tty.writeAll(Ansi.bright_cyan);
    try tty.writeAll("Uptime:");
    try tty.writeAll(Ansi.bright_white);
    try tty.writeAll(uptime);

    try tty.writeAll(Ansi.clear_eol);
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll("\n");

    // Metrics row 2: Service info
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll("  ");
    try tty.writeAll(Ansi.bright_cyan);
    try tty.writeAll("Address:");
    try tty.writeAll(Ansi.bright_white);
    try tty.writeAll(app_state.getAddress());
    try tty.writeAll(Ansi.bright_black);
    try tty.writeAll("  ");

    try tty.writeAll(Ansi.bright_cyan);
    try tty.writeAll("Status:");
    if (app_state.is_service_running) {
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
    if (app_state.logging_enabled) {
        try tty.writeAll(Ansi.bright_green);
        try tty.writeAll("ON");
    } else {
        try tty.writeAll(Ansi.bright_red);
        try tty.writeAll("OFF");
    }

    try tty.writeAll(Ansi.clear_eol);
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll("\n");
}


// ============================================================================
// Logs View
// ============================================================================

fn renderLogs(app_state: *AppState, tty: anytype) !void {
    // Header
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll(Ansi.bright_black);
    try tty.writeAll(" ");
    try tty.writeAll(Ansi.bright_yellow);
    try tty.writeAll(Ansi.bold);
    try tty.writeAll("REQUEST LOGS");
    try tty.writeAll(Ansi.reset);
    try tty.writeAll(" ");
    try tty.writeAll(Ansi.bright_black);
    const pad: usize = if (app_state.width > 15) app_state.width - 15 else 0;
    try writeSpaces(tty, pad);
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll("\n");

    // Separator
    try tty.writeAll(Ansi.box_tee_right);
    var i: usize = 0;
    while (i < 13) : (i += 1) try tty.writeAll(Ansi.box_horizontal);
    try tty.writeAll(Ansi.box_cross);
    const sep_right: usize = if (app_state.width > 17) app_state.width - 17 else 0;
    i = 0;
    while (i < sep_right) : (i += 1) try tty.writeAll(Ansi.box_horizontal);
    try tty.writeAll(Ansi.box_tee_left);
    try tty.writeAll("\n");

    // Content area
    const content_height: usize = if (app_state.height > 10) app_state.height - 10 else 5;
    var row: usize = 0;
    while (row < content_height) : (row += 1) {
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll("  ");
        try tty.writeAll(Ansi.bright_black);
        try tty.writeAll("(Log output will appear here)");
        try tty.writeAll(Ansi.clear_eol);
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll("\n");
    }

    try renderFooter(app_state, tty);
}

// ============================================================================
// Help View
// ============================================================================

fn renderHelp(app_state: *AppState, tty: anytype) !void {
    // Header
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll(Ansi.bright_black);
    try tty.writeAll(" ");
    try tty.writeAll(Ansi.bright_yellow);
    try tty.writeAll(Ansi.bold);
    try tty.writeAll("KEYBOARD SHORTCUTS");
    try tty.writeAll(Ansi.reset);
    try tty.writeAll(" ");
    try tty.writeAll(Ansi.bright_black);
    const pad: usize = if (app_state.width > 21) app_state.width - 21 else 0;
    try writeSpaces(tty, pad);
    try tty.writeAll(Ansi.box_vertical);
    try tty.writeAll("\n");

    // Separator
    try tty.writeAll(Ansi.box_tee_right);
    var i: usize = 0;
    while (i < 19) : (i += 1) try tty.writeAll(Ansi.box_horizontal);
    try tty.writeAll(Ansi.box_cross);
    const sep_right: usize = if (app_state.width > 23) app_state.width - 23 else 0;
    i = 0;
    while (i < sep_right) : (i += 1) try tty.writeAll(Ansi.box_horizontal);
    try tty.writeAll(Ansi.box_tee_left);
    try tty.writeAll("\n");

    const shortcuts = &[_]struct { key: []const u8, desc: []const u8 }{
        .{ .key = "q / Ctrl+C", .desc = "Quit application" },
        .{ .key = "1", .desc = "Dashboard view" },
        .{ .key = "2", .desc = "Logs view" },
        .{ .key = "?", .desc = "Show this help" },
        .{ .key = "↑ / k", .desc = "Move selection up" },
        .{ .key = "↓ / j", .desc = "Move selection down" },
        .{ .key = "g", .desc = "Go to first provider" },
        .{ .key = "G", .desc = "Go to last provider" },
        .{ .key = "Enter / Space", .desc = "Toggle provider enabled/disabled" },
        .{ .key = "r", .desc = "Refresh health checks" },
        .{ .key = "l", .desc = "Toggle request logging" },
        .{ .key = "Esc", .desc = "Back to dashboard / dismiss dialog" },
    };

    for (shortcuts) |sc| {
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll("  ");
        try tty.writeAll(Ansi.bold);
        try tty.writeAll(Ansi.bright_cyan);
        try writePadded(tty, sc.key, 16);
        try tty.writeAll(Ansi.reset);
        try tty.writeAll("  ");
        try tty.writeAll(Ansi.bright_white);
        try tty.writeAll(sc.desc);
        try tty.writeAll(Ansi.clear_eol);
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll("\n");
    }

    // Fill remaining space
    const content_height: usize = if (app_state.height > 10) app_state.height - 10 else 5;
    const used_rows = shortcuts.len;
    var row: usize = used_rows;
    while (row < content_height) : (row += 1) {
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll(Ansi.clear_eol);
        try tty.writeAll(Ansi.box_vertical);
        try tty.writeAll("\n");
    }

    try renderFooter(app_state, tty);
}

// ============================================================================
// Dialog Overlay
// ============================================================================

fn renderDialogOverlay(app_state: *AppState, tty: anytype) !void {
    const dlg = app_state.dialog orelse return;

    // Calculate dialog dimensions
    const dlg_width: u16 = @min(60, app_state.width - 4);
    const dlg_height: u16 = 7;
    const start_row: u16 = @divTrunc(app_state.height - dlg_height, 2);
    const start_col: u16 = @divTrunc(app_state.width - dlg_width, 2);

    // Move cursor to dialog position
    var pos_buf: [32]u8 = undefined;
    try tty.writeAll(std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ start_row, start_col }) catch "");

    // Top border (double line)
    try tty.writeAll(Ansi.bright_white);
    try tty.writeAll(Ansi.dbox_top_left);
    var i: usize = 0;
    while (i < dlg_width - 2) : (i += 1) try tty.writeAll(Ansi.dbox_horizontal);
    try tty.writeAll(Ansi.dbox_top_right);

    // Title row
    try tty.writeAll(std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ start_row + 1, start_col }) catch "");
    try tty.writeAll(Ansi.dbox_vertical);
    try tty.writeAll(Ansi.bold);
    try tty.writeAll(Ansi.bright_yellow);
    try tty.writeAll(" ");
    try tty.writeAll(dlg.title);
    try tty.writeAll(" ");
    try tty.writeAll(Ansi.reset);
    try tty.writeAll(Ansi.bright_white);
    const title_fill = if (dlg_width > 4 + dlg.title.len) dlg_width - 4 - dlg.title.len else 0;
    var j: usize = 0;
    while (j < title_fill) : (j += 1) try tty.writeAll(" ");
    try tty.writeAll(Ansi.dbox_vertical);

    // Separator
    try tty.writeAll(std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ start_row + 2, start_col }) catch "");
    try tty.writeAll(Ansi.dbox_vertical);
    j = 0;
    while (j < dlg_width - 2) : (j += 1) try tty.writeAll(Ansi.box_horizontal);
    try tty.writeAll(Ansi.dbox_vertical);

    // Message row
    try tty.writeAll(std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ start_row + 3, start_col }) catch "");
    try tty.writeAll(Ansi.dbox_vertical);
    try tty.writeAll(" ");
    try tty.writeAll(Ansi.bright_white);
    try tty.writeAll(dlg.message);
    try tty.writeAll(Ansi.reset);
    try tty.writeAll(Ansi.bright_white);
    const msg_fill = if (dlg_width > 4 + dlg.message.len) dlg_width - 4 - dlg.message.len else 0;
    j = 0;
    while (j < msg_fill) : (j += 1) try tty.writeAll(" ");
    try tty.writeAll(Ansi.dbox_vertical);

    // Empty row
    try tty.writeAll(std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ start_row + 4, start_col }) catch "");
    try tty.writeAll(Ansi.dbox_vertical);
    j = 0;
    while (j < dlg_width - 2) : (j += 1) try tty.writeAll(" ");
    try tty.writeAll(Ansi.dbox_vertical);

    // Buttons row
    try tty.writeAll(std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ start_row + 5, start_col }) catch "");
    try tty.writeAll(Ansi.dbox_vertical);
    try tty.writeAll("  ");
    try tty.writeAll(Ansi.bold);
    try tty.writeAll(Ansi.bright_green);
    try tty.writeAll("[");
    try tty.writeAll(dlg.confirm_label);
    try tty.writeAll("]");
    try tty.writeAll(Ansi.reset);
    try tty.writeAll(Ansi.bright_white);
    try tty.writeAll("  ");
    try tty.writeAll(Ansi.bold);
    try tty.writeAll(Ansi.bright_red);
    try tty.writeAll("[");
    try tty.writeAll(dlg.cancel_label);
    try tty.writeAll("]");
    try tty.writeAll(Ansi.reset);
    try tty.writeAll(Ansi.bright_white);
    const btn_fill = if (dlg_width > 10 + dlg.confirm_label.len + dlg.cancel_label.len) dlg_width - 10 - dlg.confirm_label.len - dlg.cancel_label.len else 0;
    j = 0;
    while (j < btn_fill) : (j += 1) try tty.writeAll(" ");
    try tty.writeAll(Ansi.dbox_vertical);

    // Bottom border
    try tty.writeAll(std.fmt.bufPrint(&pos_buf, "\x1b[{d};{d}H", .{ start_row + 6, start_col }) catch "");
    try tty.writeAll(Ansi.dbox_bottom_left);
    j = 0;
    while (j < dlg_width - 2) : (j += 1) try tty.writeAll(Ansi.dbox_horizontal);
    try tty.writeAll(Ansi.dbox_bottom_right);
    try tty.writeAll(Ansi.reset);
}
