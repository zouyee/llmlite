const std = @import("std");
const builtin = @import("builtin");
const proxy = @import("proxy");
const tui = @import("tui");

pub fn main(init: std.process.Init) !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const io = init.io;

    // Parse --tui flag
    var use_tui = false;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--tui")) {
            use_tui = true;
            break;
        }
    }

    std.log.info("llmlite-proxy starting...", .{});

    // Initialize components
    var key_store = proxy.VirtualKeyStore.init(allocator);
    defer key_store.deinit();

    var rate_limiter = proxy.RateLimiter.init(allocator);
    defer rate_limiter.deinit();

    var request_logger = try proxy.RequestLogger.init(allocator, null, true);
    defer request_logger.deinit();

    var metrics = proxy.MetricsCollector{};

    // Add test API key
    try key_store.add("sk-test-key", .{
        .user_id = "test-user",
        .rate_limit = 100,
        .allowed_models = null,
    });

    std.log.info("Added test API key: sk-test-key", .{});
    std.log.info("Virtual Keys: enabled", .{});
    std.log.info("Multi-tenancy: disabled (set via config)", .{});
    std.log.info("Cost Tracking: disabled (set via config)", .{});
    std.log.info("Cache: disabled (set via config)", .{});
    std.log.info("KV Backend: memory (in-memory, zero dependency)", .{});

    const port = 4000;
    var server = try proxy.Server.init(
        allocator,
        io,
        port,
        &key_store,
        &rate_limiter,
        &request_logger,
        &metrics,
    );
    errdefer server.deinit();

    if (use_tui) {
        // Register SIGWINCH for terminal resize support
        if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
            const sa = std.posix.Sigaction{
                .handler = .{ .handler = tui.handleSigwinch },
                .mask = std.posix.sigemptyset(),
                .flags = std.posix.SA.RESTART,
            };
            std.posix.sigaction(std.posix.SIG.WINCH, &sa, null);
        }

        // Server runs in background thread
        const ServerCtx = struct {
            s: *proxy.Server,
            fn run(ctx: @This()) void {
                ctx.s.start() catch |err| {
                    std.log.err("server error: {}", .{err});
                };
            }
        };
        const server_thread = try std.Thread.spawn(.{}, ServerCtx.run, .{ServerCtx{ .s = &server }});

        // Give server a moment to start listening
        std.Io.sleep(io, std.Io.Duration.fromMilliseconds(200), .real) catch {};

        // TUI runs in main thread
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.Io.File.Writer.init(.stdout(), io, &stdout_buffer);
        const stdout = &stdout_writer.interface;
        var tui_instance = tui.Tui.init(allocator, io);
        defer tui_instance.deinit(stdout);

        tui_instance.state.latency_tracker = &server.latency_tracker;
        tui_instance.state.health_checker = &server.health_checker;
        tui_instance.state.circuit_breaker = &server.circuit_breaker;
        tui_instance.state.metrics = &metrics;
        tui_instance.state.is_service_running = true;

        tui_instance.enableRawMode(stdout) catch {
            std.log.warn("Failed to enable raw mode, running without TUI", .{});
            server.stop();
            server_thread.join();
            return;
        };

        // Run the new event loop (poll-based, no busy-wait)
        tui.runEventLoop(&tui_instance.state, stdout) catch |err| {
            std.log.err("TUI error: {}", .{err});
        };

        server.stop();
        server_thread.join();
    } else {
        std.log.info("llmlite-proxy listening on http://0.0.0.0:{d}", .{port});
        try server.start();
    }
}
