import { describe, it, expect } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useHealth } from '@/hooks/useHealth'

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: false } },
})

const wrapper = ({ children }: { children: React.ReactNode }) => (
  <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
)

describe('useHealth', () => {
  it('fetches health status', async () => {
    const { result } = renderHook(() => useHealth(), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 })
    expect(result.current.data?.status).toBeDefined()
  })
})
