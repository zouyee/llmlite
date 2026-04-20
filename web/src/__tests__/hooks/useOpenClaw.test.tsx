import { describe, it, expect } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useOpenClawConfig, useUpdateOpenClawConfig } from '@/hooks/useOpenClaw'

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: false } },
})

const wrapper = ({ children }: { children: React.ReactNode }) => (
  <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
)

describe('useOpenClaw', () => {
  it('fetches config', async () => {
    const { result } = renderHook(() => useOpenClawConfig(), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data).toBeDefined()
    expect(result.current.data?.default_model).toBeDefined()
  })

  it('updates config', async () => {
    const { result } = renderHook(() => useUpdateOpenClawConfig(), { wrapper })
    const data = await result.current.mutateAsync({ temperature: 0.5 })
    expect(data).toBeDefined()
  })
})
