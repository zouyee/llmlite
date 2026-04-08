const std = @import("std");

pub const HealthHandler = struct {
    pub fn handle(self: *HealthHandler, request: *std.http.Server.Request) !void {
        _ = self;
        const path = request.path();

        if (std.mem.eql(u8, path, "/health")) {
            try request.respond(.{
                .status = .ok,
                .content_type = .json,
                .body =
                \\{"status":"healthy","version":"0.2.0"}
                ,
            });
        } else if (std.mem.eql(u8, path, "/metrics")) {
            try request.respond(.{
                .status = .ok,
                .content_type = .text,
                .body =
                \\# HELP llmlite_requests_total Total requests
                \\# TYPE llmlite_requests_total counter
                \\llmlite_requests_total 0
                \\# HELP llmlite_proxy_up Proxy is running
                \\# TYPE llmlite_proxy_up gauge
                \\llmlite_proxy_up 1
                ,
            });
        } else {
            try request.respond(.{
                .status = .not_found,
                .content_type = .text,
                .body = "Not Found",
            });
        }
    }
};
