//! Memory command dispatcher
//!
//! Commands:
//!   memory search [query] [--cat X] [--proj Y] [--since N] [--limit N]
//!   memory list [--cat X] [--proj Y] [--since N] [--limit N]
//!   memory show <id>...
//!   memory timeline <id> [--before N] [--after N]
//!   memory stats [--proj <name>]
//!   memory prune [--before <date>] [--dry-run]
//!   memory session [start|end|status]
//!
//! Aliases:
//!   mem s [query]     → memory search
//!   mem ls            → memory list
//!   mem <id>          → memory show

const std = @import("std");
const memory = @import("memory");
const modes = @import("modes");

pub fn dispatch(allocator: std.mem.Allocator, args: []const [:0]u8) !i32 {
    if (args.len == 0) {
        try printMemoryHelp();
        return 0;
    }

    const subcmd = args[0];

    if (std.mem.eql(u8, subcmd, "search") or std.mem.eql(u8, subcmd, "s")) {
        return dispatchSearch(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcmd, "list") or std.mem.eql(u8, subcmd, "ls")) {
        return dispatchList(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcmd, "show")) {
        return dispatchShow(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcmd, "timeline")) {
        return dispatchTimeline(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcmd, "stats")) {
        return dispatchStats(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcmd, "prune")) {
        return dispatchPrune(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcmd, "session")) {
        return dispatchSession(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcmd, "migrate")) {
        return dispatchMigrate(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcmd, "mode")) {
        return dispatchMode(allocator, args[1..]);
    } else {
        // Try parsing as ID for show command
        if (std.fmt.parseInt(u64, subcmd, 10)) |id| {
            return dispatchShowById(allocator, id);
        } else |_| {}

        std.debug.print("Unknown memory command: {s}\n", .{subcmd});
        try printMemoryHelp();
        return 1;
    }
}

fn dispatchSearch(allocator: std.mem.Allocator, args: []const [:0]u8) !i32 {
    var query: ?[]const u8 = null;
    var category: ?memory.MemoryCategory = null;
    var project: ?[]const u8 = null;
    var since_days: ?u32 = null;
    var limit: u32 = 20;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--cat") or std.mem.eql(u8, args[i], "-c")) {
            if (i + 1 < args.len) {
                category = memory.MemoryCategory.fromString(args[i + 1]);
                i += 1;
            }
        } else if (std.mem.eql(u8, args[i], "--proj") or std.mem.eql(u8, args[i], "-p")) {
            if (i + 1 < args.len) {
                project = args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, args[i], "--since") or std.mem.eql(u8, args[i], "-s")) {
            if (i + 1 < args.len) {
                since_days = std.fmt.parseInt(u32, args[i + 1], 10) catch null;
                i += 1;
            }
        } else if (std.mem.eql(u8, args[i], "--limit") or std.mem.eql(u8, args[i], "-n")) {
            if (i + 1 < args.len) {
                limit = std.fmt.parseInt(u32, args[i + 1], 10) catch 20;
                i += 1;
            }
        } else if (query == null) {
            query = args[i];
        }
    }

    var mem_db = try memory.MemoryDb.init(allocator);
    defer mem_db.deinit();

    var searcher = memory.Searcher.init(&mem_db);

    var filter = memory.MemoryFilter{
        .query = query,
        .category = category,
        .project = project,
        .limit = limit,
    };

    if (since_days) |days| {
        filter.date_start = std.time.timestamp() - (@as(i64, days) * 86400);
    }

    const results = try searcher.search(filter);
    defer {
        for (results) |r| {
            allocator.free(r.summary);
            allocator.free(r.project);
        }
        allocator.free(results);
    }

    if (results.len == 0) {
        std.debug.print("No memories found.\n", .{});
        return 0;
    }

    std.debug.print("Found {d} memories:\n\n", .{results.len});
    std.debug.print("{s:<6} {s:<8} {s:<12} {s}\n", .{ "ID", "Cat", "Project", "Summary" });
    std.debug.print("{s}\n", .{"-" ** 60});

    for (results) |r| {
        const cat_str = r.category.asString();
        const proj_short = if (r.project.len > 11) r.project[0..11] else r.project;
        std.debug.print("#{d:<5} {s:<8} {s:<12} {s}\n", .{
            r.id,
            cat_str,
            proj_short,
            r.summary,
        });
    }

    return 0;
}

fn dispatchList(allocator: std.mem.Allocator, args: []const [:0]u8) !i32 {
    // list is just search without a query
    return dispatchSearch(allocator, args);
}

