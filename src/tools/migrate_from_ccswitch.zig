const std = @import("std");
const fs = std.fs;

pub const MigrationResult = struct {
    providers_imported: u32,
    mcp_servers_imported: u32,
    prompts_imported: u32,
    skills_imported: u32,
    errors: [][]const u8,
};

pub const Migrator = struct {
    allocator: std.mem.Allocator,
    errors: std.array_list.Managed([]const u8),

    pub fn init(allocator: std.mem.Allocator) Migrator {
        return .{
            .allocator = allocator,
            .errors = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Migrator) void {
        for (self.errors.items) |err| {
            self.allocator.free(err);
        }
        self.errors.deinit();
    }

    pub fn migrateFromCcSwitchDir(self: *Migrator, cc_switch_dir: []const u8, output_dir: []const u8) !MigrationResult {
        var result = MigrationResult{
            .providers_imported = 0,
            .mcp_servers_imported = 0,
            .prompts_imported = 0,
            .skills_imported = 0,
            .errors = &.{},
        };

        try self.ensureOutputDir(output_dir);
        try self.migrateProviders(cc_switch_dir, output_dir, &result);
        try self.migrateMcpServers(cc_switch_dir, output_dir, &result);
        try self.migratePrompts(cc_switch_dir, output_dir, &result);
        try self.migrateSkills(cc_switch_dir, output_dir, &result);

        result.errors = try self.errors.toOwnedSlice();
        return result;
    }

    fn ensureOutputDir(self: *Migrator, path: []const u8) !void {
        fs.makeDirAbsolute(path) catch {};
        _ = self;
    }

    fn migrateProviders(self: *Migrator, src_dir: []const u8, dest_dir: []const u8, result: *MigrationResult) !void {
        const tools = [_][]const u8{ "claude", "codex", "gemini", "opencode", "openclaw" };
        for (tools) |tool| {
            const src_path = try std.fmt.allocPrint(self.allocator, "{s}/providers_{s}.json", .{ src_dir, tool });
            defer self.allocator.free(src_path);

            const dest_path = try std.fmt.allocPrint(self.allocator, "{s}/providers_{s}.json", .{ dest_dir, tool });
            defer self.allocator.free(dest_path);

            const file = fs.openFileAbsolute(src_path, .{}) catch continue;
            defer file.close();

            const content = file.readToEndAlloc(self.allocator, 1_000_000) catch continue;
            defer self.allocator.free(content);

            const dest_file = fs.createFileAbsolute(dest_path, .{}) catch {
                try self.errors.append(try std.fmt.allocPrint(self.allocator, "failed to create {s} providers", .{tool}));
                continue;
            };
            defer dest_file.close();

            dest_file.writeAll(content) catch {
                try self.errors.append(try std.fmt.allocPrint(self.allocator, "failed to write {s} providers", .{tool}));
                continue;
            };
            result.providers_imported += 1;
        }
    }

    fn migrateMcpServers(self: *Migrator, src_dir: []const u8, dest_dir: []const u8, result: *MigrationResult) !void {
        const src_path = try std.fmt.allocPrint(self.allocator, "{s}/mcp_servers.json", .{src_dir});
        defer self.allocator.free(src_path);

        const dest_path = try std.fmt.allocPrint(self.allocator, "{s}/mcp_servers.json", .{dest_dir});
        defer self.allocator.free(dest_path);

        const file = fs.openFileAbsolute(src_path, .{}) catch return;
        defer file.close();

        const content = file.readToEndAlloc(self.allocator, 1_000_000) catch return;
        defer self.allocator.free(content);

        const dest_file = fs.createFileAbsolute(dest_path, .{}) catch {
            try self.errors.append("failed to create mcp_servers file");
            return;
        };
        defer dest_file.close();

        dest_file.writeAll(content) catch {
            try self.errors.append("failed to write mcp_servers");
            return;
        };
        result.mcp_servers_imported = 1;
    }

    fn migratePrompts(self: *Migrator, src_dir: []const u8, dest_dir: []const u8, result: *MigrationResult) !void {
        const tools = [_][]const u8{ "claude", "codex", "gemini" };
        for (tools) |tool| {
            const src_path = try std.fmt.allocPrint(self.allocator, "{s}/prompts_{s}.json", .{ src_dir, tool });
            defer self.allocator.free(src_path);

            const dest_path = try std.fmt.allocPrint(self.allocator, "{s}/prompts_{s}.json", .{ dest_dir, tool });
            defer self.allocator.free(dest_path);

            const file = fs.openFileAbsolute(src_path, .{}) catch continue;
            defer file.close();

            const content = file.readToEndAlloc(self.allocator, 1_000_000) catch continue;
            defer self.allocator.free(content);

            const dest_file = fs.createFileAbsolute(dest_path, .{}) catch {
                try self.errors.append(try std.fmt.allocPrint(self.allocator, "failed to create {s} prompts", .{tool}));
                continue;
            };
            defer dest_file.close();

            dest_file.writeAll(content) catch {
                try self.errors.append(try std.fmt.allocPrint(self.allocator, "failed to write {s} prompts", .{tool}));
                continue;
            };
            result.prompts_imported += 1;
        }
    }

    fn migrateSkills(self: *Migrator, src_dir: []const u8, dest_dir: []const u8, result: *MigrationResult) !void {
        const src_path = try std.fmt.allocPrint(self.allocator, "{s}/skills.json", .{src_dir});
        defer self.allocator.free(src_path);

        const dest_path = try std.fmt.allocPrint(self.allocator, "{s}/skills.json", .{dest_dir});
        defer self.allocator.free(dest_path);

        const file = fs.openFileAbsolute(src_path, .{}) catch return;
        defer file.close();

        const content = file.readToEndAlloc(self.allocator, 1_000_000) catch return;
        defer self.allocator.free(content);

        const dest_file = fs.createFileAbsolute(dest_path, .{}) catch {
            try self.errors.append("failed to create skills file");
            return;
        };
        defer dest_file.close();

        dest_file.writeAll(content) catch {
            try self.errors.append("failed to write skills");
            return;
        };
        result.skills_imported = 1;
    }
};

pub fn migrateFromCcSwitchDir(allocator: std.mem.Allocator, cc_switch_dir: []const u8, output_dir: []const u8) !MigrationResult {
    var migrator = Migrator.init(allocator);
    defer migrator.deinit();
    return try migrator.migrateFromCcSwitchDir(cc_switch_dir, output_dir);
}
