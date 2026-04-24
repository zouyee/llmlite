//! Command Dispatcher

const std = @import("std");
const core = @import("cmd_core");
const time_compat = @import("time_compat");

var global_verbose: u8 = 0;
var global_ultra_compact: bool = false;
var g_cmd_allocator: std.mem.Allocator = std.heap.page_allocator;
var g_cmd_io: std.Io = undefined;
pub var g_cmd_executable_path: ?[]const u8 = null;

pub fn dispatch(
    allocator: std.mem.Allocator,
    io: std.Io,
    command: []const u8,
    args: []const [:0]const u8,
    verbose: u8,
    ultra_compact: bool,
    argv0: ?[]const u8,
) !i32 {
    g_cmd_allocator = allocator;
    g_cmd_io = io;
    core.g_io = io;
    core.hook.g_io = io;
    core.config.g_io = io;
    core.memory.utils.g_io = io;
    core.gain.g_io = io;
    global_verbose = verbose;
    global_ultra_compact = ultra_compact;

    // Resolve executable path to absolute for hook installation
    if (argv0) |a0| {
        if (g_cmd_executable_path == null) {
            if (std.fs.path.isAbsolute(a0)) {
                g_cmd_executable_path = try allocator.dupe(u8, a0);
            } else {
                const cwd = std.process.currentPathAlloc(io, allocator) catch null;
                if (cwd) |c| {
                    defer allocator.free(c);
                    const resolved = std.fs.path.resolve(allocator, &.{ c, a0 }) catch null;
                    if (resolved) |r| {
                        g_cmd_executable_path = r;
                    }
                }
            }
        }
    }

    if (verbose > 0) {
        std.log.info("dispatching command: {s}", .{command});
    }

    if (std.mem.eql(u8, command, "git")) {
        return dispatchGit(args);
    } else if (std.mem.eql(u8, command, "cargo")) {
        return dispatchCargo(args);
    } else if (std.mem.eql(u8, command, "npm")) {
        return dispatchNpm(args);
    } else if (std.mem.eql(u8, command, "pytest")) {
        return dispatchPytest(args);
    } else if (std.mem.eql(u8, command, "docker")) {
        return dispatchDocker(args);
    } else if (std.mem.eql(u8, command, "kubectl")) {
        return dispatchKubectl(args);
    } else if (std.mem.eql(u8, command, "init")) {
        return dispatchInit(args);
    } else if (std.mem.eql(u8, command, "config")) {
        return dispatchConfig(args);
    } else if (std.mem.eql(u8, command, "gain")) {
        return dispatchGain(args);
    } else if (std.mem.eql(u8, command, "discover")) {
        return dispatchDiscover(args);
    } else if (std.mem.eql(u8, command, "go")) {
        return dispatchGo(args);
    } else if (std.mem.eql(u8, command, "lint")) {
        return dispatchLint(args);
    } else if (std.mem.eql(u8, command, "hook")) {
        return dispatchHook(args);
    } else if (std.mem.eql(u8, command, "ls")) {
        return dispatchLs(args);
    } else if (std.mem.eql(u8, command, "read")) {
        return dispatchRead(args);
    } else if (std.mem.eql(u8, command, "find")) {
        return dispatchFind(args);
    } else if (std.mem.eql(u8, command, "grep")) {
        return dispatchGrep(args);
    } else if (std.mem.eql(u8, command, "gh")) {
        return dispatchGh(args);
    } else if (std.mem.eql(u8, command, "diff")) {
        return dispatchDiff(args);
    } else if (std.mem.eql(u8, command, "tree")) {
        return dispatchTree(args);
    } else if (std.mem.eql(u8, command, "json")) {
        return dispatchJson(args);
    } else if (std.mem.eql(u8, command, "env")) {
        return dispatchEnv(args);
    } else if (std.mem.eql(u8, command, "smart")) {
        return dispatchSmart(args);
    } else if (std.mem.eql(u8, command, "vitest")) {
        return dispatchVitest(args);
    } else if (std.mem.eql(u8, command, "golangci-lint")) {
        return dispatchGolangciLint(args);
    } else if (std.mem.eql(u8, command, "curl")) {
        return dispatchCurl(args);
    } else if (std.mem.eql(u8, command, "aws")) {
        return dispatchAws(args);
    } else if (std.mem.eql(u8, command, "deps")) {
        return dispatchDeps(args);
    } else if (std.mem.eql(u8, command, "playwright")) {
        return dispatchPlaywright(args);
    } else if (std.mem.eql(u8, command, "rake")) {
        return dispatchRake(args);
    } else if (std.mem.eql(u8, command, "rspec")) {
        return dispatchRspec(args);
    } else if (std.mem.eql(u8, command, "rubocop")) {
        return dispatchRubocop(args);
    } else if (std.mem.eql(u8, command, "bundle")) {
        return dispatchBundle(args);
    } else if (std.mem.eql(u8, command, "pip")) {
        return dispatchPip(args);
    } else if (std.mem.eql(u8, command, "wget")) {
        return dispatchWget(args);
    } else if (std.mem.eql(u8, command, "prettier")) {
        return dispatchPrettier(args);
    } else if (std.mem.eql(u8, command, "uv")) {
        return dispatchUv(args);
    } else if (std.mem.eql(u8, command, "session")) {
        return dispatchSession(args);
    } else if (std.mem.eql(u8, command, "prisma")) {
        return dispatchPrisma(args);
    } else if (std.mem.eql(u8, command, "next")) {
        return dispatchNext(args);
    } else if (std.mem.eql(u8, command, "log")) {
        return dispatchLog(args);
    } else if (std.mem.eql(u8, command, "summary")) {
        return dispatchSummary(args);
    } else if (std.mem.eql(u8, command, "proxy")) {
        return dispatchProxy(args);
    } else if (std.mem.eql(u8, command, "psql")) {
        return dispatchPsql(args);
    } else if (std.mem.eql(u8, command, "pnpm")) {
        return dispatchPnpm(args);
    } else if (std.mem.eql(u8, command, "dotnet")) {
        return dispatchDotnet(args);
    } else if (std.mem.eql(u8, command, "compose")) {
        return dispatchCompose(args);
    } else if (std.mem.eql(u8, command, "wc")) {
        return dispatchWc(args);
    } else if (std.mem.eql(u8, command, "mypy")) {
        return dispatchMypy(args);
    } else if (std.mem.eql(u8, command, "gt")) {
        return dispatchGt(args);
    } else if (std.mem.eql(u8, command, "npx")) {
        return dispatchNpx(args);
    } else if (std.mem.eql(u8, command, "err")) {
        return dispatchErr(args);
    } else if (std.mem.eql(u8, command, "rewrite")) {
        return dispatchRewrite(args);
    } else if (std.mem.eql(u8, command, "format")) {
        return dispatchFormat(args);
    } else if (std.mem.eql(u8, command, "audit")) {
        return dispatchAudit(args);
    } else if (std.mem.eql(u8, command, "verify")) {
        return dispatchVerify(args);
    } else if (std.mem.eql(u8, command, "learn")) {
        return dispatchLearn(args);
    } else if (std.mem.eql(u8, command, "economics")) {
        return dispatchEconomics(args);
    } else if (std.mem.eql(u8, command, "trust")) {
        return dispatchTrust(args);
    } else if (std.mem.eql(u8, command, "untrust")) {
        return dispatchUntrust(args);
    } else if (std.mem.eql(u8, command, "terraform")) {
        return dispatchTerraform(args);
    } else if (std.mem.eql(u8, command, "helm")) {
        return dispatchHelm(args);
    } else if (std.mem.eql(u8, command, "gcloud")) {
        return dispatchGcloud(args);
    } else if (std.mem.eql(u8, command, "ansible-playbook")) {
        return dispatchAnsiblePlaybook(args);
    } else if (std.mem.eql(u8, command, "make")) {
        return dispatchMake(args);
    } else if (std.mem.eql(u8, command, "mix")) {
        return dispatchMix(args);
    } else if (std.mem.eql(u8, command, "pre-commit")) {
        return dispatchPreCommit(args);
    } else if (std.mem.eql(u8, command, "shellcheck")) {
        return dispatchShellcheck(args);
    } else if (std.mem.eql(u8, command, "hadolint")) {
        return dispatchHadolint(args);
    } else if (std.mem.eql(u8, command, "gradle")) {
        return dispatchGradle(args);
    } else if (std.mem.eql(u8, command, "mvn")) {
        return dispatchMvn(args);
    } else if (std.mem.eql(u8, command, "swift")) {
        return dispatchSwift(args);
    } else if (std.mem.eql(u8, command, "just")) {
        return dispatchJust(args);
    } else if (std.mem.eql(u8, command, "mise")) {
        return dispatchMise(args);
    } else if (std.mem.eql(u8, command, "task")) {
        return dispatchTask(args);
    } else if (std.mem.eql(u8, command, "jj")) {
        return dispatchJj(args);
    } else if (std.mem.eql(u8, command, "ruff")) {
        return dispatchRuff(args);
    } else if (std.mem.eql(u8, command, "biome")) {
        return dispatchBiome(args);
    } else if (std.mem.eql(u8, command, "eslint")) {
        return dispatchEslint(args);
    } else if (std.mem.eql(u8, command, "tsc")) {
        return dispatchTsc(args);
    } else if (std.mem.eql(u8, command, "zig")) {
        return dispatchZig(args);
    } else if (std.mem.eql(u8, command, "kiro")) {
        return dispatchKiro(args);
    } else if (std.mem.eql(u8, command, "memory") or std.mem.eql(u8, command, "mem")) {
        return dispatchMemory(args);
    } else if (std.mem.eql(u8, command, "llm")) {
        return core.llm.dispatch(g_cmd_allocator, g_cmd_io, args);
    } else {
        std.log.err("unknown command: {s}", .{command});
        std.debug.print("unknown command: {s}\n", .{command});
        return 1;
    }
}

fn dispatchGit(args: []const [:0]const u8) !i32 {
    if (args.len == 0) {
        std.debug.print("git: missing subcommand\n", .{});
        return 1;
    }

    const subcmd = args[0];

    if (std.mem.eql(u8, subcmd, "status")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "status" }, "git status", "git status", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = if (global_ultra_compact) .ultra_compact else .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "diff")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "diff" }, "git diff", "git diff", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .grouping,
        });
    } else if (std.mem.eql(u8, subcmd, "log")) {
        // --oneline -20 is already compact; no post-filter needed
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "log", "--oneline", "-20" }, "git log", "git log", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .none,
        });
    } else if (std.mem.eql(u8, subcmd, "add")) {
        return core.runner.runPassthrough(g_cmd_allocator, &.{ "git", "add" }, global_verbose, g_cmd_io);
    } else if (std.mem.eql(u8, subcmd, "commit")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "commit" }, "git commit", "git commit", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "push")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "push" }, "git push", "git push", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "pull")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "pull" }, "git pull", "git pull", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "branch")) {
        // RTK-style: compact branch listing with current branch marked
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "branch" }, "git branch", "git branch", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "checkout")) {
        // Just pass through - checkout can have many forms
        return core.runner.runPassthrough(g_cmd_allocator, &.{ "git", "checkout" }, global_verbose, g_cmd_io);
    } else if (std.mem.eql(u8, subcmd, "fetch")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "fetch" }, "git fetch", "git fetch", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "stash")) {
        // git stash list, pop, push, drop
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("git");
        try argv.append("stash");
        for (args[1..]) |arg| try argv.append(arg);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "git stash", "git stash", .{
            .tee_label = "git",
            .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "worktree")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("git");
        try argv.append("worktree");
        for (args[1..]) |arg| try argv.append(arg);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "git worktree", "git worktree", .{
            .tee_label = "git",
            .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "show")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "show" }, "git show", "git show", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "rebase")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "rebase" }, "git rebase", "git rebase", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "merge")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "merge" }, "git merge", "git merge", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "reset")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "reset" }, "git reset", "git reset", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "restore")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "restore" }, "git restore", "git restore", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "bisect")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "bisect" }, "git bisect", "git bisect", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "blame")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "blame" }, "git blame", "git blame", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .grouping,
        });
    } else if (std.mem.eql(u8, subcmd, "clean")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "clean" }, "git clean", "git clean", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "cherry-pick")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "cherry-pick" }, "git cherry-pick", "git cherry-pick", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "revert")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "revert" }, "git revert", "git revert", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "tag")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "tag" }, "git tag", "git tag", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "submodule")) {
        var argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
        defer g_cmd_allocator.free(argv);
        argv[0] = "git";
        for (args, 1..) |arg, i| argv[i] = arg;
        return core.runner.runFiltered(g_cmd_allocator, argv, "git submodule", "git submodule", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "describe")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "describe" }, "git describe", "git describe", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "shortlog")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "shortlog" }, "git shortlog", "git shortlog", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "reflog")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "reflog" }, "git reflog", "git reflog", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "remote")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "remote" }, "git remote", "git remote", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "ls-files")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "ls-files" }, "git ls-files", "git ls-files", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "ls-tree")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "ls-tree" }, "git ls-tree", "git ls-tree", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "grep")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "git", "grep" }, "git grep", "git grep", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .grouping,
        });
    } else if (std.mem.eql(u8, subcmd, "stash")) {
        // Already handled above, but add list/show variants
        var argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
        defer g_cmd_allocator.free(argv);
        argv[0] = "git";
        for (args, 1..) |arg, i| argv[i] = arg;
        return core.runner.runFiltered(g_cmd_allocator, argv, "git stash", "git stash", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else {
        // Passthrough for any other git subcommand
        var argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
        defer g_cmd_allocator.free(argv);
        argv[0] = "git";
        for (args, 1..) |arg, i| argv[i] = arg;
        return core.runner.runPassthrough(g_cmd_allocator, argv, global_verbose, g_cmd_io);
    }
}

fn dispatchCargo(args: []const [:0]const u8) !i32 {
    if (args.len == 0) {
        std.debug.print("cargo: missing subcommand\n", .{});
        return 1;
    }

    const subcmd = args[0];

    if (std.mem.eql(u8, subcmd, "test")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "test" }, "cargo test", "cargo test", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .failure_focus,
        });
    } else if (std.mem.eql(u8, subcmd, "build")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "build" }, "cargo build", "cargo build", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .errors_only,
        });
    } else if (std.mem.eql(u8, subcmd, "clippy")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "clippy" }, "cargo clippy", "cargo clippy", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .grouping,
        });
    } else if (std.mem.eql(u8, subcmd, "check")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "check" }, "cargo check", "cargo check", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .errors_only,
        });
    } else if (std.mem.eql(u8, subcmd, "nextest")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "nextest", "run" }, "cargo nextest", "cargo nextest run", .{
            .tee_label = "cargo-nextest",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .failure_focus,
        });
    } else if (std.mem.eql(u8, subcmd, "bench")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "bench" }, "cargo bench", "cargo bench", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "tree")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "tree" }, "cargo tree", "cargo tree", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .tree_compression,
        });
    } else if (std.mem.eql(u8, subcmd, "search")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "search" }, "cargo search", "cargo search", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "install")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "install" }, "cargo install", "cargo install", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "uninstall")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "uninstall" }, "cargo uninstall", "cargo uninstall", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "doc")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "doc" }, "cargo doc", "cargo doc", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .errors_only,
        });
    } else if (std.mem.eql(u8, subcmd, "publish")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "publish" }, "cargo publish", "cargo publish", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "update")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "update" }, "cargo update", "cargo update", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "clean")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "clean" }, "cargo clean", "cargo clean", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "fmt")) {
        return core.runner.runPassthrough(g_cmd_allocator, &.{ "cargo", "fmt" }, global_verbose, g_cmd_io);
    } else if (std.mem.eql(u8, subcmd, "fix")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "fix" }, "cargo fix", "cargo fix", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .errors_only,
        });
    } else if (std.mem.eql(u8, subcmd, "add")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "add" }, "cargo add", "cargo add", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "remove")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "remove" }, "cargo remove", "cargo remove", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "generate-lockfile")) {
        return core.runner.runPassthrough(g_cmd_allocator, &.{ "cargo", "generate-lockfile" }, global_verbose, g_cmd_io);
    } else if (std.mem.eql(u8, subcmd, "metadata")) {
        return core.runner.runPassthrough(g_cmd_allocator, &.{ "cargo", "metadata" }, global_verbose, g_cmd_io);
    } else if (std.mem.eql(u8, subcmd, "package")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "package" }, "cargo package", "cargo package", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "report")) {
        // cargo report (future, new in 1.74+)
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "report" }, "cargo report", "cargo report", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else {
        // Passthrough for any other cargo subcommand
        var argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
        defer g_cmd_allocator.free(argv);
        argv[0] = "cargo";
        for (args, 1..) |arg, i| argv[i] = arg;
        return core.runner.runPassthrough(g_cmd_allocator, argv, global_verbose, g_cmd_io);
    }
}