fn dispatchShow(allocator: std.mem.Allocator, args: []const [:0]u8) !i32 {
    if (args.len == 0) {
        std.debug.print("Usage: memory show <id>...\n", .{});
        return 1;
    }

    var mem_db = try memory.MemoryDb.init(allocator);
    defer mem_db.deinit();

    for (args) |arg| {
        const id = std.fmt.parseInt(u64, arg, 10) catch {
            std.debug.print("Invalid ID: {s}\n", .{arg});
            continue;
        };

        const entry = try mem_db.getMemoryById(id);
        if (entry) |e| {
            defer {
                allocator.free(e.summary);
                allocator.free(e.context);
                allocator.free(e.project);
                allocator.free(e.session_id);
                for (e.facts) |f| allocator.free(f);
                allocator.free(e.facts);
                for (e.tags) |t| allocator.free(t);
                allocator.free(e.tags);
                for (e.commands) |c| allocator.free(c);
                allocator.free(e.commands);
            }

            std.debug.print("\n[{s}] {s}\n", .{ e.category.asString(), e.summary });
            std.debug.print("Project: {s}\n", .{e.project});
            std.debug.print("Session: {s}\n", .{e.session_id});
            std.debug.print("Created: {d}\n", .{e.created_at});
            std.debug.print("Exit: {d}\n", .{e.exit_code});
            std.debug.print("Commands: ", .{});
            for (e.commands, 0..) |cmd, ci| {
                if (ci > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{cmd});
            }
            std.debug.print("\n", .{});

            if (e.facts.len > 0) {
                std.debug.print("Facts:\n", .{});
                for (e.facts) |fact| {
                    std.debug.print("  - {s}\n", .{fact});
                }
            }

            if (e.tags.len > 0) {
                std.debug.print("Tags: ", .{});
                for (e.tags, 0..) |tag, ti| {
                    if (ti > 0) std.debug.print(", ", .{});
                    std.debug.print("{s}", .{tag});
                }
                std.debug.print("\n", .{});
            }

            if (e.context.len > 0) {
                std.debug.print("Context: {s}\n", .{e.context});
            }
        } else {
            std.debug.print("Memory #{d} not found.\n", .{id});
        }
    }

    return 0;
}

fn dispatchShowById(allocator: std.mem.Allocator, id: u64) !i32 {
    const arg = try std.fmt.allocPrint(allocator, "{d}", .{id});
    defer allocator.free(arg);
    const arg_z = try allocator.dupeZ(u8, arg);
    defer allocator.free(arg_z);
    const args = &[_][:0]u8{arg_z};
    return dispatchShow(allocator, args);
}

fn dispatchTimeline(allocator: std.mem.Allocator, args: []const [:0]u8) !i32 {
    if (args.len == 0) {
        std.debug.print("Usage: memory timeline <id> [--before N] [--after N]\n", .{});
        return 1;
    }

    const id = std.fmt.parseInt(u64, args[0], 10) catch {
        std.debug.print("Invalid ID: {s}\n", .{args[0]});
        return 1;
    };

    var before: u32 = 5;
    var after: u32 = 5;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--before") or std.mem.eql(u8, args[i], "-b")) {
            if (i + 1 < args.len) {
                before = std.fmt.parseInt(u32, args[i + 1], 10) catch 5;
                i += 1;
            }
        } else if (std.mem.eql(u8, args[i], "--after") or std.mem.eql(u8, args[i], "-a")) {
            if (i + 1 < args.len) {
                after = std.fmt.parseInt(u32, args[i + 1], 10) catch 5;
                i += 1;
            }
        }
    }

    var mem_db = try memory.MemoryDb.init(allocator);
    defer mem_db.deinit();

    var searcher = memory.Searcher.init(&mem_db);

    const results = try searcher.timeline(id, before, after);
    defer {
        for (results) |r| {
            allocator.free(r.summary);
            allocator.free(r.project);
        }
        allocator.free(results);
    }

    if (results.len == 0) {
        std.debug.print("No timeline context found for #{d}.\n", .{id});
        return 0;
    }

    std.debug.print("Timeline around #{d}:\n\n", .{id});
    std.debug.print("{s:<6} {s:<8} {s}\n", .{ "ID", "Cat", "Summary" });
    std.debug.print("{s}\n", .{"-" ** 50});

    for (results) |r| {
        const marker = if (r.id == id) " → " else "   ";
        std.debug.print("{s}#{d:<5} {s:<8} {s}\n", .{
            marker,
            r.id,
            r.category.asString(),
            r.summary,
        });
    }

    return 0;
}

