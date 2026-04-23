//! Hook System - AI Tool Integration
//!
//! Provides shell hook for intercepting and rewriting commands.
//! Inspired by RTK's auto-rewrite hook system.

const std = @import("std");

/// Global Io instance set by cmd.zig dispatch.
pub var g_io: std.Io = undefined;

// Zig 0.16.0 compat: replacement for removed _getEnvVarOwned
fn _getEnvVarOwned(allocator: std.mem.Allocator, key: [*:0]const u8) error{EnvironmentVariableNotFound, OutOfMemory}![]u8 {
    const ptr = std.c.getenv(key) orelse return error.EnvironmentVariableNotFound;
    const slice = std.mem.sliceTo(ptr, 0);
    return allocator.dupe(u8, slice);
}
const fs = std.fs;
const rules = @import("rules");

pub const HookConfig = struct {
    tool: HookTool,
    global: bool = true,
    uninstall: bool = false,
    show: bool = false,
};

pub const HookTool = enum {
    claude_code,
    copilot,
    cursor,
    gemini,
    opencode,
    windsurf,
    cline,
    openclaw,
    codex,
    zsh,
    fish,
    kiro,
};

pub const RewriteRule = struct {
    pattern: []const u8,
    replacement: []const u8,
};

pub const rewrite_rules: []const RewriteRule = &.{
    // Git commands
    .{ .pattern = "git status", .replacement = "llmlite-cmd git status" },
    .{ .pattern = "git diff", .replacement = "llmlite-cmd git diff" },
    .{ .pattern = "git log", .replacement = "llmlite-cmd git log" },
    .{ .pattern = "git add", .replacement = "llmlite-cmd git add" },
    .{ .pattern = "git commit", .replacement = "llmlite-cmd git commit" },
    .{ .pattern = "git push", .replacement = "llmlite-cmd git push" },
    .{ .pattern = "git pull", .replacement = "llmlite-cmd git pull" },
    .{ .pattern = "git branch", .replacement = "llmlite-cmd git branch" },
    .{ .pattern = "git checkout", .replacement = "llmlite-cmd git checkout" },
    .{ .pattern = "git fetch", .replacement = "llmlite-cmd git fetch" },
    .{ .pattern = "git stash", .replacement = "llmlite-cmd git stash" },
    .{ .pattern = "git worktree", .replacement = "llmlite-cmd git worktree" },
    .{ .pattern = "git show", .replacement = "llmlite-cmd git show" },
    .{ .pattern = "git rebase", .replacement = "llmlite-cmd git rebase" },
    .{ .pattern = "git merge", .replacement = "llmlite-cmd git merge" },
    .{ .pattern = "git reset", .replacement = "llmlite-cmd git reset" },
    .{ .pattern = "git restore", .replacement = "llmlite-cmd git restore" },
    // GitHub CLI
    .{ .pattern = "gh pr ", .replacement = "llmlite-cmd gh pr " },
    .{ .pattern = "gh issue ", .replacement = "llmlite-cmd gh issue " },
    .{ .pattern = "gh run ", .replacement = "llmlite-cmd gh run " },
    .{ .pattern = "gh repo ", .replacement = "llmlite-cmd gh repo " },
    .{ .pattern = "gh api ", .replacement = "llmlite-cmd gh api " },
    // Cargo
    .{ .pattern = "cargo test", .replacement = "llmlite-cmd cargo test" },
    .{ .pattern = "cargo build", .replacement = "llmlite-cmd cargo build" },
    .{ .pattern = "cargo clippy", .replacement = "llmlite-cmd cargo clippy" },
    .{ .pattern = "cargo check", .replacement = "llmlite-cmd cargo check" },
    .{ .pattern = "cargo fmt", .replacement = "llmlite-cmd cargo fmt" },
    .{ .pattern = "cargo nextest", .replacement = "llmlite-cmd cargo nextest" },
    .{ .pattern = "cargo install", .replacement = "llmlite-cmd cargo install" },
    // NPM/Node
    .{ .pattern = "npm test", .replacement = "llmlite-cmd npm test" },
    .{ .pattern = "npm run", .replacement = "llmlite-cmd npm run" },
    .{ .pattern = "npx ", .replacement = "llmlite-cmd npx " },
    .{ .pattern = "pnpm ", .replacement = "llmlite-cmd pnpm " },
    // Python
    .{ .pattern = "pytest", .replacement = "llmlite-cmd pytest" },
    .{ .pattern = "pip ", .replacement = "llmlite-cmd pip " },
    .{ .pattern = "pip3 ", .replacement = "llmlite-cmd pip " },
    .{ .pattern = "uv pip", .replacement = "llmlite-cmd uv pip" },
    .{ .pattern = "uv sync", .replacement = "llmlite-cmd uv sync" },
    // Linters/Formatters
    .{ .pattern = "eslint", .replacement = "llmlite-cmd lint eslint" },
    .{ .pattern = "biome", .replacement = "llmlite-cmd lint biome" },
    .{ .pattern = "ruff", .replacement = "llmlite-cmd lint ruff" },
    .{ .pattern = "tsc", .replacement = "llmlite-cmd tsc" },
    .{ .pattern = "prettier", .replacement = "llmlite-cmd prettier" },
    .{ .pattern = "mypy", .replacement = "llmlite-cmd mypy" },
    // Docker/Containers
    .{ .pattern = "docker ps", .replacement = "llmlite-cmd docker ps" },
    .{ .pattern = "docker images", .replacement = "llmlite-cmd docker images" },
    .{ .pattern = "docker logs", .replacement = "llmlite-cmd docker logs" },
    .{ .pattern = "docker compose", .replacement = "llmlite-cmd compose " },
    .{ .pattern = "docker build", .replacement = "llmlite-cmd docker build" },
    .{ .pattern = "docker run", .replacement = "llmlite-cmd docker run" },
    // Kubernetes
    .{ .pattern = "kubectl get", .replacement = "llmlite-cmd kubectl get" },
    .{ .pattern = "kubectl logs", .replacement = "llmlite-cmd kubectl logs" },
    .{ .pattern = "kubectl describe", .replacement = "llmlite-cmd kubectl describe" },
    .{ .pattern = "kubectl apply", .replacement = "llmlite-cmd kubectl apply" },
    .{ .pattern = "kubectl delete", .replacement = "llmlite-cmd kubectl delete" },
    .{ .pattern = "kubectl top", .replacement = "llmlite-cmd kubectl top" },
    .{ .pattern = "kubectl exec", .replacement = "llmlite-cmd kubectl exec" },
    .{ .pattern = "kubectl pods", .replacement = "llmlite-cmd kubectl pods" },
    .{ .pattern = "kubectl services", .replacement = "llmlite-cmd kubectl services" },
    // Go
    .{ .pattern = "go test", .replacement = "llmlite-cmd go test" },
    .{ .pattern = "go build", .replacement = "llmlite-cmd go build" },
    .{ .pattern = "go vet", .replacement = "llmlite-cmd go vet" },
    .{ .pattern = "golangci-lint", .replacement = "llmlite-cmd golangci-lint" },
    // Zig
    .{ .pattern = "zig build", .replacement = "llmlite-cmd zig build" },
    .{ .pattern = "zig test", .replacement = "llmlite-cmd zig test" },
    .{ .pattern = "zig fmt", .replacement = "llmlite-cmd zig fmt" },
    // Ruby
    .{ .pattern = "rake ", .replacement = "llmlite-cmd rake " },
    .{ .pattern = "rails test", .replacement = "llmlite-cmd rake test" },
    .{ .pattern = "rspec", .replacement = "llmlite-cmd rspec" },
    .{ .pattern = "rubocop", .replacement = "llmlite-cmd rubocop" },
    .{ .pattern = "bundle install", .replacement = "llmlite-cmd bundle install" },
    .{ .pattern = "bundle update", .replacement = "llmlite-cmd bundle update" },
    // .NET
    .{ .pattern = "dotnet build", .replacement = "llmlite-cmd dotnet build" },
    .{ .pattern = "dotnet test", .replacement = "llmlite-cmd dotnet test" },
    // AWS
    .{ .pattern = "aws ", .replacement = "llmlite-cmd aws " },
    // Infrastructure tools
    .{ .pattern = "terraform ", .replacement = "llmlite-cmd terraform " },
    .{ .pattern = "helm ", .replacement = "llmlite-cmd helm " },
    .{ .pattern = "ansible-playbook", .replacement = "llmlite-cmd ansible-playbook" },
    .{ .pattern = "gcloud ", .replacement = "llmlite-cmd gcloud " },
    // Shell tools
    .{ .pattern = "shellcheck", .replacement = "llmlite-cmd shellcheck" },
    .{ .pattern = "hadolint", .replacement = "llmlite-cmd hadolint" },
    // Build tools
    .{ .pattern = "make ", .replacement = "llmlite-cmd make " },
    .{ .pattern = "gradle ", .replacement = "llmlite-cmd gradle " },
    .{ .pattern = "mvn ", .replacement = "llmlite-cmd mvn " },
    // Elixir
    .{ .pattern = "mix compile", .replacement = "llmlite-cmd mix compile" },
    .{ .pattern = "mix format", .replacement = "llmlite-cmd mix format" },
    // Misc
    .{ .pattern = "psql", .replacement = "llmlite-cmd psql" },
    .{ .pattern = "curl ", .replacement = "llmlite-cmd curl " },
    .{ .pattern = "wget ", .replacement = "llmlite-cmd wget " },
    // Pre-commit
    .{ .pattern = "pre-commit ", .replacement = "llmlite-cmd pre-commit " },
    // Swift
    .{ .pattern = "swift build", .replacement = "llmlite-cmd swift build" },
    .{ .pattern = "swift test", .replacement = "llmlite-cmd swift test" },
};

