//! Model Mapper for llmlite Proxy
//!
//! Maps model names between providers based on configuration.
//! Allows substituting model names before forwarding requests.

const std = @import("std");

pub const ModelMappingConfig = struct {
    haiku_model: ?[]const u8 = null,
    sonnet_model: ?[]const u8 = null,
    opus_model: ?[]const u8 = null,
    default_model: ?[]const u8 = null,
    reasoning_model: ?[]const u8 = null,
};

/// Model mapping result
pub const ModelMappingResult = struct {
    original_model: []const u8,
    mapped_model: []const u8,
    was_mapped: bool,
};

/// Check if any model mapping is configured
pub fn hasMapping(config: *const ModelMappingConfig) bool {
    return config.haiku_model != null or
        config.sonnet_model != null or
        config.opus_model != null or
        config.default_model != null or
        config.reasoning_model != null;
}

/// Map model name based on configuration
///
/// Priority:
/// 1. Thinking mode → reasoning model
/// 2. Model type (haiku/sonnet/opus) → configured equivalent
/// 3. Default model
/// 4. Original model (no mapping)
pub fn mapModel(config: *const ModelMappingConfig, original_model: []const u8, has_thinking: bool) []const u8 {
    // 1. Thinking mode优先使用推理模型
    if (has_thinking) {
        if (config.reasoning_model) |m| {
            return m;
        }
    }

    // 2. 按模型类型匹配
    const model_lower = std.ascii.lowerString(original_model);

    if (std.mem.containsAtLeast(u8, model_lower, 1, "haiku")) {
        if (config.haiku_model) |m| {
            return m;
        }
    }
    if (std.mem.containsAtLeast(u8, model_lower, 1, "opus")) {
        if (config.opus_model) |m| {
            return m;
        }
    }
    if (std.mem.containsAtLeast(u8, model_lower, 1, "sonnet")) {
        if (config.sonnet_model) |m| {
            return m;
        }
    }

    // 3. 默认模型
    if (config.default_model) |m| {
        return m;
    }

    // 4. 无映射，保持原样
    return original_model;
}

/// Map model name with full result
pub fn mapModelFull(config: *const ModelMappingConfig, original_model: []const u8, has_thinking: bool) ModelMappingResult {
    const mapped = mapModel(config, original_model, has_thinking);
    return .{
        .original_model = original_model,
        .mapped_model = mapped,
        .was_mapped = !std.mem.eql(u8, original_model, mapped),
    };
}

/// Detect model type from model name
pub const ModelType = enum {
    haiku,
    sonnet,
    opus,
    o1,
    o3,
    o4,
    gpt4,
    gpt35,
    gemini,
    claude,
    unknown,
};

/// Detect model type from name
pub fn detectModelType(model_name: []const u8) ModelType {
    const lower = std.ascii.lowerString(model_name);

    if (std.mem.containsAtLeast(u8, lower, 1, "haiku")) {
        return .haiku;
    }
    if (std.mem.containsAtLeast(u8, lower, 1, "sonnet")) {
        return .sonnet;
    }
    if (std.mem.containsAtLeast(u8, lower, 1, "opus")) {
        return .opus;
    }
    if (std.mem.containsAtLeast(u8, lower, 1, "o1") and std.mem.containsAtLeast(u8, lower, 1, "mini")) {
        return .o1;
    }
    if (std.mem.containsAtLeast(u8, lower, 1, "o3")) {
        return .o3;
    }
    if (std.mem.containsAtLeast(u8, lower, 1, "o4")) {
        return .o4;
    }
    if (std.mem.containsAtLeast(u8, lower, 1, "gpt-4") or std.mem.containsAtLeast(u8, lower, 1, "gpt4")) {
        return .gpt4;
    }
    if (std.mem.containsAtLeast(u8, lower, 1, "gpt-3") or std.mem.containsAtLeast(u8, lower, 1, "gpt3") or std.mem.containsAtLeast(u8, lower, 1, "3.5")) {
        return .gpt35;
    }
    if (std.mem.containsAtLeast(u8, lower, 1, "gemini")) {
        return .gemini;
    }
    if (std.mem.containsAtLeast(u8, lower, 1, "claude")) {
        return .claude;
    }

    return .unknown;
}

/// Check if model is a reasoning model (o1/o3/o4 series)
pub fn isReasoningModel(model_name: []const u8) bool {
    const model_type = detectModelType(model_name);
    return model_type == .o1 or model_type == .o3 or model_type == .o4;
}

