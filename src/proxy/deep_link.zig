//! Deep Link Handler for llmlite Proxy
//!
//! Handles ccswitch:// URL scheme for importing providers, MCP servers, prompts, and skills.

const std = @import("std");

pub const DeepLinkError = error{
    InvalidUrl,
    InvalidScheme,
    InvalidAction,
    MissingParameter,
    NetworkError,
    ParseError,
    UnsupportedFormat,
};

/// Deep link action types
pub const DeepLinkActionType = enum {
    import_provider,
    import_mcp,
    import_prompt,
    import_skill,
    switch_provider,
    sync_all,
};

pub const DeepLinkAction = struct {
    action_type: DeepLinkActionType,
    url: []const u8,
    tool: []const u8,
    provider: []const u8,
};

/// Parse a ccswitch:// URL
pub fn parseDeepLink(url: []const u8) DeepLinkError!DeepLinkAction {
    if (!std.mem.startsWith(u8, url, "ccswitch://")) {
        return DeepLinkError.InvalidScheme;
    }

    const path = url[11..];

    if (std.mem.startsWith(u8, path, "import/provider")) {
        return parseImportProvider(path);
    } else if (std.mem.startsWith(u8, path, "import/mcp")) {
        return parseImportMcp(path);
    } else if (std.mem.startsWith(u8, path, "import/prompt")) {
        return parseImportPrompt(path);
    } else if (std.mem.startsWith(u8, path, "import/skill")) {
        return parseImportSkill(path);
    } else if (std.mem.startsWith(u8, path, "action/switch")) {
        return parseSwitchProvider(path);
    } else if (std.mem.startsWith(u8, path, "action/sync")) {
        return DeepLinkAction{ .action_type = .sync_all, .url = "", .tool = "", .provider = "" };
    } else if (std.mem.startsWith(u8, path, "action/")) {
        return DeepLinkError.InvalidAction;
    }

    return DeepLinkError.InvalidUrl;
}

fn parseQueryParams(path: []const u8) !std.StringArrayHashMap([]const u8) {
    var params = std.StringArrayHashMap([]const u8).init(std.heap.page_allocator);

    const question_idx = std.mem.indexOfScalar(u8, path, '?');
    if (question_idx) |q| {
        const query = path[q + 1 ..];
        var iter = std.mem.splitScalar(u8, query, '&');
        while (iter.next()) |pair| {
            if (pair.len == 0) continue;
            const eq_idx = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
            const key = pair[0..eq_idx];
            const value = try urlDecode(pair[eq_idx + 1 ..]);
            try params.put(key, value);
        }
    }

    return params;
}

fn urlDecode(input: []const u8) ![]const u8 {
    var result = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer result.deinit();

    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        if (input[i] == '%' and i + 2 < input.len) {
            const hex = input[i + 1 .. i + 3];
            const byte = std.fmt.parseInt(u8, hex, 16) catch {
                try result.append('%');
                continue;
            };
            try result.append(byte);
            i += 2;
        } else if (input[i] == '+') {
            try result.append(' ');
        } else {
            try result.append(input[i]);
        }
    }

    return result.toOwnedSlice();
}

fn parseImportProvider(path: []const u8) !DeepLinkAction {
    const params = try parseQueryParams(path);
    defer params.deinit();

    const url = params.get("url") orelse return DeepLinkError.MissingParameter;

    return DeepLinkAction{ .action_type = .import_provider, .url = url, .tool = "", .provider = "" };
}

fn parseImportMcp(path: []const u8) !DeepLinkAction {
    const params = try parseQueryParams(path);
    defer params.deinit();

    const url = params.get("url") orelse return DeepLinkError.MissingParameter;

    return DeepLinkAction{ .action_type = .import_mcp, .url = url, .tool = "", .provider = "" };
}

fn parseImportPrompt(path: []const u8) !DeepLinkAction {
    const params = try parseQueryParams(path);
    defer params.deinit();

    const url = params.get("url") orelse return DeepLinkError.MissingParameter;
    const tool = params.get("tool") orelse "claude_code";

    return DeepLinkAction{ .action_type = .import_prompt, .url = url, .tool = tool, .provider = "" };
}

fn parseImportSkill(path: []const u8) !DeepLinkAction {
    const params = try parseQueryParams(path);
    defer params.deinit();

    const url = params.get("url") orelse return DeepLinkError.MissingParameter;

    return DeepLinkAction{ .action_type = .import_skill, .url = url, .tool = "", .provider = "" };
}

fn parseSwitchProvider(path: []const u8) !DeepLinkAction {
    const params = try parseQueryParams(path);
    defer params.deinit();

    const provider = params.get("provider") orelse return DeepLinkError.MissingParameter;

    return DeepLinkAction{ .action_type = .switch_provider, .url = "", .tool = "", .provider = provider };
}

pub const DeepLinkResult = struct {
    success: bool,
    message: []const u8,
    action_type: DeepLinkActionType,
    data: ?[]const u8,
};

test "deep link parsing - import provider" {
    const url = "ccswitch://import/provider?url=https%3A%2F%2Fexample.com%2Fprovider.json";
    const action = try parseDeepLink(url);

    try std.testing.expect(action.action_type == .import_provider);
    try std.testing.expectEqualStrings("https://example.com/provider.json", action.url);
}

test "deep link parsing - switch provider" {
    const url = "ccswitch://action/switch?provider=openai-default";
    const action = try parseDeepLink(url);

    try std.testing.expect(action.action_type == .switch_provider);
    try std.testing.expectEqualStrings("openai-default", action.provider);
}

test "deep link parsing - sync all" {
    const url = "ccswitch://action/sync";
    const action = try parseDeepLink(url);

    try std.testing.expect(action.action_type == .sync_all);
}
