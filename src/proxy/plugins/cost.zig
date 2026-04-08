//! Cost Tracker Plugin for llmlite Proxy
//!
//! Model pricing database and spend calculation
//! Zero dependency - uses in-memory storage with optional SQLite persistence

const std = @import("std");
const plugin = @import("plugin");

// ============ Model Pricing ============

pub const ModelPricing = struct {
    provider: []const u8,
    model: []const u8,
    input_cost_per_mtok: f64,
    output_cost_per_mtok: f64,
    currency: []const u8,
};

// ============ In-Memory Cost Tracker ============

pub const MemoryCostTracker = struct {
    allocator: std.mem.Allocator,
    pricing: std.StringArrayHashMap(ModelPricing),
    spend_entries: std.ArrayList(plugin.CostEntry),

    pub fn init(allocator: std.mem.Allocator) MemoryCostTracker {
        var tracker = MemoryCostTracker{
            .allocator = allocator,
            .pricing = std.StringArrayHashMap(ModelPricing).init(allocator),
            .spend_entries = std.ArrayList(plugin.CostEntry).init(allocator),
        };
        tracker.initDefaultPricing();
        return tracker;
    }

    pub fn deinit(self: *MemoryCostTracker) void {
        var price_it = self.pricing.iterator();
        while (price_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.provider);
            self.allocator.free(entry.value_ptr.model);
            self.allocator.free(entry.value_ptr.currency);
        }
        self.pricing.deinit();

        for (self.spend_entries.items) |entry| {
            self.allocator.free(entry.key_id);
            if (entry.team_id) |tid| self.allocator.free(tid);
            self.allocator.free(entry.provider);
            self.allocator.free(entry.model);
        }
        self.spend_entries.deinit();
    }

    fn initDefaultPricing(self: *MemoryCostTracker) void {
        // OpenAI models
        self.addPricing("openai", "gpt-4o", 5.00, 15.00);
        self.addPricing("openai", "gpt-4o-mini", 0.15, 0.60);
        self.addPricing("openai", "gpt-3.5-turbo", 0.50, 1.50);

        // Anthropic models
        self.addPricing("anthropic", "claude-3-5-sonnet-latest", 3.00, 15.00);
        self.addPricing("anthropic", "claude-3-opus", 15.00, 75.00);

        // Google Gemini models
        self.addPricing("google", "gemini-2.0-flash", 0.00, 0.00);
        self.addPricing("google", "gemini-1.5-flash", 0.075, 0.30);

        // DeepSeek models
        self.addPricing("deepseek", "deepseek-chat", 0.14, 0.28);

        // Mistral models
        self.addPricing("mistral", "mistral-large", 2.00, 6.00);
    }

    pub fn addPricing(self: *MemoryCostTracker, provider: []const u8, model: []const u8, input_cost: f64, output_cost: f64) void {
        const key = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ provider, model }) catch return;
        self.pricing.put(key, .{
            .provider = self.allocator.dupe(u8, provider) catch return,
            .model = self.allocator.dupe(u8, model) catch return,
            .input_cost_per_mtok = input_cost,
            .output_cost_per_mtok = output_cost,
            .currency = "USD",
        }) catch return;
    }

    pub fn calculateCost(self: *MemoryCostTracker, provider: []const u8, model: []const u8, prompt_tokens: u32, completion_tokens: u32) f64 {
        const key = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ provider, model }) catch return 0.0;
        defer self.allocator.free(key);

        const pricing = self.pricing.get(key) orelse return 0.0;

        const prompt_cost = @as(f64, @floatFromInt(prompt_tokens)) / 1_000_000.0 * pricing.input_cost_per_mtok;
        const completion_cost = @as(f64, @floatFromInt(completion_tokens)) / 1_000_000.0 * pricing.output_cost_per_mtok;

        return prompt_cost + completion_cost;
    }

    pub fn toCostTracker(self: *MemoryCostTracker) plugin.CostTracker {
        return .{
            .interface = @ptrCast(self),
            .vtable = &.{
                .record = recordWrapper,
                .getTotalForKey = getTotalForKeyWrapper,
                .getTotalForTeam = getTotalForTeamWrapper,
                .getDailySpend = getDailySpendWrapper,
                .close = closeWrapper,
            },
        };
    }

    fn recordWrapper(interface: *anyopaque, entry: plugin.CostEntry) !void {
        const self: *MemoryCostTracker = @ptrCast(@alignCast(interface));
        const entry_copy = plugin.CostEntry{
            .key_id = try self.allocator.dupe(u8, entry.key_id),
            .team_id = if (entry.team_id) |tid| try self.allocator.dupe(u8, tid) else null,
            .provider = try self.allocator.dupe(u8, entry.provider),
            .model = try self.allocator.dupe(u8, entry.model),
            .prompt_tokens = entry.prompt_tokens,
            .completion_tokens = entry.completion_tokens,
            .cost = entry.cost,
            .timestamp = entry.timestamp,
        };
        try self.spend_entries.append(entry_copy);
    }

    fn getTotalForKeyWrapper(interface: *anyopaque, key_id: []const u8) f64 {
        const self: *MemoryCostTracker = @ptrCast(@alignCast(interface));
        var total: f64 = 0;
        for (self.spend_entries.items) |entry| {
            if (std.mem.eql(u8, entry.key_id, key_id)) {
                total += entry.cost;
            }
        }
        return total;
    }

    fn getTotalForTeamWrapper(interface: *anyopaque, team_id: []const u8) f64 {
        const self: *MemoryCostTracker = @ptrCast(@alignCast(interface));
        var total: f64 = 0;
        for (self.spend_entries.items) |entry| {
            if (entry.team_id) |tid| {
                if (std.mem.eql(u8, tid, team_id)) {
                    total += entry.cost;
                }
            }
        }
        return total;
    }

    fn getDailySpendWrapper(interface: *anyopaque, key_id: []const u8) f64 {
        const self: *MemoryCostTracker = @ptrCast(@alignCast(interface));
        const now = std.time.timestamp();
        const day_start = now - (now % 86400); // Start of today
        var total: f64 = 0;

        for (self.spend_entries.items) |entry| {
            if (std.mem.eql(u8, entry.key_id, key_id) and entry.timestamp >= day_start) {
                total += entry.cost;
            }
        }
        return total;
    }

    fn closeWrapper(interface: *anyopaque) void {
        const self: *MemoryCostTracker = @ptrCast(@alignCast(interface));
        self.deinit();
    }
};

// Plugin info
pub const COST_TRACKER_INFO = plugin.PluginInfo{
    .name = "cost_tracker.memory",
    .version = "1.0.0",
    .description = "In-memory cost tracker with model pricing",
    .plugin_type = .cost_tracker,
    .dependencies = &.{},
};

test "cost tracker plugin" {
    std.debug.print("Cost tracker plugin test\n", .{});
}
