# llmlite-cmd Architecture

> Developer command companion with intelligent output filtering, cross-session CLI memory, shell hooks, and token savings tracking

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
│                           src/cmd/cmd.zig                                │
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
          │ src/cmd/core/   │         │ src/cmd/core/   │ │ src/cmd/core/   │
          │ git.zig         │         │ cargo.zig       │ │ npm.zig         │
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
│  │   utils     │  │   hooks     │  │  analytics  │  │ savings_reporter│   │
│  │   .zig      │  │   .zig      │  │   .zig      │  │     .zig        │   │
│  ├─────────────┤  ├─────────────┤  ├─────────────┤  ├─────────────────┤   │
│  │Tool detection│ │Hook install │  │gain/discover│  │Async proxy report│  │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────────┘   │
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │
│  │   config    │  │  proxy_helpers│ │  session    │  │    memory       │   │
│  │   .zig      │  │   .zig        │  │   .zig      │  │    (mod.zig)    │   │
│  ├─────────────┤  ├─────────────┤  ├─────────────┤  ├─────────────────┤   │
│  │TOML + env   │  │Proxy API    │  │Session mgmt │  │CLI Memory       │   │
│  └─────────────┘  └─────────────┘  └─────────────┘  │(claude-mem)     │   │
│                                                     └─────────────────┘   │
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
    ├── gain.zig           # Token savings statistics (proxy unified / local)
    ├── discover.zig       # Savings opportunity discovery
    ├── audit.zig          # Audit logging
    ├── ccusage.zig        # CC usage statistics
    ├── cc_economics.zig   # CC economics analysis
    ├── proxy_helpers.zig  # Proxy API helpers (queryProxyApi)
    ├── savings_reporter.zig # Async savings report upload to proxy
    ├── config.zig         # TOML config + env var overrides
    ├── session.zig        # Session management
    ├── key.zig            # Key management
    ├── lexer.zig          # Lexical analysis
    ├── rules.zig          # Filtering rules
    ├── learn.zig          # Learning mode
    ├── trust.zig          # Trust management
    ├── integrity.zig      # Integrity checking
    ├── sync.zig           # Sync functionality
    │
    └── memory/            # CLI Memory system (inspired by claude-mem)
        ├── mod.zig        # Module exports
        ├── types.zig      # MemoryEntry, MemoryCategory, MemoryFilter
        ├── db.zig         # SQLite schema + CRUD (~500 lines)
        ├── recorder.zig   # Auto-categorize and record commands
        ├── search.zig     # FTS5 + metadata search + timeline
        ├── session.zig    # Session boundary detection
        ├── migrate.zig    # Schema migrations
        └── utils.zig      # Project detection helpers
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