/// Get suggested model alternatives for a given model
pub fn getSuggestedAlternative(model_name: []const u8, target_provider: []const u8) ?[]const u8 {
    _ = target_provider;
    const model_type = detectModelType(model_name);

    return switch (model_type) {
        .haiku => "claude-3-5-haiku-latest",
        .sonnet => "claude-3-5-sonnet-latest",
        .opus => "claude-3-opus-latest",
        .o1, .o3, .o4 => null, // No alternative for o-series
        .gpt4 => "claude-3-5-sonnet-latest",
        .gpt35 => "claude-3-5-haiku-latest",
        .gemini, .claude, .unknown => null,
    };
}

/// Normalize model name for comparison
pub fn normalizeModelName(model_name: []const u8) []u8 {
    // Convert to lowercase and remove common prefixes/suffixes
    var result = std.ascii.lowerString(model_name);

    // Remove common variations
    const to_remove = [_][]const u8{
        "-latest",
        "-20250101",
        "-20241101",
        "-20241001",
        "-20240901",
    };

    for (to_remove) |pattern| {
        if (std.mem.endsWith(u8, result, pattern)) {
            result = result[0 .. result.len - pattern.len];
        }
    }

    return result;
}

// ============================================================================
// TESTS
// ============================================================================

test "hasMapping - returns false when no mappings configured" {
    const config = ModelMappingConfig{
        .haiku_model = null,
        .sonnet_model = null,
        .opus_model = null,
        .default_model = null,
        .reasoning_model = null,
    };

    try std.testing.expect(!hasMapping(&config));
}

test "hasMapping - returns true when any mapping configured" {
    const config = ModelMappingConfig{
        .haiku_model = null,
        .sonnet_model = null,
        .opus_model = null,
        .default_model = "gpt-4o",
        .reasoning_model = null,
    };

    try std.testing.expect(hasMapping(&config));
}

test "mapModel - no mapping returns original" {
    const config = ModelMappingConfig{
        .haiku_model = null,
        .sonnet_model = null,
        .opus_model = null,
        .default_model = null,
        .reasoning_model = null,
    };

    const result = mapModel(&config, "gpt-4o", false);
    try std.testing.expectEqualStrings("gpt-4o", result);
}

test "mapModel - maps haiku model" {
    const config = ModelMappingConfig{
        .haiku_model = "claude-3-5-haiku-latest",
        .sonnet_model = null,
        .opus_model = null,
        .default_model = null,
        .reasoning_model = null,
    };

    const result = mapModel(&config, "gpt-3.5-haiku", false);
    try std.testing.expectEqualStrings("claude-3-5-haiku-latest", result);
}

test "mapModel - maps sonnet model" {
    const config = ModelMappingConfig{
        .haiku_model = null,
        .sonnet_model = "claude-3-5-sonnet-latest",
        .opus_model = null,
        .default_model = null,
        .reasoning_model = null,
    };

    const result = mapModel(&config, "claude-3-sonnet", false);
    try std.testing.expectEqualStrings("claude-3-5-sonnet-latest", result);
}

test "mapModel - maps opus model" {
    const config = ModelMappingConfig{
        .haiku_model = null,
        .sonnet_model = null,
        .opus_model = "claude-3-opus",
        .default_model = null,
        .reasoning_model = null,
    };

    const result = mapModel(&config, "gpt-4-opus", false);
    try std.testing.expectEqualStrings("claude-3-opus", result);
}

test "mapModel - thinking mode uses reasoning model" {
    const config = ModelMappingConfig{
        .haiku_model = null,
        .sonnet_model = null,
        .opus_model = null,
        .default_model = null,
        .reasoning_model = "sonnet-4",
    };

    const result = mapModel(&config, "haiku-3", true);
    try std.testing.expectEqualStrings("sonnet-4", result);
}

test "mapModel - default model as fallback" {
    const config = ModelMappingConfig{
        .haiku_model = null,
        .sonnet_model = null,
        .opus_model = null,
        .default_model = "gpt-4o",
        .reasoning_model = null,
    };

    const result = mapModel(&config, "unknown-model", false);
    try std.testing.expectEqualStrings("gpt-4o", result);
}

test "mapModelFull - returns mapping result with was_mapped flag" {
    const config = ModelMappingConfig{
        .haiku_model = "claude-3-5-haiku-latest",
        .sonnet_model = null,
        .opus_model = null,
        .default_model = null,
        .reasoning_model = null,
    };

    const result = mapModelFull(&config, "haiku", false);
    try std.testing.expectEqualStrings("haiku", result.original_model);
    try std.testing.expectEqualStrings("claude-3-5-haiku-latest", result.mapped_model);
    try std.testing.expect(result.was_mapped);

    const result2 = mapModelFull(&config, "unknown", false);
    try std.testing.expectEqualStrings("unknown", result2.original_model);
    try std.testing.expectEqualStrings("unknown", result2.mapped_model);
    try std.testing.expect(!result2.was_mapped);
}

