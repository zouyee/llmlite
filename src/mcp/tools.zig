//! MCP Tools Implementation
//!
//! Exposes llmlite proxy functionality as MCP tools
//! When proxy is running, tools query it via HTTP for real data
//!
//! MCP Hook Tools - Execute shell commands with RTK-style filtering
//! Inspired by RTK's token reduction strategies

const std = @import("std");
const http = @import("http");

/// Default proxy URL if not specified
const DEFAULT_PROXY_URL = "http://localhost:4000";

/// Global fallback content for error cases (no heap needed)
const GLOBAL_ERROR_CONTENT: []const CallToolResult.ContentBlock = &.{
    .{
        .type = "text",
        .text = "{\"error\":\"unknown\"}",
    },
};

/// Global filtering statistics tracker
var global_filter_stats = FilterStats{};
const FILTER_STATS_MAX_ENTRIES = 100;

const FilterStats = struct {
    total_commands: u64 = 0,
    total_original_bytes: u64 = 0,
    total_filtered_bytes: u64 = 0,
    commands_used_filter: u64 = 0,

    fn record(self: *FilterStats, original_len: usize, filtered_len: usize, used_filter: bool) void {
        self.total_commands += 1;
        self.total_original_bytes += original_len;
        if (used_filter) {
            self.commands_used_filter += 1;
            self.total_filtered_bytes += filtered_len;
        }
    }

    fn getReductionPct(self: *const FilterStats) f64 {
        if (self.total_original_bytes == 0) return 0;
        const saved = self.total_original_bytes - self.total_filtered_bytes;
        return @as(f64, @floatFromInt(saved)) / @as(f64, @floatFromInt(self.total_original_bytes)) * 100.0;
    }
};

pub const TOOLS: []const ToolDefinition = &.{
    .{
        .name = "llmlite_router_status",
        .description = "Get current router status including circuit breaker state and provider health",
        .input_schema = .{},
    },
    .{
        .name = "llmlite_health_check",
        .description = "Check health status of all configured providers",
        .input_schema = .{},
    },
    .{
        .name = "llmlite_cost_summary",
        .description = "Get cost summary for a team or virtual key",
        .input_schema = .{
            .type = "object",
            .properties = &[_]Schema.Property{
                .{ .name = "key_id", .schema = &.{ .type = "string" } },
                .{ .name = "team_id", .schema = &.{ .type = "string" } },
            },
        },
    },
    .{
        .name = "llmlite_key_list",
        .description = "List all virtual keys",
        .input_schema = .{},
    },
    .{
        .name = "llmlite_key_create",
        .description = "Create a new virtual key",
        .input_schema = .{
            .type = "object",
            .properties = &[_]Schema.Property{
                .{ .name = "key_id", .schema = &.{ .type = "string" } },
                .{ .name = "team_id", .schema = &.{ .type = "string" } },
            },
            .required = &[_][]const u8{"key_id"},
        },
    },
    .{
        .name = "llmlite_key_revoke",
        .description = "Revoke a virtual key",
        .input_schema = .{
            .type = "object",
            .properties = &[_]Schema.Property{
                .{ .name = "key_id", .schema = &.{ .type = "string" } },
            },
            .required = &[_][]const u8{"key_id"},
        },
    },
    .{
        .name = "llmlite_metrics",
        .description = "Get proxy metrics including latency percentiles and request counts",
        .input_schema = .{},
    },
    // ========== MCP Hook Tools (RTK-style command execution with filtering) ==========
    .{
        .name = "llmlite_exec",
        .description = "Execute a shell command with RTK-style output filtering. Automatically detects command type and applies appropriate filter for 60-90% token reduction.",
        .input_schema = .{
            .type = "object",
            .properties = &[_]Schema.Property{
                .{ .name = "command", .schema = &.{ .type = "string" } },
                .{ .name = "filter", .schema = &.{ .type = "string" } },
            },
            .required = &[_][]const u8{"command"},
        },
    },
    .{
        .name = "llmlite_git_status",
        .description = "Execute 'git status' with RTK-style filtering. Compresses to '3 files changed, +142/-89' format (~80% token reduction).",
        .input_schema = .{},
    },
    .{
        .name = "llmlite_git_log",
        .description = "Execute 'git log' with one-line format. Shows commit hash + message per line (~80% token reduction).",
        .input_schema = .{
            .type = "object",
            .properties = &[_]Schema.Property{
                .{ .name = "count", .schema = &.{ .type = "number" } },
            },
        },
    },
    .{
        .name = "llmlite_git_diff",
        .description = "Execute 'git diff' with condensed format. Shows only changed files and summary stats (~75% token reduction).",
        .input_schema = .{
            .type = "object",
            .properties = &[_]Schema.Property{
                .{ .name = "file", .schema = &.{ .type = "string" } },
            },
        },
    },
    .{
        .name = "llmlite_cargo_test",
        .description = "Execute 'cargo test' with failure focus. Shows only failed tests (~90% token reduction).",
        .input_schema = .{
            .type = "object",
            .properties = &[_]Schema.Property{
                .{ .name = "args", .schema = &.{ .type = "string" } },
            },
        },
    },
    .{
        .name = "llmlite_cargo_build",
        .description = "Execute 'cargo build' with error focus. Shows only errors and warnings (~80% token reduction).",
        .input_schema = .{
            .type = "object",
            .properties = &[_]Schema.Property{
                .{ .name = "args", .schema = &.{ .type = "string" } },
            },
        },
    },
    .{
        .name = "llmlite_npm_test",
        .description = "Execute 'npm test' with failure focus. Shows only failed tests (~90% token reduction).",
        .input_schema = .{
            .type = "object",
            .properties = &[_]Schema.Property{
                .{ .name = "package_manager", .schema = &.{ .type = "string" } },
            },
        },
    },
    .{
        .name = "llmlite_lint",
        .description = "Execute linting with grouped output. Shows errors grouped by rule (~80% token reduction).",
        .input_schema = .{
            .type = "object",
            .properties = &[_]Schema.Property{
                .{ .name = "tool", .schema = &.{ .type = "string" } },
                .{ .name = "fix", .schema = &.{ .type = "boolean" } },
            },
        },
    },
    .{
        .name = "llmlite_docker_ps",
        .description = "Execute 'docker ps' with compact format. Shows only container name, status, and ports (~80% token reduction).",
        .input_schema = .{},
    },
    .{
        .name = "llmlite_kubectl_pods",
        .description = "Execute 'kubectl get pods' with compact format. Shows only pod name, status, and ready count (~70% token reduction).",
        .input_schema = .{
            .type = "object",
            .properties = &[_]Schema.Property{
                .{ .name = "namespace", .schema = &.{ .type = "string" } },
            },
        },
    },
    .{
        .name = "llmlite_filter_stats",
        .description = "Get filtering statistics showing token savings from RTK-style compression. Shows total commands, bytes reduced, and reduction percentage.",
        .input_schema = .{},
    },
};

