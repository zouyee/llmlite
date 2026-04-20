const std = @import("std");

pub const VirtualKey = struct {
    id: []const u8,
    key_hash: []const u8,
    user_id: ?[]const u8,
    team_id: ?[]const u8,
    rate_limit: ?u32,
    allowed_models: ?[][]const u8,
    allowed_providers: ?[]const u8,
    created_at: i64,
    expires_at: ?i64,
    spend: f64 = 0,
    request_count: u64 = 0,
    last_used: ?i64,
    active: bool = true,
};

pub const VirtualKeyStore = struct {
    allocator: std.mem.Allocator,
    keys: std.StringArrayHashMap(VirtualKey),

    pub fn init(allocator: std.mem.Allocator) VirtualKeyStore {
        return .{
            .allocator = allocator,
            .keys = std.StringArrayHashMap(VirtualKey).init(allocator),
        };
    }

    pub fn deinit(self: *VirtualKeyStore) void {
        var it = self.keys.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.key_hash);
            if (entry.value_ptr.user_id) |uid| {
                self.allocator.free(uid);
            }
            if (entry.value_ptr.team_id) |tid| {
                self.allocator.free(tid);
            }
            if (entry.value_ptr.allowed_models) |models| {
                for (models) |m| self.allocator.free(m);
                self.allocator.free(models);
            }
            if (entry.value_ptr.allowed_providers) |providers| {
                self.allocator.free(providers);
            }
        }
        self.keys.deinit();
    }

    /// Generate a new virtual key with sk- prefix
    pub fn generateKey(self: *VirtualKeyStore, config: VirtualKeyConfig) ![]const u8 {
        const key = try generateRandomKey(self.allocator);
        errdefer self.allocator.free(key);
        try self.addWithKey(key, config);
        return key;
    }

    pub fn add(self: *VirtualKeyStore, key: []const u8, config: VirtualKeyConfig) !void {
        try self.addWithKey(key, config);
    }

    fn addWithKey(self: *VirtualKeyStore, key: []const u8, config: VirtualKeyConfig) !void {
        const key_hash = try hashKey(key, self.allocator);
        const vk = VirtualKey{
            .id = try self.allocator.dupe(u8, key),
            .key_hash = key_hash,
            .user_id = if (config.user_id) |uid| try self.allocator.dupe(u8, uid) else null,
            .team_id = if (config.team_id) |tid| try self.allocator.dupe(u8, tid) else null,
            .rate_limit = config.rate_limit,
            .allowed_models = if (config.allowed_models) |models| blk: {
                const copy = try self.allocator.alloc([]const u8, models.len);
                for (models, 0..) |m, i| copy[i] = try self.allocator.dupe(u8, m);
                break :blk copy;
            } else null,
            .allowed_providers = if (config.allowed_providers) |providers|
                try self.allocator.dupe(u8, providers)
            else
                null,
            .created_at = std.time.timestamp(),
            .expires_at = config.expires_at,
            .spend = 0,
            .request_count = 0,
            .last_used = null,
            .active = true,
        };
        try self.keys.put(try self.allocator.dupe(u8, key), vk);
    }

    pub fn validate(self: *VirtualKeyStore, key: []const u8) !void {
        const vk = self.keys.get(key) orelse {
            return error.InvalidVirtualKey;
        };
        // Check if key is active
        if (!vk.active) {
            return error.InvalidVirtualKey;
        }
        // Check expiration
        if (vk.expires_at) |expires| {
            if (std.time.timestamp() > expires) {
                return error.InvalidVirtualKey;
            }
        }
    }

    pub fn get(self: *VirtualKeyStore, key: []const u8) ?*const VirtualKey {
        return self.keys.get(key);
    }

    pub fn delete(self: *VirtualKeyStore, key: []const u8) bool {
        if (self.keys.fetchRemove(key)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value.key_hash);
            if (entry.value.user_id) |uid| self.allocator.free(uid);
            if (entry.value.team_id) |tid| self.allocator.free(tid);
            if (entry.value.allowed_models) |models| {
                for (models) |m| self.allocator.free(m);
                self.allocator.free(models);
            }
            if (entry.value.allowed_providers) |providers| {
                self.allocator.free(providers);
            }
            return true;
        }
        return false;
    }

    /// Revoke a key (soft delete - sets active=false)
    pub fn revoke(self: *VirtualKeyStore, key: []const u8) !void {
        const vk = self.keys.get(key) orelse {
            return error.InvalidVirtualKey;
        };
        vk.active = false;
    }

    /// Update spend for a key
    pub fn updateSpend(self: *VirtualKeyStore, key: []const u8, amount: f64) !void {
        const vk = self.keys.get(key) orelse {
            return error.InvalidVirtualKey;
        };
        vk.spend += amount;
        vk.request_count += 1;
        vk.last_used = std.time.timestamp();
    }

    /// Update last used timestamp
    pub fn touch(self: *VirtualKeyStore, key: []const u8) void {
        if (self.keys.get(key)) |vk| {
            vk.last_used = std.time.timestamp();
        }
    }

    pub fn checkModelAccess(self: *const VirtualKey, model: []const u8) bool {
        if (!self.active) return false;
        if (self.allowed_models) |allowed| {
            for (allowed) |m| {
                if (std.mem.eql(u8, m, model)) return true;
            }
            return false;
        }
        return true;
    }

    pub fn checkProviderAccess(self: *const VirtualKey, provider: []const u8) bool {
        if (!self.active) return false;
        if (self.allowed_providers) |allowed| {
            // allowed_providers is comma-separated string
            var it = std.mem.splitScalar(u8, allowed, ',');
            while (it.next()) |p| {
                if (std.mem.eql(u8, p, provider)) return true;
            }
            return false;
        }
        return true;
    }

    /// Get all keys for a user
    pub fn getByUser(self: *VirtualKeyStore, user_id: []const u8) []const VirtualKey {
        var result = std.array_list.Managed(VirtualKey).init(self.allocator);
        var it = self.keys.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.user_id) |uid| {
                if (std.mem.eql(u8, uid, user_id)) {
                    result.append(entry.value_ptr.*) catch {};
                }
            }
        }
        return result.toOwnedSlice();
    }

    /// Get all keys for a team
    pub fn getByTeam(self: *VirtualKeyStore, team_id: []const u8) []const VirtualKey {
        var result = std.array_list.Managed(VirtualKey).init(self.allocator);
        var it = self.keys.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.team_id) |tid| {
                if (std.mem.eql(u8, tid, team_id)) {
                    result.append(entry.value_ptr.*) catch {};
                }
            }
        }
        return result.toOwnedSlice();
    }

    fn generateRandomKey(allocator: std.mem.Allocator) ![]const u8 {
        const prefix = "sk-";
        const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        var key = std.array_list.Managed(u8).init(allocator);
        try key.appendSlice(prefix);
        const key_len = 48;
        for (0..key_len) |_| {
            const idx = std.crypto.randomInt(u6) % chars.len;
            try key.append(chars[idx]);
        }
        return key.toOwnedSlice();
    }

    fn hashKey(key: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        var hash_value: u32 = 0;
        for (key) |c| {
            hash_value +%= c;
        }
        return std.fmt.allocPrint(allocator, "{x}", .{hash_value});
    }
};

pub const VirtualKeyConfig = struct {
    user_id: ?[]const u8 = null,
    team_id: ?[]const u8 = null,
    rate_limit: ?u32 = null,
    allowed_models: ?[][]const u8 = null,
    allowed_providers: ?[]const u8 = null,
    expires_at: ?i64 = null,
};