fn dispatchStats(allocator: std.mem.Allocator, args: []const [:0]u8) !i32 {
    var project: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--proj") or std.mem.eql(u8, args[i], "-p")) {
            if (i + 1 < args.len) {
                project = args[i + 1];
                i += 1;
            }
        }
    }

    var mem_db = try memory.MemoryDb.init(allocator);
    defer mem_db.deinit();

    const stats = try mem_db.getStatsByProject(project);

    std.debug.print("\n=== Memory Statistics ===\n\n", .{});
    std.debug.print("Total memories: {d}\n", .{stats.total_count});
    std.debug.print("  Fixes:        {d}\n", .{stats.fix_count});
    std.debug.print("  Features:     {d}\n", .{stats.feat_count});
    std.debug.print("  Learnings:    {d}\n", .{stats.learn_count});
    std.debug.print("  Mistakes:     {d}\n", .{stats.mistake_count});
    std.debug.print("  Patterns:     {d}\n", .{stats.pattern_count});

    if (project) |p| {
        std.debug.print("\nProject filter: {s}\n", .{p});
    }

    return 0;
}

fn dispatchPrune(allocator: std.mem.Allocator, args: []const [:0]u8) !i32 {
    var before_days: ?u32 = null;
    var dry_run = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--before") or std.mem.eql(u8, args[i], "-b")) {
            if (i + 1 < args.len) {
                before_days = std.fmt.parseInt(u32, args[i + 1], 10) catch null;
                i += 1;
            }
        } else if (std.mem.eql(u8, args[i], "--dry-run") or std.mem.eql(u8, args[i], "-d")) {
            dry_run = true;
        }
    }

    if (before_days == null) {
        std.debug.print("Usage: memory prune --before <days> [--dry-run]\n", .{});
        return 1;
    }

    const cutoff = std.time.timestamp() - (@as(i64, before_days.?) * 86400);

    var mem_db = try memory.MemoryDb.init(allocator);
    defer mem_db.deinit();

    if (dry_run) {
        const count = try mem_db.getMemoryCount();
        std.debug.print("Dry run: would prune memories older than {d} days.\n", .{before_days.?});
        std.debug.print("Total memories in DB: {d}\n", .{count});
        return 0;
    }

    const deleted = try mem_db.pruneOldMemories(cutoff);
    std.debug.print("Pruned {d} memories older than {d} days.\n", .{ deleted, before_days.? });

    return 0;
}

fn dispatchSession(allocator: std.mem.Allocator, args: []const [:0]u8) !i32 {
    var mem_db = try memory.MemoryDb.init(allocator);
    defer mem_db.deinit();

    // Load config to get privacy mode
    const config_mod = @import("config");
    const privacy_mode: memory.types.PrivacyMode = blk: {
        if (config_mod.loadConfig(allocator)) |maybe_cfg| {
            if (maybe_cfg) |cfg| {
                break :blk switch (cfg.memory.privacy.mode) {
                    .normal => .normal,
                    .private => .private,
                };
            }
        } else |_| {}
        break :blk .normal;
    };

    var session_mgr = memory.SessionManager.initWithPrivacy(allocator, &mem_db, privacy_mode);
    defer session_mgr.deinit();

    const session_cmd = if (args.len > 0) args[0] else "status";

    if (std.mem.eql(u8, session_cmd, "start")) {
        const session_id = try session_mgr.startSession();
        defer allocator.free(session_id);
        std.debug.print("Started session: {s}\n", .{session_id});
        return 0;
    } else if (std.mem.eql(u8, session_cmd, "end")) {
        const summary = try session_mgr.endSession();
        if (summary) |s| {
            defer {
                allocator.free(s.session_id);
                allocator.free(s.project);
                allocator.free(s.task);
                allocator.free(s.learned);
                allocator.free(s.completed);
            }
            std.debug.print("Session ended.\n", .{});
            std.debug.print("Project: {s}\n", .{s.project});
            std.debug.print("Task: {s}\n", .{s.task});
            std.debug.print("Learned: {s}\n", .{s.learned});
            std.debug.print("Completed: {s}\n", .{s.completed});
            std.debug.print("Commands: {d}\n", .{s.command_count});
        } else {
            std.debug.print("Session ended (no memories recorded in this session).\n", .{});
        }
        return 0;
    } else if (std.mem.eql(u8, session_cmd, "status")) {
        const status = session_mgr.getStatus();
        if (status.active) {
            std.debug.print("Session: {s}\n", .{status.session_id});
            std.debug.print("Idle: {d} seconds\n", .{status.idle_secs});
            std.debug.print("Expires in: {d} seconds\n", .{status.expires_in_secs});
        } else {
            std.debug.print("No active session.\n", .{});
        }
        return 0;
    } else {
        std.debug.print("Unknown session command: {s}\n", .{session_cmd});
        std.debug.print("Usage: memory session [start|end|status]\n", .{});
        return 1;
    }
}

fn dispatchMigrate(allocator: std.mem.Allocator, _: []const [:0]u8) !i32 {
    var mem_db = try memory.MemoryDb.init(allocator);
    defer mem_db.deinit();

    var migrator = memory.migrate.Migrator.init(allocator, &mem_db);
    const result = try migrator.migrate();

    std.debug.print("\n=== Migration Results ===\n", .{});
    std.debug.print("Total records read: {d}\n", .{result.total_read});
    std.debug.print("Records migrated: {d}\n", .{result.migrated});
    std.debug.print("Skipped (duplicates): {d}\n", .{result.skipped_duplicates});
    std.debug.print("Failed: {d}\n", .{result.failed});

    return 0;
}