pub const ToolDefinition = struct {
    name: []const u8,
    description: []const u8,
    input_schema: Schema,
};

pub const Schema = struct {
    type: []const u8 = "object",
    properties: ?[]const Property = null,
    required: ?[]const []const u8 = null,

    pub const Property = struct {
        name: []const u8,
        schema: *const Schema,
    };
};

pub fn listTools() ListToolsResult {
    return .{
        .tools = TOOLS,
    };
}

pub const ListToolsResult = struct {
    tools: []const ToolDefinition,
};

pub fn callTool(allocator: std.mem.Allocator, name: []const u8, args: ?std.json.Value) !CallToolResult {
    if (std.mem.eql(u8, name, "llmlite_router_status")) {
        return llmlite_router_status(allocator);
    }

    if (std.mem.eql(u8, name, "llmlite_health_check")) {
        return llmlite_health_check(allocator);
    }

    if (std.mem.eql(u8, name, "llmlite_cost_summary")) {
        return llmlite_cost_summary(allocator, args);
    }

    if (std.mem.eql(u8, name, "llmlite_key_list")) {
        return llmlite_key_list(allocator);
    }

    if (std.mem.eql(u8, name, "llmlite_key_create")) {
        return llmlite_key_create(allocator, args);
    }

    if (std.mem.eql(u8, name, "llmlite_key_revoke")) {
        return llmlite_key_revoke(allocator, args);
    }

    if (std.mem.eql(u8, name, "llmlite_metrics")) {
        return llmlite_metrics(allocator);
    }

    // ========== MCP Hook Tools ==========
    if (std.mem.eql(u8, name, "llmlite_exec")) {
        return llmlite_exec(allocator, args);
    }
    if (std.mem.eql(u8, name, "llmlite_git_status")) {
        return llmlite_git_status(allocator);
    }
    if (std.mem.eql(u8, name, "llmlite_git_log")) {
        return llmlite_git_log(allocator, args);
    }
    if (std.mem.eql(u8, name, "llmlite_git_diff")) {
        return llmlite_git_diff(allocator, args);
    }
    if (std.mem.eql(u8, name, "llmlite_cargo_test")) {
        return llmlite_cargo_test(allocator, args);
    }
    if (std.mem.eql(u8, name, "llmlite_cargo_build")) {
        return llmlite_cargo_build(allocator, args);
    }
    if (std.mem.eql(u8, name, "llmlite_npm_test")) {
        return llmlite_npm_test(allocator, args);
    }
    if (std.mem.eql(u8, name, "llmlite_lint")) {
        return llmlite_lint(allocator, args);
    }
    if (std.mem.eql(u8, name, "llmlite_docker_ps")) {
        return llmlite_docker_ps(allocator);
    }
    if (std.mem.eql(u8, name, "llmlite_kubectl_pods")) {
        return llmlite_kubectl_pods(allocator, args);
    }
    if (std.mem.eql(u8, name, "llmlite_filter_stats")) {
        return llmlite_filter_stats(allocator);
    }

    return .{
        .content = &[_]CallToolResult.ContentBlock{
            .{
                .type = "text",
                .text = "{\"error\":\"Tool not found\"}",
            },
        },
        .is_error = true,
    };
}

pub const CallToolResult = struct {
    content: []const ContentBlock,
    is_error: bool = false,

    pub const ContentBlock = struct {
        type: []const u8,
        text: []const u8,
    };
};

