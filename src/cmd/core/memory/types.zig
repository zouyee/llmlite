//! Memory types - data structures for CLI memory system

const std = @import("std");

pub const MemoryCategory = enum(u8) {
    fix,        // Bug fix resolved
    feat,       // New feature implemented
    refactor,   // Code restructuring
    config,     // Configuration change
    learn,      // New tool/pattern discovered
    mistake,    // CLI mistake + correction
    pattern,    // Repeated command pattern
    decision,   // Architectural decision
    err,        // Unresolved error
    other,      // Uncategorized

    pub fn asString(self: MemoryCategory) []const u8 {
        return switch (self) {
            .fix => "fix",
            .feat => "feat",
            .refactor => "refactor",
            .config => "config",
            .learn => "learn",
            .mistake => "mistake",
            .pattern => "pattern",
            .decision => "decision",
            .err => "error",
            .other => "other",
        };
    }

    pub fn fromString(s: []const u8) MemoryCategory {
        if (std.mem.eql(u8, s, "fix")) return .fix;
        if (std.mem.eql(u8, s, "feat")) return .feat;
        if (std.mem.eql(u8, s, "refactor")) return .refactor;
        if (std.mem.eql(u8, s, "config")) return .config;
        if (std.mem.eql(u8, s, "learn")) return .learn;
        if (std.mem.eql(u8, s, "mistake")) return .mistake;
        if (std.mem.eql(u8, s, "pattern")) return .pattern;
        if (std.mem.eql(u8, s, "decision")) return .decision;
        if (std.mem.eql(u8, s, "error")) return .err;
        return .other;
    }
};

pub const MemoryEntry = struct {
    id: u64,
    category: MemoryCategory,
    summary: []const u8,
    facts: [][]const u8,
    context: []const u8,
    tags: [][]const u8,
    commands: [][]const u8,
    project: []const u8,
    session_id: []const u8,
    created_at: i64,
    exit_code: i32,
    content_hash: [32]u8,
};

pub const SessionSummary = struct {
    id: u64,
    session_id: []const u8,
    project: []const u8,
    task: []const u8,
    learned: []const u8,
    completed: []const u8,
    followups: []const u8,
    notes: []const u8,
    command_count: u32,
    created_at: i64,
};

pub const MemoryFilter = struct {
    category: ?MemoryCategory = null,
    tags: ?[][]const u8 = null,
    commands: ?[][]const u8 = null,
    project: ?[]const u8 = null,
    date_start: ?i64 = null,
    date_end: ?i64 = null,
    query: ?[]const u8 = null,
    limit: u32 = 20,
    offset: u32 = 0,
};

pub const SearchResult = struct {
    id: u64,
    category: MemoryCategory,
    summary: []const u8,
    created_at: i64,
    project: []const u8,
    relevance_score: f64,
};

pub const PrivacyMode = enum {
    normal,
    private,
};