pub fn shouldRewrite(input: []const u8) bool {
    const cls = rules.classify(input);
    return cls.matched and !cls.passthrough;
}

pub fn rewrite(input: []const u8) ?[]const u8 {
    return rules.rewrite(input);
}

fn getHomeDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = _getEnvVarOwned(allocator, "HOME") catch return error.HomeNotFound;
    return home;
}

fn getClaudeHooksDir(allocator: std.mem.Allocator) ![]u8 {
    const home = try getHomeDir(allocator);
    return std.fmt.allocPrint(allocator, "{s}/.claude/hooks", .{home});
}

fn getCursorHooksDir(allocator: std.mem.Allocator) ![]u8 {
    const home = try getHomeDir(allocator);
    return std.fmt.allocPrint(allocator, "{s}/.cursor/hooks", .{home});
}

fn getGeminiHooksDir(allocator: std.mem.Allocator) ![]u8 {
    const home = try getHomeDir(allocator);
    return std.fmt.allocPrint(allocator, "{s}/.gemini/hooks", .{home});
}

fn getOpenCodePluginsDir(allocator: std.mem.Allocator) ![]u8 {
    const home = try getHomeDir(allocator);
    return std.fmt.allocPrint(allocator, "{s}/.config/opencode/plugins", .{home});
}

fn getWindsurfRulesPath(allocator: std.mem.Allocator) ![]u8 {
    const home = try getHomeDir(allocator);
    return std.fmt.allocPrint(allocator, "{s}/.windsurfrules", .{home});
}

fn getClineRulesPath(allocator: std.mem.Allocator) ![]u8 {
    const home = try getHomeDir(allocator);
    return std.fmt.allocPrint(allocator, "{s}/.clinerules", .{home});
}

fn getCodexRulesPath(allocator: std.mem.Allocator) ![]u8 {
    const home = try getHomeDir(allocator);
    return std.fmt.allocPrint(allocator, "{s}/.codexrules", .{home});
}

fn getZshHookPath(allocator: std.mem.Allocator) ![]u8 {
    const home = try getHomeDir(allocator);
    return std.fmt.allocPrint(allocator, "{s}/.zshrc.d/llmlite-hook.zsh", .{home});
}

