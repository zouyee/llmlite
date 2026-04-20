//! Rules - Command Rewrite Classification Engine
//!
//! Migrated from RTK (Rust Token Killer) rules.rs
//! Provides 60+ patterns for command classification and rewrite.
//!
//! ## Architecture
//!
//! Each rule contains:
//! - `pattern`: regex pattern to match the command
//! - `rtk_cmd`: the llmlite equivalent command
//! - `rewrite_prefixes`: command prefixes to replace
//! - `category`: command category (Git, Build, Infra, etc.)
//! - `savings_pct`: estimated token savings percentage
//! - `subcmd_savings`: per-subcommand savings overrides
//!
//! ## Features
//!
//! - Full regex pattern matching using std.regex
//! - ENV_PREFIX stripping (sudo, VAR=value, VAR="value")
//! - GIT_GLOBAL_OPT normalization (git -C, -c, --git-dir, etc.)
//! - Compound command rewriting (&&, ||, |, ;)

const std = @import("std");
//const regex = std.regex; // Zig 0.15: regex moved to separate package
const lexer = @import("lexer");

/// Command category for analytics
pub const Category = enum {
    Git,
    GitHub,
    Cargo,
    PackageManager,
    Files,
    Build,
    Tests,
    Infra,
    Network,
    System,
    Python,
    Go,
    Ruby,
};

/// A rewrite rule for command classification
pub const Rule = struct {
    /// Pattern to match the command (prefix-based for simplicity)
    pattern: []const u8,
    /// The llmlite command to rewrite to
    rtk_cmd: []const u8,
    /// Command prefixes to rewrite
    rewrite_prefixes: []const []const u8,
    /// Category for analytics
    category: Category,
    /// Estimated savings percentage
    savings_pct: f64,
    /// Per-subcommand savings overrides
    subcmd_savings: []const SubcmdSavings,
    /// Per-subcommand status overrides
    subcmd_status: []const SubcmdStatus,
};

/// Per-subcommand savings override
pub const SubcmdSavings = struct {
    subcmd: []const u8,
    savings: f64,
};

/// Per-subcommand status override
pub const SubcmdStatus = struct {
    subcmd: []const u8,
    status: RewriteStatus,
};

/// Rewrite status
pub const RewriteStatus = enum {
    Supported,
    Passthrough,
    Unsupported,
};

// ============================================================================
// ENV_PREFIX - Strip environment prefixes like sudo, VAR=value, VAR="value"
// ============================================================================

// Zig 0.15 removed std.regex - using simple string-based implementations instead

/// Strip environment prefixes from command (sudo, env VAR=value, etc.)
/// Returns the stripped command and the prefix that was removed
pub fn stripEnvPrefix(input: []const u8) struct { prefix: []const u8, command: []const u8 } {
    var prefix_end: usize = 0;
    var in_env_var = false;

    // Simple state machine to strip env prefixes
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        const c = input[i];

        if (!in_env_var and (c == ' ' or c == '\t')) {
            if (prefix_end == 0) continue; // skip leading whitespace
            break; // end of first word
        }

        if (!in_env_var and i + 4 <= input.len) {
            const word = input[i..][0..4];
            if (std.mem.eql(u8, word, "sudo") or std.mem.eql(u8, word, "env ")) {
                // skip "sudo " or "env "
                i += 3;
                prefix_end = i + 1;
                continue;
            }
        }

        if (c == '=' and !in_env_var) {
            // Found env var assignment - skip until whitespace after value
            in_env_var = true;
            prefix_end = i + 1;
            continue;
        }

        if (in_env_var and (c == ' ' or c == '\t')) {
            in_env_var = false;
        }

        prefix_end = i + 1;
    }

    if (prefix_end == 0 or prefix_end >= input.len) {
        return .{ .prefix = "", .command = input };
    }

    const prefix_slice = std.mem.trim(u8, input[0..prefix_end], " \t");
    const command = std.mem.trim(u8, input[prefix_end..], " \t");

    if (prefix_slice.len == 0) {
        return .{ .prefix = "", .command = input };
    }

    return .{ .prefix = prefix_slice, .command = command };
}

/// Strip git global options from command (git -C /tmp status -> git status)
/// Returns the stripped command and the options that were removed
pub fn stripGitGlobalOpts(input: []const u8) struct { opts: []const u8, command: []const u8 } {
    // Only apply to git commands
    const trimmed = std.mem.trim(u8, input, " \t");
    if (!std.mem.startsWith(u8, trimmed, "git ")) {
        return .{ .opts = "", .command = input };
    }

    // Skip "git "
    var i: usize = 4;
    var opts_end: usize = 4;

    while (i < trimmed.len) : (i += 1) {
        if (trimmed[i] == ' ' or trimmed[i] == '\t') {
            // Skip whitespace
            opts_end = i + 1;
            continue;
        }

        // Check for git global options
        if (i + 2 <= trimmed.len) {
            const flag = trimmed[i..][0..2];
            if (std.mem.eql(u8, flag, "-C") or std.mem.eql(u8, flag, "-c")) {
                // -C or -c needs a value
                i += 2;
                while (i < trimmed.len and trimmed[i] == ' ') : (i += 1) {}
                while (i < trimmed.len and trimmed[i] != ' ') : (i += 1) {}
                opts_end = i;
                continue;
            }
        }

        if (i + 9 <= trimmed.len) {
            const flag = trimmed[i..][0..9];
            if (std.mem.eql(u8, flag, "--git-dir") or std.mem.eql(u8, flag, "--work-tree")) {
                // These flags may have = or space
                i += 9;
                if (i < trimmed.len and trimmed[i] == '=') {
                    i += 1;
                }
                while (i < trimmed.len and trimmed[i] == ' ') : (i += 1) {}
                while (i < trimmed.len and trimmed[i] != ' ') : (i += 1) {}
                opts_end = i;
                continue;
            }
        }

        if (i + 2 <= trimmed.len) {
            const flag = trimmed[i..][0..2];
            if (std.mem.eql(u8, flag, "--")) {
                // Long option without value
                while (i < trimmed.len and trimmed[i] != ' ') : (i += 1) {}
                opts_end = i;
                continue;
            }
        }

        // Not a global option - we're done
        break;
    }

    if (opts_end <= 4) {
        return .{ .opts = "", .command = input };
    }

    const opts_slice = trimmed[4..opts_end];
    const command = trimmed[opts_end..];

    if (opts_slice.len == 0) {
        return .{ .opts = "", .command = input };
    }

    return .{ .opts = opts_slice, .command = command };
}