fn dispatchNpm(args: []const [:0]const u8) !i32 {
    if (args.len == 0) {
        std.debug.print("npm: missing command\n", .{});
        return 1;
    }

    const subcmd = args[0];

    // Detect package manager (RTK-style: pnpm > yarn > npm)
    const pm = core.utils.detectPackageManager(g_cmd_io);

    if (std.mem.eql(u8, subcmd, "test")) {
        // For test, use the detected package manager's test runner
        switch (pm) {
            .pnpm => return core.runner.runFiltered(g_cmd_allocator, &.{ "pnpm", "test" }, "pnpm test", "npm test", .{
                .io = g_cmd_io, .verbose = global_verbose,
                .strategy = .failure_focus,
            }),
            .yarn => return core.runner.runFiltered(g_cmd_allocator, &.{ "yarn", "test" }, "yarn test", "npm test", .{
                .io = g_cmd_io, .verbose = global_verbose,
                .strategy = .failure_focus,
            }),
            .bun => return core.runner.runFiltered(g_cmd_allocator, &.{ "bun", "test" }, "bun test", "npm test", .{
                .io = g_cmd_io, .verbose = global_verbose,
                .strategy = .failure_focus,
            }),
            else => return core.runner.runFiltered(g_cmd_allocator, &.{ "npm", "test" }, "npm test", "npm test", .{
                .io = g_cmd_io, .verbose = global_verbose,
                .strategy = .failure_focus,
            }),
        }
    } else if (std.mem.eql(u8, subcmd, "run")) {
        // npm run <script> - detect package manager
        switch (pm) {
            .pnpm => return core.runner.runFiltered(g_cmd_allocator, &.{"pnpm"}, "pnpm", "npm run", .{
                .io = g_cmd_io, .verbose = global_verbose,
                .strategy = .errors_only,
            }),
            .yarn => return core.runner.runFiltered(g_cmd_allocator, &.{"yarn"}, "yarn", "npm run", .{
                .io = g_cmd_io, .verbose = global_verbose,
                .strategy = .errors_only,
            }),
            .bun => return core.runner.runFiltered(g_cmd_allocator, &.{"bun"}, "bun", "npm run", .{
                .io = g_cmd_io, .verbose = global_verbose,
                .strategy = .errors_only,
            }),
            else => {
                // Build full command with args using array_list.Managed
                var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
                try argv.append("npm");
                for (args) |arg| try argv.append(arg);
                return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "npm run", "npm run", .{
                    .verbose = global_verbose,
                    .strategy = .errors_only,
                });
            },
        }
    } else if (std.mem.eql(u8, subcmd, "install")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "npm", "install" }, "npm install", "npm install", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .progress_strip,
        });
    } else if (std.mem.eql(u8, subcmd, "list")) {
        switch (pm) {
            .pnpm => return core.runner.runFiltered(g_cmd_allocator, &.{ "pnpm", "list" }, "pnpm list", "npm list", .{
                .io = g_cmd_io, .verbose = global_verbose,
                .strategy = .tree_compression,
            }),
            .yarn => return core.runner.runFiltered(g_cmd_allocator, &.{ "yarn", "list" }, "yarn list", "npm list", .{
                .io = g_cmd_io, .verbose = global_verbose,
                .strategy = .tree_compression,
            }),
            .bun => return core.runner.runFiltered(g_cmd_allocator, &.{ "bun", "pm", "ls" }, "bun pm ls", "npm list", .{
                .io = g_cmd_io, .verbose = global_verbose,
                .strategy = .tree_compression,
            }),
            else => return core.runner.runFiltered(g_cmd_allocator, &.{ "npm", "list" }, "npm list", "npm list", .{
                .io = g_cmd_io, .verbose = global_verbose,
                .strategy = .tree_compression,
            }),
        }
    } else {
        std.debug.print("npm: unknown command: {s}\n", .{subcmd});
        return 1;
    }
}

fn dispatchPytest(args: []const [:0]const u8) !i32 {
    _ = args;
    return core.runner.runFiltered(g_cmd_allocator, &.{"pytest"}, "pytest", "pytest", .{
        .io = g_cmd_io, .verbose = global_verbose,
        .strategy = .state_machine,
    });
}

fn dispatchDocker(args: []const [:0]const u8) !i32 {
    if (args.len == 0) {
        std.debug.print("docker: missing subcommand\n", .{});
        return 1;
    }

    const subcmd = args[0];

    if (std.mem.eql(u8, subcmd, "ps")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "docker", "ps" }, "docker ps", "docker ps", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "images")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "docker", "images" }, "docker images", "docker images", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "logs")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "docker", "logs" }, "docker logs", "docker logs", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .deduplication,
        });
    } else if (std.mem.eql(u8, subcmd, "build")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "docker", "build" }, "docker build", "docker build", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "run")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "docker", "run" }, "docker run", "docker run", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "pull")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "docker", "pull" }, "docker pull", "docker pull", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "push")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "docker", "push" }, "docker push", "docker push", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "inspect")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "docker", "inspect" }, "docker inspect", "docker inspect", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else {
        return core.runner.runPassthrough(g_cmd_allocator, &.{"docker"}, global_verbose, g_cmd_io);
    }
}

fn dispatchKubectl(args: []const [:0]const u8) !i32 {
    if (args.len == 0) {
        std.debug.print("kubectl: missing subcommand (get, logs, pods, services, describe, apply, delete)\n", .{});
        return 1;
    }

    const subcmd = args[0];

    if (std.mem.eql(u8, subcmd, "get")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "kubectl", "get" }, "kubectl get", "kubectl get", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "logs")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "kubectl", "logs" }, "kubectl logs", "kubectl logs", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .deduplication,
        });
    } else if (std.mem.eql(u8, subcmd, "pods")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("kubectl");
        try argv.append("get");
        try argv.append("pods");
        for (args[1..]) |arg| try argv.append(arg);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "kubectl pods", "kubectl get pods", .{
            .tee_label = "kubectl",
            .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "services") or std.mem.eql(u8, subcmd, "svc")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("kubectl");
        try argv.append("get");
        try argv.append("services");
        for (args[1..]) |arg| try argv.append(arg);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "kubectl services", "kubectl get services", .{
            .tee_label = "kubectl",
            .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "describe")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "kubectl", "describe" }, "kubectl describe", "kubectl describe", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "apply")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "kubectl", "apply" }, "kubectl apply", "kubectl apply", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "delete")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "kubectl", "delete" }, "kubectl delete", "kubectl delete", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "top")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "kubectl", "top" }, "kubectl top", "kubectl top", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "exec")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "kubectl", "exec" }, "kubectl exec", "kubectl exec", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "rollout")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "kubectl", "rollout" }, "kubectl rollout", "kubectl rollout", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "config")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "kubectl", "config" }, "kubectl config", "kubectl config", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "port-forward")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "kubectl", "port-forward" }, "kubectl port-forward", "kubectl port-forward", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "scale")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "kubectl", "scale" }, "kubectl scale", "kubectl scale", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else {
        return core.runner.runPassthrough(g_cmd_allocator, &.{"kubectl"}, global_verbose, g_cmd_io);
    }
}

fn dispatchConfig(args: []const [:0]const u8) !i32 {
    // config - Show or create configuration
    var create_config = false;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "create") or std.mem.eql(u8, arg, "--create")) {
            create_config = true;
        }
    }

    if (create_config) {
        core.config.createDefaultConfig(g_cmd_io, g_cmd_allocator) catch |err| {
            std.debug.print("Failed to create config: {}\n", .{err});
            return 1;
        };
        return 0;
    }

    // Show current config path
    const config_path = core.config.getConfigPath(g_cmd_allocator) catch |err| {
        std.debug.print("Failed to get config path: {}\n", .{err});
        return 1;
    };
    defer g_cmd_allocator.free(config_path);

    std.debug.print("Config: {s}\n", .{config_path});
    std.debug.print("Run 'llmlite-cmd config create' to create default config.\n", .{});
    return 0;
}

fn dispatchInit(args: []const [:0]const u8) !i32 {
    var global = true;
    var agent: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-g")) {
            global = true;
        } else if (std.mem.eql(u8, args[i], "--agent")) {
            if (i + 1 < args.len) {
                agent = args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, args[i], "--show")) {
            // Show installation status
            try core.hook.printInstallStatus(g_cmd_allocator);
            return 0;
        } else if (std.mem.eql(u8, args[i], "--uninstall")) {
            // Uninstall hooks
            const tool = if (agent) |a|
                if (std.mem.eql(u8, a, "claude_code")) core.hook.HookTool.claude_code else if (std.mem.eql(u8, a, "cursor")) core.hook.HookTool.cursor else if (std.mem.eql(u8, a, "gemini")) core.hook.HookTool.gemini else if (std.mem.eql(u8, a, "opencode")) core.hook.HookTool.opencode else if (std.mem.eql(u8, a, "windsurf")) core.hook.HookTool.windsurf else if (std.mem.eql(u8, a, "cline")) core.hook.HookTool.cline else if (std.mem.eql(u8, a, "codex")) core.hook.HookTool.codex else if (std.mem.eql(u8, a, "kiro")) core.hook.HookTool.kiro else {
                    std.debug.print("Unknown agent: {s}\n", .{a});
                    return 1;
                }
            else
                core.hook.HookTool.claude_code;

            try core.hook.uninstallHook(g_cmd_allocator, tool);
            std.debug.print("Hook uninstalled.\n", .{});
            return 0;
        }
    }

    // If agent specified, install hook directly
    if (agent != null) {
        const tool = if (std.mem.eql(u8, agent.?, "claude_code")) core.hook.HookTool.claude_code else if (std.mem.eql(u8, agent.?, "cursor")) core.hook.HookTool.cursor else if (std.mem.eql(u8, agent.?, "gemini")) core.hook.HookTool.gemini else if (std.mem.eql(u8, agent.?, "opencode")) core.hook.HookTool.opencode else if (std.mem.eql(u8, agent.?, "windsurf")) core.hook.HookTool.windsurf else if (std.mem.eql(u8, agent.?, "cline")) core.hook.HookTool.cline else if (std.mem.eql(u8, agent.?, "codex")) core.hook.HookTool.codex else if (std.mem.eql(u8, agent.?, "kiro")) core.hook.HookTool.kiro else {
            std.debug.print("Unknown agent: {s}\n", .{agent.?});
            std.debug.print("Supported: claude_code, cursor, gemini, opencode, windsurf, cline, codex, kiro\n", .{});
            return 1;
        };

        switch (tool) {
            .claude_code => try core.hook.installClaudeCodeHook(g_cmd_allocator, true),
            .cursor => try core.hook.installCursorHook(g_cmd_allocator, true),
            .gemini => try core.hook.installGeminiHook(g_cmd_allocator, true),
            .opencode => try core.hook.installOpenCodeHook(g_cmd_allocator, true),
            .windsurf => try core.hook.installWindsurfHook(g_cmd_allocator, true),
            .cline => try core.hook.installClineHook(g_cmd_allocator, true),
            .codex => try core.hook.installCodexHook(g_cmd_allocator, true),
            .kiro => try core.hook.installKiroHook(g_cmd_allocator, true, g_cmd_executable_path),
            else => {
                std.debug.print("Hook not supported for this agent.\n", .{});
                return 1;
            },
        }
        std.debug.print("Hook installed for {s}\n", .{agent.?});
        std.debug.print("Restart your AI tool to activate.\n", .{});
        return 0;
    }

    std.debug.print("\n=== llmlite-cmd Installation ===\n\n", .{});

    std.debug.print("Shell alias (add to ~/.bashrc or ~/.zshrc):\n", .{});
    std.debug.print("    alias llmlite='llmlite-cmd'\n\n", .{});

    std.debug.print("Quick start:\n", .{});
    std.debug.print("    llmlite git status\n", .{});
    std.debug.print("    llmlite cargo test\n\n", .{});

    std.debug.print("AI Tool Hooks (auto-rewrite):\n", .{});
    std.debug.print("    llmlite-cmd init --agent claude_code   # Claude Code\n", .{});
    std.debug.print("    llmlite-cmd init --agent cursor        # Cursor\n", .{});
    std.debug.print("    llmlite-cmd init --agent gemini        # Gemini CLI\n", .{});
    std.debug.print("    llmlite-cmd init --agent opencode      # OpenCode\n", .{});
    std.debug.print("    llmlite-cmd init --agent windsurf      # Windsurf\n", .{});
    std.debug.print("    llmlite-cmd init --agent cline         # Cline\n", .{});
    std.debug.print("    llmlite-cmd init --agent codex          # Codex\n", .{});
    std.debug.print("    llmlite-cmd init --agent kiro           # Kiro CLI\n\n", .{});

    std.debug.print("Commands supported: git, cargo, npm, pytest, docker, kubectl, go, lint, pnpm, dotnet, compose\n", .{});
    std.debug.print("See 'llmlite hook --help' for more options.\n\n", .{});

    return 0;
}

fn dispatchGain(args: []const [:0]const u8) !i32 {
    var show_graph = false;
    var show_json = false;
    var show_history = false;
    var show_daily = false;
    var days: u32 = 90;
    var team_mode = false;

    var local_mode = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--graph")) {
            show_graph = true;
        } else if (std.mem.eql(u8, args[i], "--json")) {
            show_json = true;
        } else if (std.mem.eql(u8, args[i], "--all")) {
            days = 365;
        } else if (std.mem.eql(u8, args[i], "--history")) {
            show_history = true;
        } else if (std.mem.eql(u8, args[i], "--daily")) {
            show_daily = true;
        } else if (std.mem.eql(u8, args[i], "--team")) {
            team_mode = true;
        } else if (std.mem.eql(u8, args[i], "--local")) {
            local_mode = true;
        }
    }

    // If --team flag is set, query proxy for team-level analytics
    if (team_mode) {
        return dispatchGainFromProxy(show_json);
    }

    core.gain.showGain(g_cmd_allocator, .{
        .show_graph = show_graph,
        .show_history = show_history,
        .show_daily = show_daily,
        .days = days,
        .format = if (show_json) .json else .text,
        .local = local_mode,
    }) catch {
        std.debug.print("Token Savings Report\n", .{});
        std.debug.print("====================\n\n", .{});
        std.debug.print("(No tracking data available yet)\n", .{});
        std.debug.print("Run some commands first to see statistics.\n", .{});
        return 0;
    };

    return 0;
}