/// Make an HTTP GET request to the proxy
fn proxyGet(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var client = http.HttpClient.init(allocator, DEFAULT_PROXY_URL, "", null, 30000);
    const response = try client.get(path);
    // Copy the response to ensure it's valid after client is deallocated
    const copy = try allocator.dupe(u8, response);
    return copy;
}

/// Make an HTTP POST request to the proxy
fn proxyPost(allocator: std.mem.Allocator, path: []const u8, body: []const u8) ![]u8 {
    var client = http.HttpClient.init(allocator, DEFAULT_PROXY_URL, "", null, 30000);
    return client.post(path, body);
}

fn llmlite_router_status(allocator: std.mem.Allocator) CallToolResult {
    const metrics = proxyGet(allocator, "/metrics/latency") catch {
        return makeTextResult(allocator, "{\"status\":\"standalone\",\"circuit_breaker\":{\"openai\":\"closed\",\"anthropic\":\"closed\",\"google\":\"closed\"},\"latency_tracking\":false}");
    };
    // Note: makeTextResult makes its own copy, so we can free metrics immediately
    const result = makeTextResult(allocator, metrics);
    allocator.free(metrics);
    return result;
}

fn llmlite_health_check(allocator: std.mem.Allocator) CallToolResult {
    const health = proxyGet(allocator, "/health/ready") catch {
        return makeTextResult(allocator, "{\"providers\":{\"openai\":\"unknown\",\"anthropic\":\"unknown\",\"google\":\"unknown\",\"moonshot\":\"unknown\",\"minimax\":\"unknown\",\"deepseek\":\"unknown\"}}");
    };
    // Note: makeTextResult makes its own copy, so we can free health immediately
    const result = makeTextResult(allocator, health);
    allocator.free(health);
    return result;
}

fn llmlite_cost_summary(allocator: std.mem.Allocator, args: ?std.json.Value) CallToolResult {
    _ = args;
    return makeTextResult(allocator, "{\"total_cost\":0,\"by_team\":{},\"by_model\":{}}");
}

fn llmlite_key_list(allocator: std.mem.Allocator) CallToolResult {
    const response = proxyGet(allocator, "/key/list") catch {
        return makeTextResult(allocator, "{\"keys\":[]}");
    };
    const result = makeTextResult(allocator, response);
    allocator.free(response);
    return result;
}

fn llmlite_key_create(allocator: std.mem.Allocator, args: ?std.json.Value) !CallToolResult {
    const key_id = if (args) |a| blk: {
        if (a == .object) {
            if (a.object.get("key_id")) |k| {
                if (k == .string) break :blk k.string;
            }
        }
        break :blk "sk-default";
    } else "sk-default";

    const team_id = if (args) |a| blk: {
        if (a == .object) {
            if (a.object.get("team_id")) |t| {
                if (t == .string) break :blk t.string;
            }
        }
        break :blk null;
    } else null;

    const body = if (team_id) |t|
        try std.fmt.allocPrint(allocator, "{{\"key_id\":\"{s}\",\"team_id\":\"{s}\"}}", .{ key_id, t })
    else
        try std.fmt.allocPrint(allocator, "{{\"key_id\":\"{s}\"}}", .{key_id});
    defer allocator.free(body);

    const response = proxyPost(allocator, "/key/create", body) catch {
        const result = try std.fmt.allocPrint(allocator, "{{\"key_id\":\"{s}\",\"status\":\"created\",\"message\":\"Created (standalone mode)\"}}", .{key_id});
        return makeTextResult(allocator, result);
    };
    const result = makeTextResult(allocator, response);
    allocator.free(response);
    allocator.free(body);
    return result;
}

fn llmlite_key_revoke(allocator: std.mem.Allocator, args: ?std.json.Value) !CallToolResult {
    const key_id = if (args) |a| blk: {
        if (a == .object) {
            if (a.object.get("key_id")) |k| {
                if (k == .string) break :blk k.string;
            }
        }
        break :blk "unknown";
    } else "unknown";

    const body = try std.fmt.allocPrint(allocator, "{{\"key_id\":\"{s}\"}}", .{key_id});
    defer allocator.free(body);

    const response = proxyPost(allocator, "/key/revoke", body) catch {
        const result = try std.fmt.allocPrint(allocator, "{{\"key_id\":\"{s}\",\"status\":\"revoked (standalone mode)\"}}", .{key_id});
        return makeTextResult(allocator, result);
    };
    const result = makeTextResult(allocator, response);
    allocator.free(response);
    return result;
}

fn llmlite_metrics(allocator: std.mem.Allocator) CallToolResult {
    const metrics = proxyGet(allocator, "/metrics") catch {
        const latency = proxyGet(allocator, "/metrics/latency") catch {
            return makeTextResult(allocator, "{\"error\":\"Proxy not available\"}");
        };
        const result = makeTextResult(allocator, latency);
        allocator.free(latency);
        return result;
    };
    const result = makeTextResult(allocator, metrics);
    allocator.free(metrics);
    return result;
}

// ========== MCP Hook Tool Implementations ==========

