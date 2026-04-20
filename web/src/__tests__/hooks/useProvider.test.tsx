import { describe, it, expect } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useProviders, usePresets } from '@/hooks/useProvider'

const createWrapper = () => {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  })
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  )
}

describe('useProviders', () => {
  it('fetches providers', async () => {
    const wrapper = createWrapper()
    const { result } = renderHook(() => useProviders(), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 })
    expect(Array.isArray(result.current.data)).toBe(true)
    expect(result.current.data).toHaveLength(2)
    expect(result.current.data?.[0].id).toBe('openai')
  })
})

describe('usePresets', () => {
  it('fetches presets', async () => {
    const wrapper = createWrapper()
    const { result } = renderHook(() => usePresets(), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 })
    expect(Array.isArray(result.current.data)).toBe(true)
    expect(result.current.data).toHaveLength(1)
  })
})
