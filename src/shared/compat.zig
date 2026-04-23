//! Compatibility shim for Zig 0.16.0 migration
//!
//! Provides a managed StringArrayHashMap wrapper since the managed version
//! was removed in Zig 0.16.0. This wraps StringArrayHashMapUnmanaged and
//! stores the allocator internally, matching the old API.
//!
//! Also provides compatibility wrappers for removed APIs:
//! - getEnvVarOwned: wraps std.c.getenv to match old std.process.getEnvVarOwned
//! - runProcess: wraps std.process.run for the new (allocator, io, options) signature
//! - fileExists: wraps file access check without io

const std = @import("std");

/// Compat replacement for std.process.getEnvVarOwned (removed in 0.16.0).
/// Uses std.c.getenv and dupes the result into the provided allocator.
pub fn getEnvVarOwned(allocator: std.mem.Allocator, key: [*:0]const u8) error{EnvironmentVariableNotFound, OutOfMemory}![]u8 {
    const ptr = std.c.getenv(key) orelse return error.EnvironmentVariableNotFound;
    const slice = std.mem.sliceTo(ptr, 0);
    return allocator.dupe(u8, slice);
}

/// Compat replacement for std.fs.cwd() (removed in 0.16.0).
/// Returns a Dir that can be used for file operations.
/// Note: In 0.16.0, use std.fs.cwd() is gone. We use openDirAbsolute(".") as fallback.
pub fn cwd() std.fs.Dir {
    return std.fs.Dir{ .fd = std.posix.AT.FDCWD };
}

/// Compat replacement for std.fs.openFileAbsolute (removed in 0.16.0).
pub fn openFileAbsolute(path: []const u8, flags: std.fs.File.OpenFlags) std.fs.File.OpenError!std.fs.File {
    const dir = std.fs.Dir{ .fd = std.posix.AT.FDCWD };
    return dir.openFile(path, flags);
}

/// Compat replacement for std.fs.createFileAbsolute (removed in 0.16.0).
pub fn createFileAbsolute(path: []const u8, flags: std.fs.File.CreateFlags) std.fs.File.OpenError!std.fs.File {
    const dir = std.fs.Dir{ .fd = std.posix.AT.FDCWD };
    return dir.createFile(path, flags);
}

/// Compat replacement for std.fs.makeDirAbsolute (removed in 0.16.0).
pub fn makeDirAbsolute(path: []const u8) std.posix.MakeDirError!void {
    const dir = std.fs.Dir{ .fd = std.posix.AT.FDCWD };
    return dir.makeDir(path);
}

/// Compat replacement for std.fs.deleteFileAbsolute (removed in 0.16.0).
pub fn deleteFileAbsolute(path: []const u8) std.posix.UnlinkError!void {
    const dir = std.fs.Dir{ .fd = std.posix.AT.FDCWD };
    return dir.deleteFile(path);
}

/// Compat replacement for std.fs.openDirAbsolute (removed in 0.16.0).
pub fn openDirAbsolute(path: []const u8, flags: std.fs.Dir.OpenOptions) std.fs.Dir.OpenError!std.fs.Dir {
    const dir = std.fs.Dir{ .fd = std.posix.AT.FDCWD };
    return dir.openDir(path, flags);
}

/// Compat replacement for std.fs.accessAbsolute (removed in 0.16.0).
pub fn accessAbsolute(path: []const u8, flags: std.fs.File.OpenFlags) std.posix.AccessError!void {
    const dir = std.fs.Dir{ .fd = std.posix.AT.FDCWD };
    return dir.access(path, flags);
}

/// Compat replacement for std.fs.renameAbsolute (removed in 0.16.0).
pub fn renameAbsolute(old_path: []const u8, new_path: []const u8) std.posix.RenameError!void {
    const dir = std.fs.Dir{ .fd = std.posix.AT.FDCWD };
    return dir.rename(old_path, new_path);
}

/// Compat replacement for std.fs.deleteTreeAbsolute (removed in 0.16.0).
pub fn deleteTreeAbsolute(path: []const u8) !void {
    const dir = std.fs.Dir{ .fd = std.posix.AT.FDCWD };
    return dir.deleteTree(path);
}

/// Managed StringArrayHashMap - wraps the unmanaged version with an allocator.
/// Drop-in replacement for the removed std.StringArrayHashMap.
pub fn StringArrayHashMap(comptime V: type) type {
    return struct {
        const Self = @This();
        const Unmanaged = std.StringArrayHashMapUnmanaged(V);

        unmanaged: Unmanaged,
        allocator: std.mem.Allocator,

        pub const Entry = Unmanaged.Entry;
        pub const Iterator = Unmanaged.Iterator;

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .unmanaged = .empty,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.unmanaged.deinit(self.allocator);
        }

        pub fn put(self: *Self, key: []const u8, value: V) !void {
            return self.unmanaged.put(self.allocator, key, value);
        }

        pub fn get(self: Self, key: []const u8) ?V {
            return self.unmanaged.get(key);
        }

        pub fn getPtr(self: Self, key: []const u8) ?*V {
            return self.unmanaged.getPtr(key);
        }

        pub fn getEntry(self: Self, key: []const u8) ?Unmanaged.Entry {
            return self.unmanaged.getEntry(key);
        }

        pub fn getOrPut(self: *Self, key: []const u8) !Unmanaged.GetOrPutResult {
            return self.unmanaged.getOrPut(self.allocator, key);
        }

        pub fn getOrPutValue(self: *Self, key: []const u8, value: V) !Unmanaged.GetOrPutResult {
            return self.unmanaged.getOrPutValue(self.allocator, key, value);
        }

        pub fn contains(self: Self, key: []const u8) bool {
            return self.unmanaged.contains(key);
        }

        pub fn count(self: Self) usize {
            return self.unmanaged.count();
        }

        pub fn iterator(self: Self) Iterator {
            return self.unmanaged.iterator();
        }

        pub fn fetchSwapRemove(self: *Self, key: []const u8) ?Unmanaged.KV {
            return self.unmanaged.fetchSwapRemove(key);
        }

        pub fn fetchOrderedRemove(self: *Self, key: []const u8) ?Unmanaged.KV {
            return self.unmanaged.fetchOrderedRemove(key);
        }

        // Legacy alias
        pub fn fetchRemove(self: *Self, key: []const u8) ?Unmanaged.KV {
            return self.unmanaged.fetchSwapRemove(key);
        }

        pub fn swapRemove(self: *Self, key: []const u8) bool {
            return self.unmanaged.swapRemove(key);
        }

        pub fn orderedRemove(self: *Self, key: []const u8) bool {
            return self.unmanaged.orderedRemove(key);
        }

        pub fn keys(self: Self) [][]const u8 {
            return self.unmanaged.keys();
        }

        pub fn values(self: Self) []V {
            return self.unmanaged.values();
        }
    };
}
