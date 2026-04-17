# llmlite-cmd Architecture

> CLI command proxy that intercepts developer commands, filters output, and reduces LLM token consumption by 60-90%

## 1. Overview

**llmlite-cmd** is a standalone CLI tool that intercepts developer commands, filters their output to reduce token consumption, and tracks savings for analysis.

### Design Principles

1. **Zero-Configuration**: Works out of the box
2. **Fail-Safe**: Falls back to raw output on filter failure
3. **Exit Code Preservation**: CI/CD reliable
4. **Minimal Overhead**: <10ms proxy overhead
5. **Transparent**: Raw output available via `-v` flags

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           llmlite-cmd Architecture                          │
└─────────────────────────────────────────────────────────────────────────────┘

                              ┌─────────────────┐
                              │   Shell Hook    │
                              │  (bash/zsh)    │
                              └────────┬────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CLI Entry Point                                │
│                           src/cmd/cmd_main.zig                              │
│                                                                             │
│  $ llmlite git status    $ llmlite cargo test    $ llmlite npm run build  │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Command Dispatcher                                 │
│                         src/cmd/cmds/mod.zig                                │
│                                                                             │
│  pub const Command = enum {                                                 │
│      git, cargo, npm, pytest, docker, kubectl, system, ...                  │
│  }                                                                           │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
                    ┌─────────────┴─────────────┬──────────────────┐
                    ▼                           ▼                  ▼
          ┌─────────────────┐         ┌─────────────────┐ ┌─────────────────┐
          │   Git Module    │         │  Cargo Module   │ │   NPM Module    │
          │ src/cmd/cmds/git│         │ src/cmd/cmds/   │ │ src/cmd/cmds/   │
          │                 │         │ cargo/          │ │ npm/            │
          └────────┬────────┘         └────────┬────────┘ └────────┬────────┘
                   │                           │                   │
                   ▼                           ▼                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Core Infrastructure                                  │
│                        src/cmd/core/mod.zig                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │
│  │   runner    │  │   filter    │  │  tracking   │  │       tee       │   │
│  │   .zig      │  │   .zig      │  │   .zig      │  │       .zig      │   │
│  ├─────────────┤  ├─────────────┤  ├─────────────┤  ├─────────────────┤   │
│  │6-phase exec │  │12+ strategies│  │SQLite persist│  │Fail recovery   │   │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────────┘   │
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │
│  │   utils     │  │   hooks     │  │  analytics  │  │                 │   │
│  │   .zig      │  │   .zig      │  │   .zig      │  │                 │   │
│  ├─────────────┤  ├─────────────┤  ├─────────────┤  │                 │   │
│  │Tool detection│ │Hook install │  │  gain/discover│ │                 │   │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Actual Module Structure

