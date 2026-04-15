//! MCP (Model Context Protocol) Type Definitions
//!
//! JSON-RPC 2.0 types and MCP-specific structures

const std = @import("std");

pub const JSONRPC_VERSION = "2.0";

/// JSON-RPC 2.0 Request - uses std.json.Value for flexible parsing
pub const JsonRpcRequest = struct {
    jsonrpc: []const u8 = JSONRPC_VERSION,
    id: ?std.json.Value = null,
    method: []const u8,
    params: ?std.json.Value = null,
};

/// JSON-RPC 2.0 Response - uses std.json.Value for flexible result
pub const JsonRpcResponse = struct {
    jsonrpc: []const u8 = JSONRPC_VERSION,
    id: ?std.json.Value = null,
    result: ?std.json.Value = null,
    err: ?JsonRpcError = null,
};

/// JSON-RPC 2.0 Error
pub const JsonRpcError = struct {
    code: i32,
    message: []const u8,
    data: ?std.json.Value = null,
};

/// MCP JSON-RPC Error Codes
pub const ErrorCodes = struct {
    pub const ParseError = -32700;
    pub const InvalidRequest = -32600;
    pub const MethodNotFound = -32601;
    pub const InvalidParams = -32602;
    pub const InternalError = -32603;
    pub const ServerNotInitialized = -32002;
    pub const ContentModified = -32003;
};

/// MCP Initialize result
pub const InitializeResult = struct {
    protocol_version: []const u8 = "2024-11-05",
    capabilities: Capabilities,
    server_info: ServerInfo,

    pub const Capabilities = struct {
        tools: ToolsCapability = .{},
        resources: ResourcesCapability = .{},
        prompts: PromptsCapability = .{},
    };

    pub const ToolsCapability = struct {};
    pub const ResourcesCapability = struct {
        subscribe: bool = false,
        list_changed: bool = false,
    };
    pub const PromptsCapability = struct {
        list_changed: bool = false,
    };

    pub const ServerInfo = struct {
        name: []const u8,
        version: []const u8,
    };
};

/// MCP Request methods
pub const Methods = struct {
    pub const Initialize = "initialize";
    pub const ToolsList = "tools/list";
    pub const ToolsCall = "tools/call";
    pub const ResourcesList = "resources/list";
    pub const ResourcesRead = "resources/read";
    pub const PromptsList = "prompts/list";
    pub const PromptsGet = "prompts/get";
    pub const Shutdown = "shutdown";
    pub const Ping = "ping";
};
