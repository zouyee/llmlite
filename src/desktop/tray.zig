const std = @import("std");
const preset = @import("../proxy/preset");

pub const CliTool = preset.CliTool;

pub const TrayIcon = enum {
    normal,
    active,
    warning,
    error_state,
};

pub const TrayMenuItem = struct {
    id: []const u8,
    label: []const u8,
    enabled: bool = true,
};

pub const TrayMenu = struct {
    items: []const TrayMenuItem,
};

pub const TrayStatus = struct {
    icon: TrayIcon,
    tooltip: []const u8,
    menu: ?TrayMenu,
};

pub const TrayManager = struct {
    allocator: std.mem.Allocator,
    status: TrayStatus,
    platform: Platform,
    running: bool,

    pub const Platform = enum {
        macos,
        linux,
        windows,
        unsupported,
    };

    pub fn init(allocator: std.mem.Allocator) TrayManager {
        return .{
            .allocator = allocator,
            .status = .{
                .icon = .normal,
                .tooltip = "llmlite-proxy",
                .menu = null,
            },
            .platform = detectPlatform(),
            .running = false,
        };
    }

    pub fn deinit(self: *TrayManager) void {
        if (self.running) {
            self.stop() catch {};
        }
    }

    fn detectPlatform() Platform {
        if (@import("builtin").os.tag == .macos) return .macos;
        if (@import("builtin").os.tag == .linux) return .linux;
        if (@import("builtin").os.tag == .windows) return .windows;
        return .unsupported;
    }

    pub fn start(self: *TrayManager) !void {
        if (self.platform == .unsupported) {
            std.log.warn("system tray not supported on this platform", .{});
            return;
        }
        self.running = true;
        std.log.info("tray manager started on {s}", .{@tagName(self.platform)});
    }

    pub fn stop(self: *TrayManager) !void {
        self.running = false;
        std.log.info("tray manager stopped", .{});
    }

    pub fn setIcon(self: *TrayManager, icon: TrayIcon) !void {
        self.status.icon = icon;
        try self.update();
    }

    pub fn setTooltip(self: *TrayManager, tooltip: []const u8) !void {
        self.status.tooltip = tooltip;
        try self.update();
    }

    pub fn setMenu(self: *TrayManager, menu: TrayMenu) !void {
        self.status.menu = menu;
        try self.update();
    }

    pub fn update(self: *TrayManager) !void {
        switch (self.platform) {
            .macos => try self.updateMacos(),
            .linux => try self.updateLinux(),
            .windows => try self.updateWindows(),
            .unsupported => {},
        }
    }

    fn updateMacos(self: *TrayManager) !void {
        var script = std.ArrayList(u8).init(self.allocator);
        defer script.deinit();

        try script.appendSlice("display notification \"llmlite-proxy\" with title \"llmlite\"");
        _ = script.items;
    }

    fn updateLinux(_: *TrayManager) !void {
        std.log.debug("linux tray update not fully implemented", .{});
    }

    fn updateWindows(_: *TrayManager) !void {
        std.log.debug("windows tray update not fully implemented", .{});
    }

    pub fn showNotification(self: *TrayManager, title: []const u8, body: []const u8) !void {
        switch (self.platform) {
            .macos => try self.showMacosNotification(title, body),
            .linux => try self.showLinuxNotification(title, body),
            .windows => try self.showWindowsNotification(title, body),
            .unsupported => {},
        }
    }

    fn showMacosNotification(self: *TrayManager, title: []const u8, body: []const u8) !void {
        const script = std.fmt.allocPrint(self.allocator, "display notification \"{s}\" with title \"{s}\"", .{ body, title }) catch return;
        defer self.allocator.free(script);
        var proc = std.process.Child.init(&.{ "osascript", "-e", script }, self.allocator);
        _ = proc.spawnAndWait() catch {};
    }

    fn showLinuxNotification(_: *TrayManager, title: []const u8, body: []const u8) !void {
        var proc = std.process.Child.init(&.{ "notify-send", title, body }, std.heap.page_allocator);
        _ = proc.spawnAndWait() catch {};
    }

    fn showWindowsNotification(_: *TrayManager, _: []const u8, _: []const u8) !void {}
};

pub fn createTrayMenuForProviders(
    allocator: std.mem.Allocator,
    providers: []const []const u8,
    current: ?[]const u8,
) !TrayMenu {
    var items = std.ArrayList(TrayMenuItem).init(allocator);
    defer items.deinit();

    for (providers) |provider| {
        const is_current = current != null and std.mem.eql(u8, current.?, provider);
        try items.append(.{
            .id = provider,
            .label = if (is_current) try std.fmt.allocPrint(allocator, "* {s}", .{provider}) else provider,
            .enabled = true,
        });
    }

    return TrayMenu{
        .items = try items.toOwnedSlice(),
    };
}
