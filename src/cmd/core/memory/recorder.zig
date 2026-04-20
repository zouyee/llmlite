//! Memory recorder - auto-categorize and record command executions

const std = @import("std");
const types = @import("types.zig");
const db = @import("db.zig");
const utils = @import("utils.zig");

pub const Recorder = struct {
    allocator: std.mem.Allocator,
    memory_db: *db.MemoryDb,
    config: RecorderConfig,

    pub const RecorderConfig = struct {
        enabled: bool = true,
        auto_record: bool = true,
        max_context_length: usize = 2000,
        dedup_window_secs: i64 = 30,
        excluded_patterns: []const []const u8 = &.{},
        privacy_mode: types.PrivacyMode = .normal,
        mode: []const u8 = "code",
    };

    pub fn init(allocator: std.mem.Allocator, memory_db: *db.MemoryDb, config: RecorderConfig) Recorder {
        return Recorder{
            .allocator = allocator,
            .memory_db = memory_db,
            .config = config,
        };
    }

    /// Check if a command result should be recorded
    pub fn shouldRecord(self: *Recorder, original_cmd: []const u8, exit_code: i32) bool {
        _ = exit_code;

        // 1. Environment variable check (highest priority)
        if (isMemoryDisabledByEnv()) return false;

        // 2. Global switches
        if (!self.config.enabled or !self.config.auto_record) return false;

        // 3. Privacy mode
        if (self.config.privacy_mode == .private) return false;

        // 4. Exclusion patterns
        for (self.config.excluded_patterns) |pattern| {
            if (matchesPattern(original_cmd, pattern)) return false;
        }

        return true;
    }

    /// Record a command execution as a memory
    pub fn record(self: *Recorder, original_cmd: []const u8, filtered_output: []const u8, exit_code: i32, session_id: []const u8) !?u64 {
        if (!self.shouldRecord(original_cmd, exit_code)) return null;

        const project = try utils.detectProject(self.allocator);
        defer self.allocator.free(project);

        var category = try self.categorize(original_cmd, filtered_output, exit_code);
        category = applyWorkMode(category, self.config.mode);
        const summary = try self.generateSummary(original_cmd, exit_code);
        defer self.allocator.free(summary);

        const context = if (filtered_output.len > self.config.max_context_length)
            try self.allocator.dupe(u8, filtered_output[0..self.config.max_context_length])
        else
            try self.allocator.dupe(u8, filtered_output);
        defer self.allocator.free(context);

        const tags = try utils.extractTags(self.allocator, original_cmd, filtered_output);
        defer {
            for (tags) |t| self.allocator.free(t);
            self.allocator.free(tags);
        }

        const commands = try self.allocator.alloc([]const u8, 1);
        commands[0] = try self.allocator.dupe(u8, original_cmd);
        defer {
            for (commands) |c| self.allocator.free(c);
            self.allocator.free(commands);
        }

        const facts = try self.extractFacts(original_cmd, filtered_output, exit_code);
        defer {
            for (facts) |f| self.allocator.free(f);
            self.allocator.free(facts);
        }

        const hash = utils.computeContentHash(session_id, summary, commands);

        // Check for duplicate
        if (try self.memory_db.findDuplicate(hash, self.config.dedup_window_secs)) |_| {
            return null;
        }

        const entry = types.MemoryEntry{
            .id = 0, // auto-generated
            .category = category,
            .summary = summary,
            .facts = facts,
            .context = context,
            .tags = tags,
            .commands = commands,
            .project = try self.allocator.dupe(u8, project),
            .session_id = try self.allocator.dupe(u8, session_id),
            .created_at = std.time.timestamp(),
            .exit_code = exit_code,
            .content_hash = hash,
        };
        defer {
            self.allocator.free(entry.project);
            self.allocator.free(entry.session_id);
        }

        return try self.memory_db.insertMemory(entry);
    }

    /// Auto-categorize a command based on its content and result
    fn categorize(self: *Recorder, original_cmd: []const u8, output: []const u8, exit_code: i32) !types.MemoryCategory {
        // Check for config file modifications
        if (isConfigCommand(original_cmd)) return .config;

        // Check for git commits with feat/fix prefix
        if (isGitFeat(original_cmd)) return .feat;
        if (isGitFix(original_cmd)) return .fix;

        // Check for test/build success after failure pattern
        if (exit_code == 0 and isTestOrBuildCommand(original_cmd)) {
            // Check if previous command in this category failed
            // For now, just categorize as feat for successful builds
            if (isBuildCommand(original_cmd)) return .feat;
            return .fix;
        }

        // Error / mistake
        if (exit_code != 0) {
            // Check if it's a known error pattern vs a new discovery
            if (containsErrorPattern(output)) return .mistake;
            return .err;
        }

        // Learning: new tool or pattern
        if (isLearningCommand(original_cmd)) return .learn;

        // Default
        _ = self;
        return .other;
    }

    fn generateSummary(self: *Recorder, original_cmd: []const u8, exit_code: i32) ![]const u8 {
        const base = extractBaseCommand(original_cmd);
        if (exit_code == 0) {
            return try std.fmt.allocPrint(self.allocator, "Ran: {s}", .{base});
        } else {
            return try std.fmt.allocPrint(self.allocator, "Failed: {s} (exit {d})", .{ base, exit_code });
        }
    }

    fn extractFacts(self: *Recorder, original_cmd: []const u8, output: []const u8, exit_code: i32) ![][]const u8 {
        var facts = std.ArrayList([]const u8).empty;
        errdefer {
            for (facts.items) |f| self.allocator.free(f);
            facts.deinit(self.allocator);
        }

        // Add command as fact
        const cmd_fact = try std.fmt.allocPrint(self.allocator, "Command: {s}", .{original_cmd});
        try facts.append(self.allocator, cmd_fact);

        // Add exit code as fact
        const exit_fact = try std.fmt.allocPrint(self.allocator, "Exit code: {d}", .{exit_code});
        try facts.append(self.allocator, exit_fact);

        // Extract first line of output if available
        if (output.len > 0) {
            const first_line = if (std.mem.indexOfScalar(u8, output, '\n')) |idx|
                std.mem.trim(u8, output[0..idx], " \t\r")
            else
                std.mem.trim(u8, output, " \t\r");

            if (first_line.len > 0 and first_line.len < 200) {
                const out_fact = try std.fmt.allocPrint(self.allocator, "Output: {s}", .{first_line});
                try facts.append(self.allocator, out_fact);
            }
        }

        return facts.toOwnedSlice(self.allocator);
    }
};