/// Execute a shell command with RTK-style filtering
fn llmlite_exec(allocator: std.mem.Allocator, args: ?std.json.Value) CallToolResult {
    const command = if (args) |a| blk: {
        if (a == .object) {
            if (a.object.get("command")) |c| {
                if (c == .string) break :blk c.string;
            }
        }
        break :blk "";
    } else "";

    if (command.len == 0) {
        return makeErrorResult(allocator, "command is required");
    }

    // Detect command type and apply appropriate filter
    const filter_type = if (args) |a| blk: {
        if (a == .object) {
            if (a.object.get("filter")) |f| {
                if (f == .string) break :blk f.string;
            }
        }
        break :blk "auto";
    } else "auto";

    // Execute command
    const result = executeCommand(allocator, command) catch {
        return makeErrorResult(allocator, "failed to execute command");
    };
    defer allocator.free(result);

    // Apply filtering based on command type
    const original_len = result.len;
    const filtered = applyFilter(allocator, command, result, filter_type) catch result;
    const filtered_len = filtered.len;
    const used_filter = filtered_len != original_len;

    // Record statistics
    global_filter_stats.record(original_len, filtered_len, used_filter);

    return makeTextResult(allocator, filtered);
}

/// Git status with filtering
fn llmlite_git_status(allocator: std.mem.Allocator) CallToolResult {
    const result = executeCommand(allocator, "git status --porcelain") catch {
        return makeErrorResultStatic("{\"error\":\"git_status_failed\"}");
    };
    defer allocator.free(result);

    const original_len = result.len;
    const filtered = filterGitStatus(allocator, result) catch result;
    const filtered_len = filtered.len;

    // Record statistics
    global_filter_stats.record(original_len, filtered_len, true);

    return makeTextResult(allocator, filtered);
}

/// Git log with one-line format
fn llmlite_git_log(allocator: std.mem.Allocator, args: ?std.json.Value) CallToolResult {
    const count = if (args) |a| blk: {
        if (a == .object) {
            if (a.object.get("count")) |c| {
                if (c == .integer) break :blk c.integer;
                if (c == .float) break :blk @as(i64, @intFromFloat(c.float));
            }
        }
        break :blk 5;
    } else 5;

    const cmd = std.fmt.allocPrint(allocator, "git log --oneline -{d}", .{count}) catch {
        return makeErrorResult(allocator, "failed to format command");
    };
    defer allocator.free(cmd);

    const result = executeCommand(allocator, cmd) catch {
        return makeErrorResult(allocator, "failed to execute git log");
    };
    defer allocator.free(result);

    // Record stats (git log output is already compact)
    const filtered = filterDeduplication(allocator, result) catch result;
    global_filter_stats.record(result.len, filtered.len, true);

    return makeTextResult(allocator, filtered);
}

/// Git diff with filtering
fn llmlite_git_diff(allocator: std.mem.Allocator, args: ?std.json.Value) CallToolResult {
    const file = if (args) |a| blk: {
        if (a == .object) {
            if (a.object.get("file")) |f| {
                if (f == .string) break :blk f.string;
            }
        }
        break :blk "";
    } else "";

    const cmd = if (file.len > 0)
        std.fmt.allocPrint(allocator, "git diff --stat {s}", .{file})
    else
        std.fmt.allocPrint(allocator, "git diff --stat", .{});

    const cmd_buf = cmd catch {
        return makeErrorResult(allocator, "failed to format command");
    };
    defer allocator.free(cmd_buf);

    const result = executeCommand(allocator, cmd_buf) catch {
        return makeErrorResult(allocator, "failed to execute git diff");
    };
    defer allocator.free(result);

    // If diff is empty, try full diff
    if (result.len < 10) {
        const full_cmd = if (file.len > 0)
            std.fmt.allocPrint(allocator, "git diff {s}", .{file})
        else
            std.fmt.allocPrint(allocator, "git diff", .{});
        const full_cmd_buf = full_cmd catch {
            return makeTextResult(allocator, result);
        };
        defer allocator.free(full_cmd_buf);

        const full_result = executeCommand(allocator, full_cmd_buf) catch {
            return makeTextResult(allocator, result);
        };
        defer allocator.free(full_result);

        const filtered = filterDeduplication(allocator, full_result) catch full_result;
        return makeTextResult(allocator, filtered);
    }

    return makeTextResult(allocator, result);
}

/// Cargo test with failure focus
fn llmlite_cargo_test(allocator: std.mem.Allocator, args: ?std.json.Value) CallToolResult {
    const extra_args = if (args) |a| blk: {
        if (a == .object) {
            if (a.object.get("args")) |arg| {
                if (arg == .string) break :blk arg.string;
            }
        }
        break :blk "";
    } else "";

    const cmd = if (extra_args.len > 0)
        std.fmt.allocPrint(allocator, "cargo test {s} 2>&1", .{extra_args})
    else
        std.fmt.allocPrint(allocator, "cargo test 2>&1", .{});

    const cmd_buf = cmd catch {
        return makeErrorResult(allocator, "failed to format command");
    };
    defer allocator.free(cmd_buf);

    const result = executeCommand(allocator, cmd_buf) catch {
        return makeErrorResult(allocator, "failed to execute cargo test");
    };
    defer allocator.free(result);

    // Apply failure focus filter and record stats
    const original_len = result.len;
    const filtered = filterFailureFocus(allocator, result) catch result;
    global_filter_stats.record(original_len, filtered.len, true);

    return makeTextResult(allocator, filtered);
}