fn dispatchGainFromProxy(show_json: bool) !i32 {
    // Query proxy for team-level gain statistics
    const proxy_url = "http://localhost:4000";

    var client = std.http.Client{ .allocator = g_cmd_allocator, .io = g_cmd_io };
    defer client.deinit();

    const uri = std.Uri.parse(proxy_url ++ "/analytics/gain") catch {
        std.debug.print("gain --team: failed to parse proxy URL\n", .{});
        return 1;
    };

    var response_writer = std.Io.Writer.Allocating.init(g_cmd_allocator);
    defer response_writer.deinit();

    const response = client.fetch(.{
        .location = .{ .uri = uri },
        .method = .GET,
        .response_writer = &response_writer.writer,
    }) catch {
        std.debug.print("gain --team: proxy not reachable at {s}\n", .{proxy_url});
        std.debug.print("Make sure llmlite-proxy is running: llmlite proxy start\n", .{});
        return 1;
    };

    if (response.status != .ok) {
        std.debug.print("gain --team: proxy returned HTTP {}\n", .{response.status});
        return 1;
    }

    const body = response_writer.written();

    if (show_json) {
        // Output raw JSON
        std.debug.print("{s}\n", .{body});
        return 0;
    }

    // Parse and display human-readable summary
    const parsed = std.json.parseFromSlice(
        struct {
            total_saved_tokens: usize,
            total_requests: usize,
            avg_savings_pct: f64,
            breakdown: []struct {
                command: []const u8,
                count: usize,
                total_saved_tokens: usize,
                avg_savings_pct: f64,
            },
        },
        g_cmd_allocator,
        body,
        .{},
    ) catch {
        // If parse fails, just print raw JSON
        std.debug.print("{s}\n", .{body});
        return 0;
    };
    defer parsed.deinit();

    std.debug.print("Team Token Savings Report (via llmlite-proxy)\n", .{});
    std.debug.print("=============================================\n\n", .{});
    std.debug.print("Total Saved Tokens: {}\n", .{parsed.value.total_saved_tokens});
    std.debug.print("Total Requests: {}\n", .{parsed.value.total_requests});
    std.debug.print("Average Savings: {:.2}%\n\n", .{parsed.value.avg_savings_pct});

    if (parsed.value.breakdown.len > 0) {
        std.debug.print("Top Commands:\n", .{});
        for (parsed.value.breakdown) |cmd| {
            std.debug.print("  {s}: {} saved ({} requests, {:.1}% avg)\n", .{
                cmd.command,
                cmd.total_saved_tokens,
                cmd.count,
                cmd.avg_savings_pct,
            });
        }
    }

    return 0;
}

fn dispatchDiscover(args: []const [:0]const u8) !i32 {
    var all = false;
    var days: u32 = 7;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--all")) {
            all = true;
        } else if (std.mem.eql(u8, args[i], "--since")) {
            if (i + 1 < args.len) {
                days = std.fmt.parseInt(u32, args[i + 1], 10) catch 7;
                i += 1;
            }
        }
    }

    core.discover.discover(g_cmd_allocator, .{
        .all = all,
        .since_days = days,
    }) catch {
        std.debug.print("Discovery complete.\n", .{});
        std.debug.print("Run 'llmlite-cmd init -g' to install the hook.\n", .{});
    };

    return 0;
}

fn dispatchLint(args: []const [:0]const u8) !i32 {
    if (args.len == 0) {
        // Auto-detect linter
        if (core.utils.fileExists(g_cmd_io, "biome.json") or core.utils.fileExists(g_cmd_io, "biome.jsonc")) {
            return core.runner.runFiltered(g_cmd_allocator, &.{ "npx", "biome", "check", "." }, "biome check", "biome check", .{
                .io = g_cmd_io, .verbose = global_verbose,
                .strategy = .grouping,
            });
        } else if (core.utils.fileExists(g_cmd_io, ".eslintrc.js") or core.utils.fileExists(g_cmd_io, ".eslintrc.json") or core.utils.fileExists(g_cmd_io, "eslint.config.js")) {
            return core.runner.runFiltered(g_cmd_allocator, &.{ "npx", "eslint", "." }, "eslint", "eslint", .{
                .io = g_cmd_io, .verbose = global_verbose,
                .strategy = .grouping,
            });
        } else if (core.utils.fileExists(g_cmd_io, "ruff.toml")) {
            return core.runner.runFiltered(g_cmd_allocator, &.{ "ruff", "check", "." }, "ruff check", "ruff check", .{
                .io = g_cmd_io, .verbose = global_verbose,
                .strategy = .grouping,
            });
        } else if (core.utils.fileExists(g_cmd_io, ".prettierrc") or core.utils.fileExists(g_cmd_io, ".prettierrc.json")) {
            return core.runner.runFiltered(g_cmd_allocator, &.{ "npx", "prettier", "--check", "." }, "prettier check", "prettier", .{
                .io = g_cmd_io, .verbose = global_verbose,
                .strategy = .errors_only,
            });
        } else {
            std.debug.print("lint: no linter configuration found\n", .{});
            std.debug.print("Supported: eslint, biome, ruff, prettier\n", .{});
            return 1;
        }
    }

    // Direct linter command
    const linter = args[0];

    if (std.mem.eql(u8, linter, "eslint")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "npx", "eslint" }, "eslint", "eslint", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .grouping,
        });
    } else if (std.mem.eql(u8, linter, "biome")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "npx", "biome", "check", "." }, "biome check", "biome", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .grouping,
        });
    } else if (std.mem.eql(u8, linter, "ruff")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "ruff", "check", "." }, "ruff check", "ruff", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .grouping,
        });
    } else if (std.mem.eql(u8, linter, "prettier")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "npx", "prettier", "--check", "." }, "prettier check", "prettier", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .errors_only,
        });
    } else if (std.mem.eql(u8, linter, "tsc")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "npx", "tsc", "--noEmit" }, "tsc", "tsc", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .grouping,
        });
    } else {
        std.debug.print("lint: unknown linter '{s}'\n", .{linter});
        std.debug.print("Supported: eslint, biome, ruff, prettier, tsc\n", .{});
        return 1;
    }
}

fn dispatchGo(args: []const [:0]const u8) !i32 {
    if (args.len == 0) {
        std.debug.print("go: missing subcommand\n", .{});
        return 1;
    }

    const subcmd = args[0];

    if (std.mem.eql(u8, subcmd, "test")) {
        // Go test with NDJSON output - use ndjson_stream filter
        return core.runner.runFiltered(g_cmd_allocator, &.{ "go", "test" }, "go test", "go test", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .ndjson_stream,
        });
    } else if (std.mem.eql(u8, subcmd, "build")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "go", "build" }, "go build", "go build", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "vet")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "go", "vet" }, "go vet", "go vet", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .errors_only,
        });
    } else if (std.mem.eql(u8, subcmd, "fmt")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "go", "fmt" }, "go fmt", "go fmt", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "mod")) {
        // go mod tidy, download, etc
        return core.runner.runFiltered(g_cmd_allocator, &.{ "go", "mod" }, "go mod", "go mod", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "get")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "go", "get" }, "go get", "go get", .{
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .progress_strip,
        });
    } else {
        std.debug.print("go: unknown subcommand: {s}\n", .{subcmd});
        std.debug.print("Supported: test, build, vet, fmt, mod, get\n", .{});
        return 1;
    }
}

fn dispatchHook(args: []const [:0]const u8) !i32 {
    var install_mode = false;
    var uninstall_mode = false;
    var show_mode = false;
    var verbose = false;
    var agent: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "install")) {
            install_mode = true;
        } else if (std.mem.eql(u8, args[i], "uninstall")) {
            uninstall_mode = true;
        } else if (std.mem.eql(u8, args[i], "--show")) {
            show_mode = true;
        } else if (std.mem.eql(u8, args[i], "-v") or std.mem.eql(u8, args[i], "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, args[i], "--agent")) {
            if (i + 1 < args.len) {
                agent = args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, args[i], "claude_code") or
            std.mem.eql(u8, args[i], "cursor") or
            std.mem.eql(u8, args[i], "gemini") or
            std.mem.eql(u8, args[i], "opencode") or
            std.mem.eql(u8, args[i], "copilot") or
            std.mem.eql(u8, args[i], "windsurf") or
            std.mem.eql(u8, args[i], "cline") or
            std.mem.eql(u8, args[i], "codex") or
            std.mem.eql(u8, args[i], "zsh") or
            std.mem.eql(u8, args[i], "fish") or
            std.mem.eql(u8, args[i], "kiro"))
        {
            agent = args[i];
        }
    }

    if (show_mode) {
        try core.hook.printInstallStatus(g_cmd_allocator);
        return 0;
    }

    const tool = if (agent) |a|
        if (std.mem.eql(u8, a, "claude_code")) core.hook.HookTool.claude_code else if (std.mem.eql(u8, a, "cursor")) core.hook.HookTool.cursor else if (std.mem.eql(u8, a, "gemini")) core.hook.HookTool.gemini else if (std.mem.eql(u8, a, "opencode")) core.hook.HookTool.opencode else if (std.mem.eql(u8, a, "copilot")) core.hook.HookTool.copilot else if (std.mem.eql(u8, a, "windsurf")) core.hook.HookTool.windsurf else if (std.mem.eql(u8, a, "cline")) core.hook.HookTool.cline else if (std.mem.eql(u8, a, "codex")) core.hook.HookTool.codex else if (std.mem.eql(u8, a, "zsh")) core.hook.HookTool.zsh else if (std.mem.eql(u8, a, "fish")) core.hook.HookTool.fish else if (std.mem.eql(u8, a, "kiro")) core.hook.HookTool.kiro else {
            std.debug.print("Unknown agent: {s}\n", .{a});
            std.debug.print("Supported: claude_code, cursor, gemini, opencode, copilot, windsurf, cline, codex, zsh, fish, kiro\n", .{});
            return 1;
        }
    else
        core.hook.HookTool.claude_code; // default

    if (uninstall_mode) {
        try core.hook.uninstallHook(g_cmd_allocator, tool);
        std.debug.print("Hook uninstalled for {s}\n", .{agent orelse "claude_code"});
        return 0;
    }

    if (install_mode) {
        switch (tool) {
            .claude_code => try core.hook.installClaudeCodeHook(g_cmd_allocator, verbose),
            .cursor => try core.hook.installCursorHook(g_cmd_allocator, verbose),
            .gemini => try core.hook.installGeminiHook(g_cmd_allocator, verbose),
            .opencode => try core.hook.installOpenCodeHook(g_cmd_allocator, verbose),
            .windsurf => try core.hook.installWindsurfHook(g_cmd_allocator, verbose),
            .cline => try core.hook.installClineHook(g_cmd_allocator, verbose),
            .codex => try core.hook.installCodexHook(g_cmd_allocator, verbose),
            .zsh => try core.hook.installZshHook(g_cmd_allocator, verbose),
            .fish => try core.hook.installFishHook(g_cmd_allocator, verbose),
            .kiro => try core.hook.installKiroHook(g_cmd_allocator, verbose, g_cmd_executable_path),
            .copilot, .openclaw => {
                std.debug.print("Hook installation not yet supported for {s}.\n", .{agent orelse "claude_code"});
                return 1;
            },
        }
        std.debug.print("Hook installed for {s}\n", .{agent orelse "claude_code"});
        std.debug.print("Restart your AI tool to activate.\n", .{});
        return 0;
    }

    // Default: show status
    try core.hook.printInstallStatus(g_cmd_allocator);
    return 0;
}

fn dispatchLs(args: []const [:0]const u8) !i32 {
    // Default to current directory, or use first argument as path
    const path = if (args.len > 0) args[0] else ".";

    // Non-recursive listing (avoids exploding through .zig-cache, node_modules, .git)
    const result = std.process.run(g_cmd_allocator, g_cmd_io, .{
        .argv = &.{ "ls", "-la", path },
    }) catch {
        std.debug.print("ls: failed to list directory\n", .{});
        return 1;
    };

    // Print output
    std.debug.print("{s}", .{result.stdout});

    return switch (result.term) {
        .exited => |code| code,
        .signal => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
        .stopped => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
        .unknown => 1,
    };
}

fn dispatchRead(args: []const [:0]const u8) !i32 {
    // read <file> [start_line] [end_line] [-l level]
    // -l level: minimal, standard, aggressive (default: standard)
    if (args.len == 0) {
        std.debug.print("read: missing file argument\n", .{});
        return 1;
    }

    var file_path: ?[]const u8 = null;
    var start_line: usize = 1;
    var end_line: usize = std.math.maxInt(usize);
    var filter_level: []const u8 = "standard";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-l") and i + 1 < args.len) {
            filter_level = args[i + 1];
            i += 1;
        } else if (file_path == null) {
            file_path = args[i];
        } else if (start_line == 1 and end_line == std.math.maxInt(usize)) {
            start_line = std.fmt.parseInt(usize, args[i], 10) catch 1;
        } else if (end_line == std.math.maxInt(usize)) {
            end_line = std.fmt.parseInt(usize, args[i], 10) catch std.math.maxInt(usize);
        }
    }

    // Initialize file_path if not set
    if (file_path == null) {
        std.debug.print("read: missing file argument\n", .{});
        return 1;
    }

    const file = std.Io.Dir.cwd().openFile(g_cmd_io, file_path.?, .{}) catch {
        std.debug.print("read: cannot open '{s}': No such file or directory\n", .{file_path.?});
        return 1;
    };
    defer file.close(g_cmd_io);

    var read_buf: [4096]u8 = undefined;
    var reader = file.reader(g_cmd_io, &read_buf);
    var content: []const u8 = reader.interface.allocRemaining(g_cmd_allocator, .limited(1024 * 1024)) catch {
        std.debug.print("read: cannot read '{s}'\n", .{file_path.?});
        return 1;
    };
    defer g_cmd_allocator.free(content);

    // Apply code filtering based on level
    if (std.mem.eql(u8, filter_level, "minimal") or
        std.mem.eql(u8, filter_level, "standard") or
        std.mem.eql(u8, filter_level, "aggressive"))
    {
        const filtered = try core.filter.filter(g_cmd_allocator, content, .{
            .strategy = .code_filter,
            .level = if (std.mem.eql(u8, filter_level, "minimal"))
                .minimal
            else if (std.mem.eql(u8, filter_level, "standard"))
                .standard
            else
                .aggressive,
        });
        g_cmd_allocator.free(content);
        content = filtered.filtered;
    }

    // Print lines in range [start_line, end_line]
    var line_num: usize = 1;
    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |line| : (line_num += 1) {
        if (line_num >= start_line and (end_line == std.math.maxInt(usize) or line_num <= end_line)) {
            std.debug.print("{d}: {s}\n", .{ line_num, line });
        } else if (line_num > end_line and end_line != std.math.maxInt(usize)) {
            break;
        }
    }

    return 0;
}

fn dispatchFind(args: []const [:0]const u8) !i32 {
    // find [path] [-name pattern] [-type f|d]
    // Compact find output inspired by RTK
    // Parse arguments to build find command
    var path: []const u8 = ".";
    var name_pattern: ?[]const u8 = null;
    var find_type: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-name") and i + 1 < args.len) {
            name_pattern = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "-type") and i + 1 < args.len) {
            find_type = args[i + 1];
            i += 1;
        } else if (args[i].len > 0 and args[i][0] != '-') {
            path = args[i];
        }
    }

    // Build find argv with cache/build directory exclusions
    var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
    defer argv.deinit();
    try argv.append("find");
    try argv.append(path);
    // Exclude common cache/build directories to prevent token explosion
    const excluded = [_][]const u8{
        ".git", ".zig-cache", "zig-out", "zig-pkg",
        "node_modules", "target", "dist", "build",
        ".venv", "venv", "__pycache__", ".pytest_cache",
        "coverage", ".next", ".nuxt", ".output",
        "bin", "obj", ".gradle", ".idea", ".vscode",
    };
    for (excluded) |dir| {
        try argv.append("-not");
        try argv.append("-path");
        const pattern = try std.fmt.allocPrint(g_cmd_allocator, "*/{s}/*", .{dir});
        defer g_cmd_allocator.free(pattern);
        try argv.append(pattern);
    }
    if (name_pattern) |np| {
        try argv.append("-name");
        try argv.append(np);
    }
    try argv.append("-type");
    try argv.append(find_type orelse "f");

    const result = std.process.run(g_cmd_allocator, g_cmd_io, .{
        .argv = argv.items,
    }) catch {
        std.debug.print("find: failed to execute\n", .{});
        return 1;
    };

    std.debug.print("{s}", .{result.stdout});
    if (result.stderr.len > 0) {
        std.debug.print("{s}", .{result.stderr});
    }

    return switch (result.term) {
        .exited => |code| code,
        .signal => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
        .stopped => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
        .unknown => 1,
    };
}

