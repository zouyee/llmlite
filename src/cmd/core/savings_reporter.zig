//! Savings Reporter - Async savings report upload to llmlite-proxy
//!
//! Fire-and-forget HTTP POST with local file fallback queue.

const std = @import("std");
const shared = @import("shared_analytics");

pub const SavingsReporter = struct {
    allocator: std.mem.Allocator,
    proxy_host: []const u8,
    proxy_port: u16,
    proxy_online: bool,
    queue_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) !SavingsReporter {
        const queue_path = try getQueuePath(allocator);
        errdefer allocator.free(queue_path);

        var reporter = SavingsReporter{
            .allocator = allocator,
            .proxy_host = try allocator.dupe(u8, host),
            .proxy_port = port,
            .proxy_online = false,
            .queue_path = queue_path,
        };

        // Initial probe
        reporter.proxy_online = reporter.probe();
        return reporter;
    }

    pub fn deinit(self: *SavingsReporter) void {
        self.allocator.free(self.proxy_host);
        self.allocator.free(self.queue_path);
    }

    /// Probe proxy health with 50ms timeout (best-effort, non-blocking)
    pub fn probe(self: *SavingsReporter) bool {
        const Ctx = struct {
            event: std.Thread.ResetEvent = .{},
            result: bool = false,
        };
        var ctx: Ctx = .{};

        const thread = std.Thread.spawn(.{}, struct {
            fn f(c: *Ctx, reporter: *SavingsReporter) void {
                c.result = reporter.probeImpl();
                c.event.set();
            }
        }.f, .{ &ctx, self }) catch return false;

        ctx.event.timedWait(50_000_000) catch {
            thread.detach();
            return false;
        };
        thread.join();
        return ctx.result;
    }

    fn probeImpl(self: *SavingsReporter) bool {
        const url_str = std.fmt.allocPrint(self.allocator, "http://{s}:{d}/health/live", .{ self.proxy_host, self.proxy_port }) catch return false;
        defer self.allocator.free(url_str);

        const uri = std.Uri.parse(url_str) catch return false;
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var response_writer = std.io.Writer.Allocating.init(self.allocator);
        defer response_writer.deinit();

        const response = client.fetch(.{
            .location = .{ .uri = uri },
            .method = .GET,
            .response_writer = &response_writer.writer,
        }) catch return false;

        return response.status == .ok;
    }

    /// Spawn a fire-and-forget thread to send the report.
    /// Deep-copies string fields before spawning so the thread owns its memory.
    pub fn reportAsync(self: *SavingsReporter, report: shared.SavingsReport) void {
        const owned_cmd = self.allocator.dupe(u8, report.original_cmd) catch return;
        const owned_hostname = self.allocator.dupe(u8, report.hostname) catch {
            self.allocator.free(owned_cmd);
            return;
        };
        var owned_report = report;
        owned_report.original_cmd = owned_cmd;
        owned_report.hostname = owned_hostname;

        _ = std.Thread.spawn(.{}, asyncSendReportOwned, .{ self, owned_report }) catch |err| {
            self.allocator.free(owned_cmd);
            self.allocator.free(owned_hostname);
            std.log.warn("failed to spawn savings report thread: {}", .{err});
        };
    }

    fn asyncSendReportOwned(self: *SavingsReporter, report: shared.SavingsReport) void {
        defer {
            self.allocator.free(report.original_cmd);
            self.allocator.free(report.hostname);
        }

        sendReport(self, report) catch |err| {
            std.log.debug("savings report failed, queued: {}", .{err});
            enqueueLocal(self, report) catch {};
        };
        retryPending(self) catch {};
    }

    fn sendReport(self: *SavingsReporter, report: shared.SavingsReport) !void {
        const json_body = try shared.serializeSavingsReport(self.allocator, report);
        defer self.allocator.free(json_body);

        const url_str = try std.fmt.allocPrint(self.allocator, "http://{s}:{d}/tracking/savings", .{ self.proxy_host, self.proxy_port });
        defer self.allocator.free(url_str);

        const uri = std.Uri.parse(url_str) catch return error.ConnectionRefused;
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var response_writer = std.io.Writer.Allocating.init(self.allocator);
        defer response_writer.deinit();

        const response = client.fetch(.{
            .location = .{ .uri = uri },
            .method = .POST,
            .headers = .{ .content_type = .{ .override = "application/json" } },
            .payload = json_body,
            .response_writer = &response_writer.writer,
        }) catch return error.ConnectionRefused;

        if (response.status != .ok) {
            return error.UploadFailed;
        }
    }

    fn enqueueLocal(self: *SavingsReporter, report: shared.SavingsReport) !void {
        const json_body = try shared.serializeSavingsReport(self.allocator, report);
        defer self.allocator.free(json_body);

        var file = std.fs.openFileAbsolute(self.queue_path, .{ .mode = .write_only }) catch |err| {
            if (err == error.FileNotFound) {
                const new_file = try std.fs.createFileAbsolute(self.queue_path, .{});
                defer new_file.close();
                try new_file.writeAll(json_body);
                try new_file.writeAll("\n");
                return;
            }
            return err;
        };
        defer file.close();
        try file.seekFromEnd(0);
        try file.writeAll(json_body);
        try file.writeAll("\n");
    }

    fn retryPending(self: *SavingsReporter) !void {
        const file = std.fs.openFileAbsolute(self.queue_path, .{ .mode = .read_only }) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        defer file.close();

        var buf: [4096]u8 = undefined;
        var content = std.array_list.Managed(u8).init(self.allocator);
        defer content.deinit();

        while (true) {
            const bytes_read = try file.read(&buf);
            if (bytes_read == 0) break;
            try content.appendSlice(buf[0..bytes_read]);
        }

        if (content.items.len == 0) return;

        // Try to resend each line; collect failures for re-queue
        var failed = std.array_list.Managed([]const u8).init(self.allocator);
        defer {
            for (failed.items) |f| self.allocator.free(f);
            failed.deinit();
        }

        var line_iter = std.mem.splitScalar(u8, content.items, '\n');
        while (line_iter.next()) |line| {
            if (line.len == 0) continue;
            const report = shared.parseSavingsReport(self.allocator, line) catch {
                continue; // skip corrupt lines
            };
            defer {
                self.allocator.free(report.original_cmd);
                self.allocator.free(report.hostname);
            }

            sendReport(self, report) catch {
                try failed.append(try self.allocator.dupe(u8, line));
            };
        }

        // Rewrite queue with only failed items
        var out_file = try std.fs.createFileAbsolute(self.queue_path, .{});
        defer out_file.close();
        for (failed.items) |line| {
            try out_file.writeAll(line);
            try out_file.writeAll("\n");
        }
    }
};