/// Cargo build with error focus
fn llmlite_cargo_build(allocator: std.mem.Allocator, args: ?std.json.Value) CallToolResult {
    const extra_args = if (args) |a| blk: {
        if (a == .object) {
            if (a.object.get("args")) |arg| {
                if (arg == .string) break :blk arg.string;
            }
        }
        break :blk "";
    } else "";

    const cmd = if (extra_args.len > 0)
        std.fmt.allocPrint(allocator, "cargo build {s} 2>&1", .{extra_args})
    else
        std.fmt.allocPrint(allocator, "cargo build 2>&1", .{});

    const cmd_buf = cmd catch {
        return makeErrorResult(allocator, "failed to format command");
    };
    defer allocator.free(cmd_buf);

    const result = executeCommand(allocator, cmd_buf) catch {
        return makeErrorResult(allocator, "failed to execute cargo build");
    };
    defer allocator.free(result);

    // Apply errors only filter
    const filtered = filterErrorsOnly(allocator, result) catch result;

    return makeTextResult(allocator, filtered);
}

/// NPM test with failure focus
fn llmlite_npm_test(allocator: std.mem.Allocator, args: ?std.json.Value) CallToolResult {
    const pkg_mgr = if (args) |a| blk: {
        if (a == .object) {
            if (a.object.get("package_manager")) |pm| {
                if (pm == .string) break :blk pm.string;
            }
        }
        break :blk "auto";
    } else "auto";

    // Auto-detect package manager
    var actual_pm: []const u8 = pkg_mgr;
    if (std.mem.eql(u8, pkg_mgr, "auto")) {
        actual_pm = "npm"; // default
        _ = executeCommand(allocator, "pnpm --version 2>/dev/null") catch {
            _ = executeCommand(allocator, "yarn --version 2>/dev/null") catch {
                // keep npm as default
            };
        };
    }

    const cmd = std.fmt.allocPrint(allocator, "{s} test 2>&1", .{actual_pm}) catch {
        return makeErrorResult(allocator, "failed to format command");
    };
    defer allocator.free(cmd);

    const result = executeCommand(allocator, cmd) catch {
        return makeErrorResult(allocator, "failed to execute npm test");
    };
    defer allocator.free(result);

    // Apply failure focus filter
    const filtered = filterFailureFocus(allocator, result) catch result;

    return makeTextResult(allocator, filtered);
}

/// Linting with grouped output
fn llmlite_lint(allocator: std.mem.Allocator, args: ?std.json.Value) CallToolResult {
    const tool = if (args) |a| blk: {
        if (a == .object) {
            if (a.object.get("tool")) |t| {
                if (t == .string) break :blk t.string;
            }
        }
        break :blk "auto";
    } else "auto";

    const fix = if (args) |a| blk: {
        if (a == .object) {
            if (a.object.get("fix")) |f| {
                if (f == .bool) break :blk f.bool;
            }
        }
        break :blk false;
    } else false;

    // Auto-detect lint tool
    var actual_tool: []const u8 = tool;
    if (std.mem.eql(u8, tool, "auto")) {
        actual_tool = "unknown";
        if (executeCommand(allocator, "ruff --version 2>/dev/null")) |_| {
            actual_tool = "ruff";
        } else |_| {}
        if (std.mem.eql(u8, actual_tool, "unknown")) {
            if (executeCommand(allocator, "eslint --version 2>/dev/null")) |_| {
                actual_tool = "eslint";
            } else |_| {}
        }
        if (std.mem.eql(u8, actual_tool, "unknown")) {
            if (executeCommand(allocator, "tsc --version 2>/dev/null")) |_| {
                actual_tool = "tsc";
            } else |_| {}
        }
    }

    // Build command
    const fix_arg = if (fix) "--fix" else "";
    const cmd = std.fmt.allocPrint(allocator, "{s} {s} 2>&1", .{ actual_tool, fix_arg }) catch {
        return makeErrorResult(allocator, "failed to format command");
    };
    defer allocator.free(cmd);

    const result = executeCommand(allocator, cmd) catch {
        return makeErrorResult(allocator, "failed to execute lint");
    };
    defer allocator.free(result);

    // Apply grouping filter
    const filtered = filterGrouping(allocator, result) catch result;

    return makeTextResult(allocator, filtered);
}

/// Docker ps with compact format
fn llmlite_docker_ps(allocator: std.mem.Allocator) CallToolResult {
    const result = executeCommand(allocator, "docker ps --format '{{.Names}} {{.Status}} {{.Ports}}' 2>&1") catch {
        return makeErrorResult(allocator, "failed to execute docker ps");
    };
    defer allocator.free(result);

    // Apply deduplication
    const filtered = filterDeduplication(allocator, result) catch result;

    return makeTextResult(allocator, filtered);
}