fn dispatchGrep(args: []const [:0]const u8) !i32 {
    // grep <pattern> [file/dir] [-r] [--grouped]
    // Grouped grep output inspired by RTK
    if (args.len == 0) {
        std.debug.print("grep: missing pattern argument\n", .{});
        return 1;
    }

    const pattern = args[0];
    const search_path = if (args.len > 1 and args[1].len > 0 and args[1][0] != '-') args[1] else ".";

    const result = std.process.run(g_cmd_allocator, g_cmd_io, .{
        .argv = &.{ "grep", "-r", "--color=never", pattern, search_path },
    }) catch {
        std.debug.print("grep: failed to execute\n", .{});
        return 1;
    };

    std.debug.print("{s}", .{result.stdout});
    if (result.stderr.len > 0) {
        std.debug.print("{s}", .{result.stderr});
    }

    return switch (result.term) {
        .exited => |code| code,
        .signal => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
        .stopped => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
        .unknown => 1,
    };
}

fn dispatchGh(args: []const [:0]const u8) !i32 {
    // gh <command> [args] - GitHub CLI wrapper
    // Forward all arguments to gh CLI
    // For simplicity, use gh help if no args, otherwise pass args directly
    _ = args;

    const result = std.process.run(g_cmd_allocator, g_cmd_io, .{
        .argv = &.{ "gh", "help" },
    }) catch {
        std.debug.print("gh: failed to execute - is GitHub CLI installed?\n", .{});
        return 1;
    };

    std.debug.print("{s}", .{result.stdout});
    if (result.stderr.len > 0) {
        std.debug.print("{s}", .{result.stderr});
    }

    return switch (result.term) {
        .exited => |code| code,
        .signal => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
        .stopped => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
        .unknown => 1,
    };
}

fn dispatchDiff(args: []const [:0]const u8) !i32 {
    // diff <file1> <file2> - Compare two files (RTK-inspired)
    // Returns condensed diff output for LLM context
    if (args.len < 2) {
        std.debug.print("diff: missing file arguments\n", .{});
        std.debug.print("Usage: diff <file1> <file2>\n", .{});
        return 1;
    }

    const file1 = args[0];
    const file2 = args[1];

    // Build args string for tee recovery
    const args_str = try std.mem.concat(g_cmd_allocator, u8, &.{ "diff ", file1, " ", file2 });
    defer g_cmd_allocator.free(args_str);

    // Use runFiltered with tee support for failure recovery
    return core.runner.runFiltered(g_cmd_allocator, &.{ "diff", "-u", file1, file2 }, "diff", args_str, .{
        .tee_label = "diff",
        .strategy = .none,
    });
}

fn dispatchTree(args: []const [:0]const u8) !i32 {
    // tree [path] [-L depth] - Display directory tree (RTK-inspired)
    // Compact tree output for LLM context
    var path_idx: ?usize = null;
    var max_depth: i32 = 2; // Default depth for compact output

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-L") and i + 1 < args.len) {
            max_depth = std.fmt.parseInt(i32, args[i + 1], 10) catch 2;
            i += 1;
        } else if (args[i].len > 0 and args[i][0] != '-') {
            path_idx = i;
        }
    }

    // Format depth as string for tree command
    const depth_str = try std.fmt.allocPrint(g_cmd_allocator, "{}", .{max_depth});
    defer g_cmd_allocator.free(depth_str);

    // Build args string for tee recovery
    const tree_args = if (path_idx) |idx|
        try std.mem.concat(g_cmd_allocator, u8, &.{ "tree -L ", depth_str, " ", args[idx] })
    else
        try std.mem.concat(g_cmd_allocator, u8, &.{ "tree -L ", depth_str, " ." });
    defer g_cmd_allocator.free(tree_args);

    const tree_exit = try core.runner.runFiltered(g_cmd_allocator, if (path_idx) |idx|
        &.{ "tree", "-L", depth_str, args[idx] }
    else
        &.{ "tree", "-L", depth_str, "." }, "tree", tree_args, .{
        .tee_label = "tree",
        .strategy = .none,
    });

    // If tree succeeded (exit 0), return. Tee already saved on failure.
    if (tree_exit == 0) return 0;

    // Fallback to ls if tree is not available (exit code != 0 means failure)
    const fallback_args = if (path_idx) |idx|
        try std.mem.concat(g_cmd_allocator, u8, &.{ "ls -R ", args[idx] })
    else
        try g_cmd_allocator.dupe(u8, "ls -R .");
    defer g_cmd_allocator.free(fallback_args);

    return core.runner.runFiltered(g_cmd_allocator, if (path_idx) |idx|
        &.{ "ls", "-R", args[idx] }
    else
        &.{ "ls", "-R", "." }, "tree", fallback_args, .{
        .tee_label = "tree",
        .strategy = .none,
    });
}

fn dispatchJson(args: []const [:0]const u8) !i32 {
    // json <file> - Extract JSON structure (RTK-inspired)
    // Shows JSON keys and types without values for compact output
    if (args.len == 0) {
        std.debug.print("json: missing file argument\n", .{});
        std.debug.print("Usage: json <file.json>\n", .{});
        return 1;
    }

    const file_path = args[0];
    const file = std.Io.Dir.cwd().openFile(g_cmd_io, file_path, .{}) catch {
        std.debug.print("json: cannot open '{s}': No such file\n", .{file_path});
        return 1;
    };
    defer file.close(g_cmd_io);

    var json_read_buf: [4096]u8 = undefined;
    var json_reader = file.reader(g_cmd_io, &json_read_buf);
    const content = json_reader.interface.allocRemaining(g_cmd_allocator, .limited(1024 * 1024)) catch {
        std.debug.print("json: cannot read '{s}'\n", .{file_path});
        return 1;
    };
    defer g_cmd_allocator.free(content);

    // Parse JSON and extract structure
    // This is a simplified version - just shows top-level keys
    const parsed = std.json.parseFromSlice(std.json.Value, g_cmd_allocator, content, .{}) catch {
        // Tee recovery on parse failure - save raw content
        const args_str = try std.mem.concat(g_cmd_allocator, u8, &.{ "json ", file_path });
        defer g_cmd_allocator.free(args_str);
        _ = core.tee.save("json", args_str, content) catch null;
        std.debug.print("json: invalid JSON in '{s}'\n", .{file_path});
        return 1;
    };

    // Print compact structure
    printJsonStructure(parsed.value, 0);

    return 0;
}

fn printJsonStructure(value: std.json.Value, depth: usize) void {
    const indent = "  ";
    var i: usize = 0;
    while (i < depth) : (i += 1) {
        std.debug.print("{s}", .{indent});
    }

    switch (value) {
        .null => std.debug.print("null\n", .{}),
        .bool => std.debug.print("bool\n", .{}),
        .integer => std.debug.print("integer\n", .{}),
        .float => std.debug.print("float\n", .{}),
        .string => std.debug.print("string\n", .{}),
        .number_string => std.debug.print("number_string\n", .{}),
        .array => |arr| {
            std.debug.print("array[{d}]\n", .{arr.items.len});
            for (arr.items) |item| {
                printJsonStructure(item, depth + 1);
            }
        },
        .object => |obj| {
            std.debug.print("object\n", .{});
            var it = obj.iterator();
            while (it.next()) |entry| {
                var j: usize = 0;
                while (j < depth + 1) : (j += 1) {
                    std.debug.print("{s}", .{indent});
                }
                std.debug.print("{s}: ", .{entry.key_ptr.*});
                printJsonStructure(entry.value_ptr.*, depth + 1);
            }
        },
    }
}

fn dispatchEnv(args: []const [:0]const u8) !i32 {
    // env [-f filter] [-p] - Show environment variables (RTK-inspired)
    // Filters sensitive variables for LLM context
    var filter_pattern: ?[]const u8 = null;
    var show_values = true;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-f") and i + 1 < args.len) {
            filter_pattern = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "-p")) {
            show_values = false;
        }
    }

    // Run env command and capture output
    const result = std.process.run(g_cmd_allocator, g_cmd_io, .{
        .argv = &.{"env"},
    }) catch {
        std.debug.print("env: failed to get environment\n", .{});
        return 1;
    };

    // Tee recovery on failure - save raw output
    const env_exit = switch (result.term) {
        .exited => |code| code,
        .signal => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
        .stopped => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
        .unknown => 1,
    };
    if (env_exit != 0) {
        const args_str = if (filter_pattern) |p|
            try std.mem.concat(g_cmd_allocator, u8, &.{ "env -f ", p })
        else
            try g_cmd_allocator.dupe(u8, "env");
        defer g_cmd_allocator.free(args_str);
        _ = core.tee.save("env", args_str, result.stdout) catch null;
    }

    // Process each line
    var line_iter = std.mem.splitScalar(u8, result.stdout, '\n');
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        // Find the first '='
        if (std.mem.findScalar(u8, line, '=')) |eq_idx| {
            const key = line[0..eq_idx];
            const value = line[eq_idx + 1 ..];

            // Apply filter if specified
            if (filter_pattern) |pattern| {
                if (std.mem.find(u8, key, pattern) == null) {
                    continue;
                }
            }

            if (show_values) {
                // Hide sensitive patterns
                const is_sensitive = std.mem.find(u8, key, "SECRET") != null or
                    std.mem.find(u8, key, "PASSWORD") != null or
                    std.mem.find(u8, key, "KEY") != null or
                    std.mem.find(u8, key, "TOKEN") != null;
                if (is_sensitive) {
                    std.debug.print("{s}=***\n", .{key});
                } else {
                    std.debug.print("{s}={s}\n", .{ key, value });
                }
            } else {
                std.debug.print("{s}\n", .{key});
            }
        } else {
            // No '=' found, just print the line
            if (filter_pattern) |pattern| {
                if (std.mem.find(u8, line, pattern) == null) {
                    continue;
                }
            }
            std.debug.print("{s}\n", .{line});
        }
    }

    return switch (result.term) {
        .exited => |code| code,
        .signal => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
        .stopped => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
        .unknown => 1,
    };
}

// ============================================================================
// RTK-Inspired Additional Commands
// ============================================================================

fn dispatchSmart(args: []const [:0]const u8) !i32 {
    // smart <file> - 2-line heuristic code summary
    // Shows: function signature + first meaningful line of body
    if (args.len == 0) {
        std.debug.print("smart: missing file argument\n", .{});
        return 1;
    }

    const file_path = args[0];
    const file = std.Io.Dir.cwd().openFile(g_cmd_io, file_path, .{}) catch {
        std.debug.print("smart: cannot open '{s}'\n", .{file_path});
        return 1;
    };
    defer file.close(g_cmd_io);

    var smart_read_buf: [4096]u8 = undefined;
    var smart_reader = file.reader(g_cmd_io, &smart_read_buf);
    const content = smart_reader.interface.allocRemaining(g_cmd_allocator, .limited(1024 * 1024)) catch {
        std.debug.print("smart: cannot read '{s}'\n", .{file_path});
        return 1;
    };
    defer g_cmd_allocator.free(content);

    // Heuristic: extract function signatures and first line of each function
    var result = std.array_list.Managed(u8).init(g_cmd_allocator);
    defer result.deinit();

    var lines = std.mem.splitScalar(u8, content, '\n');
    var func_count: usize = 0;
    const max_funcs = 10;
    var found_func_body: bool = false;

    while (lines.next()) |line| {
        if (func_count >= max_funcs and found_func_body) break;

        const trimmed = std.mem.trim(u8, line, " \t");

        // Detect function definitions (simplified heuristic)
        const is_func = std.mem.find(u8, trimmed, "fn ") != null or
            std.mem.find(u8, trimmed, "func ") != null or
            std.mem.find(u8, trimmed, "def ") != null or
            std.mem.find(u8, trimmed, "pub fn ") != null or
            std.mem.find(u8, trimmed, "function ") != null;

        if (is_func) {
            if (result.items.len > 0) try result.print("\n", .{});
            try result.print("{s}", .{trimmed});
            func_count += 1;
            found_func_body = false;

            // Check if function body is on same line (e.g., `fn foo() { ... }`)
            if (std.mem.find(u8, trimmed, "{") != null) {
                // Single-line function
                found_func_body = true;
            }
        } else if (func_count > 0 and !found_func_body) {
            // This is likely the first line of the function body
            // Skip empty lines, comments, braces, and lines containing opening brace
            if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "//") and
                !std.mem.startsWith(u8, trimmed, "/*") and
                std.mem.find(u8, trimmed, "{") == null and
                std.mem.find(u8, trimmed, "}") == null)
            {
                try result.print("\n  -> {s}", .{trimmed});
                found_func_body = true;
            }
        }
    }

    if (result.items.len == 0) {
        // No functions found, just show first few lines
        var i: usize = 0;
        lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            if (i >= 3) break;
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len == 0) continue;
            if (result.items.len > 0) try result.print("\n", .{});
            try result.print("{s}", .{trimmed});
            i += 1;
        }
    }

    std.debug.print("{s}\n", .{result.items});
    return 0;
}

fn dispatchVitest(args: []const [:0]const u8) !i32 {
    // vitest [run] - Vitest compact output (failure focus + state machine)
    // Auto-detect pnpm/yarn/npm
    _ = args; // unused - vitest auto-detects
    const is_pnpm = core.utils.fileExists(g_cmd_io, "pnpm-lock.yaml");
    const is_yarn = core.utils.fileExists(g_cmd_io, "yarn.lock");

    const argv: []const []const u8 = if (is_pnpm)
        &.{ "pnpm", "vitest", "run" }
    else if (is_yarn)
        &.{ "yarn", "vitest", "run" }
    else
        &.{ "npx", "vitest", "run" };

    return core.runner.runFiltered(g_cmd_allocator, argv, "vitest", "vitest run", .{
        .tee_label = "vitest",
        .io = g_cmd_io, .verbose = global_verbose,
        .strategy = .state_machine,
    });
}

fn dispatchGolangciLint(args: []const [:0]const u8) !i32 {
    // golangci-lint run - Go linting with JSON output
    _ = args; // unused
    return core.runner.runFiltered(g_cmd_allocator, &.{ "golangci-lint", "run", "--out-format=json" }, "golangci-lint", "golangci-lint run", .{
        .tee_label = "golangci-lint",
        .io = g_cmd_io, .verbose = global_verbose,
        .strategy = .json_dual,
    });
}

fn dispatchCurl(args: []const [:0]const u8) !i32 {
    // curl <url> - Fetch URL with JSON detection and progress stripping
    if (args.len == 0) {
        std.debug.print("curl: missing URL argument\n", .{});
        return 1;
    }

    const url = args[0];

    // Build curl command with flags to avoid progress bars
    const argv = &.{ "curl", "-s", "-S", "-L", url };

    return core.runner.runFiltered(g_cmd_allocator, argv, "curl", url, .{
        .tee_label = "curl",
        .io = g_cmd_io, .verbose = global_verbose,
        .strategy = .progress_strip,
    });
}

fn dispatchAws(args: []const [:0]const u8) !i32 {
    // aws <subcommand> [args...] - AWS CLI with output filtering
    if (args.len == 0) {
        std.debug.print("aws: missing subcommand\n", .{});
        return 1;
    }

    // Build argv: ["aws", subcommand, args...]
    const argv = try g_cmd_allocator.alloc([]const u8, 1 + args.len);
    defer g_cmd_allocator.free(argv);
    argv[0] = "aws";
    for (args, 1..) |arg, i| argv[i] = arg;

    const cmd_str = try std.mem.concat(g_cmd_allocator, u8, &.{"aws"});
    defer g_cmd_allocator.free(cmd_str);

    return core.runner.runFiltered(g_cmd_allocator, argv, "aws", cmd_str, .{
        .tee_label = "aws",
        .io = g_cmd_io, .verbose = global_verbose,
        .strategy = .stats,
    });
}