fn getQueuePath(allocator: std.mem.Allocator) ![]const u8 {
    const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch {
        return try allocator.dupe(u8, "/tmp/llmlite_pending_reports.jsonl");
    };
    defer allocator.free(home_dir);

    const data_dir = try std.fmt.allocPrint(allocator, "{s}/.local/share/llmlite", .{home_dir});
    defer allocator.free(data_dir);

    std.fs.makeDirAbsolute(data_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    return try std.fmt.allocPrint(allocator, "{s}/pending_reports.jsonl", .{data_dir});
}

// ============================================================================
// Unit Tests
// ============================================================================

test "SavingsReporter probe returns false when no proxy" {
    const allocator = std.testing.allocator;

    // Use an invalid port to guarantee no server is listening
    var reporter = SavingsReporter{
        .allocator = allocator,
        .proxy_host = try allocator.dupe(u8, "127.0.0.1"),
        .proxy_port = 1, // Invalid port
        .proxy_online = false,
        .queue_path = try allocator.dupe(u8, "/tmp/test_probe_queue.jsonl"),
    };
    defer {
        allocator.free(reporter.proxy_host);
        allocator.free(reporter.queue_path);
    }

    // Probe should fail/timeout quickly (50ms max)
    const result = reporter.probe();
    try std.testing.expect(!result);
}

test "SavingsReporter enqueueLocal writes valid JSON" {
    const allocator = std.testing.allocator;

    const tmp_path = "/tmp/test_enqueue_queue.jsonl";
    // Clean up any leftover
    std.fs.deleteFileAbsolute(tmp_path) catch {};

    var reporter = SavingsReporter{
        .allocator = allocator,
        .proxy_host = try allocator.dupe(u8, "localhost"),
        .proxy_port = 4001,
        .proxy_online = false,
        .queue_path = try allocator.dupe(u8, tmp_path),
    };
    defer {
        allocator.free(reporter.proxy_host);
        allocator.free(reporter.queue_path);
        std.fs.deleteFileAbsolute(tmp_path) catch {};
    }

    const report = shared.SavingsReport{
        .timestamp = 1700000000,
        .original_cmd = "git status",
        .raw_output_tokens = 1000,
        .filtered_output_tokens = 400,
        .saved_tokens = 600,
        .savings_pct = 60.0,
        .exit_code = 0,
        .hostname = "test-host",
    };

    // First write (creates file)
    try reporter.enqueueLocal(report);

    // Second write (appends)
    try reporter.enqueueLocal(report);

    // Read back and verify
    const file = try std.fs.openFileAbsolute(tmp_path, .{ .mode = .read_only });
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(content);

    // Should have 2 lines
    var line_count: usize = 0;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        line_count += 1;

        // Each line should be valid JSON that parses
        const parsed = try shared.parseSavingsReport(allocator, line);
        defer {
            allocator.free(parsed.original_cmd);
            allocator.free(parsed.hostname);
        }
        try std.testing.expectEqualStrings("git status", parsed.original_cmd);
        try std.testing.expectEqualStrings("test-host", parsed.hostname);
        try std.testing.expectEqual(@as(u64, 600), parsed.saved_tokens);
    }
    try std.testing.expectEqual(@as(usize, 2), line_count);
}