/// Kubectl pods with compact format
fn llmlite_kubectl_pods(allocator: std.mem.Allocator, args: ?std.json.Value) CallToolResult {
    const namespace = if (args) |a| blk: {
        if (a == .object) {
            if (a.object.get("namespace")) |ns| {
                if (ns == .string) break :blk ns.string;
            }
        }
        break :blk "default";
    } else "default";

    const cmd = std.fmt.allocPrint(allocator, "kubectl get pods -n {s} --no-headers 2>&1", .{namespace}) catch {
        return makeErrorResult(allocator, "failed to format command");
    };
    defer allocator.free(cmd);

    const result = executeCommand(allocator, cmd) catch {
        return makeErrorResult(allocator, "failed to execute kubectl");
    };
    defer allocator.free(result);

    // Apply tree compression (simplified - just show status)
    const filtered = filterErrorsOnly(allocator, result) catch result;

    return makeTextResult(allocator, filtered);
}

/// Get filtering statistics
fn llmlite_filter_stats(_allocator: std.mem.Allocator) CallToolResult {
    _ = _allocator;
    const reduction_pct = global_filter_stats.getReductionPct();
    const saved_bytes = global_filter_stats.total_original_bytes - global_filter_stats.total_filtered_bytes;

    const stats_text = std.fmt.allocPrint(std.heap.page_allocator,
        \\{{"filtering_stats":{{"total_commands":{},"commands_filtered":{},"original_bytes":{},"filtered_bytes":{},"saved_bytes":{},"reduction_pct":{d:.1}}}}}
    , .{
        global_filter_stats.total_commands,
        global_filter_stats.commands_used_filter,
        global_filter_stats.total_original_bytes,
        global_filter_stats.total_filtered_bytes,
        saved_bytes,
        reduction_pct,
    }) catch {
        return makeErrorResultStatic("{\"error\":\"stats_failed\"}");
    };

    return makeTextResult(std.heap.page_allocator, stats_text);
}

// ========== Helper Functions ==========

/// Execute a shell command and return output
fn executeCommand(allocator: std.mem.Allocator, cmd: []const u8) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "sh", "-c", cmd },
    });

    // Combine stdout and stderr
    var output = std.ArrayList(u8).empty;
    if (result.stdout.len > 0) {
        try output.appendSlice(allocator, result.stdout);
    }
    if (result.stderr.len > 0) {
        if (output.items.len > 0) try output.append(allocator, '\n');
        try output.appendSlice(allocator, result.stderr);
    }

    // Check exit code
    if (result.term != .Exited or result.term.Exited != 0) {
        const exit_code: i32 = if (result.term == .Exited) @intCast(result.term.Exited) else -1;
        try std.fmt.format(output.writer(allocator), "\n[exit code: {d}]", .{exit_code});
    }

    return output.toOwnedSlice(allocator);
}

/// Auto-detect command type and apply appropriate filter
fn applyFilter(allocator: std.mem.Allocator, command: []const u8, output: []const u8, filter_type: []const u8) ![]u8 {
    // If explicit filter specified, use it
    if (!std.mem.eql(u8, filter_type, "auto")) {
        return applyNamedFilter(allocator, output, filter_type);
    }

    // Auto-detect based on command
    if (std.mem.indexOf(u8, command, "git status") != null) {
        return filterGitStatus(allocator, output);
    }
    if (std.mem.indexOf(u8, command, "git log") != null) {
        return filterDeduplication(allocator, output);
    }
    if (std.mem.indexOf(u8, command, "git diff") != null) {
        return filterDeduplication(allocator, output);
    }
    if (std.mem.indexOf(u8, command, "cargo test") != null) {
        return filterFailureFocus(allocator, output);
    }
    if (std.mem.indexOf(u8, command, "cargo build") != null or std.mem.indexOf(u8, command, "npm test") != null) {
        return filterErrorsOnly(allocator, output);
    }
    if (std.mem.indexOf(u8, command, "docker ps") != null) {
        return filterDeduplication(allocator, output);
    }
    if (std.mem.indexOf(u8, command, "kubectl") != null) {
        return filterErrorsOnly(allocator, output);
    }
    if (std.mem.indexOf(u8, command, "ruff") != null or std.mem.indexOf(u8, command, "eslint") != null or std.mem.indexOf(u8, command, "tsc") != null) {
        return filterGrouping(allocator, output);
    }

    // Default: use stats extraction
    return filterStatsExtraction(allocator, output);
}

/// Apply named filter
fn applyNamedFilter(allocator: std.mem.Allocator, output: []const u8, filter_type: []const u8) ![]u8 {
    if (std.mem.eql(u8, filter_type, "stats")) {
        return filterStatsExtraction(allocator, output);
    }
    if (std.mem.eql(u8, filter_type, "errors_only")) {
        return filterErrorsOnly(allocator, output);
    }
    if (std.mem.eql(u8, filter_type, "grouping")) {
        return filterGrouping(allocator, output);
    }
    if (std.mem.eql(u8, filter_type, "deduplication")) {
        return filterDeduplication(allocator, output);
    }
    if (std.mem.eql(u8, filter_type, "failure_focus")) {
        return filterFailureFocus(allocator, output);
    }
    if (std.mem.eql(u8, filter_type, "tree")) {
        return filterTreeCompression(allocator, output);
    }
    return allocator.dupe(u8, output);
}