fn dispatchDeps(args: []const [:0]const u8) !i32 {
    // deps - Show dependencies summary (package.json, Cargo.toml, go.mod, etc.)
    // Auto-detect project type
    _ = args; // unused - deps auto-detects project type

    // Check for package.json
    if (core.utils.fileExists(g_cmd_io, "package.json")) {
        // Check for pnpm/yarn/npm
        if (core.utils.fileExists(g_cmd_io, "pnpm-lock.yaml")) {
            return core.runner.runFiltered(g_cmd_allocator, &.{ "pnpm", "list", "--depth=0" }, "deps", "pnpm list", .{
                .tee_label = "deps",
                .io = g_cmd_io, .verbose = global_verbose,
                .strategy = .stats,
            });
        } else if (core.utils.fileExists(g_cmd_io, "yarn.lock")) {
            return core.runner.runFiltered(g_cmd_allocator, &.{ "yarn", "list", "--depth=0" }, "deps", "yarn list", .{
                .tee_label = "deps",
                .io = g_cmd_io, .verbose = global_verbose,
                .strategy = .stats,
            });
        } else {
            return core.runner.runFiltered(g_cmd_allocator, &.{ "npm", "list", "--depth=0" }, "deps", "npm list", .{
                .tee_label = "deps",
                .io = g_cmd_io, .verbose = global_verbose,
                .strategy = .stats,
            });
        }
    }

    // Check for Cargo.toml
    if (core.utils.fileExists(g_cmd_io, "Cargo.toml")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "cargo", "tree", "--depth=1" }, "deps", "cargo tree", .{
            .tee_label = "deps",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .tree_compression,
        });
    }

    // Check for go.mod
    if (core.utils.fileExists(g_cmd_io, "go.mod")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "go", "list", "-m", "all" }, "deps", "go list -m all", .{
            .tee_label = "deps",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    }

    std.debug.print("deps: no dependency file found (package.json, Cargo.toml, go.mod)\n", .{});
    return 1;
}

fn dispatchPlaywright(args: []const [:0]const u8) !i32 {
    // playwright test - Playwright E2E test output (failure focus)
    _ = args; // unused - playwright auto-detects
    const is_pnpm = core.utils.fileExists(g_cmd_io, "pnpm-lock.yaml");
    const is_yarn = core.utils.fileExists(g_cmd_io, "yarn.lock");

    const argv: []const []const u8 = if (is_pnpm)
        &.{ "pnpm", "playwright", "test" }
    else if (is_yarn)
        &.{ "yarn", "playwright", "test" }
    else
        &.{ "npx", "playwright", "test" };

    return core.runner.runFiltered(g_cmd_allocator, argv, "playwright", "playwright test", .{
        .tee_label = "playwright",
        .io = g_cmd_io, .verbose = global_verbose,
        .strategy = .failure_focus,
    });
}

fn dispatchRake(args: []const [:0]const u8) !i32 {
    // rake [task] - Ruby rake task runner (failure focus)
    const argv: []const []const u8 = if (args.len == 0)
        &.{"rake"}
    else
        &.{ "rake", args[0] };
    return core.runner.runFiltered(g_cmd_allocator, argv, "rake", "rake", .{
        .tee_label = "rake",
        .io = g_cmd_io, .verbose = global_verbose,
        .strategy = .failure_focus,
    });
}

fn dispatchRspec(args: []const [:0]const u8) !i32 {
    // rspec - Ruby RSpec test runner (JSON format)
    _ = args; // args passed through bundle exec rspec
    const argv: []const []const u8 = &.{ "bundle", "exec", "rspec" };
    return core.runner.runFiltered(g_cmd_allocator, argv, "rspec", "rspec", .{
        .tee_label = "rspec",
        .io = g_cmd_io, .verbose = global_verbose,
        .strategy = .json_dual,
    });
}

fn dispatchRubocop(args: []const [:0]const u8) !i32 {
    // rubocop - Ruby linting (JSON format)
    _ = args; // args passed through bundle exec rubocop
    const argv: []const []const u8 = &.{ "bundle", "exec", "rubocop" };
    return core.runner.runFiltered(g_cmd_allocator, argv, "rubocop", "rubocop", .{
        .tee_label = "rubocop",
        .io = g_cmd_io, .verbose = global_verbose,
        .strategy = .json_dual,
    });
}

fn dispatchBundle(args: []const [:0]const u8) !i32 {
    // bundle install/update - Ruby gem management
    const subcmd = if (args.len > 0) args[0] else "install";

    const argv: []const []const u8 = if (std.mem.eql(u8, subcmd, "install"))
        &.{ "bundle", "install" }
    else if (std.mem.eql(u8, subcmd, "update"))
        &.{ "bundle", "update" }
    else
        &.{"bundle"};

    return core.runner.runFiltered(g_cmd_allocator, argv, "bundle", "bundle", .{
        .tee_label = "bundle",
        .io = g_cmd_io, .verbose = global_verbose,
        .strategy = .deduplication,
    });
}

fn dispatchPip(args: []const [:0]const u8) !i32 {
    // pip list/outdated - Python package management
    if (args.len == 0) {
        std.debug.print("pip: missing subcommand (list, outdated)\n", .{});
        return 1;
    }

    const subcmd = args[0];
    const argv: []const []const u8 = if (std.mem.eql(u8, subcmd, "list"))
        &.{ "pip", "list" }
    else if (std.mem.eql(u8, subcmd, "outdated"))
        &.{ "pip", "list", "--outdated" }
    else if (std.mem.eql(u8, subcmd, "install"))
        &.{ "pip", "install" }
    else
        &.{ "pip", subcmd };

    return core.runner.runFiltered(g_cmd_allocator, argv, "pip", "pip", .{
        .tee_label = "pip",
        .io = g_cmd_io, .verbose = global_verbose,
        .strategy = .structure_only,
    });
}

fn dispatchWget(args: []const [:0]const u8) !i32 {
    // wget <url> - Download with progress stripping
    if (args.len == 0) {
        std.debug.print("wget: missing URL argument\n", .{});
        return 1;
    }

    const url = args[0];
    // Build wget command with flags to avoid progress bars
    const argv: []const []const u8 = &.{ "wget", "-q", "-O", "-", url };

    return core.runner.runFiltered(g_cmd_allocator, argv, "wget", url, .{
        .tee_label = "wget",
        .io = g_cmd_io, .verbose = global_verbose,
        .strategy = .progress_strip,
    });
}

fn dispatchPrettier(args: []const [:0]const u8) !i32 {
    // prettier [--check] [files...] - Format check with grouped output
    const has_check = for (args) |arg| {
        if (std.mem.eql(u8, arg, "--check")) break true;
    } else false;

    const argv: []const []const u8 = if (has_check)
        &.{ "prettier", "--check", "." }
    else
        &.{ "prettier", "." };

    return core.runner.runFiltered(g_cmd_allocator, argv, "prettier", "prettier", .{
        .tee_label = "prettier",
        .io = g_cmd_io, .verbose = global_verbose,
        .strategy = .grouping,
    });
}

fn dispatchUv(args: []const [:0]const u8) !i32 {
    // uv pip list/outdated - Modern Python package manager
    if (args.len == 0) {
        std.debug.print("uv: missing subcommand (pip list, pip outdated)\n", .{});
        return 1;
    }

    const subcmd = args[0];
    const argv: []const []const u8 = if (std.mem.eql(u8, subcmd, "pip"))
        if (args.len > 1 and std.mem.eql(u8, args[1], "list"))
            &.{ "uv", "pip", "list" }
        else if (args.len > 1 and std.mem.eql(u8, args[1], "outdated"))
            &.{ "uv", "pip", "list", "--outdated" }
        else if (args.len > 1 and std.mem.eql(u8, args[1], "install"))
            &.{ "uv", "pip", "install" }
        else
            &.{ "uv", "pip", "list" }
    else
        &.{ "uv", subcmd };

    return core.runner.runFiltered(g_cmd_allocator, argv, "uv", "uv", .{
        .tee_label = "uv",
        .io = g_cmd_io, .verbose = global_verbose,
        .strategy = .structure_only,
    });
}

fn dispatchSession(args: []const [:0]const u8) !i32 {
    // session - Show llmlite adoption across recent sessions
    var options = core.session.SessionOptions{
        .all = false,
        .since_days = 30,
        .format = "text",
        .verbose = global_verbose,
    };
    var team_mode = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--all")) {
            options.all = true;
        } else if (std.mem.eql(u8, args[i], "--since")) {
            if (i + 1 < args.len) {
                options.since_days = std.fmt.parseInt(u32, args[i + 1], 10) catch 30;
                i += 1;
            }
        } else if (std.mem.eql(u8, args[i], "--format")) {
            if (i + 1 < args.len) {
                options.format = args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, args[i], "--team")) {
            team_mode = true;
        }
    }

    // If --team flag is set, query proxy for team-level session data
    if (team_mode) {
        return dispatchSessionFromProxy(options.format);
    }

    try core.session.runSessionAnalysis(g_cmd_allocator, options);
    return 0;
}

fn dispatchSessionFromProxy(format: []const u8) !i32 {
    // Query proxy for team-level session overview
    const proxy_url = "http://localhost:4000";

    var client = std.http.Client{ .allocator = g_cmd_allocator, .io = g_cmd_io };
    defer client.deinit();

    const uri = std.Uri.parse(proxy_url ++ "/analytics/sessions") catch {
        std.debug.print("session --team: failed to parse proxy URL\n", .{});
        return 1;
    };

    var response_writer = std.Io.Writer.Allocating.init(g_cmd_allocator);
    defer response_writer.deinit();

    const response = client.fetch(.{
        .location = .{ .uri = uri },
        .method = .GET,
        .response_writer = &response_writer.writer,
    }) catch {
        std.debug.print("session --team: proxy not reachable at {s}\n", .{proxy_url});
        std.debug.print("Make sure llmlite-proxy is running: llmlite proxy start\n", .{});
        return 1;
    };

    if (response.status != .ok) {
        std.debug.print("session --team: proxy returned HTTP {}\n", .{response.status});
        return 1;
    }

    const body = response_writer.written();

    if (std.mem.eql(u8, format, "json")) {
        // Output raw JSON
        std.debug.print("{s}\n", .{body});
        return 0;
    }

    // Parse and display human-readable summary
    const parsed = std.json.parseFromSlice(
        struct {
            sessions_scanned: usize,
            total_commands: usize,
            llmlite_commands: usize,
            adoption_rate: f64,
            sessions: []struct {
                id: []const u8,
                date: []const u8,
                hostname: []const u8,
                total_cmds: usize,
                llmlite_cmds: usize,
                output_tokens: usize,
            },
        },
        g_cmd_allocator,
        body,
        .{},
    ) catch {
        // If parse fails, just print raw JSON
        std.debug.print("{s}\n", .{body});
        return 0;
    };
    defer parsed.deinit();

    std.debug.print("Team Session Report (via llmlite-proxy)\n", .{});
    std.debug.print("======================================\n\n", .{});
    std.debug.print("Sessions Scanned: {}\n", .{parsed.value.sessions_scanned});
    std.debug.print("Total Commands: {}\n", .{parsed.value.total_commands});
    std.debug.print("LLMLite Commands: {}\n", .{parsed.value.llmlite_commands});
    std.debug.print("Adoption Rate: {:.2}%\n\n", .{parsed.value.adoption_rate});

    if (parsed.value.sessions.len > 0) {
        std.debug.print("Recent Sessions:\n", .{});
        for (parsed.value.sessions[0..@min(10, parsed.value.sessions.len)]) |session| {
            std.debug.print("  {s} ({s}): {} cmds ({} llmlite)\n", .{
                session.hostname,
                session.date,
                session.total_cmds,
                session.llmlite_cmds,
            });
        }
    }

    return 0;
}

fn dispatchPrisma(args: []const [:0]const u8) !i32 {
    // prisma [subcommand] - Prisma CLI wrapper (migrate, generate, db pull, etc.)
    if (args.len == 0) {
        std.debug.print("prisma: missing subcommand (migrate, generate, db pull, db push, studio)\n", .{});
        return 1;
    }

    const subcmd = args[0];

    // Build argv: ["npx", "prisma", subcmd, args...]
    var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
    defer argv.deinit();

    // Auto-detect package manager
    const is_pnpm = core.utils.fileExists(g_cmd_io, "pnpm-lock.yaml");
    const is_yarn = core.utils.fileExists(g_cmd_io, "yarn.lock");

    if (is_pnpm) {
        try argv.append("pnpm");
        try argv.append("prisma");
    } else if (is_yarn) {
        try argv.append("yarn");
        try argv.append("prisma");
    } else {
        try argv.append("npx");
        try argv.append("prisma");
    }

    try argv.append(subcmd);
    for (args[1..]) |arg| try argv.append(arg);

    // Strategy based on subcommand
    const strategy: core.filter.FilterStrategy = if (std.mem.eql(u8, subcmd, "migrate"))
        .deduplication
    else if (std.mem.eql(u8, subcmd, "generate"))
        .stats
    else if (std.mem.eql(u8, subcmd, "studio"))
        .none
    else
        .state_machine;

    return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "prisma", "prisma", .{
        .tee_label = "prisma",
        .verbose = global_verbose,
        .strategy = strategy,
    });
}

fn dispatchNext(args: []const [:0]const u8) !i32 {
    // next [subcommand] - Next.js build/development wrapper
    if (args.len == 0) {
        std.debug.print("next: missing subcommand (build, dev, start, lint, info)\n", .{});
        return 1;
    }

    const subcmd = args[0];

    // Build argv
    var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
    defer argv.deinit();

    // Auto-detect package manager
    const is_pnpm = core.utils.fileExists(g_cmd_io, "pnpm-lock.yaml");
    const is_yarn = core.utils.fileExists(g_cmd_io, "yarn.lock");

    if (is_pnpm) {
        try argv.append("pnpm");
        try argv.append("next");
    } else if (is_yarn) {
        try argv.append("yarn");
        try argv.append("next");
    } else {
        try argv.append("npx");
        try argv.append("next");
    }

    try argv.append(subcmd);
    for (args[1..]) |arg| try argv.append(arg);

    // Strategy based on subcommand
    const strategy: core.filter.FilterStrategy = if (std.mem.eql(u8, subcmd, "build"))
        .state_machine
    else if (std.mem.eql(u8, subcmd, "lint"))
        .grouping
    else if (std.mem.eql(u8, subcmd, "dev") or std.mem.eql(u8, subcmd, "start"))
        .none
    else
        .stats;

    return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "next", "next", .{
        .tee_label = "next",
        .verbose = global_verbose,
        .strategy = strategy,
    });
}