```
src/cmd/
├── cmd_main.zig           # CLI entry point (main())
├── cmd.zig                # Command parsing and dispatch
│
└── core/                  # Core infrastructure
    ├── mod.zig            # Module re-exports
    ├── runner.zig         # 6-phase execution framework
    ├── filter.zig         # 12+ filtering strategies
    ├── tracking.zig       # SQLite persistent tracking
    ├── tee.zig            # Failure recovery
    ├── utils.zig          # Utility functions
    ├── hook.zig           # Shell hook management
    ├── config.zig         # Configuration management
    ├── session.zig        # Session management
    ├── key.zig            # Key management
    ├── lexer.zig          # Lexical analysis
    ├── rules.zig          # Filtering rules
    ├── learn.zig          # Learning mode
    ├── trust.zig          # Trust management
    ├── integrity.zig      # Integrity checking
    ├── sync.zig           # Sync functionality
    ├── read.zig           # File reading
    ├── json.zig           # JSON processing
    ├── gain.zig           # Token savings statistics
    ├── discover.zig       # Savings opportunity discovery
    ├── audit.zig          # Audit logging
    ├── ccusage.zig        # CC usage statistics
    ├── cc_economics.zig   # CC economics analysis
    ├── proxy_helpers.zig  # Proxy helpers
    │
    ├── filters/           # Filter implementations
    │   └── ...
    │
    ├── hooks/             # Shell hook templates
    │   └── ...
    │
    │── # Command modules (50+)
    ├── git.zig            # Git commands (status, diff, log, add, commit, push, pull)
    ├── cargo.zig          # Cargo commands (test, build, clippy, bench)
    ├── npm.zig            # NPM commands (test, run, install, list)
    ├── pnpm.zig           # PNPM commands
    ├── vitest.zig         # Vitest testing
    ├── pytest.zig         # Python pytest
    ├── docker.zig         # Docker commands (ps, images, logs, compose)
    ├── kubectl.zig        # Kubernetes commands (get, logs, describe, apply)
    ├── go_test.zig        # Go test
    ├── aws.zig            # AWS CLI
    ├── curl.zig           # curl commands
    ├── eslint.zig         # ESLint
    ├── tsc.zig            # TypeScript compiler
    ├── prettier.zig       # Prettier formatting
    ├── prisma.zig         # Prisma ORM
    ├── playwright.zig     # Playwright testing
    ├── nextjs.zig         # Next.js
    ├── pip.zig            # pip package manager
    ├── mypy.zig           # mypy type checking
    ├── ruff.zig           # Ruff linter
    ├── rake.zig           # Ruby Rake
    ├── rspec.zig          # Ruby RSpec
    ├── rubocop.zig        # Ruby RuboCop
    ├── dotnet.zig         # .NET CLI
    ├── java.zig           # Java commands
    ├── golangci_lint.zig  # golangci-lint
    └── toml_filter.zig    # TOML filtering
```

---

## 4. Command Taxonomy

### Git Commands (7)

| Command | Filter Strategy | Reduction | Example Output |
|---------|----------------|-----------|----------------|
| `git status` | Stats Extraction | 80% | `M src/main.zig` |
| `git diff` | Grouping + Dedupe | 75% | `+42 -8 files` |
| `git log -n N` | Stats Extraction | 80% | `5 commits, +142/-89` |
| `git add` | Passthrough → "ok" | 92% | `ok` |
| `git commit -m "msg"` | Passthrough → "ok hash" | 92% | `ok abc1234` |
| `git push` | Passthrough → "ok branch" | 92% | `ok main` |
| `git pull` | Stats Extraction | 85% | `ok 3 files +10 -2` |

### Cargo Commands (4)

| Command | Filter Strategy | Reduction | Example Output |
|---------|----------------|-----------|----------------|
| `cargo test` | Failure Focus + State Machine | 90% | `FAILED: 2/15 tests` |
| `cargo build` | Errors Only | 80% | `error[E0505]: ...` |
| `cargo clippy` | Grouping by Rule | 85% | `clippy: 12 warnings` |
| `cargo bench` | Stats Extraction | 80% | `bench: 1.2s ± 5ms` |

### NPM Commands (8)

| Command | Filter Strategy | Reduction | Example Output |
|---------|----------------|-----------|----------------|
| `npm test` | Failure Focus | 90% | `FAILED: 2 tests` |
| `npm run build` | Errors Only | 80% | `error: ...` |
| `npm install` | Progress Strip | 85% | `✓ 124 packages` |
| `npm list` | Tree Compression | 75% | `└── express@4.18` |
| `npx eslint` | Grouping by Rule | 80% | `no-unused-vars: 23` |
| `pnpm test` | Failure Focus | 90% | `FAILED: 2/15` |
| `pnpm list` | Tree Compression | 75% | `└── express@4.18` |
| `vitest` | Failure Focus | 90% | `FAIL 2 of 15` |

### Python Commands (4)

| Command | Filter Strategy | Reduction | Example Output |
|---------|----------------|-----------|----------------|
| `pytest` | State Machine + Failure Focus | 90% | `FAILED: 2/100` |
| `ruff check` | JSON Dual Mode | 80% | `F401: 12 issues` |
| `mypy` | Grouping by File | 80% | `src/main.py:5: error` |
| `pip list` | JSON Parsing | 75% | `express 4.18.2` |

