import { describe, it, expect } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useMcpServers, useCreateMcpServer, useDeleteMcpServer } from '@/hooks/useMcp'

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: false } },
})

const wrapper = ({ children }: { children: React.ReactNode }) => (
  <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
)

describe('useMcpServers', () => {
  it('fetches MCP servers', async () => {
    const { result } = renderHook(() => useMcpServers(), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 })
    expect(Array.isArray(result.current.data)).toBe(true)
  })
})

describe('useCreateMcpServer', () => {
  it('creates a server', async () => {
    const { result } = renderHook(() => useCreateMcpServer(), { wrapper })
    const data = await result.current.mutateAsync({
      name: 'Test',
      command: 'npx',
      args: ['test'],
      env: {},
      auto_start: true,
      enabled_for: [],
    })
    expect(data.id).toBeDefined()
  })
})

describe('useDeleteMcpServer', () => {
  it('deletes a server', async () => {
    const { result } = renderHook(() => useDeleteMcpServer(), { wrapper })
    await expect(result.current.mutateAsync('mcp-1')).resolves.toBeUndefined()
  })
})