fn dispatchLog(args: []const [:0]const u8) !i32 {
    // log - Show llmlite command history with deduplication
    // Similar to git log but for llmlite history
    const LogEntry = struct { timestamp: i64, original: []const u8, rtk: []const u8 };

    var limit: u32 = 50;
    var show_dedup = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-n") and i + 1 < args.len) {
            limit = std.fmt.parseInt(u32, args[i + 1], 10) catch 50;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--dedup")) {
            show_dedup = true;
        }
    }

    const home_dir = if (std.c.getenv("HOME")) |ptr|
        std.mem.sliceTo(ptr, 0)
    else {
        std.debug.print("log: HOME not set\n", .{});
        return 1;
    };
    defer g_cmd_allocator.free(home_dir);

    const history_path = std.fs.path.join(g_cmd_allocator, &.{ home_dir, ".local/share/llmlite/history.db" }) catch {
        std.debug.print("log: failed to build path\n", .{});
        return 1;
    };
    defer g_cmd_allocator.free(history_path);

    const file = std.Io.Dir.openFileAbsolute(g_cmd_io, history_path, .{}) catch {
        std.debug.print("No log history found. Run 'llmlite-cmd init -g' first.\n", .{});
        return 0;
    };
    defer file.close(g_cmd_io);

    var buf: [8192]u8 = undefined;
    var file_buffer = std.array_list.Managed(u8).init(g_cmd_allocator);
    defer file_buffer.deinit();

    while (true) {
        const bytes_read = file.readPositional(g_cmd_io, &.{&buf}, 0) catch break;
        if (bytes_read == 0) break;
        file_buffer.appendSlice(buf[0..bytes_read]) catch break;
    }

    // Parse and deduplicate if requested
    var entries = std.array_list.Managed(LogEntry).init(g_cmd_allocator);
    defer {
        for (entries.items) |e| {
            g_cmd_allocator.free(e.original);
            g_cmd_allocator.free(e.rtk);
        }
        entries.deinit();
    }

    var line_iter = std.mem.splitScalar(u8, file_buffer.items, '\n');
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        var field_iter = std.mem.splitScalar(u8, line, '|');
        const timestamp_str = field_iter.next() orelse continue;
        const timestamp = std.fmt.parseInt(i64, timestamp_str, 10) catch continue;
        const original = field_iter.next() orelse continue;
        const rtk = field_iter.next() orelse continue;

        entries.append(.{
            .timestamp = timestamp,
            .original = try g_cmd_allocator.dupe(u8, original),
            .rtk = try g_cmd_allocator.dupe(u8, rtk),
        }) catch continue;
    }

    // Sort by timestamp descending
    std.sort.heap(LogEntry, entries.items, {}, struct {
        fn less(_: void, a: LogEntry, b: LogEntry) bool {
            return a.timestamp > b.timestamp;
        }
    }.less);

    std.debug.print("\n=== llmlite Command Log ===\n\n", .{});

    if (show_dedup) {
        // Deduplicated view - show unique commands
        var seen = std.StringHashMap(struct { count: u32, last_ts: i64 }).init(g_cmd_allocator);
        defer seen.deinit();

        for (entries.items) |entry| {
            if (seen.getPtr(entry.original)) |existing| {
                existing.count += 1;
                if (entry.timestamp > existing.last_ts) {
                    existing.last_ts = entry.timestamp;
                }
            } else {
                seen.put(entry.original, .{ .count = 1, .last_ts = entry.timestamp }) catch continue;
            }
        }

        var count: u32 = 0;
        var it = seen.iterator();
        while (it.next()) |entry| {
            if (count >= limit) break;
            const cmd = entry.key_ptr.*;
            const info = entry.value_ptr.*;
            const ts = info.last_ts;
            const days_ago = @divTrunc(@as(i64, @intCast(time_compat.timestamp(g_cmd_io))) - ts, 86400);
            std.debug.print("[{d} ago] {s} (x{d})\n", .{ days_ago, cmd, info.count });
            count += 1;
        }
    } else {
        // Full log view
        var count: u32 = 0;
        for (entries.items) |entry| {
            if (count >= limit) break;
            const ts = entry.timestamp;
            const days_ago = @divTrunc(@as(i64, @intCast(time_compat.timestamp(g_cmd_io))) - ts, 86400);
            std.debug.print("[{d} ago] {s} -> {s}\n", .{ days_ago, entry.original, entry.rtk });
            count += 1;
        }
    }

    std.debug.print("\nTotal entries: {d}\n", .{entries.items.len});
    return 0;
}

fn dispatchSummary(args: []const [:0]const u8) !i32 {
    // summary - Show command usage summary (top commands, categories, etc.)
    _ = args; // Currently no options
    const CmdCount = struct { cmd: []const u8, count: u32 };

    const home_dir = if (std.c.getenv("HOME")) |ptr|
        std.mem.sliceTo(ptr, 0)
    else {
        std.debug.print("summary: HOME not set\n", .{});
        return 1;
    };

    const history_path = std.fs.path.join(g_cmd_allocator, &.{ home_dir, ".local/share/llmlite/history.db" }) catch {
        std.debug.print("summary: failed to build path\n", .{});
        return 1;
    };
    defer g_cmd_allocator.free(history_path);

    const file = std.Io.Dir.openFileAbsolute(g_cmd_io, history_path, .{}) catch {
        std.debug.print("No summary available. Run 'llmlite-cmd init -g' first.\n", .{});
        return 0;
    };
    defer file.close(g_cmd_io);

    var buf: [8192]u8 = undefined;
    var file_buffer = std.array_list.Managed(u8).init(g_cmd_allocator);
    defer file_buffer.deinit();

    while (true) {
        const bytes_read = file.readPositional(g_cmd_io, &.{&buf}, 0) catch break;
        if (bytes_read == 0) break;
        file_buffer.appendSlice(buf[0..bytes_read]) catch break;
    }

    // Count commands by category
    var cmd_counts = std.StringHashMap(u32).init(g_cmd_allocator);
    defer cmd_counts.deinit();

    var total_saved: usize = 0;

    var line_iter = std.mem.splitScalar(u8, file_buffer.items, '\n');
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        var field_iter = std.mem.splitScalar(u8, line, '|');
        _ = field_iter.next() orelse continue; // timestamp
        const original = field_iter.next() orelse continue;
        _ = field_iter.next() orelse continue; // rtk
        const saved_str = field_iter.next() orelse "0";
        const saved = std.fmt.parseInt(usize, saved_str, 10) catch 0;

        total_saved += saved;

        // Extract command name (first word)
        const first_space = std.mem.findScalar(u8, original, ' ') orelse original.len;
        const cmd_name = original[0..first_space];

        if (cmd_counts.get(cmd_name)) |count| {
            cmd_counts.put(cmd_name, count + 1) catch {};
        } else {
            cmd_counts.put(cmd_name, 1) catch {};
        }
    }

    std.debug.print("\n=== llmlite Command Summary ===\n\n", .{});

    // Sort by count
    var sorted = std.array_list.Managed(CmdCount).init(g_cmd_allocator);
    defer sorted.deinit();

    var it = cmd_counts.iterator();
    while (it.next()) |entry| {
        sorted.append(.{
            .cmd = entry.key_ptr.*,
            .count = entry.value_ptr.*,
        }) catch break;
    }

    std.sort.heap(CmdCount, sorted.items, {}, struct {
        fn less(_: void, a: CmdCount, b: CmdCount) bool {
            return a.count > b.count;
        }
    }.less);

    std.debug.print("Top Commands:\n", .{});
    var count: u32 = 0;
    for (sorted.items) |entry| {
        if (count >= 10) break;
        std.debug.print("  {s}: {d}\n", .{ entry.cmd, entry.count });
        count += 1;
    }

    std.debug.print("\nTotal commands tracked: {d}\n", .{sorted.items.len});
    std.debug.print("Total tokens saved: {d}\n", .{total_saved});
    std.debug.print("\nRun 'llmlite-cmd gain' for detailed analytics.\n", .{});

    return 0;
}

fn dispatchProxy(args: []const [:0]const u8) !i32 {
    // proxy [command] - Manage llmlite-proxy
    if (args.len == 0) {
        std.debug.print("proxy: missing subcommand (start, stop, status, logs, config, keys)\n", .{});
        return 1;
    }

    const subcmd = args[0];

    if (std.mem.eql(u8, subcmd, "start")) {
        // Start the proxy in background
        std.debug.print("Starting llmlite-proxy...\n", .{});
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("llmlite-proxy");
        if (args.len > 1 and std.mem.eql(u8, args[1], "--tui")) {
            try argv.append("--tui");
        }
        const result = std.process.run(g_cmd_allocator, g_cmd_io, .{
            .argv = try argv.toOwnedSlice(),
        }) catch {
            std.debug.print("proxy: failed to start llmlite-proxy\n", .{});
            std.debug.print("Make sure llmlite-proxy is built: zig build proxy\n", .{});
            return 1;
        };
        std.debug.print("{s}", .{result.stdout});
        if (result.stderr.len > 0) {
            std.debug.print("{s}", .{result.stderr});
        }
        return switch (result.term) {
            .exited => |code| code,
            .signal => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
            .stopped => |sig| 128 + @as(i32, @intCast(@intFromEnum(sig))),
            .unknown => 1,
        };
    } else if (std.mem.eql(u8, subcmd, "status")) {
        // Check if proxy is running
        const result = std.process.run(g_cmd_allocator, g_cmd_io, .{
            .argv = &.{ "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "http://localhost:4000/health/live" },
        }) catch {
            std.debug.print("proxy: failed to check status (curl not available?)\n", .{});
            return 1;
        };

        const code = std.fmt.parseInt(i32, std.mem.trim(u8, result.stdout, " \n\r"), 10) catch 1;
        if (code == 200) {
            std.debug.print("llmlite-proxy: running on port 4000\n", .{});
            return 0;
        } else {
            std.debug.print("llmlite-proxy: not running (HTTP {d})\n", .{code});
            return 1;
        }
    } else if (std.mem.eql(u8, subcmd, "logs")) {
        // Show recent logs (if journald available)
        const result = std.process.run(g_cmd_allocator, g_cmd_io, .{
            .argv = &.{ "journalctl", "-u", "llmlite-proxy", "-n", "50", "--no-pager" },
        }) catch {
            std.debug.print("proxy logs: journalctl not available\n", .{});
            std.debug.print("Try: tail -f /var/log/llmlite-proxy.log\n", .{});
            return 1;
        };
        std.debug.print("{s}", .{result.stdout});
        return switch (result.term) {
            .exited => |exit_code| exit_code,
            else => 1,
        };
    } else if (std.mem.eql(u8, subcmd, "config")) {
        // Show config location
        std.debug.print("llmlite-proxy config locations:\n", .{});
        std.debug.print("  ~/.config/llmlite/proxy.toml\n", .{});
        std.debug.print("  /etc/llmlite/proxy.toml\n", .{});
        std.debug.print("  ./proxy.toml (current directory)\n", .{});
        return 0;
    } else if (std.mem.eql(u8, subcmd, "keys")) {
        // Key management subcommand
        return dispatchProxyKeys(args[1..]);
    } else if (std.mem.eql(u8, subcmd, "health")) {
        return proxyGet("/health/ready", "Health check");
    } else if (std.mem.eql(u8, subcmd, "metrics")) {
        return proxyGet("/metrics", "Metrics");
    } else if (std.mem.eql(u8, subcmd, "providers")) {
        return proxyGet("/api/providers", "Providers");
    } else if (std.mem.eql(u8, subcmd, "analytics")) {
        if (args.len < 2) {
            std.debug.print("proxy analytics: missing subcommand (gain, team, sessions, unified)\n", .{});
            return 1;
        }
        const analytic = args[1];
        const path = if (std.mem.eql(u8, analytic, "gain"))
            "/analytics/gain"
        else if (std.mem.eql(u8, analytic, "team"))
            "/analytics/team"
        else if (std.mem.eql(u8, analytic, "sessions"))
            "/analytics/sessions"
        else if (std.mem.eql(u8, analytic, "unified"))
            "/analytics/unified"
        else {
            std.debug.print("proxy analytics: unknown '{s}' (gain, team, sessions, unified)\n", .{analytic});
            return 1;
        };
        return proxyGet(path, "Analytics");
    } else {
        std.debug.print("proxy: unknown subcommand '{s}'\n", .{subcmd});
        std.debug.print("Supported: start, status, logs, config, keys, health, metrics, providers, analytics\n", .{});
        return 1;
    }
}

fn proxyGet(path: []const u8, label: []const u8) !i32 {
    const proxy_url = "http://localhost:4000";
    const url = std.fmt.allocPrint(g_cmd_allocator, "{s}{s}", .{ proxy_url, path }) catch {
        std.debug.print("proxy: failed to build URL\n", .{});
        return 1;
    };
    defer g_cmd_allocator.free(url);

    const uri = std.Uri.parse(url) catch {
        std.debug.print("proxy: failed to parse URL\n", .{});
        return 1;
    };

    var client = std.http.Client{ .allocator = g_cmd_allocator, .io = g_cmd_io };
    defer client.deinit();

    var response_writer = std.Io.Writer.Allocating.init(g_cmd_allocator);
    defer response_writer.deinit();

    const response = client.fetch(.{
        .location = .{ .uri = uri },
        .method = .GET,
        .response_writer = &response_writer.writer,
    }) catch {
        std.debug.print("proxy {s}: failed to connect (is llmlite-proxy running?)\n", .{label});
        return 1;
    };

    if (response.status != .ok) {
        std.debug.print("proxy {s}: HTTP {}\n", .{ label, response.status });
        return 1;
    }

    const body = response_writer.written();
    std.debug.print("{s}\n", .{body});
    return 0;
}

fn dispatchProxyKeys(args: []const [:0]const u8) !i32 {
    // proxy keys [list|create|revoke]
    const proxy_url = "http://localhost:4000";

    if (args.len == 0) {
        std.debug.print("proxy keys: missing subcommand (list, create, revoke)\n", .{});
        std.debug.print("\nUsage:\n", .{});
        std.debug.print("  llmlite proxy keys list                    # List all virtual keys\n", .{});
        std.debug.print("  llmlite proxy keys create [--key-id ID]   # Create a new key\n", .{});
        std.debug.print("  llmlite proxy keys revoke <key>            # Revoke a key\n", .{});
        std.debug.print("\nOptions:\n", .{});
        std.debug.print("  --key-id <id>    Virtual key ID (default: auto-generated)\n", .{});
        std.debug.print("  --team-id <id>   Team ID for the key\n", .{});
        std.debug.print("  --rate-limit <n> Rate limit (requests per minute)\n", .{});
        return 1;
    }

    const action = args[0];

    if (std.mem.eql(u8, action, "list")) {
        // List all keys
        var client = std.http.Client{ .allocator = g_cmd_allocator, .io = g_cmd_io };
        defer client.deinit();

        const uri = std.Uri.parse(proxy_url ++ "/keys") catch {
            std.debug.print("proxy keys list: failed to parse URL\n", .{});
            return 1;
        };

        var response_writer = std.Io.Writer.Allocating.init(g_cmd_allocator);
        defer response_writer.deinit();

        const response = client.fetch(.{
            .location = .{ .uri = uri },
            .method = .GET,
            .response_writer = &response_writer.writer,
        }) catch {
            std.debug.print("proxy keys: failed to connect to proxy at {s}\n", .{proxy_url});
            std.debug.print("Make sure llmlite-proxy is running: llmlite proxy start\n", .{});
            return 1;
        };

        if (response.status != .ok) {
            std.debug.print("proxy keys list: proxy returned HTTP {}\n", .{response.status});
            return 1;
        }

        const body = response_writer.written();
        std.debug.print("{s}\n", .{body});
        return 0;
    } else if (std.mem.eql(u8, action, "create")) {
        // Create a new key
        var key_id: ?[]const u8 = null;
        var team_id: ?[]const u8 = null;
        var rate_limit: ?u32 = null;

        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--key-id")) {
                if (i + 1 < args.len) {
                    key_id = args[i + 1];
                    i += 1;
                }
            } else if (std.mem.eql(u8, args[i], "--team-id")) {
                if (i + 1 < args.len) {
                    team_id = args[i + 1];
                    i += 1;
                }
            } else if (std.mem.eql(u8, args[i], "--rate-limit")) {
                if (i + 1 < args.len) {
                    rate_limit = std.fmt.parseInt(u32, args[i + 1], 10) catch null;
                    i += 1;
                }
            }
        }

        // Build request body
        var body_json: []u8 = undefined;
        if (key_id != null or team_id != null or rate_limit != null) {
            var fields = try std.ArrayList(u8).initCapacity(g_cmd_allocator, 256);
            defer fields.deinit(g_cmd_allocator);

            try fields.appendSlice(g_cmd_allocator, "{");
            var first = true;
            if (key_id) |id| {
                try fields.appendSlice(g_cmd_allocator, "\"key_id\":\"");
                try fields.appendSlice(g_cmd_allocator, id);
                try fields.appendSlice(g_cmd_allocator, "\"");
                first = false;
            }
            if (team_id) |tid| {
                if (!first) try fields.appendSlice(g_cmd_allocator, ",");
                try fields.appendSlice(g_cmd_allocator, "\"team_id\":\"");
                try fields.appendSlice(g_cmd_allocator, tid);
                try fields.appendSlice(g_cmd_allocator, "\"");
                first = false;
            }
            if (rate_limit) |rl| {
                if (!first) try fields.appendSlice(g_cmd_allocator, ",");
                try fields.appendSlice(g_cmd_allocator, "\"rate_limit\":");
                const rl_str = std.fmt.allocPrint(g_cmd_allocator, "{d}", .{rl}) catch "";
                try fields.appendSlice(g_cmd_allocator, rl_str);
                first = false;
            }
            try fields.appendSlice(g_cmd_allocator, "}");
            body_json = try fields.toOwnedSlice(g_cmd_allocator);
        } else {
            body_json = try g_cmd_allocator.dupe(u8, "{}");
        }

        // HTTP Client for key creation
        var client = std.http.Client{ .allocator = g_cmd_allocator, .io = g_cmd_io };
        defer client.deinit();

        const uri = std.Uri.parse(proxy_url ++ "/key/create") catch {
            std.debug.print("proxy keys create: failed to parse URL\n", .{});
            return 1;
        };

        var response_writer = std.Io.Writer.Allocating.init(g_cmd_allocator);
        defer response_writer.deinit();

        const response = client.fetch(.{
            .location = .{ .uri = uri },
            .method = .POST,
            .extra_headers = &.{.{ .name = "Content-Type", .value = "application/json" }},
            .payload = body_json,
            .response_writer = &response_writer.writer,
        }) catch {
            std.debug.print("proxy keys: failed to connect to proxy at {s}\n", .{proxy_url});
            std.debug.print("Make sure llmlite-proxy is running: llmlite proxy start\n", .{});
            return 1;
        };

        if (response.status != .ok and response.status != .created) {
            std.debug.print("proxy keys create: proxy returned HTTP {}\n", .{response.status});
            return 1;
        }

        const body = response_writer.written();
        std.debug.print("{s}\n", .{body});
        return 0;
    } else if (std.mem.eql(u8, action, "revoke")) {
        // Revoke a key
        if (args.len < 2) {
            std.debug.print("proxy keys revoke: missing key argument\n", .{});
            std.debug.print("Usage: llmlite proxy keys revoke <key>\n", .{});
            return 1;
        }

        const key_to_revoke = args[1];

        // HTTP Client for key revocation
        var client = std.http.Client{ .allocator = g_cmd_allocator, .io = g_cmd_io };
        defer client.deinit();

        const body = try std.fmt.allocPrint(g_cmd_allocator, "{{\"key\":\"{s}\"}}", .{key_to_revoke});
        defer g_cmd_allocator.free(body);

        const uri = std.Uri.parse(proxy_url ++ "/key/revoke") catch {
            std.debug.print("proxy keys revoke: failed to parse URL\n", .{});
            return 1;
        };

        var response_writer = std.Io.Writer.Allocating.init(g_cmd_allocator);
        defer response_writer.deinit();

        const response = client.fetch(.{
            .location = .{ .uri = uri },
            .method = .POST,
            .extra_headers = &.{.{ .name = "Content-Type", .value = "application/json" }},
            .payload = body,
            .response_writer = &response_writer.writer,
        }) catch {
            std.debug.print("proxy keys: failed to connect to proxy at {s}\n", .{proxy_url});
            std.debug.print("Make sure llmlite-proxy is running: llmlite proxy start\n", .{});
            return 1;
        };

        if (response.status != .ok) {
            std.debug.print("proxy keys revoke: proxy returned HTTP {}\n", .{response.status});
            return 1;
        }

        std.debug.print("{s}\n", .{response_writer.written()});
        return 0;
    } else {
        std.debug.print("proxy keys: unknown action '{s}'\n", .{action});
        std.debug.print("Supported: list, create, revoke\n", .{});
        return 1;
    }
}

