//! Request Logger for llmlite Proxy
//!
//! Logs all requests to file in JSON format for auditing and analytics

const std = @import("std");

pub const LogEntry = struct {
    timestamp: i64,
    method: []const u8,
    path: []const u8,
    status: u16,
    latency_ms: u64,
    virtual_key_id: ?[]const u8,
    model: ?[]const u8,
    provider: ?[]const u8,
    prompt_tokens: ?u32,
    completion_tokens: ?u32,
    total_tokens: ?u32,
    error_msg: ?[]const u8,
};

pub const RequestLogger = struct {
    allocator: std.mem.Allocator,
    log_file: ?std.fs.File,
    log_requests: bool,

    pub fn init(allocator: std.mem.Allocator, log_file_path: ?[]const u8, log_requests: bool) !RequestLogger {
        var log_file: ?std.fs.File = null;

        if (log_file_path) |path| {
            log_file = try std.fs.createFileAbsolute(path, .{ .truncate = false });
            // Write JSON array header
            try log_file.?.writeAll("[\n");
        }

        return .{
            .allocator = allocator,
            .log_file = log_file,
            .log_requests = log_requests,
        };
    }

    pub fn deinit(self: *RequestLogger) void {
        if (self.log_file) |*file| {
            // Write JSON array footer
            file.writeAll("\n]") catch {};
            file.close();
        }
    }

    /// Log a request entry
    pub fn log(self: *RequestLogger, entry: LogEntry) !void {
        if (!self.log_requests) return;
        if (self.log_file == null) return;

        // Simple JSON formatting without ArrayList
        const timestamp_str = try std.fmt.allocPrint(self.allocator, "{d}", .{entry.timestamp});
        defer self.allocator.free(timestamp_str);

        const latency_str = try std.fmt.allocPrint(self.allocator, "{d}", .{entry.latency_ms});
        defer self.allocator.free(latency_str);

        const prompt_tokens = if (entry.prompt_tokens) |v| try std.fmt.allocPrint(self.allocator, "{d}", .{v}) else null;
        defer if (prompt_tokens) |s| self.allocator.free(s);

        const completion_tokens = if (entry.completion_tokens) |v| try std.fmt.allocPrint(self.allocator, "{d}", .{v}) else null;
        defer if (completion_tokens) |s| self.allocator.free(s);

        const total_tokens = if (entry.total_tokens) |v| try std.fmt.allocPrint(self.allocator, "{d}", .{v}) else null;
        defer if (total_tokens) |s| self.allocator.free(s);

        const model_str = if (entry.model) |s| try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{s}) else "null";
        defer if (entry.model) |_| self.allocator.free(model_str);

        const vk_str = if (entry.virtual_key_id) |s| try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{s}) else "null";
        defer if (entry.virtual_key_id) |_| self.allocator.free(vk_str);

        const provider_str = if (entry.provider) |s| try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{s}) else "null";
        defer if (entry.provider) |_| self.allocator.free(provider_str);

        const error_str = if (entry.error_msg) |s| try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{s}) else "null";
        defer self.allocator.free(error_str);

        const json_line = try std.fmt.allocPrint(self.allocator,
            \\{{"timestamp":{s},"method":"{s}","path":"{s}","status":{d},"latency_ms":{s},"virtual_key_id":{s},"model":{s},"provider":{s},"prompt_tokens":{s},"completion_tokens":{s},"total_tokens":{s},"error":{s}}}
        , .{
            timestamp_str,
            entry.method,
            entry.path,
            entry.status,
            latency_str,
            vk_str,
            model_str,
            provider_str,
            if (prompt_tokens) |_| prompt_tokens.? else "null",
            if (completion_tokens) |_| completion_tokens.? else "null",
            if (total_tokens) |_| total_tokens.? else "null",
            error_str,
        });
        defer self.allocator.free(json_line);

        try self.log_file.?.writeAll(json_line);
        try self.log_file.?.writeAll(",\n");
    }

    /// Create a log entry builder
    pub fn LogBuilder(_: type) type {
        return struct {
            logger: *RequestLogger,
            entry: LogEntry,

            pub fn init(logger: *RequestLogger, method: []const u8, path: []const u8) @This() {
                return .{
                    .logger = logger,
                    .entry = .{
                        .timestamp = std.time.timestamp(),
                        .method = method,
                        .path = path,
                        .status = 0,
                        .latency_ms = 0,
                        .virtual_key_id = null,
                        .model = null,
                        .provider = null,
                        .prompt_tokens = null,
                        .completion_tokens = null,
                        .total_tokens = null,
                        .error_msg = null,
                    },
                };
            }

            pub fn withStatus(self: *@This(), status: u16) *@This() {
                self.entry.status = status;
                return self;
            }

            pub fn withLatency(self: *@This(), latency_ms: u64) *@This() {
                self.entry.latency_ms = latency_ms;
                return self;
            }

            pub fn withVirtualKey(self: *@This(), key_id: []const u8) *@This() {
                self.entry.virtual_key_id = key_id;
                return self;
            }

            pub fn withModel(self: *@This(), model: []const u8, provider: []const u8) *@This() {
                self.entry.model = model;
                self.entry.provider = provider;
                return self;
            }

            pub fn withUsage(self: *@This(), prompt: u32, completion: u32, total: u32) *@This() {
                self.entry.prompt_tokens = prompt;
                self.entry.completion_tokens = completion;
                self.entry.total_tokens = total;
                return self;
            }

            pub fn withError(self: *@This(), err: []const u8) *@This() {
                self.entry.error_msg = err;
                return self;
            }

            pub fn done(self: *@This()) !void {
                try self.logger.log(self.entry);
            }
        };
    }

    pub fn startLog(self: *RequestLogger, method: []const u8, path: []const u8) LogBuilder(@TypeOf(self.*)) {
        return LogBuilder(@TypeOf(self.*)).init(self, method, path);
    }
};