fn getFishHookPath(allocator: std.mem.Allocator) ![]u8 {
    const home = try getHomeDir(allocator);
    return std.fmt.allocPrint(allocator, "{s}/.config/fish/functions/llmlite-hook.fish", .{home});
}

fn getKiroHooksDir(allocator: std.mem.Allocator) ![]u8 {
    const home = try getHomeDir(allocator);
    return std.fmt.allocPrint(allocator, "{s}/.kiro/hooks", .{home});
}

pub fn installZshHook(allocator: std.mem.Allocator, verbose: bool) !void {
    // Create .zshrc.d directory if it doesn't exist
    const home = try getHomeDir(allocator);
    defer allocator.free(home);
    const zshrc_d = try std.fmt.allocPrint(allocator, "{s}/.zshrc.d", .{home});
    defer allocator.free(zshrc_d);
    try std.Io.Dir.createDirAbsolute(g_io, zshrc_d, .default_dir);

    const hook_path = try getZshHookPath(allocator);
    defer allocator.free(hook_path);

    const hook_content =
        "# llmlite-cmd Zsh Hook\n" ++
        "# Add to ~/.zshrc: source ~/.zshrc.d/llmlite-hook.zsh\n" ++
        "\n" ++
        "llmlite_rewrite() {\n" ++
        "    local cmd=\"$1\"\n" ++
        "    case \"$cmd\" in\n" ++
        "        git\\ status*|git\\ diff*|git\\ log*|git\\ add*|git\\ commit*|git\\ push*|git\\ pull*|git\\ branch*|git\\ checkout*|git\\ fetch*|git\\ stash*)\n" ++
        "            echo \"llmlite-cmd $cmd\"\n" ++
        "            ;;\n" ++
        "        gh\\ pr\\ *|gh\\ issue\\ *|gh\\ run\\ *)\n" ++
        "            echo \"llmlite-cmd $cmd\"\n" ++
        "            ;;\n" ++
        "        cargo\\ test*|cargo\\ build*|cargo\\ clippy*|cargo\\ check*|cargo\\ nextest*)\n" ++
        "            echo \"llmlite-cmd $cmd\"\n" ++
        "            ;;\n" ++
        "        npm\\ test*|npm\\ run*|pnpm\\ *)\n" ++
        "            echo \"llmlite-cmd $cmd\"\n" ++
        "            ;;\n" ++
        "        pytest*|pip\\ *|uv\\ *)\n" ++
        "            echo \"llmlite-cmd $cmd\"\n" ++
        "            ;;\n" ++
        "        docker\\ ps*|docker\\ images*|docker\\ logs*|docker\\ compose*)\n" ++
        "            echo \"llmlite-cmd $cmd\"\n" ++
        "            ;;\n" ++
        "        kubectl\\ *)\n" ++
        "            echo \"llmlite-cmd $cmd\"\n" ++
        "            ;;\n" ++
        "        go\\ test*|go\\ build*|go\\ vet*)\n" ++
        "            echo \"llmlite-cmd $cmd\"\n" ++
        "            ;;\n" ++
        "        eslint*|biome*|ruff*|tsc*|prettier*|lint*)\n" ++
        "            echo \"llmlite-cmd $cmd\"\n" ++
        "            ;;\n" ++
        "        vitest*|playwright*|mypy*)\n" ++
        "            echo \"llmlite-cmd $cmd\"\n" ++
        "            ;;\n" ++
        "        ls|ll|tree|find|grep)\n" ++
        "            echo \"llmlite-cmd $cmd\"\n" ++
        "            ;;\n" ++
        "        *)\n" ++
        "            echo \"$cmd\"\n" ++
        "            ;;\n" ++
        "    esac\n" ++
        "}\n" ++
        "\n" ++
        "# Alias common commands to use llmlite-cmd\n" ++
        "alias git='llmlite-cmd git'\n" ++
        "alias cargo='llmlite-cmd cargo'\n" ++
        "alias npm='llmlite-cmd npm'\n" ++
        "alias pnpm='llmlite-cmd pnpm'\n" ++
        "alias docker='llmlite-cmd docker'\n" ++
        "alias kubectl='llmlite-cmd kubectl'\n" ++
        "alias go='llmlite-cmd go'\n" ++
        "alias pytest='llmlite-cmd pytest'\n" ++
        "alias pip='llmlite-cmd pip'\n" ++
        "alias uv='llmlite-cmd uv'\n";

    {
        const file = try std.Io.Dir.createFileAbsolute(g_io, hook_path, .{});
        defer file.close(g_io);
        try file.writeStreamingAll(g_io, hook_content);
    }

    if (verbose) {
        std.debug.print("Created: {s}\n", .{hook_path});
        std.debug.print("Add to ~/.zshrc: source {s}\n", .{hook_path});
    }
}

pub fn installFishHook(allocator: std.mem.Allocator, verbose: bool) !void {
    // Create fish functions directory if it doesn't exist
    const home = try getHomeDir(allocator);
    defer allocator.free(home);
    const fish_dir = try std.fmt.allocPrint(allocator, "{s}/.config/fish/functions", .{home});
    defer allocator.free(fish_dir);
    try std.Io.Dir.createDirAbsolute(g_io, fish_dir, .default_dir);

    const hook_path = try getFishHookPath(allocator);
    defer allocator.free(hook_path);

    const hook_content =
        "# llmlite-cmd Fish Hook\n" ++
        "# llmlite-cmd automatically rewrites commands for token savings\n" ++
        "\n" ++
        "function llmlite-hook --on-event fish_prompt\n" ++
        "    # Nothing needed on prompt\n" ++
        "end\n" ++
        "\n" ++
        "function llmlite-rewrite --on-variable CMDDURATION\n" ++
        "    # Rewrite command before execution\n" ++
        "end\n" ++
        "\n" ++
        "# Alias common commands to use llmlite-cmd\n" ++
        "alias git llmlite-cmd git\n" ++
        "alias cargo llmlite-cmd cargo\n" ++
        "alias npm llmlite-cmd npm\n" ++
        "alias pnpm llmlite-cmd pnpm\n" ++
        "alias docker llmlite-cmd docker\n" ++
        "alias kubectl llmlite-cmd kubectl\n" ++
        "alias go llmlite-cmd go\n" ++
        "alias pytest llmlite-cmd pytest\n" ++
        "alias pip llmlite-cmd pip\n" ++
        "alias uv llmlite-cmd uv\n" ++
        "\n" ++
        "# Fish wrapper for llmlite-cmd integration\n" ++
        "function llmlite-cmd --description 'Token-optimized command runner'\n" ++
        "    command llmlite-cmd $argv\n" ++
        "end\n";

    {
        const file = try std.Io.Dir.createFileAbsolute(g_io, hook_path, .{});
        defer file.close(g_io);
        try file.writeStreamingAll(g_io, hook_content);
    }

    if (verbose) {
        std.debug.print("Created: {s}\n", .{hook_path});
        std.debug.print("Fish hooks installed. Restart fish or run: source {s}\n", .{hook_path});
    }
}

