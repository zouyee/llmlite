//! llmlite-cmd - CLI Tool for LLM Token Optimization

const std = @import("std");
const cmd = @import("cmd");
const cmd_core = @import("cmd_core");

pub fn main(init: std.process.Init) !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const io = init.io;

    // Get environment variables for memory subsystem
    const home_dir: ?[]const u8 = if (std.c.getenv("HOME")) |ptr|
        std.mem.sliceTo(ptr, 0)
    else
        null;
    _ = home_dir;

    const memory_disabled = if (std.c.getenv("LLMLITE_MEMORY_DISABLED")) |ptr| blk: {
        const val = std.mem.sliceTo(ptr, 0);
        break :blk std.mem.eql(u8, val, "1") or std.mem.eql(u8, val, "true");
    } else false;
    _ = memory_disabled;

    try cmd_core.tracking.init(allocator);
    defer cmd_core.tracking.deinit();

    try cmd_core.tee.init(allocator);
    defer cmd_core.tee.deinit();

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) {
        try printHelp();
        return;
    }

    var verbose: u8 = 0;
    var ultra_compact = false;
    var idx: usize = 1;

    while (idx < args.len) : (idx += 1) {
        const arg = args[idx];
        if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            verbose = 1;
        } else if (std.mem.eql(u8, arg, "-vv")) {
            verbose = 2;
        } else if (std.mem.eql(u8, arg, "-vvv")) {
            verbose = 3;
        } else if (std.mem.eql(u8, arg, "-u") or std.mem.eql(u8, arg, "--ultra-compact")) {
            ultra_compact = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printHelp();
            return;
        } else {
            break;
        }
    }

    if (idx >= args.len) {
        try printHelp();
        return;
    }

    const command = args[idx];
    const cmd_args = args[idx + 1 ..];

    const exit_code = try cmd.dispatch(allocator, io, command, cmd_args, verbose, ultra_compact);

    std.process.exit(@as(u8, @intCast(exit_code & 0xFF)));
}

