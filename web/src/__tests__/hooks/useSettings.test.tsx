import { describe, it, expect } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useSettingsTheme, useUpdateSettingsTheme, useSyncWebDAV, useExportBackup } from '@/hooks/useSettings'

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: false } },
})

const wrapper = ({ children }: { children: React.ReactNode }) => (
  <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
)

describe('useSettings', () => {
  it('fetches theme config', async () => {
    const { result } = renderHook(() => useSettingsTheme(), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 })
    expect(result.current.data?.theme).toBeDefined()
  })

  it('updates theme', async () => {
    const { result } = renderHook(() => useUpdateSettingsTheme(), { wrapper })
    await expect(result.current.mutateAsync({ theme: 'dark' })).resolves.toBeDefined()
  })

  it('syncs webdav', async () => {
    const { result } = renderHook(() => useSyncWebDAV(), { wrapper })
    await expect(result.current.mutateAsync()).resolves.toBeDefined()
  })

  it('exports backup', async () => {
    const { result } = renderHook(() => useExportBackup(), { wrapper })
    const data = await result.current.mutateAsync()
    expect(data.version).toBeDefined()
  })
})