### Docker Commands (6)

| Command | Filter Strategy | Reduction | Example Output |
|---------|----------------|-----------|----------------|
| `docker ps` | Stats Extraction | 80% | `3 containers running` |
| `docker images` | Stats Extraction | 80% | `5 images` |
| `docker logs` | Deduplication | 85% | `error (x5)` |
| `docker compose ps` | Stats Extraction | 80% | `3 services: 2 up` |
| `kubectl get pods` | Stats Extraction | 80% | `3/5 Running` |
| `kubectl logs` | Deduplication | 85% | `error (x5)` |

### System Commands (6)

| Command | Filter Strategy | Reduction | Example Output |
|---------|----------------|-----------|----------------|
| `ls -la` | Tree Compression | 70% | `src/ (12 files)` |
| `tree` | Tree Compression | 70% | `src/├── main.zig` |
| `cat file` | Code Filtering | 60% | (strip comments) |
| `grep -r pattern` | Grouping by File | 75% | `src/a.zig:5: match` |
| `find . -name` | Stats Extraction | 80% | `5 .zig files` |
| `wc -l` | Stats Extraction | 85% | `42 lines` |

---

## 5. Core Infrastructure

### 5.1 Runner (6-Phase Execution)

```zig
// src/cmd/core/runner.zig

pub const RunOptions = struct {
    /// Combine stdout and stderr for filtering
    combined: bool = true,
    /// Enable tee for failure recovery
    tee_label: ?[]const u8 = null,
    /// Verbosity level
    verbose: u8 = 0,
};

/// 6-phase execution framework
pub fn runFiltered(
    allocator: std.mem.Allocator,
    cmd: *std.process.Child,
    cmd_name: []const u8,
    raw_args: []const u8,
    filter_fn: *const fn ([]const u8) ![]const u8,
    options: RunOptions,
) !i32 {
    // Phase 1: EXECUTE
    const output = try cmd.run();
    const exit_code = output.term.Exited;
    
    // Combine stdout and stderr
    const raw_output = if (options.combined)
        try concat(allocator, output.stdout, output.stderr)
    else
        output.stdout;
    defer if (options.combined) allocator.free(raw_output);

    // Phase 2: FILTER
    const filtered = filter_fn(raw_output) catch {
        // Fallback to raw on filter failure
        if (options.verbose > 0) {
            std.log.warn("filter failed, using raw output", .{});
        }
        try allocator.dupe(u8, raw_output);
    };
    defer allocator.free(filtered);

    // Phase 3: TEE (failure recovery)
    if (options.tee_label) |label| {
        if (exit_code != 0) {
            try tee.save(label, raw_args, raw_output);
        }
    }

    // Phase 4: PRINT
    try std.io.getStdOut().writeAll(filtered);

    // Phase 5: TRACK
    try tracking.track(allocator, .{
        .original_cmd = raw_args,
        .rtk_cmd = cmd_name,
        .raw_output = raw_output,
        .filtered_output = filtered,
        .exit_code = exit_code,
    });

    // Phase 6: EXIT
    return exit_code;
}
```

### 5.2 Filter Strategies

```zig
// src/cmd/core/filter.zig

pub const FilterStrategy = enum {
    /// No filtering
    none,
    /// Stats extraction (count lines, errors, etc.)
    stats,
    /// Errors/warnings only
    errors_only,
    /// Group by pattern (file, rule, etc.)
    grouping,
    /// Remove duplicates with counts
    deduplication,
    /// Keep schema, strip values
    structure_only,
    /// Strip comments/bodies
    code_filter,
    /// Failures only
    failure_focus,
    /// Directory tree format
    tree_compression,
    /// Remove progress bars
    progress_strip,
    /// JSON/text dual
    json_dual,
    /// State machine parsing
    state_machine,
    /// NDJSON streaming
    ndjson_stream,
    /// Ultra-compact (ASCII icons)
    ultra_compact,
};

pub const FilterLevel = enum {
    none,
    minimal,   // ~20-40% reduction
    standard,  // ~50-70% reduction
    aggressive, // ~70-90% reduction
};

pub const FilterConfig = struct {
    strategy: FilterStrategy,
    level: FilterLevel = .standard,
};

pub const FilterResult = struct {
    filtered: []const u8,
    original_len: usize,
    filtered_len: usize,
    reduction_pct: f64,
    strategy_used: FilterStrategy,
};
```