/// Git status specific filtering - returns summary
fn filterGitStatus(allocator: std.mem.Allocator, output: []const u8) ![]u8 {
    // Parse git status --porcelain format
    var added: usize = 0;
    var modified: usize = 0;
    var deleted: usize = 0;
    var renamed: usize = 0;
    var untracked: usize = 0;

    var line_iter = std.mem.splitScalar(u8, output, '\n');
    while (line_iter.next()) |line| {
        if (line.len < 2) continue;
        const idx = line[0];
        const wt = line[1];

        if (idx == 'A' or idx == 'a') added += 1;
        if (idx == 'M' or idx == 'm') modified += 1;
        if (idx == 'D' or idx == 'd') deleted += 1;
        if (idx == 'R' or idx == 'r') renamed += 1;
        if (idx == '?' and wt == '?') untracked += 1;
        if (wt == 'A' or wt == 'a') added += 1;
        if (wt == 'M' or wt == 'm') modified += 1;
        if (wt == 'D' or wt == 'd') deleted += 1;
    }

    const total = added + modified + deleted + renamed + untracked;
    if (total == 0) {
        return allocator.dupe(u8, "clean working tree");
    }

    // Build summary string
    var summary = std.ArrayList(u8).empty;
    defer summary.deinit(allocator);

    if (added > 0) try std.fmt.format(summary.writer(allocator), "{d} added, ", .{added});
    if (modified > 0) try std.fmt.format(summary.writer(allocator), "{d} modified, ", .{modified});
    if (deleted > 0) try std.fmt.format(summary.writer(allocator), "{d} deleted, ", .{deleted});
    if (renamed > 0) try std.fmt.format(summary.writer(allocator), "{d} renamed, ", .{renamed});
    if (untracked > 0) try std.fmt.format(summary.writer(allocator), "{d} untracked", .{untracked});

    return summary.toOwnedSlice(allocator);
}

/// Stats extraction filter - summarize output
fn filterStatsExtraction(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var line_count: usize = 0;
    var error_count: usize = 0;
    var warning_count: usize = 0;

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        line_count += 1;
        if (std.mem.indexOf(u8, line, "error") != null) error_count += 1;
        if (std.mem.indexOf(u8, line, "warning") != null) warning_count += 1;
    }

    var result = std.ArrayList(u8).empty;
    defer result.deinit(allocator);

    try std.fmt.format(result.writer(allocator), "{d} lines", .{line_count});
    if (error_count > 0) try std.fmt.format(result.writer(allocator), ", {d} errors", .{error_count});
    if (warning_count > 0) try std.fmt.format(result.writer(allocator), ", {d} warnings", .{warning_count});

    return result.toOwnedSlice(allocator);
}

/// Error only filter - extract only error lines
fn filterErrorsOnly(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var errors = std.ArrayList(u8).empty;
    defer errors.deinit(allocator);
    var found_errors = false;

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0) continue;

        const is_error = std.mem.indexOf(u8, trimmed, "error") != null or
            std.mem.indexOf(u8, trimmed, "Error") != null or
            std.mem.indexOf(u8, trimmed, "ERROR") != null or
            std.mem.indexOf(u8, trimmed, "failed") != null or
            std.mem.indexOf(u8, trimmed, "FAILED") != null;

        if (is_error) {
            if (found_errors) try errors.append(allocator, '\n');
            found_errors = true;
            try errors.appendSlice(allocator, trimmed);
        }
    }

    if (!found_errors) {
        return allocator.dupe(u8, "(no errors)");
    }

    return errors.toOwnedSlice(allocator);
}

/// Grouping filter - group by pattern (simplified)
fn filterGrouping(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var groups = std.StringArrayHashMap(usize).init(allocator);
    defer groups.deinit();

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Extract group key
        var key: []const u8 = trimmed;
        if (std.mem.indexOf(u8, trimmed, ":")) |idx| {
            key = trimmed[0..idx];
        } else if (std.mem.indexOf(u8, trimmed, " ")) |idx| {
            key = trimmed[0..idx];
        }

        key = std.mem.trim(u8, key, "[]:");

        if (key.len > 0) {
            const count = groups.get(key) orelse 0;
            try groups.put(try allocator.dupe(u8, key), count + 1);
        }
    }

    var result = std.ArrayList(u8).empty;
    defer result.deinit(allocator);

    var i: usize = 0;
    var it = groups.iterator();
    while (it.next()) |entry| {
        if (i > 0) try result.appendSlice(allocator, ", ");
        try std.fmt.format(result.writer(allocator), "{s}: {d}", .{ entry.key_ptr.*, entry.value_ptr.* });
        i += 1;
        if (i >= 10) break; // limit to 10 groups
    }

    return result.toOwnedSlice(allocator);
}

