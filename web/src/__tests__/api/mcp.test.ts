import { describe, it, expect } from 'vitest'
import { mcpApi } from '@/lib/api/mcp'

describe('mcpApi', () => {
  it('lists servers', async () => {
    const data = await mcpApi.list()
    expect(Array.isArray(data)).toBe(true)
  })

  it('gets a server', async () => {
    const data = await mcpApi.get('mcp-1')
    expect(data.id).toBe('mcp-1')
  })

  it('creates a server', async () => {
    const data = await mcpApi.create({
      name: 'Test MCP',
      command: 'npx',
      args: ['test'],
      env: {},
      auto_start: true,
      enabled_for: ['claude_code'],
    })
    expect(data.id).toBeDefined()
  })

  it('updates a server', async () => {
    const data = await mcpApi.update('mcp-1', { name: 'Updated' })
    expect(data).toBeDefined()
  })

  it('deletes a server', async () => {
    await expect(mcpApi.delete('mcp-1')).resolves.toBeUndefined()
  })

  it('starts a server', async () => {
    await expect(mcpApi.start('mcp-1')).resolves.toBeUndefined()
  })

  it('stops a server', async () => {
    await expect(mcpApi.stop('mcp-1')).resolves.toBeUndefined()
  })

  it('restarts a server', async () => {
    await expect(mcpApi.restart('mcp-1')).resolves.toBeUndefined()
  })
})
