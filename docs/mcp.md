# MCP Server Integration

llmlite provides an MCP (Model Context Protocol) server that exposes routing and management capabilities as tools for AI agents (e.g. Hermes Agent, Claude Code).

## Overview

The MCP protocol allows AI agents to:
- Query llmlite's router status
- Check provider health
- Manage virtual keys
- Monitor costs

## Source Structure

```
src/mcp/
├── server.zig    # MCP server implementation (JSON-RPC 2.0 over stdio)
├── tools.zig     # Tool definitions
└── types.zig     # MCP type definitions
```

## Available Tools

### `llmlite_router_status`

Get the current status of the edge router, including circuit breaker states.

**Response Example:**
```json
{
  "status": "operational",
  "circuit_breaker": {
    "openai": "closed",
    "anthropic": "closed",
    "google": "closed"
  },
  "latency_tracking": true
}
```

### `llmlite_health_check`

Check the health status of all configured LLM providers.

**Response Example:**
```json
{
  "providers": {
    "openai": "healthy",
    "anthropic": "healthy",
    "google": "healthy",
    "moonshot": "unknown",
    "minimax": "unknown",
    "deepseek": "unknown"
  }
}
```

### `llmlite_cost_summary`

Get cost summary for teams and models.

**Parameters:**
- `key_id` (optional): Filter by virtual key
- `team_id` (optional): Filter by team

**Response Example:**
```json
{
  "total_cost": 0,
  "by_team": {},
  "by_model": {}
}
```

### `llmlite_key_list`

List all virtual keys.

**Response Example:**
```json
{
  "keys": []
}
```

### `llmlite_key_create`

Create a new virtual key.

**Parameters:**
- `key_id` (required): The key ID to create
- `team_id` (optional): Team association

**Response Example:**
```json
{
  "key_id": "sk-hermes",
  "status": "created",
  "message": "Virtual key created"
}
```

### `llmlite_key_revoke`

Revoke an existing virtual key.

**Parameters:**
- `key_id` (required): The key ID to revoke

**Response Example:**
```json
{
  "key_id": "sk-hermes",
  "status": "revoked"
}
```

## Hermes Agent Configuration

Add llmlite as an MCP server in your Hermes configuration:

```yaml
# ~/.hermes/config.yaml
mcp_servers:
  llmlite:
    command: /path/to/llmlite-mcp
    tools:
      include:
        - llmlite_router_status
        - llmlite_health_check
        - llmlite_key_list
        - llmlite_key_create
        - llmlite_key_revoke
```

## JSON-RPC Protocol

The MCP server implements JSON-RPC 2.0 over stdio:

**Initialize Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocol_version": "2024-11-05",
    "capabilities": {},
    "client_info": {"name": "hermes", "version": "1.0.0"}
  }
}
```

**Tools/List Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list",
  "params": {}
}
```

**Tools/Call Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "llmlite_router_status",
    "arguments": {}
  }
}
```

## Health Endpoints for K8s

For container orchestration, llmlite-proxy provides:

| Endpoint | Purpose |
|----------|---------|
| `GET /health` | Basic health check |
| `GET /health/live` | Liveness probe (K8s) |
| `GET /health/ready` | Readiness probe (checks provider health) |
| `GET /metrics` | Prometheus metrics |
| `GET /metrics/latency` | Per-provider latency JSON |

## Example Usage

With Hermes Agent:

```
$ hermes
You: What providers are currently healthy?
→ Calling llmlite_health_check
← All major providers (OpenAI, Anthropic, Google) are healthy with low latency.

You: Create a new key for the research team
→ Calling llmlite_key_create with {"key_id": "sk-research", "team_id": "research"}
← Virtual key created: sk-research

You: What's our current spending?
→ Calling llmlite_cost_summary
← Total cost: $0.00 (no requests processed yet)
```

## Building the MCP Server

```bash
# Build the MCP server
zig build -Doptimize=ReleaseSmall

# Binary at:
# zig-out/bin/llmlite-mcp
```

## Proxy Health Endpoints (K8s)

For container orchestration, llmlite-proxy provides:

| Endpoint | Purpose |
|----------|---------|
| `GET /health` | Basic health check |
| `GET /health/live` | Liveness probe (K8s) |
| `GET /health/ready` | Readiness probe (checks provider health) |
| `GET /metrics` | Prometheus metrics |
| `GET /metrics/latency` | Per-provider latency JSON |
