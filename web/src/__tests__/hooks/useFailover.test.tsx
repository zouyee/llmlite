import { describe, it, expect } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useFailoverQueue, useFailoverConfig, useCircuitBreakerConfig } from '@/hooks/useFailover'

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: false } },
})

const wrapper = ({ children }: { children: React.ReactNode }) => (
  <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
)

describe('useFailover', () => {
  it('fetches failover queue', async () => {
    const { result } = renderHook(() => useFailoverQueue(), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 })
    expect(Array.isArray(result.current.data?.providers)).toBe(true)
  })

  it('fetches failover config', async () => {
    const { result } = renderHook(() => useFailoverConfig(), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 })
    expect(typeof result.current.data?.enabled).toBe('boolean')
  })

  it('fetches circuit breaker config', async () => {
    const { result } = renderHook(() => useCircuitBreakerConfig(), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 })
    expect(typeof result.current.data?.failure_threshold).toBe('number')
  })
})
