//! Event Loop & Event Handler
//!
//! Pattern from llmfit-tui:
//! - tui_events.rs: sole place that mutates App in the TUI loop
//! - crossterm-style: poll(timeout) then read()
//!
//! Pattern from cc-switch:
//! - Global shortcuts (Escape → back, view switching)
//! - Conditional keybinding hints per view

const std = @import("std");
const builtin = @import("builtin");
const app = @import("app.zig");
const input = @import("input.zig");

const AppState = app.AppState;
const View = app.View;
const InputMode = app.InputMode;
const KeyEvent = input.KeyEvent;

// Terminal resize support
var g_resize_pending: std.atomic.Value(bool) = .init(false);

const SigType = if (builtin.os.tag == .windows) c_int else std.posix.SIG;
pub fn handleSigwinch(_: SigType) callconv(.c) void {
    g_resize_pending.store(true, .monotonic);
}

/// Check if terminal resize is pending and clear the flag
pub fn checkResize() bool {
    return g_resize_pending.swap(false, .monotonic);
}

// ============================================================================
// Event Loop
// ============================================================================

/// Run the main event loop.
///
/// Pattern: poll stdin for 100ms → if ready, read bytes → parse keys → handle.
/// This avoids the busy-wait of the old implementation and properly handles
/// raw mode input on macOS.
pub fn run(app_state: *AppState, tty: anytype) !void {
    if (builtin.os.tag == .windows) {
        return error.NotSupported;
    }

    var leftover_buf: [32]u8 = undefined;
    var leftover_len: usize = 0;

    while (app_state.isRunning()) {
        // 1. Check terminal resize
        if (checkResize()) {
            app_state.detectSize();
            app_state.markRefresh();
        }

        // 2. Render if needed
        if (app_state.should_refresh) {
            try render_mod.render(app_state, tty);
        }

        // 3. Poll stdin with 100ms timeout
        var fds = [_]std.posix.pollfd{
            .{ .fd = std.posix.STDIN_FILENO, .events = std.posix.POLL.IN, .revents = 0 },
        };
        const ready = std.posix.poll(&fds, 100) catch |err| {
            std.log.err("poll error: {}", .{err});
            continue;
        };

        if (ready > 0 and (fds[0].revents & std.posix.POLL.IN) != 0) {
            // Build read buffer: leftover from previous incomplete sequence + new space
            var buf: [64]u8 = undefined;
            @memcpy(buf[0..leftover_len], leftover_buf[0..leftover_len]);

            const max_read = buf.len - leftover_len;
            const n = std.posix.read(std.posix.STDIN_FILENO, buf[leftover_len..][0..max_read]) catch |err| {
                std.log.err("read error: {}", .{err});
                leftover_len = 0;
                continue;
            };

            if (n == 0) continue;

            const total = leftover_len + n;
            var offset: usize = 0;

            while (offset < total) {
                const result = input.parseKey(buf[offset..total]);
                if (result.event) |evt| {
                    try handle(app_state, evt);
                    offset += result.consumed;
                } else {
                    // Incomplete sequence - save for next iteration
                    const remaining = total - offset;
                    if (remaining <= leftover_buf.len) {
                        @memcpy(leftover_buf[0..remaining], buf[offset..total]);
                        leftover_len = remaining;
                    } else {
                        leftover_len = 0; // Buffer overflow, discard
                    }
                    break;
                }
            }

            // If we consumed everything, clear leftover
            if (offset >= total) {
                leftover_len = 0;
            }
        }
    }
}

const render_mod = @import("render.zig");

// ============================================================================
// Event Handler - Sole place that mutates AppState
// ============================================================================

pub fn handle(app_state: *AppState, event: KeyEvent) !void {
    // Global shortcuts first
    if (try handleGlobal(app_state, event)) return;

    // Mode-specific handling
    switch (app_state.input_mode) {
        .normal => try handleNormal(app_state, event),
        .confirm => try handleConfirm(app_state, event),
    }
}

/// Global shortcuts active in all modes (except dialogs intercept first).
/// Returns true if event was consumed.
fn handleGlobal(app_state: *AppState, event: KeyEvent) !bool {
    switch (event) {
        .ctrl_c, .ctrl_d => {
            app_state.stop();
            return true;
        },
        .char => |c| {
            switch (c) {
                'q', 'Q' => {
                    app_state.stop();
                    return true;
                },
                '1' => {
                    app_state.switchView(.dashboard);
                    return true;
                },
                '2' => {
                    app_state.switchView(.logs);
                    return true;
                },
                else => {},
            }
        },
        else => {},
    }
    return false;
}

