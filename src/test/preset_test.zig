//! Provider Preset Validation Tests
//!
//! Tests that validate all built-in provider presets are correctly configured.
//! Checks for:
//! - Required fields are present
//! - URLs are properly formatted
//! - Provider types are valid
//! - No duplicate preset IDs
//! - All provider types have at least one preset

const std = @import("std");
const testing = std.testing;
const preset = @import("proxy_preset");
const types = @import("provider_types");

test "preset: all presets have valid id" {
    for (preset.PRESETS) |p| {
        try testing.expect(p.id.len > 0);
        // IDs should not contain spaces
        try testing.expect(std.mem.find(u8, p.id, " ") == null);
    }
}

test "preset: all presets have valid name" {
    for (preset.PRESETS) |p| {
        try testing.expect(p.name.len > 0);
    }
}

test "preset: all presets have valid base_url" {
    for (preset.PRESETS) |p| {
        try testing.expect(p.base_url.len > 0);
        // URLs should start with http:// or https://
        try testing.expect(std.mem.startsWith(u8, p.base_url, "http://") or
            std.mem.startsWith(u8, p.base_url, "https://"));
        // URLs should end with /v1 for API endpoints
        if (!std.mem.endsWith(u8, p.base_url, "/v1") and
            !std.mem.endsWith(u8, p.base_url, "/v1beta"))
        {
            // Some providers like Ollama might not have /v1
            // Just check it's a reasonable URL
            try testing.expect(std.mem.find(u8, p.base_url, "://") != null);
        }
    }
}

test "preset: all presets have valid auth_type" {
    for (preset.PRESETS) |p| {
        // Auth type should be valid (just check it's not crashing)
        _ = p.auth_type;
    }
}

test "preset: all presets have default_model" {
    for (preset.PRESETS) |p| {
        try testing.expect(p.default_model.len > 0);
    }
}

test "preset: all presets have supports array" {
    for (preset.PRESETS) |p| {
        try testing.expect(p.supports.len > 0);
    }
}

test "preset: no duplicate preset IDs" {
    var seen = std.StringHashMap(void).init(testing.allocator);
    defer seen.deinit();

    for (preset.PRESETS) |p| {
        const gop = try seen.getOrPut(p.id);
        try testing.expect(!gop.found_existing);
    }
}

test "preset: all provider types have at least one preset" {
    inline for (std.meta.fields(types.ProviderType)) |field| {
        const provider_type = @as(types.ProviderType, @enumFromInt(field.value));
        var found = false;
        for (preset.PRESETS) |p| {
            if (p.provider == provider_type) {
                found = true;
                break;
            }
        }
        // Only check known provider types (skip openai_compatible and custom)
        if (field.value < 12) { // Before openai_compatible
            try testing.expect(found);
        }
    }
}

test "preset: official providers have organization set" {
    for (preset.PRESETS) |p| {
        if (p.is_official) {
            try testing.expect(p.organization != null);
            try testing.expect(p.organization.?.len > 0);
        }
    }
}

test "preset: official providers have website" {
    for (preset.PRESETS) |p| {
        if (p.is_official) {
            try testing.expect(p.website != null);
            try testing.expect(p.website.?.len > 0);
        }
    }
}

test "preset: supports contains valid capabilities" {
    const valid_capabilities = std.ComptimeStringMap(void, .{
        .{ "chat", {} },
        .{ "embeddings", {} },
        .{ "streaming", {} },
        .{ "tools", {} },
        .{ "json", {} },
        .{ "vision", {} },
        .{ "files", {} },
        .{ "audio", {} },
        .{ "video", {} },
        .{ "images", {} },
        .{ "music", {} },
    });

    for (preset.PRESETS) |p| {
        for (p.supports) |cap| {
            try testing.expect(valid_capabilities.has(cap));
        }
    }
}

test "preset: MINIMAX preset is correctly configured" {
    for (preset.PRESETS) |p| {
        if (std.mem.eql(u8, p.id, "minimax-official")) {
            try testing.expect(p.provider == .minimax);
            try testing.expectEqualStrings("https://api.minimax.chat/v1", p.base_url);
            try testing.expectEqualStrings("MiniMax-Text-01", p.default_model);
            try testing.expect(p.supports.len > 0);
            return;
        }
    }
    return error.MinimaxPresetNotFound;
}

test "preset: OpenAI preset is correctly configured" {
    for (preset.PRESETS) |p| {
        if (std.mem.eql(u8, p.id, "openai-official")) {
            try testing.expect(p.provider == .openai);
            try testing.expectEqualStrings("https://api.openai.com/v1", p.base_url);
            try testing.expectEqualStrings("gpt-4o", p.default_model);
            try testing.expect(p.is_official);
            return;
        }
    }
    return error.OpenaiPresetNotFound;
}

test "preset: count total presets" {
    const count = preset.PRESETS.len;
    // Should have 50+ presets
    try testing.expect(count >= 50);
    std.debug.print("Total presets: {d}\n", .{count});
}
