//! Tee - Failure Recovery

const std = @import("std");

pub const Tee = struct {
    allocator: std.mem.Allocator,
    directory: []const u8,
    max_files: usize = 20,

    pub fn init(allocator: std.mem.Allocator) !Tee {
        const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch {
            return Tee{
                .allocator = allocator,
                .directory = try allocator.dupe(u8, "/tmp/llmlite_tee"),
            };
        };
        defer allocator.free(home_dir);

        const tee_dir = try std.fmt.allocPrint(allocator, "{s}/.local/share/llmlite/tee", .{home_dir});
        errdefer allocator.free(tee_dir);

        std.fs.makeDirAbsolute(tee_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        return Tee{
            .allocator = allocator,
            .directory = tee_dir,
        };
    }

    pub fn deinit(self: *Tee) void {
        self.allocator.free(self.directory);
    }

    pub fn save(self: *Tee, label: []const u8, args: []const u8, output: []const u8) ![]const u8 {
        const timestamp = std.time.timestamp();
        const sanitized_label = try std.mem.replaceOwned(u8, self.allocator, label, "/", "_");
        defer self.allocator.free(sanitized_label);

        const filename = try std.fmt.allocPrint(self.allocator, "{d}_{s}.log", .{ timestamp, sanitized_label });
        defer self.allocator.free(filename);

        const filepath = try std.fs.path.join(self.allocator, &.{ self.directory, filename });
        errdefer self.allocator.free(filepath);

        const file = try std.fs.createFileAbsolute(filepath, .{});
        defer file.close();

        try file.writeAll(output);
        try file.writeAll("\n--- LLMLITE METADATA ---\n");

        const metadata = try std.fmt.allocPrint(self.allocator, "label: {s}\nargs: {s}\ntimestamp: {d}\n", .{
            label,
            args,
            timestamp,
        });
        defer self.allocator.free(metadata);
        try file.writeAll(metadata);

        self.rotate() catch {};

        std.log.info("tee saved: {s}", .{filepath});
        return filepath;
    }

    fn rotate(self: *Tee) !void {
        var dir = try std.fs.openDirAbsolute(self.directory, .{});
        defer dir.close();

        const FileEntry = struct { name: []const u8, mtime: i128 };
        var entries = std.array_list.Managed(FileEntry).init(self.allocator);
        defer {
            for (entries.items) |e| self.allocator.free(e.name);
            entries.deinit();
        }

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".log")) continue;

            const full_path = try std.fs.path.join(self.allocator, &.{ self.directory, entry.name });
            defer self.allocator.free(full_path);

            const file = try std.fs.openFileAbsolute(full_path, .{});
            defer file.close();
            const stat = try file.stat();
            try entries.append(.{
                .name = try self.allocator.dupe(u8, entry.name),
                .mtime = stat.mtime,
            });
        }

        std.sort.heap(FileEntry, entries.items, {}, struct {
            fn less(_: void, a: FileEntry, b: FileEntry) bool {
                return a.mtime > b.mtime;
            }
        }.less);

        if (entries.items.len > self.max_files) {
            for (entries.items[self.max_files..]) |entry| {
                const full_path = try std.fs.path.join(self.allocator, &.{ self.directory, entry.name });
                defer self.allocator.free(full_path);

                std.fs.deleteFileAbsolute(full_path) catch {};
            }
        }
    }
};

var global_tee: ?*Tee = null;

pub fn init(allocator: std.mem.Allocator) !void {
    if (global_tee != null) return;
    const tee = try allocator.create(Tee);
    errdefer allocator.destroy(tee);
    tee.* = try Tee.init(allocator);
    global_tee = tee;
}

pub fn deinit() void {
    if (global_tee) |tee| {
        tee.deinit();
        tee.allocator.destroy(tee);
        global_tee = null;
    }
}

pub fn save(label: []const u8, args: []const u8, output: []const u8) !?[]const u8 {
    if (global_tee) |tee| {
        return try tee.save(label, args, output);
    }
    return null;
}