### 5.3 Tracking (SQLite)

```zig
// src/cmd/core/tracking.zig

pub const Tracker = struct {
    allocator: std.mem.Allocator,
    db: SQLite,
};

pub const TrackingRecord = struct {
    timestamp: i64,
    original_cmd: []const u8,
    rtk_cmd: []const u8,
    raw_output: []const u8,
    filtered_output: []const u8,
    exit_code: i32,
};

pub fn track(tracker: *Tracker, record: TrackingRecord) !void {
    const input_tokens = estimateTokens(record.raw_output);
    const output_tokens = estimateTokens(record.filtered_output);
    const saved_tokens = input_tokens - output_tokens;
    const savings_pct = (@as(f64, @floatFromInt(saved_tokens)) / @as(f64, @floatFromInt(input_tokens))) * 100.0;

    try tracker.db.exec(
        \\ INSERT INTO commands (timestamp, original_cmd, rtk_cmd, 
        \\   input_tokens, output_tokens, saved_tokens, savings_pct, exit_code)
        \\ VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    , .{
        record.timestamp,
        record.original_cmd,
        record.rtk_cmd,
        input_tokens,
        output_tokens,
        saved_tokens,
        savings_pct,
        record.exit_code,
    });
}

fn estimateTokens(text: []const u8) usize {
    // Heuristic: ~4 chars per token
    return @as(usize, @ceil(@as(f64, @floatFromInt(text.len)) / 4.0));
}
```

### 5.4 Tee (Failure Recovery)

```zig
// src/cmd/core/tee.zig

pub const Tee = struct {
    allocator: std.mem.Allocator,
    directory: []const u8,
    max_files: usize = 20,
    max_size: usize = 1024 * 1024, // 1MB
};

pub fn save(tee: *Tee, label: []const u8, raw_output: []const u8) !void {
    const timestamp = std.time.timestamp();
    const filename = try std.fmt.allocPrint(
        tee.allocator,
        "{d}_{s}.log",
        .{ timestamp, label }
    );
    defer tee.allocator.free(filename);

    const filepath = try std.fs.path.join(tee.allocator, &.{ tee.directory, filename });
    defer tee.allocator.free(filepath);

    const file = try std.fs.createFileAbsolute(filepath, .{});
    defer file.close();

    try file.writeAll(raw_output);
    try tee.rotate(); // Remove old files if > max_files
}
```

---

## 6. Command Module Pattern

```zig
// src/cmd/cmds/git/git.zig

const std = @import("std");
const runner = @import("../../core/runner");
const filter = @import("../../core/filter");

pub const GitSubcommand = enum {
    status,
    diff,
    log,
    add,
    commit,
    push,
    pull,
};

/// Main entry point for git commands
pub fn run(allocator: std.mem.Allocator, args: [][]const u8, verbose: u8) !i32 {
    if (args.len == 0) return error.NoSubcommand;

    const subcmd = parseSubcommand(args[0]) orelse {
        std.log.err("unknown git subcommand: {s}", .{args[0]});
        return 1;
    };

    return switch (subcmd) {
        .status => runStatus(allocator, args[1..], verbose),
        .diff => runDiff(allocator, args[1..], verbose),
        .log => runLog(allocator, args[1..], verbose),
        .add => runAdd(allocator, args[1..], verbose),
        .commit => runCommit(allocator, args[1..], verbose),
        .push => runPush(allocator, args[1..], verbose),
        .pull => runPull(allocator, args[1..], verbose),
    };
}

fn runStatus(allocator: std.mem.Allocator, args: [][]const u8, verbose: u8) !i32 {
    var cmd = std.process.Child.init(&.{ "git", "status" }, allocator);
    try cmd.addArgs(args);

    return runner.runFiltered(allocator, &cmd, "git status", "git status", filterGitStatus, .{
        .combined = true,
        .tee_label = "git_status",
        .verbose = verbose,
    });
}

fn filterGitStatus(raw: []const u8) ![]const u8 {
    // Parse git status output and extract key information
    // Returns compact format like:
    // M src/main.zig
    // A src/new.zig
    // ?? untracked.txt
    // 
    // Returns ~20 chars instead of ~500 chars (96% reduction)
}
```