test "detectModelType - identifies haiku" {
    try std.testing.expect(detectModelType("claude-3-haiku") == .haiku);
    try std.testing.expect(detectModelType("haiku-3") == .haiku);
    try std.testing.expect(detectModelType("anthropic/haiku") == .haiku);
}

test "detectModelType - identifies sonnet" {
    try std.testing.expect(detectModelType("claude-3-sonnet") == .sonnet);
    try std.testing.expect(detectModelType("sonnet-4") == .sonnet);
}

test "detectModelType - identifies opus" {
    try std.testing.expect(detectModelType("claude-3-opus") == .opus);
    try std.testing.expect(detectModelType("opus-4") == .opus);
}

test "detectModelType - identifies o1/o3/o4" {
    try std.testing.expect(detectModelType("o1") == .o1);
    try std.testing.expect(detectModelType("o1-mini") == .o1);
    try std.testing.expect(detectModelType("o3") == .o3);
    try std.testing.expect(detectModelType("o4") == .o4);
}

test "detectModelType - identifies gpt4" {
    try std.testing.expect(detectModelType("gpt-4") == .gpt4);
    try std.testing.expect(detectModelType("gpt4") == .gpt4);
    try std.testing.expect(detectModelType("gpt-4-turbo") == .gpt4);
}

test "detectModelType - identifies gpt35" {
    try std.testing.expect(detectModelType("gpt-3.5-turbo") == .gpt35);
    try std.testing.expect(detectModelType("gpt-3") == .gpt35);
}

test "detectModelType - identifies gemini" {
    try std.testing.expect(detectModelType("gemini-1.5-pro") == .gemini);
    try std.testing.expect(detectModelType("gemini-2.0-flash") == .gemini);
}

test "detectModelType - identifies claude" {
    try std.testing.expect(detectModelType("claude-3.5-sonnet-latest") == .claude);
}

test "isReasoningModel - o1/o3/o4 are reasoning models" {
    try std.testing.expect(isReasoningModel("o1"));
    try std.testing.expect(isReasoningModel("o1-mini"));
    try std.testing.expect(isReasoningModel("o3"));
    try std.testing.expect(isReasoningModel("o4"));
}

test "isReasoningModel - other models are not reasoning" {
    try std.testing.expect(!isReasoningModel("gpt-4o"));
    try std.testing.expect(!isReasoningModel("claude-3-sonnet"));
    try std.testing.expect(!isReasoningModel("gemini-1.5-flash"));
}

test "getSuggestedAlternative - returns claude alternatives for various models" {
    try std.testing.expectEqualStrings("claude-3-5-haiku-latest", getSuggestedAlternative("haiku", "anthropic").?);
    try std.testing.expectEqualStrings("claude-3-5-sonnet-latest", getSuggestedAlternative("sonnet", "anthropic").?);
    try std.testing.expectEqualStrings("claude-3-opus-latest", getSuggestedAlternative("opus", "anthropic").?);
    try std.testing.expectEqualStrings("claude-3-5-sonnet-latest", getSuggestedAlternative("gpt-4", "anthropic").?);
    try std.testing.expectEqualStrings("claude-3-5-haiku-latest", getSuggestedAlternative("gpt-3.5", "anthropic").?);
}

test "getSuggestedAlternative - o-series returns null" {
    try std.testing.expect(getSuggestedAlternative("o1", "openai") == null);
    try std.testing.expect(getSuggestedAlternative("o3", "openai") == null);
    try std.testing.expect(getSuggestedAlternative("o4", "openai") == null);
}

test "normalizeModelName - removes -latest suffix" {
    const result = normalizeModelName("claude-3-5-sonnet-latest");
    try std.testing.expectEqualStrings("claude-3-5-sonnet", result);
}

test "normalizeModelName - removes date suffixes" {
    const result = normalizeModelName("claude-3-5-sonnet-20250101");
    try std.testing.expectEqualStrings("claude-3-5-sonnet", result);
}

test "normalizeModelName - converts to lowercase" {
    const result = normalizeModelName("Claude-3-5-Sonnet-Latest");
    try std.testing.expectEqualStrings("claude-3-5-sonnet", result);
}