/// 6-phase execution framework (Phase 5.3 added for proxy reporting)
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

    // Phase 5: TRACK (local SQLite)
    try tracking.track(allocator, .{
        .original_cmd = raw_args,
        .rtk_cmd = cmd_name,
        .raw_output = raw_output,
        .filtered_output = filtered,
        .exit_code = exit_code,
    });

    // Phase 5.3: REPORT (async upload to proxy)
    // Sends SavingsReport to llmlite-proxy /tracking/savings
    // Fire-and-forget with JSONL fallback queue
    savings_reporter.reportAsync(.{
        .timestamp = time_compat.timestamp(io),
        .original_cmd = raw_args,
        .raw_output_tokens = estimateTokens(raw_output),
        .filtered_output_tokens = estimateTokens(filtered),
        .saved_tokens = saved,
        .savings_pct = pct,
        .exit_code = exit_code,
        .hostname = hostname,
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

pub fn save(tee: *Tee, io: std.Io, label: []const u8, raw_output: []const u8) !void {
    const timestamp = time_compat.timestamp(io);
    const filename = try std.fmt.allocPrint(
        tee.allocator,
        "{d}_{s}.log",
        .{ timestamp, label }
    );
    defer tee.allocator.free(filename);

    const filepath = try std.fs.path.join(tee.allocator, &.{ tee.directory, filename });
    defer tee.allocator.free(filepath);

    const file = try std.Io.Dir.createFileAbsolute(io, filepath, .{});
    defer file.close(io);

    try file.writeStreamingAll(io, raw_output);
    try tee.rotate(); // Remove old files if > max_files
}
```

---

## 6. Command Module Pattern

```zig
// src/cmd/core/git.zig

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

## 9. Proxy-Cmd Integration Data Flow

When both `llmlite-proxy` and `llmlite-cmd` are running, cmd automatically reports token savings to the proxy for centralized analytics.

```
┌─────────────────┐     POST /tracking/savings      ┌─────────────────────────┐
│  llmlite-cmd    │ ───────────────────────────────▶ │  llmlite-proxy:4000     │
│  (after filter) │  JSON: SavingsReport            │  ┌─────────────────┐    │
│                 │                                 │  │ SavingsStore    │    │
│  ┌───────────┐  │     (fire-and-forget thread)    │  │ (in-memory +   │    │
│  │ JSONL     │  │                                 │  │  mutex)         │    │
│  │ Fallback  │  │◀─────────────────────────────── │  └─────────────────┘    │
│  │ Queue     │  │  On failure, write to local     │         │               │
│  │ (retry)   │  │  ~/.local/share/llmlite/        │         ▼               │
│  └───────────┘  │  pending_reports.jsonl          │  ┌─────────────────┐    │
└─────────────────┘                                 │  │ UnifiedHandler  │    │
                                                    │  │ GET /analytics/ │    │
                                                    │  │ unified?days=N  │    │
                                                    │  └─────────────────┘    │
                                                    └─────────────────────────┘
                                                              │
                                                              ▼
                                                    ┌─────────────────────────┐
                                                    │  llmlite-cmd gain       │
                                                    │  (queries unified)      │
                                                    └─────────────────────────┘
```

### Shared Types (`src/shared/analytics_types.zig`)

Shared between proxy and cmd to avoid duplication:

```zig
pub const SavingsReport = struct {
    timestamp: i64,
    original_cmd: []const u8,
    raw_output_tokens: u64,
    filtered_output_tokens: u64,
    saved_tokens: u64,
    savings_pct: f64,
    exit_code: i32,
    hostname: []const u8,
};

pub const UnifiedResponse = struct {
    api_cost: ApiCostSummary,    // Proxy-side API spend
    cmd_savings: CmdSavingsSummary, // Cmd-reported token savings
    net_cost: f64,
};
```

### Proxy Modules

| Module | File | Description |
|--------|------|-------------|
| `SavingsStore` | `src/proxy/savings_store.zig` | Thread-safe in-memory storage for SavingsReport |
| `SavingsHandler` | `src/proxy/handlers/savings_handler.zig` | POST /tracking/savings |
| `UnifiedHandler` | `src/proxy/handlers/unified_handler.zig` | GET /analytics/unified |

### Cmd Modules

| Module | File | Description |
|--------|------|-------------|
| `SavingsReporter` | `src/cmd/core/savings_reporter.zig` | Async upload with 50ms probe timeout |
| `Gain` | `src/cmd/core/gain.zig` | Query proxy or local history.db |
| `Config` | `src/cmd/core/config.zig` | TOML `[analytics]` / `[analytics.proxy]` parsing |

### Config Example

```toml
[analytics]
enabled = true
retention_days = 90
sync_interval_secs = 300

[analytics.proxy]
host = "localhost"
port = 4001
```

Environment variable overrides:
- `LLMLITE_PROXY_HOST` — overrides `analytics.proxy.host`
- `LLMLITE_PROXY_PORT` — overrides `analytics.proxy.port`

---

## 10. CLI Memory System (claude-mem inspired)

The memory system is a cross-session command memory inspired by [claude-mem](https://github.com/NousResearch/claude-mem). It records, categorizes, and retrieves CLI command executions with full-text search.

### Data Model

```zig
pub const MemoryCategory = enum {
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
```

### SQLite Schema

```sql
-- Memories table
CREATE TABLE memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category TEXT NOT NULL,
    summary TEXT NOT NULL,
    facts TEXT,           -- JSON array
    context TEXT,
    tags TEXT,            -- JSON array
    commands TEXT,        -- JSON array
    project TEXT,
    session_id TEXT,
    created_at INTEGER NOT NULL,
    exit_code INTEGER,
    content_hash BLOB     -- SHA-256 for deduplication
);

-- FTS5 virtual table for full-text search
CREATE VIRTUAL TABLE memories_fts USING fts5(
    summary, context, tags, commands,
    content='memories', content_rowid='id'
);

-- Session summaries
CREATE TABLE session_summaries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    project TEXT,
    task TEXT,
    learned TEXT,
    completed TEXT,
    followups TEXT,
    notes TEXT,
    command_count INTEGER,
    created_at INTEGER NOT NULL
);
```

### Recording Triggers

The `Recorder` module automatically categorizes command executions:

| Trigger | Category | Detection |
|---------|----------|-----------|
| Command failed | `mistake` | `exit_code != 0` |
| Repeated command | `pattern` | Same command within 30s |
| First successful build | `feat` | `cargo build` success after failure |
| Config file modified | `config` | File extension ∈ {json, toml, yaml} |
| Tests now passing | `fix` | Was failing, now passing |
| New tool discovered | `learn` | Command not in known set |

### Privacy

- **Normal mode**: Full recording with SQLite persistence
- **Private mode**: In-memory only, no persistence (`LLMLITE_MEMORY_PRIVATE=1`)
- **Excluded patterns**: Configurable regex patterns to skip recording

### Three-Layer Search

```bash
# Layer 1: Quick search (compact results)
llmlite-cmd memory search "auth bug"
# → | ID | Time | Cat | Summary |
# → | #1 | 2d ago | fix | Fixed JWT expiration |

# Layer 2: Timeline context
llmlite-cmd memory timeline 1
# → Chronological context (5 before, 5 after)

# Layer 3: Full details
llmlite-cmd memory show 1
# → Complete memory entry with facts, tags, commands
```

### Configuration

```toml
[memory]
enabled = true
auto_record = true
max_context_length = 2000
dedup_window_secs = 30

[memory.privacy]
mode = "normal"          # "normal" or "private"
excluded_patterns = ["*password*", "*secret*", "*token*"]
```

### Mode System

The memory system supports four work modes that change which categories are recorded and which are downgraded to `other`:

| Mode | Focus | Ignored (→ other) | Use Case |
|------|-------|-------------------|----------|
| `code` (default) | fix, feat, mistake, pattern | — | Daily coding |
| `infra` | config, decision, pattern | feat, refactor | Deploy/scale/monitor |
| `data` | config, pattern, learn | feat, refactor | ETL/schema/query |
| `writing` | decision, learn, other | err, mistake | Documentation/writing |

```bash
llmlite-cmd memory mode show       # Current mode + focus/ignore list
llmlite-cmd memory mode set infra  # Switch mode
llmlite-cmd memory mode list       # All modes
```

Mode is persisted in `~/.config/llmlite/config.toml` under `[memory] mode = "..."`.

### Module Summary

| File | Lines | Purpose |
|------|-------|---------|
| `types.zig` | 98 | Data structures |
| `db.zig` | 489 | SQLite CRUD + migrations |
| `recorder.zig` | 281 | Auto-recording + categorization |
| `search.zig` | 242 | FTS5 + metadata search |
| `session.zig` | 370 | Session management |
| `migrate.zig` | 161 | Schema version migrations |
| `utils.zig` | 120 | Project detection helpers |
| `modes.zig` | 220 | Work mode system (code/infra/data/writing) |

---

## 11. Implementation Phases

### Phase 1: Core Framework (Week 1)
- [x] Create `src/cmd/` directory structure
- [x] Implement `cmd_main.zig` CLI entry
- [x] Implement `runner.zig` 6-phase framework
- [x] Implement `filter.zig` (migrate from existing)
- [x] Implement `tracking.zig` with SQLite
- [x] Implement `tee.zig`
- [x] Basic build configuration

### Phase 2: Git Commands (Week 1-2)
- [x] `git status` - Stats Extraction
- [x] `git diff` - Grouping + Deduplication
- [x] `git log` - Stats Extraction
- [x] `git add/commit/push/pull` - Passthrough

### Phase 3: Cargo Commands (Week 2)
- [x] `cargo test` - Failure Focus + State Machine
- [x] `cargo build` - Errors Only
- [x] `cargo clippy` - Grouping by Rule

### Phase 4: NPM/JS Commands (Week 2-3)
- [x] `npm test` - Failure Focus
- [x] `npm run build` - Errors Only
- [x] `npm install` - Progress Strip
- [x] `pnpm list` - Tree Compression
- [x] `vitest` - Failure Focus

### Phase 5: Python Commands (Week 3)
- [x] `pytest` - State Machine + Failure Focus
- [x] `ruff check` - JSON Dual Mode
- [x] `mypy` - Grouping by File

### Phase 6: Docker/Kubectl (Week 3)
- [x] `docker ps/images/logs` - Stats/Dedupe
- [x] `docker compose ps` - Stats
- [x] `kubectl get pods/logs` - Stats/Dedupe

### Phase 7: Hook System (Week 3-4)
- [x] Hook installation script
- [x] Bash hook
- [x] Zsh hook
- [x] Hook verification tool

### Phase 8: Analytics (Week 4)
- [x] `llmlite gain` - Statistics display (proxy unified / local fallback)
- [x] `llmlite gain --graph` - ASCII graph
- [x] `llmlite gain --history` - History view
- [x] `llmlite gain --local` - Force local data (skip proxy)
- [x] `llmlite gain --json` / `--csv` - Machine-readable output
- [x] `llmlite discover` - Savings opportunities

### Phase 9: CLI Memory (Week 5-6)
- [x] `memory/` module structure - types, db, recorder, search, session
- [x] SQLite schema + migrations - memories, memories_fts, session_summaries
- [x] Auto-recording with categorization - fix, feat, mistake, pattern, etc.
- [x] FTS5 full-text search - fallback to metadata search
- [x] Timeline context retrieval
- [x] Privacy mode (normal / private)
- [x] `llmlite memory search` - CLI search command
- [x] `llmlite memory list` - CLI list command
- [x] `llmlite memory show` - CLI show command
- [x] `llmlite memory timeline` - CLI timeline command
- [x] Mode system (code/infra/data/writing)
- [ ] Learn module memory integration

### Phase 9: Remaining Commands (Week 4-6)
- [x] Go commands (`go test`, `golangci-lint`)
- [x] AWS CLI
- [x] Ruby commands (`rake`, `rspec`, `rubocop`, `bundle`)
- [x] System commands (`ls`, `tree`, `read`, `grep`, `find`, `wc`)
- [x] Additional commands: zig, kiro, biome, terraform, helm, gcloud, ansible-playbook, gradle, mvn, swift, just, mise, task, jj, and more

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
llmlite-cmd - Developer command companion

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
    llmlite-cmd gain             Show token savings (proxy or local)
    llmlite-cmd gain --local     Force local data, skip proxy
    llmlite-cmd gain --graph     ASCII graph
    llmlite-cmd gain --json      JSON output
    llmlite-cmd gain --csv       CSV output
    llmlite-cmd gain --history   Recent history
    llmlite-cmd discover         Find savings opportunities
```

---

## 12. File Structure Summary

```
src/cmd/
├── cmd_main.zig           # 136 lines - CLI entry point (main())
├── cmd.zig                # 3,819 lines - Command dispatcher (80+ commands)
│
└── core/                  # ~29,500 lines total
    ├── mod.zig            # 89 lines - Module re-exports
    │
    # Core Infrastructure (~4,500 lines)
    ├── runner.zig         # 285 lines - 6-phase execution framework
    ├── filter.zig         # 762 lines - 12+ filtering strategies
    ├── tracking.zig       # 187 lines - SQLite persistent tracking
    ├── tee.zig            # 135 lines - Failure recovery
    ├── utils.zig          # 150 lines - Utility functions
    ├── hook.zig           # 1,072 lines - Shell hook management (bash/zsh)
    ├── config.zig         # 280 lines - TOML + env var overrides
    ├── session.zig        # 662 lines - Session management
    ├── key.zig            # 134 lines - Key management
    ├── lexer.zig          # 505 lines - Lexical analysis
    ├── rules.zig          # 1,770 lines - Filtering rules
    ├── learn.zig          # 1,107 lines - Learning mode
    ├── trust.zig          # 246 lines - Trust management
    ├── integrity.zig      # 220 lines - Integrity checking
    ├── sync.zig           # 473 lines - Sync functionality
    ├── read.zig           # 275 lines - File reading
    ├── json.zig           # 310 lines - JSON processing
    ├── audit.zig          # 166 lines - Audit logging
    ├── ccusage.zig        # 351 lines - CC usage statistics
    ├── cc_economics.zig   # 376 lines - CC economics analysis
    │
    # Proxy-Cmd Integration (~1,000 lines)
    ├── proxy_helpers.zig  # 70 lines - Proxy API helpers (queryProxyApi)
    ├── savings_reporter.zig # 396 lines - Async proxy upload + JSONL queue
    ├── gain.zig           # 558 lines - Token savings statistics (proxy/local)
    ├── discover.zig       # 823 lines - Savings opportunity discovery
    │
    # CLI Memory System (~2,250 lines)
    ├── modes.zig          # 220 lines - Work mode system (code/infra/data/writing)
    ├── memory_cmd.zig     # 457 lines - Memory command dispatcher
    ├── memory/            # 1,791 lines - Memory core library
    │   ├── mod.zig        # 30 lines - Module exports
    │   ├── types.zig      # 98 lines - MemoryEntry, MemoryCategory, etc.
    │   ├── db.zig         # 489 lines - SQLite CRUD + migrations
    │   ├── recorder.zig   # 281 lines - Auto-recording + categorization
    │   ├── search.zig     # 242 lines - FTS5 + metadata search
    │   ├── session.zig    # 370 lines - Session boundary detection
    │   ├── migrate.zig    # 161 lines - Schema migrations
    │   └── utils.zig      # 120 lines - Project detection helpers
    │
    # Command Modules (~50 modules, ~20,000 lines)
    ├── git.zig            # 476 lines - Git commands (status, diff, log, add, ...)
    ├── cargo.zig          # 476 lines - Cargo commands (test, build, clippy, ...)
    ├── npm.zig            # 206 lines - NPM commands (test, run, install, list)
    ├── pnpm.zig           # 216 lines - PNPM commands
    ├── vitest.zig         # 230 lines - Vitest testing
    ├── pytest.zig         # 342 lines - Python pytest
    ├── docker.zig         # 341 lines - Docker commands (ps, images, logs, ...)
    ├── kubectl.zig        # 391 lines - Kubernetes commands
    ├── go_test.zig        # 426 lines - Go test
    ├── golangci_lint.zig  # 200 lines - golangci-lint
    ├── aws.zig            # 308 lines - AWS CLI
    ├── curl.zig           # 200 lines - curl commands
    ├── eslint.zig         # 184 lines - ESLint
    ├── tsc.zig            # 295 lines - TypeScript compiler
    ├── prettier.zig       # 214 lines - Prettier formatting
    ├── prisma.zig         # 139 lines - Prisma ORM
    ├── playwright.zig     # 147 lines - Playwright testing
    ├── nextjs.zig         # 145 lines - Next.js
    ├── pip.zig            # 202 lines - pip package manager
    ├── mypy.zig           # 198 lines - mypy type checking
    ├── ruff.zig           # 291 lines - Ruff linter
    ├── rake.zig           # 100 lines - Ruby Rake
    ├── rspec.zig          # 190 lines - Ruby RSpec
    ├── rubocop.zig        # 193 lines - Ruby RuboCop
    ├── dotnet.zig         # 232 lines - .NET CLI
    ├── java.zig           # 394 lines - Java commands
    ├── toml_filter.zig    # 1,489 lines - TOML filtering
    └── ... (40+ more command modules)

TOTAL: ~33,500 lines of Zig code
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
- SavingsReporter enqueue/retry logic
- Gain command normalization and output

### Integration Tests
- Real command execution with fixtures
- Snapshot testing for filtered output
- Hook installation/verification
- Proxy-cmd end-to-end data flow

### Property-Based Tests
- 40 correctness properties covering:
  - Serialization round-trips (SavingsReport, UnifiedResponse)
  - Invalid JSON rejection
  - estimateTokens monotonicity
  - Config parsing round-trip
  - Time range filtering correctness

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