/// Normal mode: navigation, actions, view-specific shortcuts
fn handleNormal(app_state: *AppState, event: KeyEvent) !void {
    switch (app_state.current_view) {
        .dashboard => try handleDashboard(app_state, event),
        .logs => try handleLogs(app_state, event),
        .help => {
            // Any key exits help
            app_state.switchView(.dashboard);
        },
    }
}

/// Dashboard view input handling
fn handleDashboard(app_state: *AppState, event: KeyEvent) !void {
    switch (event) {
        .char => |c| {
            switch (c) {
                '?' => app_state.switchView(.help),
                'r', 'R' => {
                    if (app_state.refresh_callback) |cb| {
                        cb(app_state.refresh_context);
                    }
                    app_state.markRefresh();
                },
                'l', 'L' => {
                    app_state.logging_enabled = !app_state.logging_enabled;
                    if (app_state.logger_toggle_callback) |cb| {
                        cb(app_state.logger_toggle_context, app_state.logging_enabled);
                    }
                    std.log.info("Logging {s}", .{if (app_state.logging_enabled) "enabled" else "disabled"});
                    app_state.markRefresh();
                },
                'j', 'J' => {
                    if (app_state.selected_index < app_state.providers.len - 1) {
                        app_state.selected_index += 1;
                        app_state.markRefresh();
                    }
                },
                'k', 'K' => {
                    if (app_state.selected_index > 0) {
                        app_state.selected_index -= 1;
                        app_state.markRefresh();
                    }
                },
                'g' => {
                    app_state.selected_index = 0;
                    app_state.markRefresh();
                },
                'G' => {
                    app_state.selected_index = app_state.providers.len - 1;
                    app_state.markRefresh();
                },
                ' ' => {
                    // Toggle provider enabled/disabled
                    if (app_state.selected_index < app_state.enabled_providers.len) {
                        app_state.enabled_providers[app_state.selected_index] = !app_state.enabled_providers[app_state.selected_index];
                        const provider_name = app_state.providers[app_state.selected_index].toString();
                        const state = if (app_state.enabled_providers[app_state.selected_index]) "enabled" else "disabled";
                        std.log.info("Provider '{s}' {s}", .{ provider_name, state });
                        app_state.markRefresh();
                    }
                },
                else => {},
            }
        },
        .arrow_up => {
            if (app_state.selected_index > 0) {
                app_state.selected_index -= 1;
                app_state.markRefresh();
            }
        },
        .arrow_down => {
            if (app_state.selected_index < app_state.providers.len - 1) {
                app_state.selected_index += 1;
                app_state.markRefresh();
            }
        },
        .home => {
            app_state.selected_index = 0;
            app_state.markRefresh();
        },
        .end => {
            app_state.selected_index = app_state.providers.len - 1;
            app_state.markRefresh();
        },
        .enter => {
            // Toggle provider
            if (app_state.selected_index < app_state.enabled_providers.len) {
                app_state.enabled_providers[app_state.selected_index] = !app_state.enabled_providers[app_state.selected_index];
                const provider_name = app_state.providers[app_state.selected_index].toString();
                const state = if (app_state.enabled_providers[app_state.selected_index]) "enabled" else "disabled";
                std.log.info("Provider '{s}' {s}", .{ provider_name, state });
                app_state.markRefresh();
            }
        },
        .escape => {
            // Escape in dashboard does nothing (no dialog to close)
        },
        else => {},
    }
}

/// Logs view input handling
fn handleLogs(app_state: *AppState, event: KeyEvent) !void {
    switch (event) {
        .char => |c| {
            switch (c) {
                '?' => app_state.switchView(.help),
                'r', 'R' => app_state.markRefresh(),
                'j', 'J' => {}, // Scroll down (placeholder)
                'k', 'K' => {}, // Scroll up (placeholder)
                else => {},
            }
        },
        .arrow_up => {}, // Scroll up (placeholder)
        .arrow_down => {}, // Scroll down (placeholder)
        .escape => app_state.switchView(.dashboard),
        else => {},
    }
}

/// Confirm dialog input handling
fn handleConfirm(app_state: *AppState, event: KeyEvent) !void {
    const dlg = app_state.dialog orelse {
        app_state.dismissDialog();
        return;
    };

    switch (event) {
        .char => |c| {
            if (c == 'y' or c == 'Y') {
                dlg.on_confirm(app_state);
                app_state.dismissDialog();
            } else if (c == 'n' or c == 'N' or c == 'q') {
                dlg.on_cancel(app_state);
                app_state.dismissDialog();
            }
        },
        .enter => {
            dlg.on_confirm(app_state);
            app_state.dismissDialog();
        },
        .escape => {
            dlg.on_cancel(app_state);
            app_state.dismissDialog();
        },
        else => {},
    }
}