test "SavingsReporter retryPending with empty queue is no-op" {
    const allocator = std.testing.allocator;

    const tmp_path = "/tmp/test_retry_empty_queue.jsonl";
    // Ensure file does not exist
    std.fs.deleteFileAbsolute(tmp_path) catch {};

    var reporter = SavingsReporter{
        .allocator = allocator,
        .proxy_host = try allocator.dupe(u8, "localhost"),
        .proxy_port = 4001,
        .proxy_online = false,
        .queue_path = try allocator.dupe(u8, tmp_path),
    };
    defer {
        allocator.free(reporter.proxy_host);
        allocator.free(reporter.queue_path);
    }

    // Should not error when queue file doesn't exist
    try reporter.retryPending();
}

test "SavingsReporter retryPending rewrites failed items" {
    const allocator = std.testing.allocator;

    const tmp_path = "/tmp/test_retry_rewrite_queue.jsonl";
    std.fs.deleteFileAbsolute(tmp_path) catch {};

    var reporter = SavingsReporter{
        .allocator = allocator,
        .proxy_host = try allocator.dupe(u8, "127.0.0.1"),
        .proxy_port = 1, // Invalid port so sendReport always fails
        .proxy_online = false,
        .queue_path = try allocator.dupe(u8, tmp_path),
    };
    defer {
        allocator.free(reporter.proxy_host);
        allocator.free(reporter.queue_path);
        std.fs.deleteFileAbsolute(tmp_path) catch {};
    }

    const report = shared.SavingsReport{
        .timestamp = 1700000000,
        .original_cmd = "git status",
        .raw_output_tokens = 1000,
        .filtered_output_tokens = 400,
        .saved_tokens = 600,
        .savings_pct = 60.0,
        .exit_code = 0,
        .hostname = "test-host",
    };

    // Pre-populate queue with a valid report
    try reporter.enqueueLocal(report);

    // Retry should read, try to send (fail), and rewrite the queue
    try reporter.retryPending();

    // Verify queue still has the report (since send fails)
    const file = try std.fs.openFileAbsolute(tmp_path, .{ .mode = .read_only });
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(content);

    var line_count: usize = 0;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        line_count += 1;

        const parsed = try shared.parseSavingsReport(allocator, line);
        defer {
            allocator.free(parsed.original_cmd);
            allocator.free(parsed.hostname);
        }
        try std.testing.expectEqualStrings("git status", parsed.original_cmd);
    }
    try std.testing.expectEqual(@as(usize, 1), line_count);
}
