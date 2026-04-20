//! Memory module - CLI memory system for llmlite-cmd
//!
//! Provides persistent memory capabilities inspired by claude-mem:
//! - Automatic recording of command executions with categorization
//! - Full-text search via SQLite FTS5
//! - Session management and summaries
//! - Privacy filtering and auto-pruning

const std = @import("std");

// Re-export submodules
pub const types = @import("types.zig");
pub const db = @import("db.zig");
pub const search = @import("search.zig");
pub const recorder = @import("recorder.zig");
pub const session = @import("session.zig");
pub const utils = @import("utils.zig");
pub const migrate = @import("migrate.zig");

// Re-export key types
pub const MemoryEntry = types.MemoryEntry;
pub const MemoryCategory = types.MemoryCategory;
pub const MemoryFilter = types.MemoryFilter;
pub const SessionSummary = types.SessionSummary;
pub const MemoryDb = db.MemoryDb;
pub const Searcher = search.Searcher;
pub const Recorder = recorder.Recorder;
pub const SessionManager = session.SessionManager;
pub const SessionStatus = session.SessionStatus;
pub const Migrator = migrate.Migrator;
