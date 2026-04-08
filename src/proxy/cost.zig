//! Cost Tracking for llmlite Proxy
//!
//! Model pricing database and spend calculation

const std = @import("std");

pub const ModelPricing = struct {
    provider: []const u8,
    model: []const u8,
    input_cost_per_mtok: f64, // Cost per million input tokens
    output_cost_per_mtok: f64, // Cost per million output tokens
    currency: []const u8 = "USD",
};

pub const CostTracker = struct {
    allocator: std.mem.Allocator,
    pricing: std.StringArrayHashMap(ModelPricing),

    pub fn init(allocator: std.mem.Allocator) CostTracker {
        var tracker = CostTracker{
            .allocator = allocator,
            .pricing = std.StringArrayHashMap(ModelPricing).init(allocator),
        };
        tracker.initDefaultPricing();
        return tracker;
    }

    pub fn deinit(self: *CostTracker) void {
        var it = self.pricing.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.provider);
            self.allocator.free(entry.value_ptr.model);
            self.allocator.free(entry.value_ptr.currency);
        }
        self.pricing.deinit();
    }

    /// Initialize with default pricing for common models
    fn initDefaultPricing(self: *CostTracker) void {
        // OpenAI models
        self.addPricing("openai", "gpt-4o", 5.00, 15.00); // $5/M input, $15/M output
        self.addPricing("openai", "gpt-4o-mini", 0.15, 0.60);
        self.addPricing("openai", "gpt-4-turbo", 10.00, 30.00);
        self.addPricing("openai", "gpt-3.5-turbo", 0.50, 1.50);
        self.addPricing("openai", "text-embedding-3-small", 0.02, 0.02); // Per million
        self.addPricing("openai", "text-embedding-3-large", 0.13, 0.13);

        // Anthropic models
        self.addPricing("anthropic", "claude-3-5-sonnet-latest", 3.00, 15.00);
        self.addPricing("anthropic", "claude-3-opus", 15.00, 75.00);
        self.addPricing("anthropic", "claude-3-haiku", 0.25, 1.25);
        self.addPricing("anthropic", "claude-3-sonnet", 3.00, 15.00);

        // Google Gemini models
        self.addPricing("google", "gemini-2.0-flash", 0.00, 0.00); // Free tier
        self.addPricing("google", "gemini-1.5-flash", 0.075, 0.30);
        self.addPricing("google", "gemini-1.5-pro", 1.25, 5.00);

        // Minimax models
        self.addPricing("minimax", "abab6-chat", 0.10, 0.10);
        self.addPricing("minimax", "abab6.5s-chat", 0.10, 0.10);

        // Kimi models
        self.addPricing("moonshot", "moonshot-v1-8k", 0.06, 0.06);
        self.addPricing("moonshot", "moonshot-v1-32k", 0.12, 0.12);
        self.addPricing("moonshot", "moonshot-v1-128k", 0.90, 0.90);

        // DeepSeek models
        self.addPricing("deepseek", "deepseek-chat", 0.14, 0.28);
        self.addPricing("deepseek", "deepseek-coder", 0.14, 0.28);

        // Mistral models
        self.addPricing("mistral", "mistral-large", 2.00, 6.00);
        self.addPricing("mistral", "mistral-small", 0.20, 0.60);

        // Cohere models
        self.addPricing("cohere", "command-r-plus", 3.00, 15.00);
        self.addPricing("cohere", "command-r", 0.50, 1.50);

        // Fireworks models
        self.addPricing("fireworks", "llama-v3-70b-instruct", 0.88, 2.64);
        self.addPricing("fireworks", "llama-v3-8b-instruct", 0.20, 0.20);

        // Perplexity models
        self.addPricing("perplexity", "llama-3.1-sonar-large-128k-online", 1.00, 1.00);
        self.addPricing("perplexity", "llama-3.1-sonar-small-128k-online", 0.20, 0.20);

        // Cerebras models
        self.addPricing("cerebras", "llama-3.1-8b", 0.10, 0.10);
        self.addPricing("cerebras", "llama-3.1-70b", 0.60, 0.60);
    }

    /// Add pricing for a model
    pub fn addPricing(self: *CostTracker, provider: []const u8, model: []const u8, input_cost: f64, output_cost: f64) void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ provider, model });
        self.pricing.put(key, .{
            .provider = self.allocator.dupe(u8, provider) catch return,
            .model = self.allocator.dupe(u8, model) catch return,
            .input_cost_per_mtok = input_cost,
            .output_cost_per_mtok = output_cost,
        }) catch return;
    }

    /// Get pricing for a model
    pub fn getPricing(self: *CostTracker, provider: []const u8, model: []const u8) ?*const ModelPricing {
        const key = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ provider, model }) catch return null;
        defer self.allocator.free(key);
        return self.pricing.get(key);
    }

    /// Calculate cost for a request
    pub fn calculateCost(self: *CostTracker, provider: []const u8, model: []const u8, prompt_tokens: u32, completion_tokens: u32) f64 {
        const pricing = self.getPricing(provider, model) orelse {
            // Default pricing if model not found (free)
            return 0.0;
        };

        const prompt_cost = @as(f64, @floatFromInt(prompt_tokens)) / 1_000_000.0 * pricing.input_cost_per_mtok;
        const completion_cost = @as(f64, @floatFromInt(completion_tokens)) / 1_000_000.0 * pricing.output_cost_per_mtok;

        return prompt_cost + completion_cost;
    }

    /// Calculate cost from usage (cost already computed in usage struct)
    pub fn calculateFromUsage(_: *CostTracker, usage: *const Usage) f64 {
        return usage.cost;
    }
};