fn printHelp() !void {
    std.debug.print("llmlite-cmd - CLI tool for LLM token optimization (inspired by RTK)\n\n", .{});
    std.debug.print("USAGE:\n", .{});
    std.debug.print("    llmlite-cmd <command> [args...]\n\n", .{});
    std.debug.print("COMMANDS:\n", .{});
    std.debug.print("    git <subcommand>     Git commands (status, diff, log, fetch, stash, branch, checkout, add, commit, push, pull, rebase, merge)\n", .{});
    std.debug.print("    cargo <subcommand>   Cargo commands (test, build, clippy, check, nextest)\n", .{});
    std.debug.print("    npm <command>        NPM commands (test, run, install, list) - auto-detects pnpm/yarn\n", .{});
    std.debug.print("    pytest               Python pytest (filtered for test failures)\n", .{});
    std.debug.print("    docker <subcommand>  Docker commands (ps, images, logs)\n", .{});
    std.debug.print("    kubectl <subcommand> Kubernetes (get, logs, pods, services, describe, apply, delete, top, exec)\n", .{});
    std.debug.print("    lint [tool]          Linter (eslint, biome, ruff, prettier, tsc) - auto-detects\n", .{});
    std.debug.print("    go <command>         Go commands (test, build, vet)\n", .{});
    std.debug.print("    ls [path]            List directory contents (tree format)\n", .{});
    std.debug.print("    read <file> [start] [end]  Read file with line numbers\n", .{});
    std.debug.print("    find [path] [-name pattern] [-type f|d]  Find files\n", .{});
    std.debug.print("    grep <pattern> [path] [-r] [--no-grouped]  Search with grouped output\n", .{});
    std.debug.print("    diff <file1> <file2>  Compare two files (RTK-inspired)\n", .{});
    std.debug.print("    tree [path] [-L depth]  Display directory tree (RTK-inspired)\n", .{});
    std.debug.print("    json <file>           Show JSON structure (RTK-inspired)\n", .{});
    std.debug.print("    env [-f pattern] [-p]  Show environment variables (RTK-inspired)\n", .{});
    std.debug.print("    smart <file>         2-line code summary (RTK-inspired)\n", .{});
    std.debug.print("    vitest                Vitest test runner (RTK-inspired)\n", .{});
    std.debug.print("    playwright            Playwright E2E tests (RTK-inspired)\n", .{});
    std.debug.print("    golangci-lint         Go linting (RTK-inspired)\n", .{});
    std.debug.print("    curl <url>            Fetch URL with progress stripping (RTK-inspired)\n", .{});
    std.debug.print("    aws <subcommand>      AWS CLI with output filtering (RTK-inspired)\n", .{});
    std.debug.print("    deps                 Dependencies summary (RTK-inspired)\n", .{});
    std.debug.print("    rake [task]          Ruby rake task runner (RTK-inspired)\n", .{});
    std.debug.print("    rspec                Ruby RSpec test runner (RTK-inspired)\n", .{});
    std.debug.print("    rubocop              Ruby linting (RTK-inspired)\n", .{});
    std.debug.print("    bundle [subcommand]  Ruby gem management (RTK-inspired)\n", .{});
    std.debug.print("    pip <subcommand>     Python pip (list, outdated)\n", .{});
    std.debug.print("    wget <url>           Download with progress stripping\n", .{});
    std.debug.print("    prettier [--check]   Format check (RTK-inspired)\n", .{});
    std.debug.print("    uv <subcommand>      Modern Python package manager\n", .{});
    std.debug.print("    prisma <subcommand>  Prisma CLI (migrate, generate, db pull)\n", .{});
    std.debug.print("    next <subcommand>    Next.js (build, dev, start, lint)\n", .{});
    std.debug.print("    psql <args>         PostgreSQL client (compact output)\n", .{});
    std.debug.print("    pnpm <subcommand>    pnpm (list, outdated, install, build, test)\n", .{});
    std.debug.print("    dotnet <subcommand>  .NET CLI (build, test, restore, format)\n", .{});
    std.debug.print("    compose <subcommand> Docker Compose (ps, logs, build, up, down)\n", .{});
    std.debug.print("    wc <args>           Word/line/byte count (compact)\n", .{});
    std.debug.print("    mypy <args>         Mypy type checker (grouped errors)\n", .{});
    std.debug.print("    gt <subcommand>     Graphite (log, submit, sync, restack)\n", .{});
    std.debug.print("    npx <command>       npx with intelligent routing\n", .{});
    std.debug.print("    err <command>       Run command, show errors only\n", .{});
    std.debug.print("    rewrite <cmd>       Rewrite to llmlite (for hooks)\n", .{});
    std.debug.print("    format              Auto-detect and format (prettier, ruff, rustfmt, gofmt)\n", .{});
    std.debug.print("    gh <command> [args] GitHub CLI wrapper\n", .{});
    std.debug.print("    zig <subcommand>    Zig compiler (build, test, fmt, ast, translate-c)\n\n", .{});
    std.debug.print("ANALYTICS:\n", .{});
    std.debug.print("    gain [--graph] [--json] [--all]    Show token savings statistics\n", .{});
    std.debug.print("    discover [--all] [--since N]       Find missed savings opportunities\n", .{});
    std.debug.print("    log [-n N] [--dedup]              Show command log (RTK-inspired)\n", .{});
    std.debug.print("    summary                         Show command usage summary\n", .{});
    std.debug.print("    session                         Show llmlite adoption across sessions\n\n", .{});
    std.debug.print("LLM:\n", .{});
    std.debug.print("    llm chat <prompt>                Chat completion via proxy\n", .{});
    std.debug.print("    llm complete <prompt>            Single-shot completion\n", .{});
    std.debug.print("    llm embed <text>                 Generate embeddings\n", .{});
    std.debug.print("    llm models [--provider <p>]      List available models\n", .{});
    std.debug.print("    llm providers                    List supported providers\n\n", .{});

    std.debug.print("PROXY:\n", .{});
    std.debug.print("    proxy start [--tui]              Start llmlite-proxy (with TUI dashboard)\n", .{});
    std.debug.print("    proxy status                     Check if proxy is running\n", .{});
    std.debug.print("    proxy health                     Health check (readiness probe)\n", .{});
    std.debug.print("    proxy metrics                    Prometheus metrics\n", .{});
    std.debug.print("    proxy providers                  List configured providers\n", .{});
    std.debug.print("    proxy analytics <type>           Analytics (gain|team|sessions|unified)\n", .{});
    std.debug.print("    proxy keys list|create|revoke    Virtual key management\n", .{});
    std.debug.print("    proxy logs                       Show proxy logs (journalctl)\n", .{});
    std.debug.print("    proxy config                     Show config file locations\n\n", .{});
    std.debug.print("SETUP:\n", .{});
    std.debug.print("    init [-g] [--agent x]             Install shell hook for AI tools\n", .{});
    std.debug.print("    hook [install|uninstall|show]     Manage AI tool hooks\n\n", .{});
    std.debug.print("GLOBAL FLAGS:\n", .{});
    std.debug.print("    -u, --ultra-compact  ASCII icons, inline format\n", .{});
    std.debug.print("    -v, --verbose        Increase verbosity (-v, -vv, -vvv)\n", .{});
    std.debug.print("    -h, --help           Show this help\n\n", .{});
    std.debug.print("EXAMPLES:\n", .{});
    std.debug.print("    llmlite-cmd git status\n", .{});
    std.debug.print("    llmlite-cmd cargo test\n", .{});
    std.debug.print("    llmlite-cmd npm test -u\n", .{});
    std.debug.print("    llmlite-cmd gain --graph\n", .{});
    std.debug.print("    llmlite-cmd lint biome\n", .{});
    std.debug.print("    llmlite-cmd smart src/main.zig\n", .{});
    std.debug.print("    llmlite-cmd deps\n\n", .{});
    std.debug.print("Token savings: 60-90% reduction in LLM token usage\n", .{});
}