pub fn installClaudeCodeHook(allocator: std.mem.Allocator, verbose: bool) !void {
    const hooks_dir = try getClaudeHooksDir(allocator);
    defer allocator.free(hooks_dir);

    try std.Io.Dir.createDirAbsolute(g_io, hooks_dir, .default_dir);

    const hook_path = try std.fmt.allocPrint(allocator, "{s}/llmlite-rewrite.bash", .{hooks_dir});
    defer allocator.free(hook_path);

    var content = std.array_list.Managed(u8).init(allocator);
    defer content.deinit();

    try content.print(
        "#!/bin/bash\n" ++
            "# llmlite Claude Code Hook\n" ++
            "LLMLITE_BIN=\"llmlite-cmd\"\n" ++
            "rewrite_command() {{\n" ++
            "    local cmd=\"$1\"\n" ++
            "    case \"$cmd\" in\n" ++
            "        git\\ status*|git\\ diff*|git\\ log*|git\\ add*|git\\ commit*|git\\ push*|git\\ pull*|git\\ branch*|git\\ checkout*)\n" ++
            "            echo \"${{LLMLITE_BIN}} $cmd\"\n" ++
            "            ;;\n" ++
            "        gh\\ pr\\ *|gh\\ issue\\ *|gh\\ run\\ *)\n" ++
            "            echo \"${{LLMLITE_BIN}} $cmd\"\n" ++
            "            ;;\n" ++
            "        cargo\\ test*|cargo\\ build*|cargo\\ clippy*)\n" ++
            "            echo \"${{LLMLITE_BIN}} $cmd\"\n" ++
            "            ;;\n" ++
            "        npm\\ test*|npm\\ run*)\n" ++
            "            echo \"${{LLMLITE_BIN}} $cmd\"\n" ++
            "            ;;\n" ++
            "        pytest*)\n" ++
            "            echo \"${{LLMLITE_BIN}} pytest\"\n" ++
            "            ;;\n" ++
            "        docker\\ ps*|docker\\ images*|docker\\ logs*)\n" ++
            "            echo \"${{LLMLITE_BIN}} $cmd\"\n" ++
            "            ;;\n" ++
            "        kubectl\\ get*|kubectl\\ logs*)\n" ++
            "            echo \"${{LLMLITE_BIN}} $cmd\"\n" ++
            "            ;;\n" ++
            "        go\\ test*|go\\ build*|go\\ vet*)\n" ++
            "            echo \"${{LLMLITE_BIN}} $cmd\"\n" ++
            "            ;;\n" ++
            "        *)\n" ++
            "            echo \"$cmd\"\n" ++
            "            ;;\n" ++
            "    esac\n" ++
            "}}\n" ++
            "if [ -n \"$1\" ]; then\n" ++
            "    rewrite_command \"$1\"\n" ++
            "fi\n",
        .{},
    );

    {
        const file = try std.Io.Dir.createFileAbsolute(g_io, hook_path, .{});
        defer file.close(g_io);
        try file.writeStreamingAll(g_io, content.items);
    }

    if (verbose) {
        std.debug.print("Created: {s}\n", .{hook_path});
    }

    const settings_path = try std.fmt.allocPrint(allocator, "{s}/settings.json", .{hooks_dir});
    defer allocator.free(settings_path);

    const settings_json =
        \\{
        \\"hooks\\": {
        \\"PreToolUse\\": {
        \\"bash\\": {
        \\"command\\": \\"~/.claude/hooks/llmlite-rewrite.bash\\"
        \\}
        \\}
        \\}
        \\}
    ;

    {
        const file = try std.Io.Dir.createFileAbsolute(g_io, settings_path, .{});
        defer file.close(g_io);
        try file.writeStreamingAll(g_io, settings_json);
    }

    if (verbose) {
        std.debug.print("Created: {s}\n", .{settings_path});
    }
}

pub fn installCursorHook(allocator: std.mem.Allocator, verbose: bool) !void {
    const hooks_dir = try getCursorHooksDir(allocator);
    defer allocator.free(hooks_dir);

    try std.Io.Dir.createDirAbsolute(g_io, hooks_dir, .default_dir);

    const hook_path = try std.fmt.allocPrint(allocator, "{s}/llmlite-rewrite.bash", .{hooks_dir});
    defer allocator.free(hook_path);

    const hook_content =
        "#!/bin/bash\n" ++
        "# llmlite Cursor Hook\n" ++
        "LLMLITE_BIN=\"llmlite-cmd\"\n" ++
        "case \"$1\" in\n" ++
        "    git\\ *|gh\\ *|cargo\\ *|npm\\ *|pytest|docker\\ *|kubectl\\ *|go\\ test*)\n" ++
        "        echo \"${{LLMLITE_BIN}} $1\"\n" ++
        "        ;;\n" ++
        "    *)\n" ++
        "        echo \"$1\"\n" ++
        "        ;;\n" ++
        "esac\n";

    {
        const file = try std.Io.Dir.createFileAbsolute(g_io, hook_path, .{});
        defer file.close(g_io);
        try file.writeStreamingAll(g_io, hook_content);
    }

    if (verbose) {
        std.debug.print("Created: {s}\n", .{hook_path});
    }

    const hooks_json_path = try std.fmt.allocPrint(allocator, "{s}/hooks.json", .{hooks_dir});
    defer allocator.free(hooks_json_path);

    const hooks_json =
        \\{
        \\"version\\": 1,
        \\"hooks\\": [
        \\{
        \\"type\\": \\"preToolUse\\",
        \\"name\\": \\"llmlite-rewrite\\",
        \\"pattern\\": \\"bash\\",
        \\"command\\": \\"~/.cursor/hooks/llmlite-rewrite.bash\\"
        \\}
        \\]
        \\}
    ;

    {
        const file = try std.Io.Dir.createFileAbsolute(g_io, hooks_json_path, .{});
        defer file.close(g_io);
        try file.writeStreamingAll(g_io, hooks_json);
    }

    if (verbose) {
        std.debug.print("Updated: {s}\n", .{hooks_json_path});
    }
}