---

## 7. Shell Hook System

### 7.1 Hook Installation

```bash
# rtk init -g
# Installs hook to ~/.bashrc or ~/.zshrc

# Bash (~/.bashrc)
if [ -f ~/.config/llmlite/hook.sh ]; then
    PROMPT_COMMAND="~/.config/llmlite/hook.sh; $PROMPT_COMMAND"
fi

# Zsh (~/.zshrc)
if [ -f ~/.config/llmlite/hook.zsh ]; then
    precmd_functions+=(~/.config/llmlite/hook.zig)
fi
```

### 7.2 Hook Logic (Bash)

```bash
#!/bin/bash
# ~/.config/llmlite/hook.sh

# Extract the last command
last_cmd="${READLINE_LINE:-}"

# Check if it matches a rewritable pattern
case "$last_cmd" in
    git\ status|git\ diff|git\ log|git\ add|git\ commit|git\ push|git\ pull)
        # Rewrite to llmlite
        READLINE_LINE="llmlite ${last_cmd}"
        READLINE_POINT=$((READLINE_POINT + 9))
        ;;
    cargo\ test|cargo\ build|cargo\ clippy)
        READLINE_LINE="llmlite ${last_cmd}"
        READLINE_POINT=$((READLINE_POINT + 9))
        ;;
    npm\ test|npm\ run|npm\ install)
        READLINE_LINE="llmlite ${last_cmd}"
        READLINE_POINT=$((READLINE_POINT + 9))
        ;;
esac
```

---

## 8. SQLite Schema

```sql
-- Token tracking database: ~/.local/share/llmlite/history.db

CREATE TABLE IF NOT EXISTS commands (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,           -- Unix timestamp
    original_cmd TEXT NOT NULL,           -- "git status"
    rtk_cmd TEXT NOT NULL,               -- "llmlite git status"
    input_tokens INTEGER NOT NULL,        -- Raw output tokens
    output_tokens INTEGER NOT NULL,       -- Filtered output tokens
    saved_tokens INTEGER NOT NULL,        -- input - output
    savings_pct REAL NOT NULL,           -- Percentage saved
    exec_time_ms INTEGER DEFAULT 0,       -- Execution time
    exit_code INTEGER DEFAULT 0           -- Command exit code
);

CREATE INDEX idx_timestamp ON commands(timestamp);
CREATE INDEX idx_original_cmd ON commands(original_cmd);

-- Cleanup: keep last 90 days
DELETE FROM commands WHERE timestamp < datetime('now', '-90 days');

-- Parse failures for debugging
CREATE TABLE IF NOT EXISTS parse_failures (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,
    raw_command TEXT NOT NULL,
    error_message TEXT NOT NULL,
    fallback_succeeded INTEGER DEFAULT 0
);
```

---

## 9. Implementation Phases

### Phase 1: Core Framework (Week 1)
- [ ] Create `src/cmd/` directory structure
- [ ] Implement `cmd_main.zig` CLI entry
- [ ] Implement `runner.zig` 6-phase framework
- [ ] Implement `filter.zig` (migrate from existing)
- [ ] Implement `tracking.zig` with SQLite
- [ ] Implement `tee.zig`
- [ ] Basic build configuration