pub const Usage = struct {
    prompt_tokens: u32,
    completion_tokens: u32,
    total_tokens: u32,
    cost: f64 = 0,
};

pub const SpendEntry = struct {
    timestamp: i64,
    key_id: []const u8,
    team_id: ?[]const u8,
    project_id: ?[]const u8,
    provider: []const u8,
    model: []const u8,
    prompt_tokens: u32,
    completion_tokens: u32,
    cost: f64,
};

pub const SpendTracker = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(SpendEntry),

    pub fn init(allocator: std.mem.Allocator) SpendTracker {
        return .{
            .allocator = allocator,
            .entries = std.ArrayList(SpendEntry).init(allocator),
        };
    }

    pub fn deinit(self: *SpendTracker) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.key_id);
            if (entry.team_id) |tid| self.allocator.free(tid);
            if (entry.project_id) |pid| self.allocator.free(pid);
            self.allocator.free(entry.provider);
            self.allocator.free(entry.model);
        }
        self.entries.deinit();
    }

    /// Record a spend entry
    pub fn record(self: *SpendTracker, entry: SpendEntry) !void {
        const copy = SpendEntry{
            .timestamp = entry.timestamp,
            .key_id = try self.allocator.dupe(u8, entry.key_id),
            .team_id = if (entry.team_id) |tid| try self.allocator.dupe(u8, tid) else null,
            .project_id = if (entry.project_id) |pid| try self.allocator.dupe(u8, pid) else null,
            .provider = try self.allocator.dupe(u8, entry.provider),
            .model = try self.allocator.dupe(u8, entry.model),
            .prompt_tokens = entry.prompt_tokens,
            .completion_tokens = entry.completion_tokens,
            .cost = entry.cost,
        };
        try self.entries.append(copy);
    }

    /// Get total spend for a key
    pub fn getTotalForKey(self: *SpendTracker, key_id: []const u8) f64 {
        var total: f64 = 0;
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.key_id, key_id)) {
                total += entry.cost;
            }
        }
        return total;
    }

    /// Get total spend for a team
    pub fn getTotalForTeam(self: *SpendTracker, team_id: []const u8) f64 {
        var total: f64 = 0;
        for (self.entries.items) |entry| {
            if (entry.team_id) |tid| {
                if (std.mem.eql(u8, tid, team_id)) {
                    total += entry.cost;
                }
            }
        }
        return total;
    }

    /// Get total spend for a project
    pub fn getTotalForProject(self: *SpendTracker, project_id: []const u8) f64 {
        var total: f64 = 0;
        for (self.entries.items) |entry| {
            if (entry.project_id) |pid| {
                if (std.mem.eql(u8, pid, project_id)) {
                    total += entry.cost;
                }
            }
        }
        return total;
    }

    /// Get spend entries for a key within time range
    pub fn getEntriesForKey(self: *SpendTracker, key_id: []const u8, start_time: i64, end_time: i64) []const SpendEntry {
        var result = std.ArrayList(SpendEntry).init(self.allocator);
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.key_id, key_id) and entry.timestamp >= start_time and entry.timestamp <= end_time) {
                result.append(entry) catch {};
            }
        }
        return result.toOwnedSlice();
    }

    /// Get daily spend breakdown
    pub fn getDailySpend(self: *SpendTracker, key_id: []const u8) []const struct { date: []const u8, cost: f64 } {
        var daily = std.StringArrayHashMap(f64).init(self.allocator);
        defer daily.deinit();

        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.key_id, key_id)) {
                const date = std.TimeTimestamp.format(entry.timestamp, "%Y-%m-%d") catch continue;
                const existing = daily.get(date) orelse 0;
                daily.put(date, existing + entry.cost) catch {};
            }
        }

        var result = std.ArrayList(struct { date: []const u8, cost: f64 }).init(self.allocator);
        var it = daily.iterator();
        while (it.next()) |entry| {
            result.append(.{ .date = entry.key_ptr.*, .cost = entry.value_ptr.* }) catch {};
        }
        return result.toOwnedSlice();
    }

    /// Get monthly spend breakdown
    pub fn getMonthlySpend(self: *SpendTracker, key_id: []const u8) []const struct { month: []const u8, cost: f64 } {
        var monthly = std.StringArrayHashMap(f64).init(self.allocator);
        defer monthly.deinit();

        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.key_id, key_id)) {
                const month = std.TimeTimestamp.format(entry.timestamp, "%Y-%m") catch continue;
                const existing = monthly.get(month) orelse 0;
                monthly.put(month, existing + entry.cost) catch {};
            }
        }

        var result = std.ArrayList(struct { month: []const u8, cost: f64 }).init(self.allocator);
        var it = monthly.iterator();
        while (it.next()) |entry| {
            result.append(.{ .month = entry.key_ptr.*, .cost = entry.value_ptr.* }) catch {};
        }
        return result.toOwnedSlice();
    }
};