pub fn installGeminiHook(allocator: std.mem.Allocator, verbose: bool) !void {
    const hooks_dir = try getGeminiHooksDir(allocator);
    defer allocator.free(hooks_dir);

    try std.Io.Dir.createDirAbsolute(g_io, hooks_dir, .default_dir);

    const hook_path = try std.fmt.allocPrint(allocator, "{s}/llmlite-hook-gemini.bash", .{hooks_dir});
    defer allocator.free(hook_path);

    const hook_content =
        "#!/bin/bash\n" ++
        "# llmlite Gemini CLI Hook\n" ++
        "LLMLITE_BIN=\"llmlite-cmd\"\n" ++
        "case \"$1\" in\n" ++
        "    git\\ *|gh\\ *|cargo\\ *|npm\\ *|pytest|docker\\ *|kubectl\\ *)\n" ++
        "        exec ${{LLMLITE_BIN}} \"$@\"\n" ++
        "        ;;\n" ++
        "    *)\n" ++
        "        exec \"$@\"\n" ++
        "        ;;\n" ++
        "esac\n";

    {
        const file = try std.Io.Dir.createFileAbsolute(g_io, hook_path, .{});
        defer file.close(g_io);
        try file.writeStreamingAll(g_io, hook_content);
    }

    if (verbose) {
        std.debug.print("Created: {s}\n", .{hook_path});
    }

    const settings_path = try std.fmt.allocPrint(allocator, "{s}/settings.json", .{hooks_dir});
    defer allocator.free(settings_path);

    const settings_json =
        \\{
        \\"hooks\\": {
        \\"beforeTool\\": [
        \\{
        \\"name\\": \\"llmlite-rewrite\\",
        \\"command\\": \\"~/.gemini/hooks/llmlite-hook-gemini.bash\\",
        \\"tool\\": \\"bash\\"
        \\}
        \\]
        \\}
        \\}
    ;

    {
        const file = try std.Io.Dir.createFileAbsolute(g_io, settings_path, .{});
        defer file.close(g_io);
        try file.writeStreamingAll(g_io, settings_json);
    }

    if (verbose) {
        std.debug.print("Updated: {s}\n", .{settings_path});
    }
}

pub fn installOpenCodeHook(allocator: std.mem.Allocator, verbose: bool) !void {
    const plugins_dir = try getOpenCodePluginsDir(allocator);
    defer allocator.free(plugins_dir);

    try std.Io.Dir.createDirAbsolute(g_io, plugins_dir, .default_dir);

    const plugin_path = try std.fmt.allocPrint(allocator, "{s}/llmlite-plugin.ts", .{plugins_dir});
    defer allocator.free(plugin_path);

    const plugin_content =
        "// llmlite OpenCode Plugin\n" ++
        "export const llmlitePlugin = {\n" ++
        "  name: 'llmlite',\n" ++
        "  version: '1.0.0',\n" ++
        "  toolExecuteBefore: async (tool: string, args: string[]) => {\n" ++
        "    if (tool !== 'bash') return args;\n" ++
        "    const cmd = args[0] || '';\n" ++
        "    const BIN = 'llmlite-cmd';\n" ++
        "    if (/^git /.test(cmd)) return [BIN, ...args];\n" ++
        "    if (/^gh /.test(cmd)) return [BIN, ...args];\n" ++
        "    if (/^cargo /.test(cmd)) return [BIN, ...args];\n" ++
        "    if (/^npm /.test(cmd)) return [BIN, ...args];\n" ++
        "    if (/^pytest/.test(cmd)) return [BIN, 'pytest'];\n" ++
        "    if (/^docker /.test(cmd)) return [BIN, ...args];\n" ++
        "    if (/^kubectl /.test(cmd)) return [BIN, ...args];\n" ++
        "    return args;\n" ++
        "  }\n" ++
        "};\n" ++
        "export default llmlitePlugin;\n";

    {
        const file = try std.Io.Dir.createFileAbsolute(g_io, plugin_path, .{});
        defer file.close(g_io);
        try file.writeStreamingAll(g_io, plugin_content);
    }

    if (verbose) {
        std.debug.print("Created: {s}\n", .{plugin_path});
    }
}

pub fn installWindsurfHook(allocator: std.mem.Allocator, verbose: bool) !void {
    const rules_path = try getWindsurfRulesPath(allocator);
    defer allocator.free(rules_path);

    // Windsurf uses .windsurfrules to instruct the AI to prefix commands
    const content =
        "// llmlite-cmd Windsurf integration\n" ++
        "// Prefix all shell commands with llmlite-cmd for token savings\n" ++
        "\n" ++
        "Whenever you run a shell command, prefix it with 'llmlite-cmd' to reduce token usage.\n" ++
        "For example: 'git status' becomes 'llmlite-cmd git status'\n" ++
        "\n" ++
        "Supported commands: git, cargo, npm, pytest, docker, kubectl, go, lint\n";

    {
        const file = try std.Io.Dir.createFileAbsolute(g_io, rules_path, .{});
        defer file.close(g_io);
        try file.writeStreamingAll(g_io, content);
    }

    if (verbose) {
        std.debug.print("Created: {s}\n", .{rules_path});
    }
}