### Phase 2: Git Commands (Week 1-2)
- [ ] `git status` - Stats Extraction
- [ ] `git diff` - Grouping + Deduplication
- [ ] `git log` - Stats Extraction
- [ ] `git add/commit/push/pull` - Passthrough

### Phase 3: Cargo Commands (Week 2)
- [ ] `cargo test` - Failure Focus + State Machine
- [ ] `cargo build` - Errors Only
- [ ] `cargo clippy` - Grouping by Rule

### Phase 4: NPM/JS Commands (Week 2-3)
- [ ] `npm test` - Failure Focus
- [ ] `npm run build` - Errors Only
- [ ] `npm install` - Progress Strip
- [ ] `pnpm list` - Tree Compression
- [ ] `vitest` - Failure Focus

### Phase 5: Python Commands (Week 3)
- [ ] `pytest` - State Machine + Failure Focus
- [ ] `ruff check` - JSON Dual Mode
- [ ] `mypy` - Grouping by File

### Phase 6: Docker/Kubectl (Week 3)
- [ ] `docker ps/images/logs` - Stats/Dedupe
- [ ] `docker compose ps` - Stats
- [ ] `kubectl get pods/logs` - Stats/Dedupe

### Phase 7: Hook System (Week 3-4)
- [ ] Hook installation script
- [ ] Bash hook
- [ ] Zsh hook
- [ ] Hook verification tool

### Phase 8: Analytics (Week 4)
- [ ] `llmlite gain` - Statistics display
- [ ] `llmlite gain --graph` - ASCII graph
- [ ] `llmlite gain --history` - History view
- [ ] `llmlite discover` - Savings opportunities

### Phase 9: Remaining Commands (Week 4-6)
- [ ] Go commands
- [ ] AWS CLI
- [ ] Ruby commands
- [ ] System commands (ls, tree, grep, find)
- [ ] Additional commands as needed

---

## 10. Build Configuration

```zig
// build.zig additions

// llmlite-cmd executable
const cmd_main_module = b.addModule("cmd_main", .{
    .root_source_file = b.path("src/cmd/cmd_main.zig"),
    .target = target,
    .optimize = optimize,
    .dependencies = &.{
        .{ .name = "sqlite", .module = sqlite_module },
    },
});

const cmd_exe = b.addExecutable(.{
    .name = "llmlite-cmd",
    .root_module = cmd_main_module,
    .target = target,
    .optimize = optimize,
});

b.installArtifact(cmd_exe);
```

---

## 11. CLI Interface

```
llmlite-cmd - CLI tool for LLM token optimization

USAGE:
    llmlite-cmd <command> [args...]

COMMANDS:
    git <subcommand>     Git commands (status, diff, log, add, commit, push, pull)
    cargo <subcommand>   Cargo commands (test, build, clippy, bench)
    npm <command>        NPM commands (test, run, install, list)
    pytest               Python pytest
    docker <subcommand>  Docker commands (ps, images, logs)
    kubectl <subcommand> Kubernetes commands (get, logs, describe)
    system <command>     System commands (ls, tree, read, grep, find)

GLOBAL FLAGS:
    -u, --ultra-compact  ASCII icons, inline format (extra savings)
    -v, --verbose        Increase verbosity (-v, -vv, -vvv)
    -h, --help           Show this help

HOOK COMMANDS:
    llmlite-cmd init -g          Install shell hook
    llmlite-cmd init -g --uninstall  Remove hook

ANALYTICS:
    llmlite-cmd gain             Show token savings
    llmlite-cmd gain --graph     ASCII graph
    llmlite-cmd gain --history   Recent history
    llmlite-cmd discover         Find savings opportunities
```

---

## 12. File Structure Summary