fn dispatchPsql(args: []const [:0]const u8) !i32 {
    // psql - PostgreSQL client with compact output
    // Strip borders and compress tables for token savings
    var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
    defer argv.deinit();

    try argv.append("psql");
    for (args) |arg| try argv.append(arg);

    return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "psql", "psql", .{
        .tee_label = "psql",
        .verbose = global_verbose,
        .strategy = .structure_only,
    });
}

fn dispatchPnpm(args: []const [:0]const u8) !i32 {
    // pnpm - pnpm package manager with ultra-compact output
    if (args.len == 0) {
        return core.runner.runPassthrough(g_cmd_allocator, &.{"pnpm"}, global_verbose, g_cmd_io);
    }

    const subcmd = args[0];

    if (std.mem.eql(u8, subcmd, "list")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "pnpm", "list", "--depth=0" }, "pnpm list", "pnpm list", .{
            .tee_label = "pnpm",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .tree_compression,
        });
    } else if (std.mem.eql(u8, subcmd, "outdated")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "pnpm", "outdated" }, "pnpm outdated", "pnpm outdated", .{
            .tee_label = "pnpm",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "install")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "pnpm", "install" }, "pnpm install", "pnpm install", .{
            .tee_label = "pnpm",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .progress_strip,
        });
    } else if (std.mem.eql(u8, subcmd, "build")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "pnpm", "build" }, "pnpm build", "pnpm build", .{
            .tee_label = "pnpm",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "test")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "pnpm", "test" }, "pnpm test", "pnpm test", .{
            .tee_label = "pnpm",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .failure_focus,
        });
    } else if (std.mem.eql(u8, subcmd, "dev")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "pnpm", "dev" }, "pnpm dev", "pnpm dev", .{
            .tee_label = "pnpm",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .none,
        });
    } else if (std.mem.eql(u8, subcmd, "typecheck")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "pnpm", "typecheck" }, "pnpm typecheck", "pnpm typecheck", .{
            .tee_label = "pnpm",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .grouping,
        });
    } else {
        // Passthrough for other pnpm commands
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("pnpm");
        for (args) |arg| try argv.append(arg);
        return core.runner.runPassthrough(g_cmd_allocator, try argv.toOwnedSlice(), global_verbose, g_cmd_io);
    }
}

fn dispatchDotnet(args: []const [:0]const u8) !i32 {
    // dotnet - .NET CLI with compact output
    if (args.len == 0) {
        return core.runner.runPassthrough(g_cmd_allocator, &.{"dotnet"}, global_verbose, g_cmd_io);
    }

    const subcmd = args[0];

    if (std.mem.eql(u8, subcmd, "build")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "dotnet", "build" }, "dotnet build", "dotnet build", .{
            .tee_label = "dotnet",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .errors_only,
        });
    } else if (std.mem.eql(u8, subcmd, "test")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "dotnet", "test" }, "dotnet test", "dotnet test", .{
            .tee_label = "dotnet",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .failure_focus,
        });
    } else if (std.mem.eql(u8, subcmd, "restore")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "dotnet", "restore" }, "dotnet restore", "dotnet restore", .{
            .tee_label = "dotnet",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "format")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "dotnet", "format" }, "dotnet format", "dotnet format", .{
            .tee_label = "dotnet",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "run")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "dotnet", "run" }, "dotnet run", "dotnet run", .{
            .tee_label = "dotnet",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "publish")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "dotnet", "publish" }, "dotnet publish", "dotnet publish", .{
            .tee_label = "dotnet",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else {
        // Passthrough for other dotnet commands
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("dotnet");
        for (args) |arg| try argv.append(arg);
        return core.runner.runPassthrough(g_cmd_allocator, try argv.toOwnedSlice(), global_verbose, g_cmd_io);
    }
}

fn dispatchCompose(args: []const [:0]const u8) !i32 {
    // compose - Docker Compose commands with compact output
    if (args.len == 0) {
        std.debug.print("compose: missing subcommand (ps, logs, build, up, down)\n", .{});
        return 1;
    }

    const subcmd = args[0];

    if (std.mem.eql(u8, subcmd, "ps")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "docker", "compose", "ps" }, "compose ps", "docker compose ps", .{
            .tee_label = "compose",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "logs")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("docker");
        try argv.append("compose");
        try argv.append("logs");
        // Optional service name as second arg
        if (args.len > 1) try argv.append(args[1]);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "compose logs", "docker compose logs", .{
            .tee_label = "compose",
            .verbose = global_verbose,
            .strategy = .deduplication,
        });
    } else if (std.mem.eql(u8, subcmd, "build")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("docker");
        try argv.append("compose");
        try argv.append("build");
        for (args[1..]) |arg| try argv.append(arg);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "compose build", "docker compose build", .{
            .tee_label = "compose",
            .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "up")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("docker");
        try argv.append("compose");
        try argv.append("up");
        for (args[1..]) |arg| try argv.append(arg);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "compose up", "docker compose up", .{
            .tee_label = "compose",
            .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "down")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "docker", "compose", "down" }, "compose down", "docker compose down", .{
            .tee_label = "compose",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else {
        // Passthrough for other compose commands
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("docker");
        try argv.append("compose");
        for (args) |arg| try argv.append(arg);
        return core.runner.runPassthrough(g_cmd_allocator, try argv.toOwnedSlice(), global_verbose, g_cmd_io);
    }
}

fn dispatchWc(args: []const [:0]const u8) !i32 {
    // wc - Word/line/byte count with compact output
    var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
    defer argv.deinit();

    try argv.append("wc");
    for (args) |arg| try argv.append(arg);

    return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "wc", "wc", .{
        .tee_label = "wc",
        .verbose = global_verbose,
        .strategy = .stats,
    });
}

fn dispatchMypy(args: []const [:0]const u8) !i32 {
    // mypy - Mypy type checker with grouped error output
    var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
    defer argv.deinit();

    try argv.append("mypy");
    for (args) |arg| try argv.append(arg);

    return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "mypy", "mypy", .{
        .tee_label = "mypy",
        .verbose = global_verbose,
        .strategy = .grouping,
    });
}

fn dispatchGt(args: []const [:0]const u8) !i32 {
    // gt - Graphite (gt) stacked PR commands with compact output
    if (args.len == 0) {
        std.debug.print("gt: missing subcommand (log, submit, sync, restack, create, branch)\n", .{});
        return 1;
    }

    const subcmd = args[0];

    if (std.mem.eql(u8, subcmd, "log")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("gt");
        try argv.append("log");
        for (args[1..]) |arg| try argv.append(arg);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "gt log", "gt log", .{
            .tee_label = "gt",
            .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "submit")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("gt");
        try argv.append("submit");
        for (args[1..]) |arg| try argv.append(arg);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "gt submit", "gt submit", .{
            .tee_label = "gt",
            .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "sync")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "gt", "sync" }, "gt sync", "gt sync", .{
            .tee_label = "gt",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "restack")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "gt", "restack" }, "gt restack", "gt restack", .{
            .tee_label = "gt",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "create")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "gt", "create" }, "gt create", "gt create", .{
            .tee_label = "gt",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (std.mem.eql(u8, subcmd, "branch")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("gt");
        try argv.append("branch");
        for (args[1..]) |arg| try argv.append(arg);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "gt branch", "gt branch", .{
            .tee_label = "gt",
            .verbose = global_verbose,
            .strategy = .stats,
        });
    } else {
        // Passthrough for other gt commands
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("gt");
        for (args) |arg| try argv.append(arg);
        return core.runner.runPassthrough(g_cmd_allocator, try argv.toOwnedSlice(), global_verbose, g_cmd_io);
    }
}

fn dispatchNpx(args: []const [:0]const u8) !i32 {
    // npx - npx with intelligent routing
    if (args.len == 0) {
        return core.runner.runPassthrough(g_cmd_allocator, &.{"npx"}, global_verbose, g_cmd_io);
    }

    const cmd = args[0];

    // Route to specialized filters if available
    if (std.mem.eql(u8, cmd, "tsc")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "npx", "tsc" }, "tsc", "npx tsc", .{
            .tee_label = "tsc",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .grouping,
        });
    } else if (std.mem.eql(u8, cmd, "eslint")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "npx", "eslint" }, "eslint", "npx eslint", .{
            .tee_label = "eslint",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .grouping,
        });
    } else if (std.mem.eql(u8, cmd, "prettier")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "npx", "prettier" }, "prettier", "npx prettier", .{
            .tee_label = "prettier",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .grouping,
        });
    } else if (std.mem.eql(u8, cmd, "prisma")) {
        // Route to prisma
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("npx");
        try argv.append("prisma");
        for (args[1..]) |arg| try argv.append(arg);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "prisma", "npx prisma", .{
            .tee_label = "prisma",
            .verbose = global_verbose,
            .strategy = .state_machine,
        });
    } else if (std.mem.eql(u8, cmd, "vitest")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "npx", "vitest" }, "vitest", "npx vitest", .{
            .tee_label = "vitest",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .state_machine,
        });
    } else if (std.mem.eql(u8, cmd, "playwright")) {
        return core.runner.runFiltered(g_cmd_allocator, &.{ "npx", "playwright" }, "playwright", "npx playwright", .{
            .tee_label = "playwright",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .failure_focus,
        });
    } else {
        // Passthrough for other npx commands
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("npx");
        for (args) |arg| try argv.append(arg);
        return core.runner.runPassthrough(g_cmd_allocator, try argv.toOwnedSlice(), global_verbose, g_cmd_io);
    }
}

fn dispatchErr(args: []const [:0]const u8) !i32 {
    // err - Run command and show only errors/warnings
    if (args.len == 0) {
        std.debug.print("err: missing command to run\n", .{});
        return 1;
    }

    var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
    defer argv.deinit();

    for (args) |arg| try argv.append(arg);

    return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "err", args[0], .{
        .tee_label = "err",
        .verbose = global_verbose,
        .strategy = .errors_only,
    });
}

fn dispatchRewrite(args: []const [:0]const u8) !i32 {
    // rewrite - Rewrite a raw command to its llmlite equivalent
    // Used by Claude Code, Gemini CLI, and other LLM hooks
    // Exits 0 and prints the rewritten command if supported
    // Exits 1 with no output if the command has no llmlite equivalent

    if (args.len == 0) {
        return 1;
    }

    // Reconstruct command from args (handles: llmlite rewrite ls -la vs llmlite rewrite "ls -la")
    const input = try std.mem.join(g_cmd_allocator, " ", args[0..]);
    defer g_cmd_allocator.free(input);

    // Try to find a rewrite rule
    if (core.hook.shouldRewrite(input)) {
        if (core.hook.rewrite(input)) |rewritten| {
            const stdout = std.Io.File.stdout();
            stdout.writeStreamingAll(g_cmd_io, rewritten) catch {};
            stdout.writeStreamingAll(g_cmd_io, "\n") catch {};
            return 0;
        }
    }

    // No rewrite found - return exit code 1 with no output
    return 1;
}