fn isMemoryDisabledByEnv() bool {
    const env_val = std.process.getEnvVarOwned(std.heap.page_allocator, "LLMLITE_MEMORY_DISABLED") catch return false;
    defer std.heap.page_allocator.free(env_val);
    return std.mem.eql(u8, env_val, "1") or std.mem.eql(u8, env_val, "true");
}

fn matchesPattern(text: []const u8, pattern: []const u8) bool {
    // Simple glob: * matches anything
    if (std.mem.eql(u8, pattern, "*")) return true;
    if (std.mem.startsWith(u8, pattern, "*") and std.mem.endsWith(u8, pattern, "*")) {
        const middle = pattern[1 .. pattern.len - 1];
        return std.mem.indexOf(u8, text, middle) != null;
    }
    if (std.mem.startsWith(u8, pattern, "*")) {
        return std.mem.endsWith(u8, text, pattern[1..]);
    }
    if (std.mem.endsWith(u8, pattern, "*")) {
        return std.mem.startsWith(u8, text, pattern[0 .. pattern.len - 1]);
    }
    return std.mem.eql(u8, text, pattern);
}

fn extractBaseCommand(cmd: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, cmd, " \t\r\n");
    if (trimmed.len == 0) return trimmed;

    var i: usize = 0;
    while (i < trimmed.len and trimmed[i] != ' ') : (i += 1) {}
    return trimmed[0..i];
}

fn isConfigCommand(cmd: []const u8) bool {
    const config_exts = [_][]const u8{ ".json", ".toml", ".yaml", ".yml", ".ini", ".conf" };
    for (config_exts) |ext| {
        if (indexOfIgnoreCase(cmd, ext) != null) return true;
    }
    return false;
}

/// Case-insensitive substring search
fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (needle.len > haystack.len) return null;

    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(needle[j])) break;
        } else {
            return i;
        }
    }
    return null;
}

fn isGitFeat(cmd: []const u8) bool {
    return std.mem.startsWith(u8, cmd, "git commit") and
        (std.mem.indexOf(u8, cmd, "feat:") != null or std.mem.indexOf(u8, cmd, "feat(") != null);
}

fn isGitFix(cmd: []const u8) bool {
    return std.mem.startsWith(u8, cmd, "git commit") and
        (std.mem.indexOf(u8, cmd, "fix:") != null or std.mem.indexOf(u8, cmd, "fix(") != null);
}

fn isTestOrBuildCommand(cmd: []const u8) bool {
    return std.mem.indexOf(u8, cmd, "test") != null or
        std.mem.indexOf(u8, cmd, "build") != null;
}

fn isBuildCommand(cmd: []const u8) bool {
    return std.mem.indexOf(u8, cmd, "build") != null;
}

/// Downgrade categories ignored by the current work mode.
fn applyWorkMode(category: types.MemoryCategory, mode: []const u8) types.MemoryCategory {
    if (std.mem.eql(u8, mode, "infra")) {
        if (category == .feat or category == .refactor) return .other;
    } else if (std.mem.eql(u8, mode, "data")) {
        if (category == .feat or category == .refactor) return .other;
    } else if (std.mem.eql(u8, mode, "writing")) {
        if (category == .err or category == .mistake) return .other;
    }
    return category;
}

fn isLearningCommand(cmd: []const u8) bool {
    const learning_cmds = [_][]const u8{ "help", "--help", "-h", "man ", "info " };
    for (learning_cmds) |lc| {
        if (std.mem.indexOf(u8, cmd, lc) != null) return true;
    }
    return false;
}

fn containsErrorPattern(output: []const u8) bool {
    const patterns = [_][]const u8{
        "error:", "Error:", "ERROR:", "failed", "Failed", "FAILED",
        "not found", "permission denied", "invalid", "unknown",
    };
    for (patterns) |p| {
        if (std.mem.indexOf(u8, output, p) != null) return true;
    }
    return false;
}