pub fn installClineHook(allocator: std.mem.Allocator, verbose: bool) !void {
    const rules_path = try getClineRulesPath(allocator);
    defer allocator.free(rules_path);

    // Cline uses .clinerules to instruct the AI to prefix commands
    const content =
        "// llmlite-cmd Cline integration\n" ++
        "// Prefix all shell commands with llmlite-cmd for token savings\n" ++
        "\n" ++
        "Whenever you run a shell command, prefix it with 'llmlite-cmd' to reduce token usage.\n" ++
        "For example: 'git status' becomes 'llmlite-cmd git status'\n" ++
        "\n" ++
        "Supported commands: git, cargo, npm, pytest, docker, kubectl, go, lint\n";

    {
        const file = try std.Io.Dir.createFileAbsolute(g_io, rules_path, .{});
        defer file.close(g_io);
        try file.writeStreamingAll(g_io, content);
    }

    if (verbose) {
        std.debug.print("Created: {s}\n", .{rules_path});
    }
}

pub fn installCodexHook(allocator: std.mem.Allocator, verbose: bool) !void {
    const rules_path = try getCodexRulesPath(allocator);
    defer allocator.free(rules_path);

    // Codex uses .codexrules to instruct the AI to prefix commands
    const content =
        "// llmlite-cmd Codex integration\n" ++
        "// Prefix all shell commands with llmlite-cmd for token savings\n" ++
        "\n" ++
        "Whenever you run a shell command, prefix it with 'llmlite-cmd' to reduce token usage.\n" ++
        "For example: 'git status' becomes 'llmlite-cmd git status'\n" ++
        "\n" ++
        "Supported commands: git, cargo, npm, pytest, docker, kubectl, go, lint, prisma, next\n";

    {
        const file = try std.Io.Dir.createFileAbsolute(g_io, rules_path, .{});
        defer file.close(g_io);
        try file.writeStreamingAll(g_io, content);
    }

    if (verbose) {
        std.debug.print("Created: {s}\n", .{rules_path});
    }
}

fn getCopilotInstructionsPath(allocator: std.mem.Allocator) ![]u8 {
    const home = try getHomeDir(allocator);
    return std.fmt.allocPrint(allocator, "{s}/.github/copilot-instructions.md", .{home});
}

fn getOpenClawRulesPath(allocator: std.mem.Allocator) ![]u8 {
    const home = try getHomeDir(allocator);
    return std.fmt.allocPrint(allocator, "{s}/.openclaw/rules.md", .{home});
}

pub fn installCopilotHook(allocator: std.mem.Allocator, verbose: bool) !void {
    // Create .github directory if it doesn't exist
    const home = try getHomeDir(allocator);
    defer allocator.free(home);
    const github_dir = try std.fmt.allocPrint(allocator, "{s}/.github", .{home});
    defer allocator.free(github_dir);
    try std.Io.Dir.createDirAbsolute(g_io, github_dir, .default_dir);

    const hooks_dir = try std.fmt.allocPrint(allocator, "{s}/.github/hooks", .{home});
    defer allocator.free(hooks_dir);
    try std.Io.Dir.createDirAbsolute(g_io, hooks_dir, .default_dir);

    // Write copilot-instructions.md
    const instructions_path = try getCopilotInstructionsPath(allocator);
    defer allocator.free(instructions_path);

    const instructions =
        \\# llmlite-cmd — Token-Optimized CLI
        \\
        \\**llmlite-cmd** is a CLI proxy that filters and compresses command outputs, saving 60-90% tokens.
        \\
        \\## Rule
        \\
        \\Always prefix shell commands with `llmlite-cmd`:
        \\
        \\```bash
        \\# Instead of:              Use:
        \\git status                 llmlite-cmd git status
        \\git log -10                llmlite-cmd git log -10
        \\cargo test                 llmlite-cmd cargo test
        \\docker ps                  llmlite-cmd docker ps
        \\kubectl get pods           llmlite-cmd kubectl get
        \\```
        \\
        \\## Meta commands (use directly)
        \\
        \\```bash
        \\llmlite-cmd gain              # Token savings dashboard
        \\llmlite-cmd discover          # Find missed opportunities
        \\llmlite-cmd proxy <cmd>       # Run raw but track usage
        \\```
    ;

    {
        const file = try std.Io.Dir.createFileAbsolute(g_io, instructions_path, .{});
        defer file.close(g_io);
        try file.writeStreamingAll(g_io, instructions);
    }

    if (verbose) {
        std.debug.print("Created: {s}\n", .{instructions_path});
    }

    std.debug.print("\nGitHub Copilot integration installed.\n", .{});
    std.debug.print("Works with VS Code Copilot Chat and Copilot CLI.\n", .{});
}

pub fn installOpenClawHook(allocator: std.mem.Allocator, verbose: bool) !void {
    // OpenClaw uses a rules.md file in ~/.openclaw/
    const home = try getHomeDir(allocator);
    defer allocator.free(home);
    const openclaw_dir = try std.fmt.allocPrint(allocator, "{s}/.openclaw", .{home});
    defer allocator.free(openclaw_dir);
    try std.Io.Dir.createDirAbsolute(g_io, openclaw_dir, .default_dir);

    const rules_path = try getOpenClawRulesPath(allocator);
    defer allocator.free(rules_path);

    const content =
        "\\# llmlite-cmd OpenClaw Integration\n" ++
        "\\n" ++
        "Prefix all shell commands with `llmlite-cmd` for token savings.\n" ++
        "\\n" ++
        "## Supported Commands\n" ++
        "\\n" ++
        "git, cargo, npm, pytest, docker, kubectl, go, lint, prisma, next\n";

    {
        const file = try std.Io.Dir.createFileAbsolute(g_io, rules_path, .{});
        defer file.close(g_io);
        try file.writeStreamingAll(g_io, content);
    }

    if (verbose) {
        std.debug.print("Created: {s}\n", .{rules_path});
    }

    std.debug.print("\nOpenClaw integration installed.\n", .{});
}

