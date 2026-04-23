//! Test Infrastructure - Mock HTTP server and test utilities
//!
//! This module provides testing utilities for llmlite, including:
//! - Mock HTTP server for simulating API responses
//! - Test utilities for JSON parsing
//! - Response builders for different API endpoints

const std = @import("std");
const http = @import("http");

// ============================================================================
// Mock Server
// ============================================================================

pub const MockServer = struct {
    allocator: std.mem.Allocator,
    port: u16,
    responses: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, port: u16) MockServer {
        return .{
            .allocator = allocator,
            .port = port,
            .responses = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *MockServer) void {
        var it = self.responses.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.responses.deinit();
    }

    /// Register a response for a given path and method
    pub fn registerResponse(self: *MockServer, method: []const u8, path: []const u8, response: []const u8) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ method, path });
        errdefer self.allocator.free(key);
        try self.responses.put(key, response);
    }

    /// Register a chat completion response
    pub fn registerChatCompletion(self: *MockServer, response: []const u8) !void {
        try self.registerResponse("POST", "/chat/completions", response);
    }

    /// Register a models list response
    pub fn registerModelsList(self: *MockServer, response: []const u8) !void {
        try self.registerResponse("GET", "/models", response);
    }

    /// Register an embeddings response
    pub fn registerEmbeddings(self: *MockServer, response: []const u8) !void {
        try self.registerResponse("POST", "/embeddings", response);
    }
};

// ============================================================================
// Test Response Builders
// ============================================================================

pub const ResponseBuilder = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ResponseBuilder {
        return .{ .allocator = allocator };
    }

    /// Build a chat completion response
    pub fn chatCompletion(self: *ResponseBuilder, id: []const u8, model: []const u8, content: []const u8) ![]u8 {
        const json = try std.fmt.allocPrint(self.allocator,
            \\{{"id":"{s}","object":"chat.completion","created":1234567890,"model":"{s}","choices":[{{"index":0,"message":{{"role":"assistant","content":"{s}"}},"finish_reason":"stop"}}],"usage":{{"prompt_tokens":10,"completion_tokens":20,"total_tokens":30}}}
        , .{ id, model, content });
        return json;
    }

    /// Build a models list response
    pub fn modelsList(self: *ResponseBuilder) ![]u8 {
        const json = try std.fmt.allocPrint(self.allocator,
            \\{{"object":"list","data":[{{"id":"gpt-4o","object":"model","created":1234567890,"owned_by":"openai"}},{{"id":"gpt-4o-mini","object":"model","created":1234567890,"owned_by":"openai"}}]}}
        , .{});
        return json;
    }

    /// Build an embeddings response
    pub fn embeddings(self: *ResponseBuilder, input: []const u8) ![]u8 {
        const json = try std.fmt.allocPrint(self.allocator,
            \\{{"object":"list","data":[{{"object":"embedding","embedding":[0.1,0.2,0.3],"index":0}}],"model":"text-embedding-3-small","usage":{{"prompt_tokens":5,"total_tokens":5}}}
        , .{input});
        return json;
    }

    /// Build a completion response
    pub fn completion(self: *ResponseBuilder, id: []const u8, text: []const u8) ![]u8 {
        const json = try std.fmt.allocPrint(self.allocator,
            \\{{"id":"{s}","object":"text_completion","created":1234567890,"model":"gpt-3.5-turbo-instruct","choices":[{{"text":"{s}","index":0,"finish_reason":"stop"}}],"usage":{{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}}
        , .{ id, text });
        return json;
    }

    /// Build a file response
    pub fn fileObject(self: *ResponseBuilder, id: []const u8, filename: []const u8) ![]u8 {
        const json = try std.fmt.allocPrint(self.allocator,
            \\{{"id":"{s}","object":"file","bytes":100,"created_at":1234567890,"filename":"{s}","purpose":"fine-tune"}}
        , .{ id, filename });
        return json;
    }

    /// Build an error response
    pub fn errorResponse(self: *ResponseBuilder, code: []const u8, message: []const u8) ![]u8 {
        const json = try std.fmt.allocPrint(self.allocator,
            \\{{"error":{{"code":"{s}","message":"{s}"}}}}
        , .{ code, message });
        return json;
    }
};

// ============================================================================
// Test Assertions
// ============================================================================

pub const Assert = struct {
    /// Assert two strings are equal
    pub fn stringsEqual(a: []const u8, b: []const u8) !void {
        if (!std.mem.eql(u8, a, b)) {
            return error.NotEqual;
        }
    }

    /// Assert a JSON string contains a field
    pub fn jsonHasField(self: *ResponseBuilder, json_str: []const u8, field: []const u8) !void {
        _ = self;
        if (std.mem.find(u8, json_str, field) == null) {
            return error.FieldNotFound;
        }
    }

    /// Assert parsing succeeds
    pub fn validJson(_: *ResponseBuilder, json_str: []const u8) !void {
        var parser = std.json.Parser.init(std.heap.page_allocator, .{});
        defer parser.deinit();
        _ = try parser.parse(json_str);
    }
};

// ============================================================================
// Test HTTP Client
// ============================================================================

pub const TestHttpClient = struct {
    allocator: std.mem.Allocator,
    mock: *MockServer,
    last_request: std.ArrayListUnmanaged(u8),

    pub fn init(allocator: std.mem.Allocator, mock: *MockServer) TestHttpClient {
        return .{
            .allocator = allocator,
            .mock = mock,
            .last_request = .empty,
        };
    }

    pub fn deinit(self: *TestHttpClient) void {
        self.last_request.deinit(self.allocator);
    }

    pub fn post(self: *TestHttpClient, path: []const u8, body: []const u8) ![]u8 {
        // Store last request for inspection
        try self.last_request.resize(self.allocator, body.len);
        @memcpy(self.last_request.items, body);

        // Look up mock response
        const key = try std.fmt.allocPrint(self.allocator, "POST:{s}", .{path});
        defer self.allocator.free(key);

        const response = self.mock.responses.get(key) orelse {
            return error.NotFound;
        };

        return try self.allocator.dupe(u8, response);
    }

    pub fn get(self: *TestHttpClient, path: []const u8) ![]u8 {
        const key = try std.fmt.allocPrint(self.allocator, "GET:{s}", .{path});
        defer self.allocator.free(key);

        const response = self.mock.responses.get(key) orelse {
            return error.NotFound;
        };

        return try self.allocator.dupe(u8, response);
    }

    pub fn delete(self: *TestHttpClient, path: []const u8) ![]u8 {
        const key = try std.fmt.allocPrint(self.allocator, "DELETE:{s}", .{path});
        defer self.allocator.free(key);

        const response = self.mock.responses.get(key) orelse {
            return error.NotFound;
        };

        return try self.allocator.dupe(u8, response);
    }
};