```
src/cmd/
├── cmd_main.zig           # 500 lines - CLI entry, argument parsing
├── cmd.zig                # 300 lines - Command enum, dispatcher
│
├── cmds/                  # 15,000+ lines total
│   ├── mod.zig            # 200 lines - Command routing
│   ├── git/
│   │   └── git.zig        # 800 lines - 7 git commands
│   ├── cargo/
│   │   └── cargo.zig      # 600 lines - 4 cargo commands
│   ├── npm/
│   │   └── npm.zig        # 500 lines - npm/pnpm/vitest
│   ├── pytest/
│   │   └── pytest.zig     # 400 lines
│   ├── docker/
│   │   └── docker.zig     # 400 lines
│   ├── kubectl/
│   │   └── kubectl.zig    # 400 lines
│   ├── go/
│   │   └── go.zig         # 500 lines
│   ├── python/
│   │   ├── ruff.zig       # 300 lines
│   │   └── pip.zig        # 300 lines
│   ├── aws/
│   │   └── aws.zig        # 500 lines
│   ├── ruby/
│   │   └── ruby.zig       # 400 lines
│   └── system/
│       ├── ls.zig         # 200 lines
│       ├── tree.zig       # 200 lines
│       ├── read.zig       # 300 lines
│       ├── grep.zig       # 300 lines
│       └── find.zig       # 200 lines
│
├── core/                  # 5,000+ lines
│   ├── mod.zig            # 100 lines
│   ├── runner.zig         # 400 lines - 6-phase framework
│   ├── filter.zig         # 1,500 lines - 12+ strategies
│   ├── tracking.zig       # 600 lines - SQLite
│   ├── tee.zig            # 300 lines
│   ├── utils.zig          # 500 lines
│   └── constants.zig      # 100 lines
│
├── hooks/                 # 2,000+ lines
│   ├── mod.zig            # 100 lines
│   ├── hook.zig           # 500 lines - hook logic
│   ├── install.zig        # 400 lines - init commands
│   ├── bash_hook.sh       # 200 lines
│   └── zsh_hook.zsh       # 200 lines
│
└── analytics/            # 2,000+ lines
    ├── mod.zig            # 100 lines
    ├── gain.zig           # 1,000 lines - statistics
    └── discover.zig       # 800 lines - opportunities

TOTAL: ~25,000 lines of Zig code
```

---

## 13. Dependencies

| Dependency | Purpose | Type |
|------------|---------|------|
| Zig stdlib | Everything | Built-in |
| SQLite | Token tracking persistence | Zig package |

### SQLite Package (build.zig)

```zig
const sqlite_module = b.dependency("sqlite", .{
    .target = target,
    .optimize = optimize,
}).module("sqlite");

// Or use zig-sqlite from:
// https://github.com/vrischmann/zig-sqlite
```

---

## 14. Testing Strategy

### Unit Tests
- Filter strategy correctness
- Token estimation accuracy
- SQLite read/write

### Integration Tests
- Real command execution with fixtures
- Snapshot testing for filtered output
- Hook installation/verification

### Token Savings Validation
- Every command must achieve >= 60% reduction
- Measured against real project outputs

---

## 15. Performance Targets

| Metric | Target |
|--------|--------|
| Binary size | < 800KB (ReleaseSmall) |
| Command overhead | < 10ms |
| Filter latency | < 5ms |
| Startup time | < 50ms |
| Memory usage | < 10MB |

---

## 16. Comparison with RTK

| Feature | RTK | llmlite-cmd |
|---------|-----|-------------|
| Commands | 100+ | 100+ (planned) |
| Binary size | ~3-5MB | < 800KB |
| Filter strategies | 12 | 12+ |
| Hook systems | 3 (bash/zsh/fish) | 3 (planned) |
| Token tracking | SQLite | SQLite |
| Analytics | gain, discover | gain, discover (planned) |
| Tee recovery | Yes | Yes |
| Ultra-compact | Yes | Yes |
| Auto-rewrite | Yes | Yes (planned) |

---

## 17. Future Considerations

- WASM compilation for browser-based tools
- Plugin system for custom filters
- Remote configuration sync
- Multi-language support in analytics
