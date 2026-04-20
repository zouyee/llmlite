import { describe, it, expect } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useUsageOverview, useUsageTrends, useRequestLogs, useModelStats, useCostConfig } from '@/hooks/useUsage'

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: false } },
})

const wrapper = ({ children }: { children: React.ReactNode }) => (
  <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
)

describe('useUsage', () => {
  it('fetches overview', async () => {
    const { result } = renderHook(() => useUsageOverview(), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 })
    expect(typeof result.current.data?.total_requests).toBe('number')
  })

  it('fetches trends', async () => {
    const { result } = renderHook(() => useUsageTrends(), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 })
    expect(Array.isArray(result.current.data)).toBe(true)
  })

  it('fetches logs', async () => {
    const { result } = renderHook(() => useRequestLogs(), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 })
    expect(Array.isArray(result.current.data)).toBe(true)
  })

  it('fetches model stats', async () => {
    const { result } = renderHook(() => useModelStats(), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 })
    expect(Array.isArray(result.current.data)).toBe(true)
  })

  it('fetches cost config', async () => {
    const { result } = renderHook(() => useCostConfig(), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 })
    expect(Array.isArray(result.current.data)).toBe(true)
  })
})
