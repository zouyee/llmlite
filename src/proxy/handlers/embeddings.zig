//! Embeddings Handler for llmlite Proxy
//!
//! Handles /v1/embeddings requests

const std = @import("std");
const http = @import("../../http.zig");
const types = @import("../../provider/types.zig");
const registry = @import("../../provider/registry.zig");

pub const EmbeddingsHandler = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) EmbeddingsHandler {
        return .{ .allocator = allocator };
    }

    pub fn handle(self: *EmbeddingsHandler, request: *std.http.Server.Request, api_key: []const u8) !void {
        const body = try request.reader().readAllAlloc(self.allocator, 1_000_000);
        defer self.allocator.free(body);

        const embeddings_request = try std.json.parseFromSlice(
            EmbeddingsRequest,
            self.allocator,
            body,
            .{},
        );
        defer embeddings_request.deinit();

        std.log.info("embeddings: model={s}", .{embeddings_request.value.model});

        // Route to provider based on model
        const target = self.routeModel(embeddings_request.value.model);
        const response = try self.callProvider(&embeddings_request.value, target, api_key);

        try request.respond(.{
            .status = .ok,
            .content_type = .json,
            .body = response,
        });
    }

    fn routeModel(self: *EmbeddingsHandler, model: []const u8) EmbeddingsTarget {
        _ = self;
        // Check if model has provider prefix (e.g., "openai/text-embedding-ada-002")
        if (std.mem.indexOf(u8, model, "/")) |idx| {
            const provider_str = model[0..idx];
            const model_name = model[idx + 1 ..];
            if (types.ProviderType.fromString(provider_str)) |provider_type| {
                return .{ .provider = provider_type, .model = model_name };
            }
        }
        // Default to OpenAI
        return .{ .provider = .openai, .model = model };
    }

    fn callProvider(self: *EmbeddingsHandler, req: *const EmbeddingsRequest, target: EmbeddingsTarget, api_key: []const u8) ![]u8 {
        const provider_config = registry.getProviderConfig(target.provider);

        var client = http.HttpClient.initWithAuthType(
            self.allocator,
            provider_config.base_url,
            api_key,
            null,
            30000,
            provider_config.auth_type,
        );
        defer client.deinit();

        // Transform request to provider format
        const request_body = try self.transformRequest(target.provider, req);
        defer self.allocator.free(request_body);

        // Get endpoint
        const endpoint = switch (target.provider) {
            .google => try std.fmt.allocPrint(self.allocator, "/models/{s}:predict", .{target.model}),
            else => try self.allocator.dupe(u8, "/embeddings"),
        };
        defer self.allocator.free(endpoint);

        // Call provider
        const response = try client.post(endpoint, request_body);

        // Parse and convert response to OpenAI format
        const parsed = try self.parseResponse(target.provider, response);
        defer self.allocator.free(parsed);

        return parsed;
    }

    fn transformRequest(self: *EmbeddingsHandler, provider: types.ProviderType, req: *const EmbeddingsRequest) ![]u8 {
        return switch (provider) {
            .google => try self.transformGoogleRequest(req),
            else => try self.transformOpenAIRequest(req),
        };
    }

    fn transformOpenAIRequest(self: *EmbeddingsHandler, req: *const EmbeddingsRequest) ![]u8 {
        var input_json: []const u8 = undefined;

        switch (req.input) {
            .string => |s| {
                input_json = try std.json.Stringify.valueAlloc(self.allocator, s, .{});
            },
            .strings => |arr| {
                input_json = try std.json.Stringify.valueAlloc(self.allocator, arr, .{});
            },
        }
        defer self.allocator.free(input_json);

        return try std.fmt.allocPrint(self.allocator,
            \\{{"model":"{s}","input":{s},"encoding_format":"{s}"}}
        , .{
            req.model,
            input_json,
            req.encoding_format,
        });
    }

    fn transformGoogleRequest(self: *EmbeddingsHandler, req: *const EmbeddingsRequest) ![]u8 {
        var instances: []const u8 = undefined;

        switch (req.input) {
            .string => |s| {
                instances = try std.json.Stringify.valueAlloc(self.allocator, &.{.{ .content = s }}, .{});
            },
            .strings => |arr| {
                var instances_arr = std.array_list.Managed(struct { content: []const u8 }).init(self.allocator);
                defer instances_arr.deinit();
                for (arr) |s| {
                    instances_arr.append(.{ .content = s }) catch {};
                }
                instances = try std.json.Stringify.valueAlloc(self.allocator, instances_arr.items, .{});
            },
        }
        defer self.allocator.free(instances);

        return try std.fmt.allocPrint(self.allocator,
            \\{{"instances":{s},"model":"models/{s}"}}
        , .{
            instances,
            req.model,
        });
    }

    fn parseResponse(self: *EmbeddingsHandler, provider: types.ProviderType, response: []const u8) ![]u8 {
        return switch (provider) {
            .google => try self.parseGoogleResponse(response),
            else => try self.allocator.dupe(u8, response), // OpenAI format is already correct
        };
    }

    fn parseGoogleResponse(self: *EmbeddingsHandler, response: []const u8) ![]u8 {
        const parsed = try std.json.parseFromSlice(struct {
            predictions: []struct {
                embeddings: struct {
                    values: []f64,
                },
            },
        }, self.allocator, response, .{});
        defer parsed.deinit();

        var data_items = std.array_list.Managed(struct {
            object: []const u8,
            embedding: []f64,
            index: u32,
        }).init(self.allocator);
        defer {
            for (data_items.items) |item| {
                self.allocator.free(item.embedding);
            }
            data_items.deinit();
        }

        for (parsed.value.predictions, 0..) |pred, i| {
            const embedding = try self.allocator.alloc(f64, pred.embeddings.values.len);
            @memcpy(embedding, pred.embeddings.values);
            data_items.append(.{
                .object = "embedding",
                .embedding = embedding,
                .index = @intCast(i),
            }) catch {
                self.allocator.free(embedding);
            };
        }

        var total_tokens: u32 = 0;
        for (data_items.items) |item| {
            total_tokens += @intCast(item.embedding.len);
        }

        return std.json.Stringify.valueAlloc(self.allocator, .{
            .object = "list",
            .data = data_items.items,
            .model = "gemini-embedding",
            .usage = .{
                .prompt_tokens = total_tokens,
                .total_tokens = total_tokens,
            },
        }, .{});
    }
};

pub const EmbeddingsTarget = struct {
    provider: types.ProviderType,
    model: []const u8,
};

pub const EmbeddingsRequest = struct {
    model: []const u8,
    input: EmbeddingsInput,
    encoding_format: []const u8 = "float",
};

pub const EmbeddingsInput = union(enum) {
    string: []const u8,
    strings: [][]const u8,
};

pub const EmbeddingsResponse = struct {
    object: []const u8,
    data: []EmbeddingData,
    model: []const u8,
    usage: EmbeddingsUsage,
};

pub const EmbeddingData = struct {
    object: []const u8,
    embedding: []f32,
    index: u32,
};

pub const EmbeddingsUsage = struct {
    prompt_tokens: u32,
    total_tokens: u32,
};