/// In-memory metrics collector
pub const MetricsCollector = struct {
    requests_total: u64 = 0,
    requests_success: u64 = 0,
    requests_error: u64 = 0,
    latency_sum_ms: u64 = 0,
    tokens_total: u64 = 0,

    pub fn recordRequest(self: *MetricsCollector, success: bool, latency_ms: u64, tokens: u32) void {
        self.requests_total += 1;
        if (success) {
            self.requests_success += 1;
        } else {
            self.requests_error += 1;
        }
        self.latency_sum_ms += latency_ms;
        self.tokens_total += tokens;
    }

    /// Get Prometheus-formatted metrics
    pub fn prometheusMetrics(self: *const MetricsCollector, uptime_seconds: u64) []const u8 {
        // Format metrics into a static buffer
        var buf: [512]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "# HELP llmlite_requests_total Total requests\n# TYPE llmlite_requests_total counter\nllmlite_requests_total {d}\n# HELP llmlite_requests_success Successful requests\n# TYPE llmlite_requests_success counter\nllmlite_requests_success {d}\n# HELP llmlite_requests_error Failed requests\n# TYPE llmlite_requests_error counter\nllmlite_requests_error {d}\n# HELP llmlite_latency_ms Request latency sum in milliseconds\n# TYPE llmlite_latency_ms counter\nllmlite_latency_ms_sum {d}\n# HELP llmlite_tokens_total Tokens processed\n# TYPE llmlite_tokens_total counter\nllmlite_tokens_total {d}\n# HELP llmlite_uptime_seconds Proxy uptime in seconds\n# TYPE llmlite_uptime_seconds gauge\nllmlite_uptime_seconds {d}\n", .{
            self.requests_total,
            self.requests_success,
            self.requests_error,
            self.latency_sum_ms,
            self.tokens_total,
            uptime_seconds,
        }) catch return "error formatting metrics";
        return result;
    }
};
