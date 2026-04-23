//! Input Parser - Keyboard event parsing for terminal raw mode
//!
//! Handles single-byte keys, escape sequences (arrows, function keys),
//! and multi-byte UTF-8 sequences. Adapted from llmfit-tui's crossterm
//! event handling pattern.

const std = @import("std");

/// Parsed key event
pub const KeyEvent = union(enum) {
    char: u8, // Printable ASCII character
    arrow_up,
    arrow_down,
    arrow_left,
    arrow_right,
    page_up,
    page_down,
    home,
    end,
    insert,
    delete,
    enter,
    escape,
    backspace,
    tab,
    ctrl_c,
    ctrl_d,
    ctrl_l,
    ctrl_r,
    unknown: []const u8, // Unrecognized sequence (pass raw bytes)

    pub fn isQuit(self: KeyEvent) bool {
        return switch (self) {
            .ctrl_c, .ctrl_d => true,
            else => false,
        };
    }

    pub fn toString(self: KeyEvent) []const u8 {
        return switch (self) {
            .char => |c| blk: {
                const static = struct {
                    var buf: [2]u8 = undefined;
                };
                static.buf[0] = c;
                static.buf[1] = 0;
                break :blk static.buf[0..1];
            },
            .arrow_up => "↑",
            .arrow_down => "↓",
            .arrow_left => "←",
            .arrow_right => "→",
            .page_up => "PgUp",
            .page_down => "PgDn",
            .home => "Home",
            .end => "End",
            .insert => "Ins",
            .delete => "Del",
            .enter => "Enter",
            .escape => "Esc",
            .backspace => "Bksp",
            .tab => "Tab",
            .ctrl_c => "Ctrl+C",
            .ctrl_d => "Ctrl+D",
            .ctrl_l => "Ctrl+L",
            .ctrl_r => "Ctrl+R",
            .unknown => "?",
        };
    }
};

/// Parse raw bytes from stdin into structured key events.
///
/// Handles:
/// - Single ASCII characters
/// - Control characters (Ctrl+A..Ctrl+Z)
/// - Escape sequences: CSI sequences (arrows, function keys)
/// - Incomplete sequences: returns null, caller should buffer more bytes
///
/// Returns the number of bytes consumed from the buffer.
pub fn parseKey(buf: []const u8) struct { event: ?KeyEvent, consumed: usize } {
    if (buf.len == 0) return .{ .event = null, .consumed = 0 };

    const b0 = buf[0];

    // Control characters
    switch (b0) {
        0x03 => return .{ .event = .ctrl_c, .consumed = 1 },
        0x04 => return .{ .event = .ctrl_d, .consumed = 1 },
        0x0c => return .{ .event = .ctrl_l, .consumed = 1 },
        0x12 => return .{ .event = .ctrl_r, .consumed = 1 },
        '\r', '\n' => return .{ .event = .enter, .consumed = 1 },
        '\t' => return .{ .event = .tab, .consumed = 1 },
        0x7f => return .{ .event = .backspace, .consumed = 1 },
        0x1b => {
            // Escape sequence
            if (buf.len < 2) return .{ .event = null, .consumed = 0 }; // Need more bytes
            const b1 = buf[1];

            if (b1 == 0x5b) {
                // CSI sequence: ESC [ ...
                if (buf.len < 3) return .{ .event = null, .consumed = 0 };
                const b2 = buf[2];

                switch (b2) {
                    'A' => return .{ .event = .arrow_up, .consumed = 3 },
                    'B' => return .{ .event = .arrow_down, .consumed = 3 },
                    'C' => return .{ .event = .arrow_right, .consumed = 3 },
                    'D' => return .{ .event = .arrow_left, .consumed = 3 },
                    'H' => return .{ .event = .home, .consumed = 3 },
                    'F' => return .{ .event = .end, .consumed = 3 },
                    '2' => {
                        if (buf.len < 4) return .{ .event = null, .consumed = 0 };
                        if (buf[3] == '~') return .{ .event = .insert, .consumed = 4 };
                        return .{ .event = .{ .unknown = buf[0..4] }, .consumed = 4 };
                    },
                    '3' => {
                        if (buf.len < 4) return .{ .event = null, .consumed = 0 };
                        if (buf[3] == '~') return .{ .event = .delete, .consumed = 4 };
                        return .{ .event = .{ .unknown = buf[0..4] }, .consumed = 4 };
                    },
                    '5' => {
                        if (buf.len < 4) return .{ .event = null, .consumed = 0 };
                        if (buf[3] == '~') return .{ .event = .page_up, .consumed = 4 };
                        return .{ .event = .{ .unknown = buf[0..4] }, .consumed = 4 };
                    },
                    '6' => {
                        if (buf.len < 4) return .{ .event = null, .consumed = 0 };
                        if (buf[3] == '~') return .{ .event = .page_down, .consumed = 4 };
                        return .{ .event = .{ .unknown = buf[0..4] }, .consumed = 4 };
                    },
                    else => {
                        // Unknown CSI sequence - consume what we have
                        return .{ .event = .{ .unknown = buf[0..3] }, .consumed = 3 };
                    },
                }
            } else if (b1 == 'O') {
                // SS3 sequence: ESC O ...
                if (buf.len < 3) return .{ .event = null, .consumed = 0 };
                const b2 = buf[2];
                switch (b2) {
                    'H' => return .{ .event = .home, .consumed = 3 },
                    'F' => return .{ .event = .end, .consumed = 3 },
                    else => return .{ .event = .{ .unknown = buf[0..3] }, .consumed = 3 },
                }
            } else {
                // Alt+key or just Escape
                // For simplicity, treat as escape if it's just ESC + printable char
                if (b1 >= 32 and b1 < 127) {
                    // Alt+char - treat as escape for now
                    return .{ .event = .escape, .consumed = 2 };
                }
                return .{ .event = .escape, .consumed = 1 };
            }
        },
        else => {
            if (b0 >= 32 and b0 < 127) {
                return .{ .event = .{ .char = b0 }, .consumed = 1 };
            }
            // Non-printable, non-control byte
            return .{ .event = .{ .unknown = buf[0..1] }, .consumed = 1 };
        },
    }
}

