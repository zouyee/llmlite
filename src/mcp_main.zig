//! llmlite MCP Server - Main Entry Point
//!
//! Run as: zig build mcp && ./zig-out/bin/llmlite-mcp

const std = @import("std");
const mcp_server = @import("mcp_server");
const mcp_types = @import("mcp_types");
const mcp_tools = @import("mcp_tools");

pub fn main() !void {
    _ = mcp_types;
    _ = mcp_tools;

    // Initialize MCP server
    var server = mcp_server.Server.init(std.heap.page_allocator, "llmlite", "0.2.0");

    // Get stdin/stdout using direct POSIX I/O
    const stdin_handle: std.posix.fd_t = std.posix.STDIN_FILENO;
    const stdout_handle: std.posix.fd_t = std.posix.STDOUT_FILENO;

    // Buffer for reading
    var read_buffer: [8192]u8 = undefined;
    var line_buffer: [8192]u8 = undefined;
    var line_len: usize = 0;

    while (true) {
        // Read data from stdin
        const bytes_read = std.posix.read(stdin_handle, &read_buffer) catch break;

        if (bytes_read == 0) {
            // EOF - exit gracefully
            break;
        }

        // Process the read data - look for newline-delimited JSON
        var i: usize = 0;
        while (i < bytes_read) : (i += 1) {
            const byte = read_buffer[i];
            if (byte == '\n') {
                const request = line_buffer[0..line_len];
                line_len = 0;

                const trimmed = std.mem.trim(u8, request, " \t\r");
                if (trimmed.len == 0) continue;

                // Handle the request
                const response = server.handleRequest(trimmed) catch {
                    const err_resp = "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32603,\"message\":\"Internal error\"},\"id\":null}\n";
                    _ = std.posix.write(stdout_handle, err_resp) catch {};
                    continue;
                };

                // Write response
                _ = std.posix.write(stdout_handle, response) catch {};
                _ = std.posix.write(stdout_handle, "\n") catch {};

                // Check if this was a shutdown request
                if (std.mem.indexOf(u8, trimmed, "\"shutdown\"")) |_| {
                    break;
                }
            } else {
                if (line_len < line_buffer.len - 1) {
                    line_buffer[line_len] = byte;
                    line_len += 1;
                }
            }
        }
    }
}