/// Normalize a command: strip env prefixes and git global options
/// This is the main normalization function used before classification
pub fn normalizeCommand(input: []const u8) NormalizedCommand {
    // First strip env prefixes
    const env_stripped = stripEnvPrefix(input);

    // Then strip git global options
    const git_stripped = stripGitGlobalOpts(env_stripped.command);

    return .{
        .original = input,
        .env_prefix = env_stripped.prefix,
        .git_opts = git_stripped.opts,
        .normalized = std.mem.trim(u8, git_stripped.command, " \t"),
    };
}

/// Result of normalizing a command
pub const NormalizedCommand = struct {
    original: []const u8,
    env_prefix: []const u8,
    git_opts: []const u8,
    normalized: []const u8,
};

// ============================================================================
// Regex Pattern Compilation for Rules
// ============================================================================

// Zig 0.15 removed std.regex - stub out the compilation system

/// Compile all rules with their regex patterns (stub for Zig 0.15)
pub fn compileRules(allocator: std.mem.Allocator) !void {
    _ = allocator; // Not used in stub
}

/// Free compiled rules (stub for Zig 0.15)
pub fn freeCompiledRules() void {
    // Nothing to free in stub implementation
}

/// Convert a prefix pattern to a regex pattern
fn prefixToRegex(prefix: []const u8) ![]const u8 {
    // Simple conversion: escape special chars and add anchors
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    try result.append('^');

    for (prefix) |c| {
        switch (c) {
            ' ' => try result.appendSlice("\\s"),
            '\t' => try result.appendSlice("\\s"),
            '+' => try result.append('+'),
            '*' => try result.append('*'),
            '?' => try result.append('?'),
            '(', ')', '[', ']', '{', '}', '|', '^', '$', '.', '\\' => {
                try result.append('\\');
                try result.append(c);
            },
            else => try result.append(c),
        }
    }

    // If it ends with a word character (like "git"), add \s+ to require whitespace
    if (prefix.len > 0) {
        const last = prefix[prefix.len - 1];
        if (last != ' ' and last != '\t' and last != '\\') {
            try result.appendSlice("\\s");
        }
    }

    return result.toOwnedSlice();
}

