//! Guardrail Plugin for llmlite Proxy
//!
//! Content filtering and PII detection
//! Zero dependency - uses regex patterns

const std = @import("std");
const plugin = @import("plugin");

// ============ Content Filter ============

pub const ContentFilter = struct {
    allocator: std.mem.Allocator,
    blocked_words: [][]const u8,
    blocked_patterns: [][]const u8,

    pub fn init(allocator: std.mem.Allocator, blocked_words: [][]const u8) ContentFilter {
        return .{
            .allocator = allocator,
            .blocked_words = blocked_words,
            .blocked_patterns = &.{}, // Could add regex patterns
        };
    }

    pub fn deinit(self: *ContentFilter) void {
        self.allocator.free(self.blocked_words);
    }

    pub fn toGuardrail(self: *ContentFilter) plugin.Guardrail {
        return .{
            .interface = @ptrCast(self),
            .vtable = &.{
                .checkContent = contentCheckWrapper,
                .checkJson = jsonCheckWrapper,
                .close = closeWrapper,
            },
        };
    }

    fn containsBlockedWord(content: []const u8, blocked: [][]const u8) ?[]const u8 {
        for (blocked) |word| {
            if (std.mem.find(u8, content, word) != null) {
                return word;
            }
        }
        return null;
    }

    fn contentCheckWrapper(interface: *anyopaque, content: []const u8) plugin.GuardrailResult {
        const self: *ContentFilter = @ptrCast(@alignCast(interface));

        if (containsBlockedWord(content, self.blocked_words)) |word| {
            return .{
                .allowed = false,
                .reason = try std.fmt.allocPrint(self.allocator, "blocked word: {s}", .{word}),
                .filtered_content = null,
            };
        }

        return .{ .allowed = true, .reason = null, .filtered_content = null };
    }

    fn jsonCheckWrapper(interface: *anyopaque, json: []const u8) plugin.GuardrailResult {
        const self: *ContentFilter = @ptrCast(@alignCast(interface));
        // Simple JSON content extraction - look for "content" or "text" fields
        // For a real implementation, parse the JSON properly
        _ = self;
        _ = json;
        return .{ .allowed = true, .reason = null, .filtered_content = null };
    }

    fn closeWrapper(interface: *anyopaque) void {
        const self: *ContentFilter = @ptrCast(@alignCast(interface));
        self.deinit();
    }
};

// ============ PII Detector ============

pub const PiiDetector = struct {
    allocator: std.mem.Allocator,
    detect_email: bool,
    detect_phone: bool,
    detect_ssn: bool,

    pub fn init(allocator: std.mem.Allocator, detect_email: bool, detect_phone: bool, detect_ssn: bool) PiiDetector {
        return .{
            .allocator = allocator,
            .detect_email = detect_email,
            .detect_phone = detect_phone,
            .detect_ssn = detect_ssn,
        };
    }

    pub fn deinit(self: *PiiDetector) void {
        _ = self;
    }

    pub fn toGuardrail(self: *PiiDetector) plugin.Guardrail {
        return .{
            .interface = @ptrCast(self),
            .vtable = &.{
                .checkContent = piiCheckWrapper,
                .checkJson = piiJsonCheckWrapper,
                .close = piiCloseWrapper,
            },
        };
    }

    fn detectPii(content: []const u8, detector: *const PiiDetector) ?struct { type: []const u8, value: []const u8 } {
        if (detector.detect_email) {
            // Simple email pattern
            if (std.mem.find(u8, content, "@") != null) {
                // Try to extract email
                var start: usize = 0;
                var end: usize = content.len;
                for (content, 0..) |c, i| {
                    if (c == '@') {
                        // Back up to find start
                        var j = i;
                        while (j > 0 and std.ascii.isAlphanumeric(content[j - 1])) j -= 1;
                        start = j;
                        // Find end
                        j = i + 1;
                        while (j < content.len and (std.ascii.isAlphanumeric(content[j]) or content[j] == '.')) j += 1;
                        end = j;
                        break;
                    }
                }
                if (start < end) {
                    return .{ .type = "email", .value = content[start..end] };
                }
            }
        }

        if (detector.detect_phone) {
            // Simple phone pattern (XXX-XXX-XXXX or (XXX) XXX-XXXX)
            var found = false;
            for (content, 0..) |c, i| {
                if (c == '-' or c == '(') {
                    found = true;
                    // Try to extract phone
                    var j = i;
                    while (j < content.len and (std.ascii.isDigit(content[j]) or content[j] == '-' or content[j] == ' ' or content[j] == '(' or content[j] == ')')) j += 1;
                    if (j > i) {
                        return .{ .type = "phone", .value = content[i..j] };
                    }
                }
            }
        }

        if (detector.detect_ssn) {
            // Simple SSN pattern (XXX-XX-XXXX)
            for (content, 0..) |c, i| {
                if (c == '-' and i + 4 < content.len and content[i + 4] == '-') {
                    // Might be SSN format
                    return .{ .type = "ssn", .value = "***-**-****" };
                }
            }
        }

        return null;
    }

    fn piiCheckWrapper(interface: *anyopaque, content: []const u8) plugin.GuardrailResult {
        const self: *PiiDetector = @ptrCast(@alignCast(interface));

        if (detectPii(content, self)) |pii| {
            return .{
                .allowed = true, // PII found but not blocked, just flagged
                .reason = try std.fmt.allocPrint(self.allocator, "PII detected: {s}", .{pii.type}),
                .filtered_content = null,
            };
        }

        return .{ .allowed = true, .reason = null, .filtered_content = null };
    }

    fn piiJsonCheckWrapper(interface: *anyopaque, json: []const u8) plugin.GuardrailResult {
        const self: *PiiDetector = @ptrCast(@alignCast(interface));
        _ = self;
        _ = json;
        // Would parse JSON and check content fields
        return .{ .allowed = true, .reason = null, .filtered_content = null };
    }

    fn piiCloseWrapper(interface: *anyopaque) void {
        const self: *PiiDetector = @ptrCast(@alignCast(interface));
        self.deinit();
    }
};