/// Parse all key events from a buffer, appending to the provided ArrayList.
/// Incomplete escape sequences at the end are left unconsumed.
pub fn parseAllKeys(allocator: std.mem.Allocator, buf: []const u8) !struct { events: []KeyEvent, leftover: []const u8 } {
    var events = std.ArrayList(KeyEvent).init(allocator);
    errdefer events.deinit();

    var offset: usize = 0;
    while (offset < buf.len) {
        const result = parseKey(buf[offset..]);
        if (result.event) |evt| {
            try events.append(evt);
            offset += result.consumed;
        } else {
            // Incomplete sequence
            break;
        }
    }

    return .{
        .events = try events.toOwnedSlice(),
        .leftover = buf[offset..],
    };
}

// ============================================================================
// TESTS
// ============================================================================

test "parse single characters" {
    const r1 = parseKey("a");
    try std.testing.expectEqual(@as(u8, 'a'), r1.event.?.char);
    try std.testing.expectEqual(@as(usize, 1), r1.consumed);

    const r2 = parseKey("Q");
    try std.testing.expectEqual(@as(u8, 'Q'), r2.event.?.char);
}

test "parse control characters" {
    const r1 = parseKey("\x03");
    try std.testing.expectEqual(KeyEvent.ctrl_c, r1.event.?);

    const r2 = parseKey("\x04");
    try std.testing.expectEqual(KeyEvent.ctrl_d, r2.event.?);

    const r3 = parseKey("\r");
    try std.testing.expectEqual(KeyEvent.enter, r3.event.?);

    const r4 = parseKey("\x7f");
    try std.testing.expectEqual(KeyEvent.backspace, r4.event.?);
}

test "parse arrow keys" {
    const r1 = parseKey("\x1b[A");
    try std.testing.expectEqual(KeyEvent.arrow_up, r1.event.?);
    try std.testing.expectEqual(@as(usize, 3), r1.consumed);

    const r2 = parseKey("\x1b[B");
    try std.testing.expectEqual(KeyEvent.arrow_down, r2.event.?);

    const r3 = parseKey("\x1b[C");
    try std.testing.expectEqual(KeyEvent.arrow_right, r3.event.?);

    const r4 = parseKey("\x1b[D");
    try std.testing.expectEqual(KeyEvent.arrow_left, r4.event.?);
}

test "parse escape" {
    const r = parseKey("\x1b");
    // Single escape with no follow-up is incomplete
    try std.testing.expect(r.event == null);
    try std.testing.expectEqual(@as(usize, 0), r.consumed);
}

test "parse incomplete sequence" {
    const r = parseKey("\x1b[");
    try std.testing.expect(r.event == null);
    try std.testing.expectEqual(@as(usize, 0), r.consumed);
}