fn printMemoryHelp() !void {
    std.debug.print("\n=== llmlite Memory ===\n\n", .{});
    std.debug.print("USAGE:\n", .{});
    std.debug.print("    llmlite memory <command> [args...]\n", .{});
    std.debug.print("    llmlite mem <command> [args...]\n\n", .{});
    std.debug.print("COMMANDS:\n", .{});
    std.debug.print("    search [query]          Search memories (FTS5 + metadata)\n", .{});
    std.debug.print("    list [--cat X]          List recent memories\n", .{});
    std.debug.print("    show <id>...            Show full memory details\n", .{});
    std.debug.print("    timeline <id>           Context around memory\n", .{});
    std.debug.print("    stats [--proj X]        Memory statistics\n", .{});
    std.debug.print("    prune --before <days>   Clean old memories\n", .{});
    std.debug.print("    session [cmd]           Session management\n", .{});
    std.debug.print("    migrate                 Migrate history.db to memory.db\n", .{});
    std.debug.print("    mode [show|set|list]    Work mode management\n\n", .{});
    std.debug.print("ALIASES:\n", .{});
    std.debug.print("    mem s [query]           memory search\n", .{});
    std.debug.print("    mem ls                  memory list\n", .{});
    std.debug.print("    mem <id>                memory show\n\n", .{});
}

// ------------------------------------------------------------------
// Mode commands
// ------------------------------------------------------------------

fn dispatchMode(allocator: std.mem.Allocator, args: []const [:0]u8) !i32 {
    if (args.len == 0) {
        return dispatchModeShow(allocator);
    }

    const subcmd = args[0];
    if (std.mem.eql(u8, subcmd, "show") or std.mem.eql(u8, subcmd, "s")) {
        return dispatchModeShow(allocator);
    } else if (std.mem.eql(u8, subcmd, "set")) {
        return dispatchModeSet(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcmd, "list") or std.mem.eql(u8, subcmd, "ls")) {
        return dispatchModeList();
    } else {
        std.debug.print("Unknown mode command: {s}\n", .{subcmd});
        try printModeHelp();
        return 1;
    }
}

fn dispatchModeShow(allocator: std.mem.Allocator) !i32 {
    const current = try modes.getCurrentMode(allocator);
    const cfg = modes.getDefaultConfig(current);

    std.debug.print("\n=== Work Mode ===\n\n", .{});
    std.debug.print("Current:  {s}\n", .{cfg.name});
    std.debug.print("{s}\n\n", .{cfg.description});

    std.debug.print("Focus categories:\n", .{});
    for (cfg.focus) |cat| {
        std.debug.print("  - {s}\n", .{@tagName(cat)});
    }

    if (cfg.ignore.len > 0) {
        std.debug.print("\nIgnored categories (downgraded to 'other'):\n", .{});
        for (cfg.ignore) |cat| {
            std.debug.print("  - {s}\n", .{@tagName(cat)});
        }
    }
    std.debug.print("\n", .{});
    return 0;
}

fn dispatchModeSet(allocator: std.mem.Allocator, args: []const [:0]u8) !i32 {
    if (args.len == 0) {
        std.debug.print("Usage: llmlite memory mode set <code|infra|data|writing>\n", .{});
        return 1;
    }

    const mode_str = args[0];
    const mode = modes.WorkMode.fromString(mode_str);
    if (mode == null) {
        std.debug.print("Unknown mode: {s}\n", .{mode_str});
        std.debug.print("Valid modes: code, infra, data, writing\n", .{});
        return 1;
    }

    try modes.setCurrentMode(allocator, mode.?);
    std.debug.print("Work mode set to: {s}\n", .{mode.?.asString()});
    return 0;
}

fn dispatchModeList() !i32 {
    const all_modes = &[_]modes.WorkMode{ .code, .infra, .data, .writing };

    std.debug.print("\n=== Work Modes ===\n\n", .{});
    for (all_modes) |m| {
        const cfg = modes.getDefaultConfig(m);
        std.debug.print("  {s:8}  {s}\n", .{ cfg.name, cfg.description });
    }
    std.debug.print("\nUse 'llmlite memory mode set <mode>' to switch.\n\n", .{});
    return 0;
}

fn printModeHelp() !void {
    std.debug.print("\n=== Mode Commands ===\n\n", .{});
    std.debug.print("  show          Display current mode and its settings\n", .{});
    std.debug.print("  set <mode>    Switch to a different work mode\n", .{});
    std.debug.print("  list          List all available modes\n\n", .{});
}