pub fn installKiroHook(allocator: std.mem.Allocator, verbose: bool) !void {
    // Kiro uses ~/.kiro/hooks/ for hook scripts (similar to Claude Code)
    const hooks_dir = try getKiroHooksDir(allocator);
    defer allocator.free(hooks_dir);

    try std.Io.Dir.createDirAbsolute(g_io, hooks_dir, .default_dir);

    const hook_path = try std.fmt.allocPrint(allocator, "{s}/llmlite-rewrite.bash", .{hooks_dir});
    defer allocator.free(hook_path);

    var content = std.array_list.Managed(u8).init(allocator);
    defer content.deinit();

    try content.print(
        "#!/bin/bash\n" ++
            "# llmlite Kiro Hook (rules-engine powered)\n" ++
            "# Auto-syncs with llmlite-cmd rule definitions\n" ++
            "LLMLITE_BIN=\"llmlite-cmd\"\n" ++
            "rewrite_command() {{\n" ++
            "    local cmd=\"$1\"\n" ++
            "    local rewritten=$(\"${{LLMLITE_BIN}}\" rewrite \"$cmd\" 2>/dev/null)\n" ++
            "    if [ $? -eq 0 ] && [ -n \"$rewritten\" ]; then\n" ++
            "        echo \"$rewritten\"\n" ++
            "    else\n" ++
            "        echo \"$cmd\"\n" ++
            "    fi\n" ++
            "}}\n" ++
            "if [ -n \"$1\" ]; then\n" ++
            "    rewrite_command \"$1\"\n" ++
            "fi\n",
        .{},
    );

    {
        const file = try std.Io.Dir.createFileAbsolute(g_io, hook_path, .{});
        defer file.close(g_io);
        try file.writeStreamingAll(g_io, content.items);
    }

    if (verbose) {
        std.debug.print("Created: {s}\n", .{hook_path});
    }

    // Create settings.json for Kiro hook configuration
    const settings_path = try std.fmt.allocPrint(allocator, "{s}/settings.json", .{hooks_dir});
    defer allocator.free(settings_path);

    const settings_json =
        \\{
        \\  "hooks": {
        \\    "PreToolUse": {
        \\      "bash": {
        \\        "command": "~/.kiro/hooks/llmlite-rewrite.bash"
        \\      }
        \\    }
        \\  }
        \\}
    ;

    {
        const file = try std.Io.Dir.createFileAbsolute(g_io, settings_path, .{});
        defer file.close(g_io);
        try file.writeStreamingAll(g_io, settings_json);
    }

    if (verbose) {
        std.debug.print("Created: {s}\n", .{settings_path});
    }

    std.debug.print("\nKiro integration installed.\n", .{});
    std.debug.print("Restart Kiro CLI to activate the hook.\n", .{});
}

pub fn isHookInstalled(allocator: std.mem.Allocator, tool: HookTool) !bool {
    switch (tool) {
        .claude_code => {
            const hooks_dir = try getClaudeHooksDir(allocator);
            defer allocator.free(hooks_dir);
            const hook_path = try std.fmt.allocPrint(allocator, "{s}/llmlite-rewrite.bash", .{hooks_dir});
            defer allocator.free(hook_path);
            std.Io.Dir.accessAbsolute(g_io, hook_path, .{}) catch return false;
            return true;
        },
        .cursor => {
            const hooks_dir = try getCursorHooksDir(allocator);
            defer allocator.free(hooks_dir);
            const hook_path = try std.fmt.allocPrint(allocator, "{s}/llmlite-rewrite.bash", .{hooks_dir});
            defer allocator.free(hook_path);
            std.Io.Dir.accessAbsolute(g_io, hook_path, .{}) catch return false;
            return true;
        },
        .gemini => {
            const hooks_dir = try getGeminiHooksDir(allocator);
            defer allocator.free(hooks_dir);
            const hook_path = try std.fmt.allocPrint(allocator, "{s}/llmlite-hook-gemini.bash", .{hooks_dir});
            defer allocator.free(hook_path);
            std.Io.Dir.accessAbsolute(g_io, hook_path, .{}) catch return false;
            return true;
        },
        .opencode => {
            const plugins_dir = try getOpenCodePluginsDir(allocator);
            defer allocator.free(plugins_dir);
            const plugin_path = try std.fmt.allocPrint(allocator, "{s}/llmlite-plugin.ts", .{plugins_dir});
            defer allocator.free(plugin_path);
            std.Io.Dir.accessAbsolute(g_io, plugin_path, .{}) catch return false;
            return true;
        },
        .windsurf => {
            const rules_path = try getWindsurfRulesPath(allocator);
            defer allocator.free(rules_path);
            std.Io.Dir.accessAbsolute(g_io, rules_path, .{}) catch return false;
            return true;
        },
        .cline => {
            const rules_path = try getClineRulesPath(allocator);
            defer allocator.free(rules_path);
            std.Io.Dir.accessAbsolute(g_io, rules_path, .{}) catch return false;
            return true;
        },
        .zsh => {
            const hook_path = try getZshHookPath(allocator);
            defer allocator.free(hook_path);
            std.Io.Dir.accessAbsolute(g_io, hook_path, .{}) catch return false;
            return true;
        },
        .fish => {
            const hook_path = try getFishHookPath(allocator);
            defer allocator.free(hook_path);
            std.Io.Dir.accessAbsolute(g_io, hook_path, .{}) catch return false;
            return true;
        },
        .copilot => {
            const instructions_path = try getCopilotInstructionsPath(allocator);
            defer allocator.free(instructions_path);
            std.Io.Dir.accessAbsolute(g_io, instructions_path, .{}) catch return false;
            return true;
        },
        .openclaw => {
            const rules_path = try getOpenClawRulesPath(allocator);
            defer allocator.free(rules_path);
            std.Io.Dir.accessAbsolute(g_io, rules_path, .{}) catch return false;
            return true;
        },
        .codex => {
            const rules_path = try getCodexRulesPath(allocator);
            defer allocator.free(rules_path);
            std.Io.Dir.accessAbsolute(g_io, rules_path, .{}) catch return false;
            return true;
        },
        .kiro => {
            const hooks_dir = try getKiroHooksDir(allocator);
            defer allocator.free(hooks_dir);
            const hook_path = try std.fmt.allocPrint(allocator, "{s}/llmlite-rewrite.bash", .{hooks_dir});
            defer allocator.free(hook_path);
            std.Io.Dir.accessAbsolute(g_io, hook_path, .{}) catch return false;
            return true;
        },
    }
}