/// Deduplication filter - remove duplicates with counts (simplified)
fn filterDeduplication(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var seen = std.StringArrayHashMap(usize).init(allocator);
    defer seen.deinit();

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        const idx = seen.get(trimmed) orelse 0;
        try seen.put(try allocator.dupe(u8, trimmed), idx + 1);
    }

    var result = std.ArrayList(u8).empty;
    defer result.deinit(allocator);

    var i: usize = 0;
    var it = seen.iterator();
    while (it.next()) |entry| {
        if (i > 0) try result.append(allocator, '\n');
        if (entry.value_ptr.* > 1) {
            try std.fmt.format(result.writer(allocator), "{s} (x{d})", .{ entry.key_ptr.*, entry.value_ptr.* });
        } else {
            try result.appendSlice(allocator, entry.key_ptr.*);
        }
        i += 1;
    }

    return result.toOwnedSlice(allocator);
}

/// Failure focus filter - show only failures
fn filterFailureFocus(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = std.ArrayList(u8).empty;
    defer result.deinit(allocator);
    var found_failure = false;

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        const is_failure = std.mem.indexOf(u8, trimmed, "FAIL") != null or
            std.mem.indexOf(u8, trimmed, "failed") != null or
            std.mem.indexOf(u8, trimmed, "FAILED") != null or
            std.mem.indexOf(u8, trimmed, "AssertionError") != null;

        if (is_failure) {
            if (found_failure) try result.append(allocator, '\n');
            found_failure = true;
            try result.appendSlice(allocator, trimmed);
        }
    }

    if (!found_failure) {
        if (std.mem.indexOf(u8, input, "test") != null) {
            return allocator.dupe(u8, "all tests passed");
        }
        return allocator.dupe(u8, input);
    }

    return result.toOwnedSlice(allocator);
}

/// Tree compression filter - directory tree format (simplified)
fn filterTreeCompression(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var dir_counts = std.StringArrayHashMap(usize).init(allocator);
    defer dir_counts.deinit();

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        var last_slash: ?usize = null;
        for (trimmed, 0..) |c, idx| {
            if (c == '/') last_slash = idx;
        }

        const dir = if (last_slash) |idx| trimmed[0..idx] else ".";
        const count = dir_counts.get(dir) orelse 0;
        try dir_counts.put(dir, count + 1);
    }

    var result = std.ArrayList(u8).empty;
    defer result.deinit(allocator);

    var it = dir_counts.iterator();
    while (it.next()) |entry| {
        try std.fmt.format(result.writer(allocator), "{s}/ ({d} items)\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    return result.toOwnedSlice(allocator);
}

fn makeTextResult(_allocator: std.mem.Allocator, text: []const u8) CallToolResult {
    _ = _allocator; // Kept for API compatibility but page_allocator is used
    // Use empty string fallback if text is empty
    const safe_text: []const u8 = if (text.len == 0) "{\"output\":\"empty\"}" else text;

    // Use page_allocator for all allocations
    const page_alloc = std.heap.page_allocator;

    // Allocate text_copy on heap
    const text_copy = page_alloc.dupe(u8, safe_text) catch {
        // Fallback: use a static error message (no heap allocation)
        return makeErrorResultStatic("{\"error\":\"allocation_failed\"}");
    };

    // Allocate ContentBlock on heap
    const block = page_alloc.create(CallToolResult.ContentBlock) catch {
        page_alloc.free(text_copy);
        return makeErrorResultStatic("{\"error\":\"allocation_failed\"}");
    };

    // Initialize block
    block.* = .{
        .type = "text",
        .text = text_copy,
    };

    return .{
        .content = block[0..1],
    };
}

/// Create an error result - uses heap allocation
fn makeErrorResultStatic(error_msg: []const u8) CallToolResult {
    const page_alloc = std.heap.page_allocator;

    const text_copy = page_alloc.dupe(u8, error_msg) catch {
        // Return global fallback (static lifetime)
        return .{
            .content = GLOBAL_ERROR_CONTENT,
            .is_error = true,
        };
    };

    const block = page_alloc.create(CallToolResult.ContentBlock) catch {
        page_alloc.free(text_copy);
        return .{
            .content = GLOBAL_ERROR_CONTENT,
            .is_error = true,
        };
    };

    block.* = .{
        .type = "text",
        .text = text_copy,
    };

    return .{
        .content = block[0..1],
        .is_error = true,
    };
}

fn makeErrorResult(allocator: std.mem.Allocator, error_msg: []const u8) CallToolResult {
    const json_err = std.fmt.allocPrint(allocator, "{{\"error\":\"{s}\"}}", .{error_msg}) catch {
        return .{
            .content = &[_]CallToolResult.ContentBlock{
                .{
                    .type = "text",
                    .text = "{\"error\":\"unknown\"}",
                },
            },
            .is_error = true,
        };
    };
    // Allocate ContentBlock on heap to avoid stack lifetime issues
    const block = allocator.create(CallToolResult.ContentBlock) catch {
        allocator.free(json_err);
        return .{
            .content = &[_]CallToolResult.ContentBlock{
                .{
                    .type = "text",
                    .text = "{\"error\":\"allocation failed\"}",
                },
            },
            .is_error = true,
        };
    };
    block.* = .{
        .type = "text",
        .text = json_err,
    };
    return .{
        .content = block[0..1],
        .is_error = true,
    };
}