// ============ Full Guardrail (Content + PII) ============

pub const FullGuardrail = struct {
    allocator: std.mem.Allocator,
    content_filter: ContentFilter,
    pii_detector: PiiDetector,

    pub fn init(allocator: std.mem.Allocator, blocked_words: [][]const u8, detect_email: bool, detect_phone: bool, detect_ssn: bool) FullGuardrail {
        return .{
            .allocator = allocator,
            .content_filter = ContentFilter.init(allocator, blocked_words),
            .pii_detector = PiiDetector.init(allocator, detect_email, detect_phone, detect_ssn),
        };
    }

    pub fn deinit(self: *FullGuardrail) void {
        self.content_filter.deinit();
        self.pii_detector.deinit();
    }

    pub fn toGuardrail(self: *FullGuardrail) plugin.Guardrail {
        return .{
            .interface = @ptrCast(self),
            .vtable = &.{
                .checkContent = fullCheckWrapper,
                .checkJson = fullJsonCheckWrapper,
                .close = fullCloseWrapper,
            },
        };
    }

    fn fullCheckWrapper(interface: *anyopaque, content: []const u8) plugin.GuardrailResult {
        const self: *FullGuardrail = @ptrCast(@alignCast(interface));

        // First check content filter
        const filter_result = ContentFilter.contentCheckWrapper(@ptrCast(&self.content_filter), content);
        if (!filter_result.allowed) {
            return filter_result;
        }

        // Then check PII
        return PiiDetector.piiCheckWrapper(@ptrCast(&self.pii_detector), content);
    }

    fn fullJsonCheckWrapper(interface: *anyopaque, json: []const u8) plugin.GuardrailResult {
        const self: *FullGuardrail = @ptrCast(@alignCast(interface));
        _ = self;
        _ = json;
        return .{ .allowed = true, .reason = null, .filtered_content = null };
    }

    fn fullCloseWrapper(interface: *anyopaque) void {
        const self: *FullGuardrail = @ptrCast(@alignCast(interface));
        self.deinit();
    }
};

// Plugin info
pub const CONTENT_FILTER_INFO = plugin.PluginInfo{
    .name = "guardrail.content_filter",
    .version = "1.0.0",
    .description = "Content filtering based on blocked words",
    .plugin_type = .guardrail,
    .dependencies = &.{},
};

pub const PII_DETECTOR_INFO = plugin.PluginInfo{
    .name = "guardrail.pii_detect",
    .version = "1.0.0",
    .description = "PII detection (email, phone, SSN)",
    .plugin_type = .guardrail,
    .dependencies = &.{},
};

pub const FULL_GUARDRAIL_INFO = plugin.PluginInfo{
    .name = "guardrail.full",
    .version = "1.0.0",
    .description = "Full guardrail with content filter and PII detection",
    .plugin_type = .guardrail,
    .dependencies = &.{},
};

test "guardrail plugin" {
    std.debug.print("Guardrail plugin test\n", .{});
}