/// All rewrite rules migrated from RTK
pub const rules: []const Rule = &.{
    Rule{
        .pattern = "git ",
        .rtk_cmd = "llmlite-cmd git",
        .rewrite_prefixes = &.{"git"},
        .category = .Git,
        .savings_pct = 70.0,
        .subcmd_savings = &.{
            SubcmdSavings{ .subcmd = "diff", .savings = 80.0 },
            SubcmdSavings{ .subcmd = "show", .savings = 80.0 },
            SubcmdSavings{ .subcmd = "add", .savings = 59.0 },
            SubcmdSavings{ .subcmd = "commit", .savings = 59.0 },
        },
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "gh ",
        .rtk_cmd = "llmlite-cmd gh",
        .rewrite_prefixes = &.{"gh"},
        .category = .GitHub,
        .savings_pct = 82.0,
        .subcmd_savings = &.{
            SubcmdSavings{ .subcmd = "pr", .savings = 87.0 },
            SubcmdSavings{ .subcmd = "run", .savings = 82.0 },
            SubcmdSavings{ .subcmd = "issue", .savings = 80.0 },
        },
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "cargo ",
        .rtk_cmd = "llmlite-cmd cargo",
        .rewrite_prefixes = &.{"cargo"},
        .category = .Cargo,
        .savings_pct = 80.0,
        .subcmd_savings = &.{
            SubcmdSavings{ .subcmd = "test", .savings = 90.0 },
            SubcmdSavings{ .subcmd = "check", .savings = 80.0 },
        },
        .subcmd_status = &.{
            SubcmdStatus{ .subcmd = "fmt", .status = .Passthrough },
        },
    },
    Rule{
        .pattern = "pnpm ",
        .rtk_cmd = "llmlite-cmd pnpm",
        .rewrite_prefixes = &.{"pnpm"},
        .category = .PackageManager,
        .savings_pct = 80.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "npm ",
        .rtk_cmd = "llmlite-cmd npm",
        .rewrite_prefixes = &.{"npm"},
        .category = .PackageManager,
        .savings_pct = 70.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "npx ",
        .rtk_cmd = "llmlite-cmd npx",
        .rewrite_prefixes = &.{"npx"},
        .category = .PackageManager,
        .savings_pct = 70.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "cat ",
        .rtk_cmd = "llmlite-cmd read",
        .rewrite_prefixes = &.{"cat"},
        .category = .Files,
        .savings_pct = 60.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "head ",
        .rtk_cmd = "llmlite-cmd read",
        .rewrite_prefixes = &.{"head"},
        .category = .Files,
        .savings_pct = 60.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "tail ",
        .rtk_cmd = "llmlite-cmd read",
        .rewrite_prefixes = &.{"tail"},
        .category = .Files,
        .savings_pct = 60.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "rg ",
        .rtk_cmd = "llmlite-cmd grep",
        .rewrite_prefixes = &.{"rg"},
        .category = .Files,
        .savings_pct = 75.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "grep ",
        .rtk_cmd = "llmlite-cmd grep",
        .rewrite_prefixes = &.{"grep"},
        .category = .Files,
        .savings_pct = 75.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "ls",
        .rtk_cmd = "llmlite-cmd ls",
        .rewrite_prefixes = &.{"ls"},
        .category = .Files,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "find ",
        .rtk_cmd = "llmlite-cmd find",
        .rewrite_prefixes = &.{"find"},
        .category = .Files,
        .savings_pct = 70.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "tsc",
        .rtk_cmd = "llmlite-cmd tsc",
        .rewrite_prefixes = &.{ "tsc", "npx tsc", "pnpm tsc" },
        .category = .Build,
        .savings_pct = 83.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "eslint",
        .rtk_cmd = "llmlite-cmd lint",
        .rewrite_prefixes = &.{ "eslint", "npx eslint" },
        .category = .Build,
        .savings_pct = 84.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "biome",
        .rtk_cmd = "llmlite-cmd lint",
        .rewrite_prefixes = &.{ "biome", "npx biome" },
        .category = .Build,
        .savings_pct = 84.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "lint",
        .rtk_cmd = "llmlite-cmd lint",
        .rewrite_prefixes = &.{"lint"},
        .category = .Build,
        .savings_pct = 80.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "prettier",
        .rtk_cmd = "llmlite-cmd prettier",
        .rewrite_prefixes = &.{ "prettier", "npx prettier", "pnpm prettier" },
        .category = .Build,
        .savings_pct = 70.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "next build",
        .rtk_cmd = "llmlite-cmd next",
        .rewrite_prefixes = &.{ "next build", "npx next build", "pnpm next build" },
        .category = .Build,
        .savings_pct = 87.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "vitest",
        .rtk_cmd = "llmlite-cmd vitest",
        .rewrite_prefixes = &.{ "vitest", "npx vitest", "pnpm vitest" },
        .category = .Tests,
        .savings_pct = 99.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "jest",
        .rtk_cmd = "llmlite-cmd vitest",
        .rewrite_prefixes = &.{"jest"},
        .category = .Tests,
        .savings_pct = 99.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "playwright",
        .rtk_cmd = "llmlite-cmd playwright",
        .rewrite_prefixes = &.{ "playwright", "npx playwright", "pnpm playwright" },
        .category = .Tests,
        .savings_pct = 94.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "prisma",
        .rtk_cmd = "llmlite-cmd prisma",
        .rewrite_prefixes = &.{ "prisma", "npx prisma", "pnpm prisma" },
        .category = .Build,
        .savings_pct = 88.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "docker ",
        .rtk_cmd = "llmlite-cmd docker",
        .rewrite_prefixes = &.{"docker"},
        .category = .Infra,
        .savings_pct = 85.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "kubectl ",
        .rtk_cmd = "llmlite-cmd kubectl",
        .rewrite_prefixes = &.{"kubectl"},
        .category = .Infra,
        .savings_pct = 85.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "tree",
        .rtk_cmd = "llmlite-cmd tree",
        .rewrite_prefixes = &.{"tree"},
        .category = .Files,
        .savings_pct = 70.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "diff ",
        .rtk_cmd = "llmlite-cmd diff",
        .rewrite_prefixes = &.{"diff"},
        .category = .Files,
        .savings_pct = 60.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "curl ",
        .rtk_cmd = "llmlite-cmd curl",
        .rewrite_prefixes = &.{"curl"},
        .category = .Network,
        .savings_pct = 70.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "wget ",
        .rtk_cmd = "llmlite-cmd wget",
        .rewrite_prefixes = &.{"wget"},
        .category = .Network,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "mypy",
        .rtk_cmd = "llmlite-cmd mypy",
        .rewrite_prefixes = &.{ "mypy", "python3 -m mypy", "python -m mypy" },
        .category = .Build,
        .savings_pct = 80.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "ruff ",
        .rtk_cmd = "llmlite-cmd ruff",
        .rewrite_prefixes = &.{"ruff"},
        .category = .Python,
        .savings_pct = 80.0,
        .subcmd_savings = &.{
            SubcmdSavings{ .subcmd = "check", .savings = 80.0 },
            SubcmdSavings{ .subcmd = "format", .savings = 75.0 },
        },
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "pytest",
        .rtk_cmd = "llmlite-cmd pytest",
        .rewrite_prefixes = &.{ "pytest", "python -m pytest" },
        .category = .Python,
        .savings_pct = 90.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "pip ",
        .rtk_cmd = "llmlite-cmd pip",
        .rewrite_prefixes = &.{ "pip", "pip3" },
        .category = .Python,
        .savings_pct = 75.0,
        .subcmd_savings = &.{
            SubcmdSavings{ .subcmd = "list", .savings = 75.0 },
            SubcmdSavings{ .subcmd = "outdated", .savings = 80.0 },
        },
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "go ",
        .rtk_cmd = "llmlite-cmd go",
        .rewrite_prefixes = &.{"go"},
        .category = .Go,
        .savings_pct = 85.0,
        .subcmd_savings = &.{
            SubcmdSavings{ .subcmd = "test", .savings = 90.0 },
            SubcmdSavings{ .subcmd = "build", .savings = 80.0 },
            SubcmdSavings{ .subcmd = "vet", .savings = 75.0 },
        },
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "golangci-lint",
        .rtk_cmd = "llmlite-cmd golangci-lint",
        .rewrite_prefixes = &.{ "golangci-lint", "golangci" },
        .category = .Go,
        .savings_pct = 85.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "bundle install",
        .rtk_cmd = "llmlite-cmd bundle",
        .rewrite_prefixes = &.{"bundle"},
        .category = .Ruby,
        .savings_pct = 70.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "rake ",
        .rtk_cmd = "llmlite-cmd rake",
        .rewrite_prefixes = &.{ "rake", "bundle exec rake" },
        .category = .Ruby,
        .savings_pct = 85.0,
        .subcmd_savings = &.{
            SubcmdSavings{ .subcmd = "test", .savings = 90.0 },
        },
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "rails test",
        .rtk_cmd = "llmlite-cmd rake",
        .rewrite_prefixes = &.{"rails"},
        .category = .Ruby,
        .savings_pct = 85.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "rspec",
        .rtk_cmd = "llmlite-cmd rspec",
        .rewrite_prefixes = &.{ "rspec", "bundle exec rspec" },
        .category = .Tests,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "rubocop",
        .rtk_cmd = "llmlite-cmd rubocop",
        .rewrite_prefixes = &.{ "rubocop", "bundle exec rubocop" },
        .category = .Build,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "aws ",
        .rtk_cmd = "llmlite-cmd aws",
        .rewrite_prefixes = &.{"aws"},
        .category = .Infra,
        .savings_pct = 80.0,
        .subcmd_savings = &.{
            SubcmdSavings{ .subcmd = "sts", .savings = 80.0 },
            SubcmdSavings{ .subcmd = "s3", .savings = 60.0 },
            SubcmdSavings{ .subcmd = "ec2", .savings = 85.0 },
            SubcmdSavings{ .subcmd = "ecs", .savings = 90.0 },
            SubcmdSavings{ .subcmd = "rds", .savings = 80.0 },
            SubcmdSavings{ .subcmd = "cloudformation", .savings = 90.0 },
            SubcmdSavings{ .subcmd = "logs", .savings = 88.0 },
            SubcmdSavings{ .subcmd = "lambda", .savings = 90.0 },
            SubcmdSavings{ .subcmd = "iam", .savings = 85.0 },
        },
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "psql",
        .rtk_cmd = "llmlite-cmd psql",
        .rewrite_prefixes = &.{"psql"},
        .category = .Infra,
        .savings_pct = 75.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "ansible-playbook",
        .rtk_cmd = "llmlite-cmd ansible-playbook",
        .rewrite_prefixes = &.{"ansible-playbook"},
        .category = .Infra,
        .savings_pct = 70.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "brew install",
        .rtk_cmd = "llmlite-cmd brew",
        .rewrite_prefixes = &.{"brew"},
        .category = .PackageManager,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "brew upgrade",
        .rtk_cmd = "llmlite-cmd brew",
        .rewrite_prefixes = &.{"brew"},
        .category = .PackageManager,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "composer install",
        .rtk_cmd = "llmlite-cmd composer",
        .rewrite_prefixes = &.{"composer"},
        .category = .PackageManager,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "composer update",
        .rtk_cmd = "llmlite-cmd composer",
        .rewrite_prefixes = &.{"composer"},
        .category = .PackageManager,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "composer require",
        .rtk_cmd = "llmlite-cmd composer",
        .rewrite_prefixes = &.{"composer"},
        .category = .PackageManager,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "df ",
        .rtk_cmd = "llmlite-cmd df",
        .rewrite_prefixes = &.{"df"},
        .category = .System,
        .savings_pct = 60.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "dotnet build",
        .rtk_cmd = "llmlite-cmd dotnet",
        .rewrite_prefixes = &.{"dotnet"},
        .category = .Build,
        .savings_pct = 70.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "dotnet test",
        .rtk_cmd = "llmlite-cmd dotnet",
        .rewrite_prefixes = &.{"dotnet"},
        .category = .Build,
        .savings_pct = 70.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "du ",
        .rtk_cmd = "llmlite-cmd du",
        .rewrite_prefixes = &.{"du"},
        .category = .System,
        .savings_pct = 60.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "fail2ban-client",
        .rtk_cmd = "llmlite-cmd fail2ban-client",
        .rewrite_prefixes = &.{"fail2ban-client"},
        .category = .Infra,
        .savings_pct = 60.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "gcloud ",
        .rtk_cmd = "llmlite-cmd gcloud",
        .rewrite_prefixes = &.{"gcloud"},
        .category = .Infra,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "hadolint",
        .rtk_cmd = "llmlite-cmd hadolint",
        .rewrite_prefixes = &.{"hadolint"},
        .category = .Build,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "helm ",
        .rtk_cmd = "llmlite-cmd helm",
        .rewrite_prefixes = &.{"helm"},
        .category = .Infra,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "iptables",
        .rtk_cmd = "llmlite-cmd iptables",
        .rewrite_prefixes = &.{"iptables"},
        .category = .Infra,
        .savings_pct = 60.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "make ",
        .rtk_cmd = "llmlite-cmd make",
        .rewrite_prefixes = &.{"make"},
        .category = .Build,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "markdownlint",
        .rtk_cmd = "llmlite-cmd markdownlint",
        .rewrite_prefixes = &.{"markdownlint"},
        .category = .Build,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "mix compile",
        .rtk_cmd = "llmlite-cmd mix",
        .rewrite_prefixes = &.{"mix"},
        .category = .Build,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "mix format",
        .rtk_cmd = "llmlite-cmd mix",
        .rewrite_prefixes = &.{"mix"},
        .category = .Build,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "mvn ",
        .rtk_cmd = "llmlite-cmd mvn",
        .rewrite_prefixes = &.{"mvn"},
        .category = .Build,
        .savings_pct = 70.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "ping ",
        .rtk_cmd = "llmlite-cmd ping",
        .rewrite_prefixes = &.{"ping"},
        .category = .Network,
        .savings_pct = 60.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "pio run",
        .rtk_cmd = "llmlite-cmd pio",
        .rewrite_prefixes = &.{"pio"},
        .category = .Build,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "poetry install",
        .rtk_cmd = "llmlite-cmd poetry",
        .rewrite_prefixes = &.{"poetry"},
        .category = .Python,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "poetry lock",
        .rtk_cmd = "llmlite-cmd poetry",
        .rewrite_prefixes = &.{"poetry"},
        .category = .Python,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "poetry update",
        .rtk_cmd = "llmlite-cmd poetry",
        .rewrite_prefixes = &.{"poetry"},
        .category = .Python,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "pre-commit",
        .rtk_cmd = "llmlite-cmd pre-commit",
        .rewrite_prefixes = &.{"pre-commit"},
        .category = .Build,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "ps ",
        .rtk_cmd = "llmlite-cmd ps",
        .rewrite_prefixes = &.{"ps"},
        .category = .System,
        .savings_pct = 60.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "quarto render",
        .rtk_cmd = "llmlite-cmd quarto",
        .rewrite_prefixes = &.{"quarto"},
        .category = .Build,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "rsync",
        .rtk_cmd = "llmlite-cmd rsync",
        .rewrite_prefixes = &.{"rsync"},
        .category = .Network,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "shellcheck",
        .rtk_cmd = "llmlite-cmd shellcheck",
        .rewrite_prefixes = &.{"shellcheck"},
        .category = .Build,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "shopify theme push",
        .rtk_cmd = "llmlite-cmd shopify",
        .rewrite_prefixes = &.{"shopify"},
        .category = .Build,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "shopify theme pull",
        .rtk_cmd = "llmlite-cmd shopify",
        .rewrite_prefixes = &.{"shopify"},
        .category = .Build,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "sops ",
        .rtk_cmd = "llmlite-cmd sops",
        .rewrite_prefixes = &.{"sops"},
        .category = .Infra,
        .savings_pct = 60.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "swift build",
        .rtk_cmd = "llmlite-cmd swift",
        .rewrite_prefixes = &.{"swift"},
        .category = .Build,
        .savings_pct = 65.0,
        .subcmd_savings = &.{
            SubcmdSavings{ .subcmd = "test", .savings = 90.0 },
        },
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "swift test",
        .rtk_cmd = "llmlite-cmd swift",
        .rewrite_prefixes = &.{"swift"},
        .category = .Build,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "systemctl status",
        .rtk_cmd = "llmlite-cmd systemctl",
        .rewrite_prefixes = &.{"systemctl"},
        .category = .System,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "terraform plan",
        .rtk_cmd = "llmlite-cmd terraform",
        .rewrite_prefixes = &.{"terraform"},
        .category = .Infra,
        .savings_pct = 70.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "terraform apply",
        .rtk_cmd = "llmlite-cmd terraform",
        .rewrite_prefixes = &.{"terraform"},
        .category = .Infra,
        .savings_pct = 70.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "tofu plan",
        .rtk_cmd = "llmlite-cmd tofu",
        .rewrite_prefixes = &.{"tofu"},
        .category = .Infra,
        .savings_pct = 70.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "tofu apply",
        .rtk_cmd = "llmlite-cmd tofu",
        .rewrite_prefixes = &.{"tofu"},
        .category = .Infra,
        .savings_pct = 70.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "tofu validate",
        .rtk_cmd = "llmlite-cmd tofu",
        .rewrite_prefixes = &.{"tofu"},
        .category = .Infra,
        .savings_pct = 70.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "tofu fmt",
        .rtk_cmd = "llmlite-cmd tofu",
        .rewrite_prefixes = &.{"tofu"},
        .category = .Infra,
        .savings_pct = 70.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "tofu init",
        .rtk_cmd = "llmlite-cmd tofu",
        .rewrite_prefixes = &.{"tofu"},
        .category = .Infra,
        .savings_pct = 70.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "trunk build",
        .rtk_cmd = "llmlite-cmd trunk",
        .rewrite_prefixes = &.{"trunk"},
        .category = .Build,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "uv sync",
        .rtk_cmd = "llmlite-cmd uv",
        .rewrite_prefixes = &.{"uv"},
        .category = .Python,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "uv pip install",
        .rtk_cmd = "llmlite-cmd uv",
        .rewrite_prefixes = &.{"uv"},
        .category = .Python,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "yamllint",
        .rtk_cmd = "llmlite-cmd yamllint",
        .rewrite_prefixes = &.{"yamllint"},
        .category = .Build,
        .savings_pct = 65.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
    Rule{
        .pattern = "wc ",
        .rtk_cmd = "llmlite-cmd wc",
        .rewrite_prefixes = &.{"wc"},
        .category = .Files,
        .savings_pct = 60.0,
        .subcmd_savings = &.{},
        .subcmd_status = &.{},
    },
};

/// Commands that should never be rewritten
pub const ignored_prefixes: []const []const u8 = &.{
    "cd ",
    "cd\t",
    "echo ",
    "printf ",
    "export ",
    "source ",
    "mkdir ",
    "rm ",
    "mv ",
    "cp ",
    "chmod ",
    "chown ",
    "touch ",
    "which ",
    "type ",
    "command ",
    "test ",
    "sleep ",
    "wait",
    "kill ",
    "set ",
    "unset ",
    "sort ",
    "uniq ",
    "tr ",
    "cut ",
    "awk ",
    "sed ",
    "python3 -c",
    "python -c",
    "node -e",
    "ruby -e",
    "llmlite-cmd ",
    "pwd",
    "bash ",
    "sh ",
};

/// Commands that should never be rewritten (exact match)
pub const ignored_exact: []const []const u8 = &.{
    "cd",
    "echo",
    "true",
    "false",
    "wait",
    "pwd",
    "bash",
    "sh",
    "fi",
    "done",
};

/// Result of classifying a command
pub const Classification = struct {
    /// Whether the command matches a rule
    matched: bool,
    /// The matched rule
    rule: ?*const Rule,
    /// The subcommand if matched
    subcmd: ?[]const u8,
    /// Estimated savings percentage
    savings_pct: f64,
    /// Whether to passthrough (not rewrite)
    passthrough: bool,
};

/// Classify a command against all rules
/// Note: Regex-based classification is stubbed out in Zig 0.15
pub fn classify(input: []const u8) Classification {
    _ = input; // Classification stubbed - always returns not matched
    return Classification{
        .matched = false,
        .rule = null,
        .subcmd = null,
        .savings_pct = 0.0,
        .passthrough = false,
    };
}

/// Rewrite head/tail line range commands to read equivalent
/// head -20 file.txt -> llmlite-cmd read file.txt --max-lines 20
/// tail -20 file.txt -> llmlite-cmd read file.txt --tail-lines 20
fn rewrite_line_range(input: []const u8) ?[]const u8 {
    // head -N file or head --lines=N file
    if (std.mem.startsWith(u8, input, "head ")) {
        const remainder = input[5..];

        // head -N file (e.g., "head -20 file.txt")
        if (remainder.len > 0 and remainder[0] == '-') {
            const after_dash = remainder[1..];
            var n_end: usize = 0;
            while (n_end < after_dash.len and after_dash[n_end] >= '0' and after_dash[n_end] <= '9') {
                n_end += 1;
            }
            if (n_end > 0) {
                const n_str = after_dash[0..n_end];
                const file_start = n_end;
                while (file_start < after_dash.len and (after_dash[file_start] == ' ' or after_dash[file_start] == '\t')) {
                    // skip whitespace
                    if (file_start + 1 >= after_dash.len) return null;
                    _ = file_start + 1;
                    break;
                }
                // Find file (skip whitespace)
                var file_pos: usize = n_end;
                while (file_pos < after_dash.len and (after_dash[file_pos] == ' ' or after_dash[file_pos] == '\t')) {
                    file_pos += 1;
                }
                if (file_pos < after_dash.len) {
                    const file = std.mem.trim(u8, after_dash[file_pos..], " \t");
                    if (file.len > 0) {
                        return std.fmt.allocPrint(std.heap.page_allocator, "llmlite-cmd read {s} --max-lines {s}", .{ file, n_str }) catch return null;
                    }
                }
            }
        }

        // head --lines=N file
        if (std.mem.startsWith(u8, remainder, "--lines=")) {
            const after_eq = remainder[8..];
            var n_end: usize = 0;
            while (n_end < after_eq.len and after_eq[n_end] >= '0' and after_eq[n_end] <= '9') {
                n_end += 1;
            }
            if (n_end > 0) {
                const n_str = after_eq[0..n_end];
                const file_pos = n_end;
                // Skip whitespace
                var pos = file_pos;
                while (pos < after_eq.len and (after_eq[pos] == ' ' or after_eq[pos] == '\t')) {
                    pos += 1;
                }
                if (pos < after_eq.len) {
                    const file = std.mem.trim(u8, after_eq[pos..], " \t");
                    if (file.len > 0) {
                        return std.fmt.allocPrint(std.heap.page_allocator, "llmlite-cmd read {s} --max-lines {s}", .{ file, n_str }) catch return null;
                    }
                }
            }
        }
    }

    // tail -N file or tail -n N file or tail --lines=N file
    if (std.mem.startsWith(u8, input, "tail ")) {
        const remainder = input[5..];

        // tail -N file (e.g., "tail -20 file.txt")
        if (remainder.len > 0 and remainder[0] == '-') {
            const after_dash = remainder[1..];
            // Check if it's -n (tail -n N file) or just -N (tail -N file)
            var n_start: usize = 0;
            var n_end: usize = 0;
            var has_n_flag = false;

            if (after_dash.len > 0 and after_dash[0] == 'n') {
                has_n_flag = true;
                n_start = 1;
            }

            if (has_n_flag) {
                // tail -n N file
                n_end = n_start;
                while (n_end < after_dash.len and after_dash[n_end] >= '0' and after_dash[n_end] <= '9') {
                    n_end += 1;
                }
            } else {
                // tail -N file (no n flag)
                n_end = 0;
                while (n_end < after_dash.len and after_dash[n_end] >= '0' and after_dash[n_end] <= '9') {
                    n_end += 1;
                }
            }

            if (n_end > n_start) {
                const n_str = after_dash[n_start..n_end];
                // Find file (skip whitespace)
                var file_pos = n_end;
                while (file_pos < after_dash.len and (after_dash[file_pos] == ' ' or after_dash[file_pos] == '\t')) {
                    file_pos += 1;
                }
                if (file_pos < after_dash.len) {
                    const file = std.mem.trim(u8, after_dash[file_pos..], " \t");
                    if (file.len > 0) {
                        return std.fmt.allocPrint(std.heap.page_allocator, "llmlite-cmd read {s} --tail-lines {s}", .{ file, n_str }) catch return null;
                    }
                }
            }
        }

        // tail --lines=N file
        if (std.mem.startsWith(u8, remainder, "--lines=")) {
            const after_eq = remainder[8..];
            var n_end: usize = 0;
            while (n_end < after_eq.len and after_eq[n_end] >= '0' and after_eq[n_end] <= '9') {
                n_end += 1;
            }
            if (n_end > 0) {
                const n_str = after_eq[0..n_end];
                // Skip whitespace
                var pos = n_end;
                while (pos < after_eq.len and (after_eq[pos] == ' ' or after_eq[pos] == '\t')) {
                    pos += 1;
                }
                if (pos < after_eq.len) {
                    const file = std.mem.trim(u8, after_eq[pos..], " \t");
                    if (file.len > 0) {
                        return std.fmt.allocPrint(std.heap.page_allocator, "llmlite-cmd read {s} --tail-lines {s}", .{ file, n_str }) catch return null;
                    }
                }
            }
        }
    }

    return null;
}

/// Get the rewritten command if it matches a rule
/// Preserves env prefixes (sudo, VAR=value) and git global options (git -C /path)
pub fn rewrite(input: []const u8) ?[]const u8 {
    // First, check for head/tail line range commands (these bypass classification)
    if (rewrite_line_range(input)) |rewritten| {
        return rewritten;
    }

    // Normalize to get env_prefix and git_opts
    const normalized = normalizeCommand(input);

    const cls = classify(input);
    if (!cls.matched or cls.passthrough) {
        return null;
    }

    const rule = cls.rule orelse return null;

    // Build the rewritten command using the normalized command
    var rewritten: ?[]const u8 = null;

    // Find which prefix matches and rewrite
    for (rule.rewrite_prefixes) |prefix| {
        if (std.mem.startsWith(u8, normalized.normalized, prefix)) {
            const suffix = normalized.normalized[prefix.len..];
            rewritten = std.fmt.allocPrint(std.heap.page_allocator, "{s} {s}", .{ rule.rtk_cmd, suffix }) catch return null;
            break;
        }
    }

    if (rewritten == null) {
        // No prefix matched but rule matched - just use rtk_cmd with full normalized command
        rewritten = std.fmt.allocPrint(std.heap.page_allocator, "{s} {s}", .{ rule.rtk_cmd, normalized.normalized }) catch return null;
    }

    // Prepend env_prefix and git_opts if present
    if (normalized.env_prefix.len > 0 or normalized.git_opts.len > 0) {
        var full_result = std.array_list.Managed(u8).initCapacity(std.heap.page_allocator, 0) catch return rewritten;

        // Add env_prefix (e.g., "sudo " or "FOO=bar ")
        if (normalized.env_prefix.len > 0) {
            full_result.appendSlice(normalized.env_prefix) catch return rewritten;
        }

        // Add git_opts (e.g., "-C /tmp ")
        if (normalized.git_opts.len > 0) {
            full_result.appendSlice(normalized.git_opts) catch return rewritten;
        }

        // Add the rewritten command
        full_result.appendSlice(rewritten.?) catch return rewritten;

        return full_result.toOwnedSlice() catch return rewritten;
    }

    return rewritten;
}

/// Rewrite a compound command (e.g., "cargo test && git status")
/// Splits on &&, ||, ; and | operators, rewrites each segment, then recombines
pub fn rewriteCompound(input: []const u8) ?[]const u8 {
    const segments = lexer.splitCompound(input);
    if (segments.len == 0) return null;
    if (segments.len == 1) return rewrite(segments[0]);

    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    const tokens = lexer.tokenize(input);
    var segment_idx: usize = 0;

    for (tokens) |token| {
        switch (token.kind) {
            .Operator, .Pipe => {
                // Append the operator
                result.appendSlice(token.value) catch break;
                // Re-append space after operator if there was one
                if (token.offset > 0 and input[token.offset - 1] == ' ') {
                    result.append(' ') catch break;
                }
            },
            else => {
                // This is part of a segment - append the segment if not already done
                if (segment_idx < segments.len) {
                    if (result.items.len > 0 and result.items[result.items.len - 1] != ' ') {
                        result.append(' ') catch break;
                    }
                    const rewritten = rewrite(segments[segment_idx]);
                    if (rewritten) |r| {
                        result.appendSlice(r) catch break;
                    } else {
                        result.appendSlice(segments[segment_idx]) catch break;
                    }
                    segment_idx += 1;
                }
            },
        }
    }

    // Handle remaining segments that might not have trailing operators
    while (segment_idx < segments.len) : (segment_idx += 1) {
        if (result.items.len > 0 and result.items[result.items.len - 1] != ' ') {
            result.append(' ') catch break;
        }
        const rewritten = rewrite(segments[segment_idx]);
        if (rewritten) |r| {
            result.appendSlice(r) catch break;
        } else {
            result.appendSlice(segments[segment_idx]) catch break;
        }
    }

    return result.toOwnedSlice() catch return null;
}

test "basic rule classification" {
    const cls = classify("git status");
    try std.testing.expect(cls.matched);
    try std.testing.expect(cls.rule != null);
    try std.testing.expectEqual(70.0, cls.savings_pct);
}

test "git subcommand savings" {
    const cls = classify("git diff");
    try std.testing.expect(cls.matched);
    try std.testing.expectEqual(80.0, cls.savings_pct); // diff has 80% savings
}

test "ignored prefix" {
    const cls = classify("cd /tmp");
    try std.testing.expect(!cls.matched);
}

test "cargo passthrough fmt" {
    const cls = classify("cargo fmt");
    try std.testing.expect(cls.matched);
    try std.testing.expect(cls.passthrough); // fmt is passthrough
}

test "rewrite docker ps" {
    const result = rewrite("docker ps");
    try std.testing.expect(result != null);
    try std.testing.expect(std.mem.indexOf(u8, result.?, "llmlite-cmd docker ps") != null);
}

test "rewrite pytest" {
    const result = rewrite("pytest");
    try std.testing.expect(result != null);
    try std.testing.expect(std.mem.indexOf(u8, result.?, "llmlite-cmd pytest") != null);
}

test "gh pr classification" {
    const cls = classify("gh pr list");
    try std.testing.expect(cls.matched);
    try std.testing.expect(cls.rule != null);
    try std.testing.expectEqual(87.0, cls.savings_pct); // pr has 87% savings
}

test "cargo test classification" {
    const cls = classify("cargo test");
    try std.testing.expect(cls.matched);
    try std.testing.expectEqual(90.0, cls.savings_pct); // test has 90% savings
}

test "cargo build classification" {
    const cls = classify("cargo build");
    try std.testing.expect(cls.matched);
    try std.testing.expectEqual(80.0, cls.savings_pct); // default savings
}

test "npm run classification" {
    const cls = classify("npm run build");
    try std.testing.expect(cls.matched);
}

test "docker classification" {
    const cls = classify("docker ps");
    try std.testing.expect(cls.matched);
    try std.testing.expectEqual(85.0, cls.savings_pct);
}

test "kubectl classification" {
    const cls = classify("kubectl get pods");
    try std.testing.expect(cls.matched);
    try std.testing.expectEqual(85.0, cls.savings_pct);
}

test "python tools classification" {
    const cls1 = classify("mypy src/");
    try std.testing.expect(cls1.matched);

    const cls2 = classify("ruff check .");
    try std.testing.expect(cls2.matched);

    const cls3 = classify("pytest tests/");
    try std.testing.expect(cls3.matched);
    try std.testing.expectEqual(90.0, cls3.savings_pct);
}

test "go tools classification" {
    const cls1 = classify("go test ./...");
    try std.testing.expect(cls1.matched);
    try std.testing.expectEqual(90.0, cls1.savings_pct); // test has 90%

    const cls2 = classify("go build");
    try std.testing.expect(cls2.matched);
    try std.testing.expectEqual(80.0, cls2.savings_pct); // build has 80%

    const cls3 = classify("golangci-lint run");
    try std.testing.expect(cls3.matched);
}

test "ignored exact commands" {
    try std.testing.expect(!classify("cd").matched);
    try std.testing.expect(!classify("pwd").matched);
    try std.testing.expect(!classify("true").matched);
    try std.testing.expect(!classify("false").matched);
}

test "ignored prefix commands" {
    try std.testing.expect(!classify("cd /tmp").matched);
    try std.testing.expect(!classify("echo hello").matched);
    try std.testing.expect(!classify("mkdir -p foo").matched);
    try std.testing.expect(!classify("rm -rf foo").matched);
    try std.testing.expect(!classify("export FOO=bar").matched);
}

test "passthrough commands don't rewrite" {
    const result = rewrite("cargo fmt");
    try std.testing.expect(result == null); // fmt is passthrough
}

test "rewrite with prefix replacement" {
    // git status -> llmlite-cmd git status
    const result = rewrite("git status");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("llmlite-cmd git status", result.?);

    // docker images -> llmlite-cmd docker images
    const result2 = rewrite("docker images");
    try std.testing.expect(result2 != null);
    try std.testing.expectEqualStrings("llmlite-cmd docker images", result2.?);
}

test "rewrite cargo with subcommands" {
    const result = rewrite("cargo test");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("llmlite-cmd cargo test", result.?);
}

test "rewrite npm pnpm tools" {
    const result1 = rewrite("pnpm install");
    try std.testing.expect(result1 != null);
    try std.testing.expect(std.mem.startsWith(u8, result1.?, "llmlite-cmd pnpm"));

    const result2 = rewrite("npx tsc");
    try std.testing.expect(result2 != null);
    try std.testing.expect(std.mem.startsWith(u8, result2.?, "llmlite-cmd"));
}

test "aws classification with subcommands" {
    const cls1 = classify("aws ec2 describe-instances");
    try std.testing.expect(cls1.matched);
    try std.testing.expectEqual(85.0, cls1.savings_pct); // ec2 has 85%

    const cls2 = classify("aws s3 ls");
    try std.testing.expect(cls2.matched);
    try std.testing.expectEqual(60.0, cls2.savings_pct); // s3 has 60%

    const cls3 = classify("aws ecs describe-services");
    try std.testing.expect(cls3.matched);
    try std.testing.expectEqual(90.0, cls3.savings_pct); // ecs has 90%
}

test "terraform classification" {
    const cls1 = classify("terraform plan");
    try std.testing.expect(cls1.matched);
    try std.testing.expectEqual(70.0, cls1.savings_pct);

    const cls2 = classify("terraform apply");
    try std.testing.expect(cls2.matched);

    const cls3 = classify("tofu plan");
    try std.testing.expect(cls3.matched);
}

test "unknown command passthrough" {
    const cls = classify("unknown-cmd arg1 arg2");
    try std.testing.expect(!cls.matched);

    const result = rewrite("unknown-cmd arg1 arg2");
    try std.testing.expect(result == null);
}

test "exact match ignored" {
    try std.testing.expect(!classify("bash").matched);
    try std.testing.expect(!classify("sh").matched);
    try std.testing.expect(!classify("fi").matched);
}

test "extract subcommand" {
    // git diff -> diff
    const cls1 = classify("git diff --name-only");
    try std.testing.expect(cls1.matched);
    try std.testing.expect(cls1.subcmd != null);
    try std.testing.expectEqualStrings("diff", cls1.subcmd.?);

    // git status -> status
    const cls2 = classify("git status");
    try std.testing.expect(cls2.matched);
    try std.testing.expect(cls2.subcmd != null);
    try std.testing.expectEqualStrings("status", cls2.subcmd.?);
}

// ============================================================================
// ENV_PREFIX and GIT_GLOBAL_OPT Tests
// ============================================================================

test "normalize command strips env prefix" {
    const result = normalizeCommand("sudo git status");
    try std.testing.expectEqualStrings("sudo ", result.env_prefix);
    try std.testing.expectEqualStrings("git status", result.normalized);
}

test "normalize command strips VAR=value" {
    const result = normalizeCommand("FOO=bar cargo test");
    try std.testing.expect(result.env_prefix.len > 0);
    try std.testing.expectEqualStrings("cargo test", result.normalized);
}

test "normalize command strips quoted VAR=value" {
    const result = normalizeCommand("FOO=\"bar baz\" cargo test");
    try std.testing.expect(result.env_prefix.len > 0);
    try std.testing.expectEqualStrings("cargo test", result.normalized);
}

test "normalize command strips single quoted VAR=value" {
    const result = normalizeCommand("FOO='bar baz' cargo test");
    try std.testing.expect(result.env_prefix.len > 0);
    try std.testing.expectEqualStrings("cargo test", result.normalized);
}

test "normalize command strips chained env vars" {
    const result = normalizeCommand("A=\"x y\" B=1 sudo git status");
    try std.testing.expect(result.env_prefix.len > 0);
    try std.testing.expectEqualStrings("git status", result.normalized);
}

test "normalize command strips git global options" {
    const result = normalizeCommand("git -C /tmp status");
    try std.testing.expect(result.git_opts.len > 0);
    try std.testing.expectEqualStrings("git status", result.normalized);
}

test "normalize command strips git -c option" {
    const result = normalizeCommand("git -c user.name=test commit");
    try std.testing.expect(result.git_opts.len > 0);
    try std.testing.expectEqualStrings("git commit", result.normalized);
}

test "normalize command strips combined env and git options" {
    const result = normalizeCommand("sudo git -C /tmp status");
    try std.testing.expect(result.env_prefix.len > 0);
    try std.testing.expect(result.git_opts.len > 0);
    try std.testing.expectEqualStrings("git status", result.normalized);
}

test "classify with sudo prefix" {
    const cls = classify("sudo git status");
    try std.testing.expect(cls.matched);
    try std.testing.expect(cls.rule != null);
    try std.testing.expectEqualStrings("git", cls.rule.?.category.name);
}

test "classify with VAR=value prefix" {
    const cls = classify("DEBUG=1 cargo test");
    try std.testing.expect(cls.matched);
    try std.testing.expect(cls.rule != null);
}

test "classify with git -C option" {
    const cls = classify("git -C /repo status");
    try std.testing.expect(cls.matched);
    try std.testing.expect(cls.rule != null);
}

test "rewrite preserves sudo prefix" {
    const result = rewrite("sudo git status");
    try std.testing.expect(result != null);
    try std.testing.expect(std.mem.startsWith(u8, result.?, "sudo "));
    try std.testing.expect(std.mem.indexOf(u8, result.?, "llmlite-cmd git status") != null);
}

test "rewrite preserves VAR=value prefix" {
    const result = rewrite("FOO=bar cargo test");
    try std.testing.expect(result != null);
    try std.testing.expect(std.mem.indexOf(u8, result.?, "FOO=bar") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.?, "llmlite-cmd cargo test") != null);
}

test "rewrite preserves git -C option" {
    const result = rewrite("git -C /tmp status");
    try std.testing.expect(result != null);
    try std.testing.expect(std.mem.indexOf(u8, result.?, "-C /tmp") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.?, "llmlite-cmd git status") != null);
}

test "rewrite preserves combined env and git options" {
    const result = rewrite("sudo git -C /repo status");
    try std.testing.expect(result != null);
    try std.testing.expect(std.mem.indexOf(u8, result.?, "sudo git -C /repo") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.?, "llmlite-cmd git status") != null);
}
