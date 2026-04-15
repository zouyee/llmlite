//! Utils - Utility Functions

const std = @import("std");

pub fn commandExists(name: []const u8) bool {
    var child = std.process.Child.init(&.{ "which", name }, std.heap.page_allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = child.wait() catch return false;
    return term == .Exited and term.Exited == 0;
}

pub fn resolveCommand(name: []const u8) ?[]const u8 {
    var child = std.process.Child.init(&.{ "which", name }, std.heap.page_allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = child.wait() catch return null;

    if (term != .Exited or term.Exited != 0) return null;
    return name;
}

pub const PackageManager = enum {
    npm,
    pnpm,
    yarn,
    bun,
    pip,
    poetry,
    cargo,
    unknown,
};

pub fn detectPackageManager() PackageManager {
    if (fileExists("pnpm-lock.yaml")) return .pnpm;
    if (fileExists("yarn.lock")) return .yarn;
    if (fileExists("bun.lockb")) return .bun;
    if (fileExists("package-lock.json")) return .npm;
    if (fileExists("Pipfile.lock")) return .poetry;
    if (fileExists("requirements.txt")) return .pip;
    if (fileExists("Cargo.lock")) return .cargo;
    return .unknown;
}

pub fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn truncate(allocator: std.mem.Allocator, s: []const u8, max_len: usize) ![]const u8 {
    if (s.len <= max_len) return allocator.dupe(u8, s);

    const truncated_len = if (max_len > 3) max_len - 3 else max_len;
    const result = try allocator.alloc(u8, max_len);
    @memcpy(result[0..truncated_len], s[0..truncated_len]);
    @memcpy(result[truncated_len..], "...");

    return result;
}

pub fn stripAnsi(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var i: usize = 0;

    while (i < text.len) {
        if (text[i] == '\x1b') {
            i += 1;
            while (i < text.len and text[i] != 'm') {
                i += 1;
            }
            i += 1;
            continue;
        }
        try result.append(text[i]);
        i += 1;
    }

    return result.toOwnedSlice();
}

pub fn countTokens(text: []const u8) usize {
    if (text.len == 0) return 0;
    return @intFromFloat(@ceil(@as(f64, @floatFromInt(text.len)) / 4.0));
}

pub fn formatBytes(allocator: std.mem.Allocator, bytes: u64) ![]const u8 {
    const units = &[_][]const u8{ "B", "KB", "MB", "GB", "TB" };
    var value: f64 = @as(f64, @floatFromInt(bytes));
    var unit_idx: usize = 0;

    while (value >= 1024 and unit_idx < units.len - 1) {
        value /= 1024;
        unit_idx += 1;
    }

    if (unit_idx == 0) {
        return std.fmt.allocPrint(allocator, "{d} {s}", .{ @as(u64, @intFromFloat(value)), units[unit_idx] });
    } else {
        return std.fmt.allocPrint(allocator, "{d:.1} {s}", .{ value, units[unit_idx] });
    }
}

pub fn isCI() bool {
    _ = std.process.getEnvVarOwned(std.heap.page_allocator, "CI") catch return false;
    return true;
}

/// Format a token count with K/M suffixes for readability.
/// Examples: 1_234_567 -> "1.2M", 59_234 -> "59.2K", 694 -> "694"
pub fn formatTokens(allocator: std.mem.Allocator, n: usize) ![]const u8 {
    if (n >= 1_000_000) {
        return std.fmt.allocPrint(allocator, "{d:.1}M", .{@as(f64, @floatFromInt(n)) / 1_000_000.0});
    } else if (n >= 1_000) {
        return std.fmt.allocPrint(allocator, "{d:.1}K", .{@as(f64, @floatFromInt(n)) / 1_000.0});
    } else {
        return std.fmt.allocPrint(allocator, "{d}", .{n});
    }
}

/// Format USD amount with adaptive precision.
/// Examples: 1234.567 -> "$1234.57", 0.0096 -> "$0.0096"
pub fn formatUsd(allocator: std.mem.Allocator, amount: f64) ![]const u8 {
    if (!std.math.isFinite(amount)) {
        return allocator.dupe(u8, "$0.00");
    }
    if (amount >= 0.01) {
        return std.fmt.allocPrint(allocator, "${d:.2}", .{amount});
    } else {
        return std.fmt.allocPrint(allocator, "${d:.4}", .{amount});
    }
}

/// Format cost-per-token as $/MTok (e.g., "$3.86/MTok")
pub fn formatCpt(allocator: std.mem.Allocator, cpt: f64) ![]const u8 {
    if (!std.math.isFinite(cpt) or cpt <= 0.0) {
        return allocator.dupe(u8, "$0.00/MTok");
    }
    const cpt_per_million = cpt * 1_000_000.0;
    return std.fmt.allocPrint(allocator, "${d:.2}/MTok", .{cpt_per_million});
}

/// Format an ok confirmation message.
/// Examples: ("merged", "#42") -> "ok merged #42", ("commented", "") -> "ok commented"
pub fn okConfirmation(allocator: std.mem.Allocator, action: []const u8, detail: []const u8) ![]const u8 {
    if (detail.len == 0) {
        return std.fmt.allocPrint(allocator, "ok {s}", .{action});
    } else {
        return std.fmt.allocPrint(allocator, "ok {s} {s}", .{ action, detail });
    }
}