pub fn uninstallHook(allocator: std.mem.Allocator, tool: HookTool) !void {
    switch (tool) {
        .claude_code => {
            const hooks_dir = try getClaudeHooksDir(allocator);
            defer allocator.free(hooks_dir);
            const hook_path = try std.fmt.allocPrint(allocator, "{s}/llmlite-rewrite.bash", .{hooks_dir});
            defer allocator.free(hook_path);
            std.Io.Dir.deleteFileAbsolute(g_io, hook_path) catch {};
            const settings_path = try std.fmt.allocPrint(allocator, "{s}/settings.json", .{hooks_dir});
            defer allocator.free(settings_path);
            std.Io.Dir.deleteFileAbsolute(g_io, settings_path) catch {};
        },
        .cursor => {
            const hooks_dir = try getCursorHooksDir(allocator);
            defer allocator.free(hooks_dir);
            const hook_path = try std.fmt.allocPrint(allocator, "{s}/llmlite-rewrite.bash", .{hooks_dir});
            defer allocator.free(hook_path);
            std.Io.Dir.deleteFileAbsolute(g_io, hook_path) catch {};
            const hooks_json_path = try std.fmt.allocPrint(allocator, "{s}/hooks.json", .{hooks_dir});
            defer allocator.free(hooks_json_path);
            std.Io.Dir.deleteFileAbsolute(g_io, hooks_json_path) catch {};
        },
        .gemini => {
            const hooks_dir = try getGeminiHooksDir(allocator);
            defer allocator.free(hooks_dir);
            const hook_path = try std.fmt.allocPrint(allocator, "{s}/llmlite-hook-gemini.bash", .{hooks_dir});
            defer allocator.free(hook_path);
            std.Io.Dir.deleteFileAbsolute(g_io, hook_path) catch {};
        },
        .opencode => {
            const plugins_dir = try getOpenCodePluginsDir(allocator);
            defer allocator.free(plugins_dir);
            const plugin_path = try std.fmt.allocPrint(allocator, "{s}/llmlite-plugin.ts", .{plugins_dir});
            defer allocator.free(plugin_path);
            std.Io.Dir.deleteFileAbsolute(g_io, plugin_path) catch {};
        },
        .windsurf => {
            const rules_path = try getWindsurfRulesPath(allocator);
            defer allocator.free(rules_path);
            std.Io.Dir.deleteFileAbsolute(g_io, rules_path) catch {};
        },
        .cline => {
            const rules_path = try getClineRulesPath(allocator);
            defer allocator.free(rules_path);
            std.Io.Dir.deleteFileAbsolute(g_io, rules_path) catch {};
        },
        .zsh => {
            const hook_path = try getZshHookPath(allocator);
            defer allocator.free(hook_path);
            std.Io.Dir.deleteFileAbsolute(g_io, hook_path) catch {};
        },
        .fish => {
            const hook_path = try getFishHookPath(allocator);
            defer allocator.free(hook_path);
            std.Io.Dir.deleteFileAbsolute(g_io, hook_path) catch {};
        },
        .copilot => {
            const instructions_path = try getCopilotInstructionsPath(allocator);
            defer allocator.free(instructions_path);
            std.Io.Dir.deleteFileAbsolute(g_io, instructions_path) catch {};
        },
        .openclaw => {
            const rules_path = try getOpenClawRulesPath(allocator);
            defer allocator.free(rules_path);
            std.Io.Dir.deleteFileAbsolute(g_io, rules_path) catch {};
        },
        .codex => {
            const rules_path = try getCodexRulesPath(allocator);
            defer allocator.free(rules_path);
            std.Io.Dir.deleteFileAbsolute(g_io, rules_path) catch {};
        },
        .kiro => {
            const hooks_dir = try getKiroHooksDir(allocator);
            defer allocator.free(hooks_dir);
            const hook_path = try std.fmt.allocPrint(allocator, "{s}/llmlite-rewrite.bash", .{hooks_dir});
            defer allocator.free(hook_path);
            std.Io.Dir.deleteFileAbsolute(g_io, hook_path) catch {};
            const settings_path = try std.fmt.allocPrint(allocator, "{s}/settings.json", .{hooks_dir});
            defer allocator.free(settings_path);
            std.Io.Dir.deleteFileAbsolute(g_io, settings_path) catch {};
        },
    }
}

pub fn printInstallStatus(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== llmlite-cmd Installation Status ===\n\n", .{});
    std.debug.print("Binary: installed\n", .{});

    const tools = .{
        .{ .name = "Claude Code", .tool = HookTool.claude_code },
        .{ .name = "Cursor", .tool = HookTool.cursor },
        .{ .name = "Gemini CLI", .tool = HookTool.gemini },
        .{ .name = "OpenCode", .tool = HookTool.opencode },
        .{ .name = "Windsurf", .tool = HookTool.windsurf },
        .{ .name = "Cline", .tool = HookTool.cline },
        .{ .name = "Copilot", .tool = HookTool.copilot },
        .{ .name = "OpenClaw", .tool = HookTool.openclaw },
        .{ .name = "Codex", .tool = HookTool.codex },
        .{ .name = "Zsh", .tool = HookTool.zsh },
        .{ .name = "Fish", .tool = HookTool.fish },
        .{ .name = "Kiro CLI", .tool = HookTool.kiro },
    };

    std.debug.print("Hooks:\n", .{});

    inline for (tools) |t| {
        const installed = isHookInstalled(allocator, t.tool) catch false;
        if (installed) {
            std.debug.print("  {s}: installed\n", .{t.name});
        } else {
            std.debug.print("  {s}: not installed\n", .{t.name});
        }
    }

    std.debug.print("\nRun 'llmlite-cmd hook install --agent <name>' to install.\n", .{});
}