fn dispatchFormat(args: []const [:0]const u8) !i32 {
    // format - Universal formatter that auto-detects project type
    // Routes to: prettier, ruff format, black, rustfmt, gofmt, etc.

    // Auto-detect formatter based on project files
    const has_prettier = core.utils.fileExists(g_cmd_io, "package.json") or core.utils.fileExists(g_cmd_io, ".prettierrc");
    const has_ruff = core.utils.fileExists(g_cmd_io, "ruff.toml") or core.utils.fileExists(g_cmd_io, "pyproject.toml");
    const has_rustfmt = core.utils.fileExists(g_cmd_io, "Cargo.toml");
    const has_gofmt = core.utils.fileExists(g_cmd_io, "go.mod");

    if (has_prettier) {
        // Use prettier for JS/TS projects
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("npx");
        try argv.append("prettier");
        for (args) |arg| try argv.append(arg);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "prettier", "format", .{
            .tee_label = "prettier",
            .verbose = global_verbose,
            .strategy = .grouping,
        });
    } else if (has_ruff) {
        // Use ruff for Python projects
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("ruff");
        try argv.append("format");
        for (args) |arg| try argv.append(arg);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "ruff format", "format", .{
            .tee_label = "ruff",
            .verbose = global_verbose,
            .strategy = .grouping,
        });
    } else if (has_rustfmt) {
        // Use rustfmt for Rust projects
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("cargo");
        try argv.append("fmt");
        for (args) |arg| try argv.append(arg);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "cargo fmt", "format", .{
            .tee_label = "rustfmt",
            .verbose = global_verbose,
            .strategy = .stats,
        });
    } else if (has_gofmt) {
        // Use gofmt/go fmt for Go projects
        return core.runner.runFiltered(g_cmd_allocator, &.{ "go", "fmt" }, "go fmt", "format", .{
            .tee_label = "gofmt",
            .io = g_cmd_io, .verbose = global_verbose,
            .strategy = .stats,
        });
    } else {
        // No formatter detected
        std.debug.print("format: no formatter detected. Supported: prettier, ruff, rustfmt, gofmt\n", .{});
        std.debug.print("Add one of: package.json, ruff.toml, Cargo.toml, go.mod\n", .{});
        return 1;
    }
}

fn dispatchAudit(args: []const [:0]const u8) !i32 {
    // audit - Show hook usage statistics
    var since_days: u32 = 30;
    var format_json = false;
    var verbose = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--since") and i + 1 < args.len) {
            since_days = std.fmt.parseInt(u32, args[i + 1], 10) catch 30;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--json")) {
            format_json = true;
        } else if (std.mem.eql(u8, args[i], "-v") or std.mem.eql(u8, args[i], "--verbose")) {
            verbose = true;
        }
    }

    const options = core.audit.AuditOptions{
        .since_days = since_days,
        .format = if (format_json) .json else .text,
        .verbose = verbose,
    };

    try core.audit.showAudit(g_cmd_io, g_cmd_allocator, options);
    return 0;
}

fn dispatchVerify(args: []const [:0]const u8) !i32 {
    // verify - Check hook integrity (SHA-256 verification)
    _ = args;
    try core.integrity.showVerificationStatus(g_cmd_io, g_cmd_allocator);
    return 0;
}

fn dispatchMemory(args: []const [:0]const u8) !i32 {
    const home = std.c.getenv("HOME") orelse return 1;
    return core.memory_cmd.dispatch(g_cmd_allocator, g_cmd_io, std.mem.sliceTo(home, 0), args);
}

fn dispatchLearn(args: []const [:0]const u8) !i32 {
    // learn - Detect CLI error patterns from history
    var min_confidence: f64 = 0.5;
    var min_occurrences: u32 = 2;
    var format_json = false;
    var write_rules = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--min-confidence") and i + 1 < args.len) {
            min_confidence = std.fmt.parseFloat(f64, args[i + 1]) catch 0.5;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--min-occurrences") and i + 1 < args.len) {
            min_occurrences = std.fmt.parseInt(u32, args[i + 1], 10) catch 2;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--json")) {
            format_json = true;
        } else if (std.mem.eql(u8, args[i], "--write-rules")) {
            write_rules = true;
        }
    }

    const options = core.learn.LearnOptions{
        .min_confidence = min_confidence,
        .min_occurrences = min_occurrences,
        .output_format = if (format_json) .json else .text,
        .write_rules = write_rules,
    };

    try core.learn.analyzeCorrections(g_cmd_allocator, options);
    return 0;
}

fn dispatchEconomics(args: []const [:0]const u8) !i32 {
    // economics - Claude API spending vs llmlite savings analysis
    var period = core.cc_economics.EconomicsPeriod.daily;
    var format_json = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--weekly")) {
            period = .weekly;
        } else if (std.mem.eql(u8, args[i], "--monthly")) {
            period = .monthly;
        } else if (std.mem.eql(u8, args[i], "--json")) {
            format_json = true;
        }
    }

    const options = core.cc_economics.EconomicsOptions{
        .period = period,
        .format = if (format_json) .json else .text,
    };

    try core.cc_economics.showEconomics(g_cmd_allocator, options);
    return 0;
}

fn dispatchTrust(args: []const [:0]const u8) !i32 {
    // trust - Trust a project-local TOML filter
    var list_only = false;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--list")) {
            list_only = true;
        }
    }

    if (list_only) {
        const trusted = core.trust.listTrusted(g_cmd_allocator) catch &.{};
        defer {
            for (trusted) |t| g_cmd_allocator.free(t);
            g_cmd_allocator.free(trusted);
        }

        std.debug.print("Trusted filters:\n", .{});
        if (trusted.len == 0) {
            std.debug.print("  (none)\n", .{});
        } else {
            for (trusted) |t| {
                std.debug.print("  {s}\n", .{t});
            }
        }
        return 0;
    }

    // Trust a specific filter file
    const filter_path = ".llmlite/filters.toml";

    core.trust.trustFilter(g_cmd_allocator, filter_path) catch |err| {
        std.debug.print("Failed to trust filter: {}\n", .{err});
        return 1;
    };

    std.debug.print("Trusted: {s}\n", .{filter_path});
    return 0;
}

fn dispatchUntrust(args: []const [:0]const u8) !i32 {
    _ = args; // args not used for now
    // untrust - Revoke trust for a project-local TOML filter
    const filter_path = ".llmlite/filters.toml";

    core.trust.untrustFilter(g_cmd_allocator, filter_path) catch |err| {
        std.debug.print("Failed to untrust filter: {}\n", .{err});
        return 1;
    };

    std.debug.print("Untrusted: {s}\n", .{filter_path});
    return 0;
}

fn dispatchTerraform(args: []const [:0]const u8) !i32 {
    // terraform - Infrastructure as Code with compact output
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "terraform";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "terraform ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "terraform", raw_args, .{
        .strategy = .errors_only,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchHelm(args: []const [:0]const u8) !i32 {
    // helm - Kubernetes package manager with compact output
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "helm";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "helm ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "helm", raw_args, .{
        .strategy = .errors_only,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchGcloud(args: []const [:0]const u8) !i32 {
    // gcloud - GCP CLI with compact output
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "gcloud";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "gcloud ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "gcloud", raw_args, .{
        .strategy = .errors_only,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchAnsiblePlaybook(args: []const [:0]const u8) !i32 {
    // ansible-playbook - Ansible playbook runner with compact output
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "ansible-playbook";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "ansible-playbook ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "ansible-playbook", raw_args, .{
        .strategy = .errors_only,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchMake(args: []const [:0]const u8) !i32 {
    // make - Build tool with filtered output
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "make";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "make ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "make", raw_args, .{
        .strategy = .errors_only,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchMix(args: []const [:0]const u8) !i32 {
    // mix - Elixir build tool with compact output
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "mix";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "mix ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "mix", raw_args, .{
        .strategy = .errors_only,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchPreCommit(args: []const [:0]const u8) !i32 {
    // pre-commit - Git hooks framework with compact output
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "pre-commit";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "pre-commit ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "pre-commit", raw_args, .{
        .strategy = .errors_only,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchShellcheck(args: []const [:0]const u8) !i32 {
    // shellcheck - Shell script linter with compact output
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "shellcheck";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "shellcheck ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "shellcheck", raw_args, .{
        .strategy = .errors_only,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchHadolint(args: []const [:0]const u8) !i32 {
    // hadolint - Dockerfile linter with compact output
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "hadolint";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "hadolint ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "hadolint", raw_args, .{
        .strategy = .errors_only,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchGradle(args: []const [:0]const u8) !i32 {
    // gradle - Java build tool with compact output
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "gradle";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "gradle ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "gradle", raw_args, .{
        .strategy = .errors_only,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchMvn(args: []const [:0]const u8) !i32 {
    // mvn - Maven build tool with compact output
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "mvn";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "mvn ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "mvn", raw_args, .{
        .strategy = .errors_only,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchSwift(args: []const [:0]const u8) !i32 {
    // swift - Swift build tool with compact output
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "swift";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "swift ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "swift", raw_args, .{
        .strategy = .errors_only,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchJust(args: []const [:0]const u8) !i32 {
    // just - Command runner (rust)
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "just";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "just ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "just", raw_args, .{
        .strategy = .stats,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchMise(args: []const [:0]const u8) !i32 {
    // mise - Rust version manager
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "mise";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "mise ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "mise", raw_args, .{
        .strategy = .stats,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchTask(args: []const [:0]const u8) !i32 {
    // task - Task runner (go-task)
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "task";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "task ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "task", raw_args, .{
        .strategy = .stats,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchJj(args: []const [:0]const u8) !i32 {
    // jj - Jujutsu VCS (Git-compatible)
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "jj";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "jj ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "jj", raw_args, .{
        .strategy = .stats,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchRuff(args: []const [:0]const u8) !i32 {
    // ruff - Python linter and formatter
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "ruff";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "ruff ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "ruff", raw_args, .{
        .strategy = .errors_only,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchBiome(args: []const [:0]const u8) !i32 {
    // biome - JS/TS linter and formatter
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "biome";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "biome ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "biome", raw_args, .{
        .strategy = .errors_only,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchEslint(args: []const [:0]const u8) !i32 {
    // eslint - JavaScript/TypeScript linter
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "eslint";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "eslint ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "eslint", raw_args, .{
        .strategy = .errors_only,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchTsc(args: []const [:0]const u8) !i32 {
    // tsc - TypeScript compiler
    const argv = try g_cmd_allocator.alloc([]const u8, args.len + 1);
    defer g_cmd_allocator.free(argv);
    argv[0] = "tsc";
    for (args, 1..) |arg, i| argv[i] = arg;
    const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "tsc ", try std.mem.join(g_cmd_allocator, " ", args) });
    defer g_cmd_allocator.free(raw_args);
    return core.runner.runFiltered(g_cmd_allocator, argv, "tsc", raw_args, .{
        .strategy = .errors_only,
        .io = g_cmd_io, .verbose = global_verbose,
    });
}

fn dispatchZig(args: []const [:0]const u8) !i32 {
    // zig - Zig compiler and build system
    // Supports: build, fmt, ast, translate-c, std, build-obj, etc.
    if (args.len == 0) {
        std.debug.print("zig: missing subcommand\n", .{});
        return 1;
    }

    const subcmd = args[0];

    // zig build - filtered for errors/warnings
    if (std.mem.eql(u8, subcmd, "build")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("zig");
        try argv.append("build");
        for (args[1..]) |arg| try argv.append(arg);
        const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "zig build ", try std.mem.join(g_cmd_allocator, " ", args[1..]) });
        defer g_cmd_allocator.free(raw_args);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "zig build", raw_args, .{
            .strategy = .errors_only,
            .verbose = global_verbose,
        });
    }

    // zig test - filtered for test results
    if (std.mem.eql(u8, subcmd, "test")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("zig");
        try argv.append("test");
        for (args[1..]) |arg| try argv.append(arg);
        const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "zig test ", try std.mem.join(g_cmd_allocator, " ", args[1..]) });
        defer g_cmd_allocator.free(raw_args);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "zig test", raw_args, .{
            .strategy = .failure_focus,
            .verbose = global_verbose,
        });
    }

    // zig fmt - passthrough (formatting is visual)
    if (std.mem.eql(u8, subcmd, "fmt")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("zig");
        try argv.append("fmt");
        for (args[1..]) |arg| try argv.append(arg);
        return core.runner.runPassthrough(g_cmd_allocator, try argv.toOwnedSlice(), global_verbose, g_cmd_io);
    }

    // zig ast - show AST (passthrough for inspection)
    if (std.mem.eql(u8, subcmd, "ast")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("zig");
        try argv.append("ast");
        for (args[1..]) |arg| try argv.append(arg);
        return core.runner.runPassthrough(g_cmd_allocator, try argv.toOwnedSlice(), global_verbose, g_cmd_io);
    }

    // zig translate-c - C to Zig translation
    if (std.mem.eql(u8, subcmd, "translate-c")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("zig");
        try argv.append("translate-c");
        for (args[1..]) |arg| try argv.append(arg);
        const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "zig translate-c ", try std.mem.join(g_cmd_allocator, " ", args[1..]) });
        defer g_cmd_allocator.free(raw_args);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "zig translate-c", raw_args, .{
            .strategy = .stats,
            .verbose = global_verbose,
        });
    }

    // zig std - show standard library
    if (std.mem.eql(u8, subcmd, "std")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("zig");
        try argv.append("std");
        for (args[1..]) |arg| try argv.append(arg);
        return core.runner.runPassthrough(g_cmd_allocator, try argv.toOwnedSlice(), global_verbose, g_cmd_io);
    }

    // zig build-obj - compile object file
    if (std.mem.eql(u8, subcmd, "build-obj")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("zig");
        try argv.append("build-obj");
        for (args[1..]) |arg| try argv.append(arg);
        const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "zig build-obj ", try std.mem.join(g_cmd_allocator, " ", args[1..]) });
        defer g_cmd_allocator.free(raw_args);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "zig build-obj", raw_args, .{
            .strategy = .errors_only,
            .verbose = global_verbose,
        });
    }

    // zig build-lib - compile library
    if (std.mem.eql(u8, subcmd, "build-lib")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("zig");
        try argv.append("build-lib");
        for (args[1..]) |arg| try argv.append(arg);
        const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "zig build-lib ", try std.mem.join(g_cmd_allocator, " ", args[1..]) });
        defer g_cmd_allocator.free(raw_args);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "zig build-lib", raw_args, .{
            .strategy = .errors_only,
            .verbose = global_verbose,
        });
    }

    // zig build-exe - compile executable
    if (std.mem.eql(u8, subcmd, "build-exe")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("zig");
        try argv.append("build-exe");
        for (args[1..]) |arg| try argv.append(arg);
        const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "zig build-exe ", try std.mem.join(g_cmd_allocator, " ", args[1..]) });
        defer g_cmd_allocator.free(raw_args);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "zig build-exe", raw_args, .{
            .strategy = .errors_only,
            .verbose = global_verbose,
        });
    }

    // zig fmt --check - check formatting without changes
    if (std.mem.eql(u8, subcmd, "fmt") and args.len > 1 and std.mem.eql(u8, args[1], "--check")) {
        var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
        defer argv.deinit();
        try argv.append("zig");
        try argv.append("fmt");
        try argv.append("--check");
        for (args[2..]) |arg| try argv.append(arg);
        const raw_args = try std.mem.concat(g_cmd_allocator, u8, &.{ "zig fmt --check ", try std.mem.join(g_cmd_allocator, " ", args[2..]) });
        defer g_cmd_allocator.free(raw_args);
        return core.runner.runFiltered(g_cmd_allocator, try argv.toOwnedSlice(), "zig fmt --check", raw_args, .{
            .strategy = .stats,
            .verbose = global_verbose,
        });
    }

    // Default: passthrough for unknown subcommands
    var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
    defer argv.deinit();
    try argv.append("zig");
    for (args) |arg| try argv.append(arg);
    return core.runner.runPassthrough(g_cmd_allocator, try argv.toOwnedSlice(), global_verbose, g_cmd_io);
}

fn dispatchKiro(args: []const [:0]const u8) !i32 {
    // kiro <subcommand> [args...] - Kiro CLI wrapper
    // Kiro is an AI-powered coding assistant (agentic IDE/CLI)
    // Output is conversational, so we use passthrough strategy

    if (args.len == 0) {
        // No args - just launch kiro interactive chat
        return core.runner.runPassthrough(g_cmd_allocator, &.{"kiro"}, global_verbose, g_cmd_io);
    }

    // Build kiro-cli command
    var argv = std.array_list.Managed([]const u8).init(g_cmd_allocator);
    defer argv.deinit();
    try argv.append("kiro");
    for (args) |arg| try argv.append(arg);

    return core.runner.runPassthrough(g_cmd_allocator, try argv.toOwnedSlice(), global_verbose, g_cmd_io);
}
