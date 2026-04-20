import { describe, it, expect } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useFileTree, useFileContent, useSaveFile, useDailyMemory, useSaveDailyMemory } from '@/hooks/useWorkspace'

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: false } },
})

const wrapper = ({ children }: { children: React.ReactNode }) => (
  <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
)

describe('useWorkspace', () => {
  it('fetches file tree', async () => {
    const { result } = renderHook(() => useFileTree(), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 })
    expect(Array.isArray(result.current.data)).toBe(true)
  })

  it('fetches file content', async () => {
    const { result } = renderHook(() => useFileContent('/README.md'), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 })
    expect(result.current.data?.content).toBeDefined()
  })

  it('saves file', async () => {
    const { result } = renderHook(() => useSaveFile(), { wrapper })
    await expect(result.current.mutateAsync({ path: '/test.txt', content: 'hello' })).resolves.toBeUndefined()
  })

  it('fetches daily memory', async () => {
    const { result } = renderHook(() => useDailyMemory('2024-01-01'), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 })
    expect(result.current.data?.content).toBeDefined()
  })

  it('saves daily memory', async () => {
    const { result } = renderHook(() => useSaveDailyMemory(), { wrapper })
    await expect(result.current.mutateAsync({ date: '2024-01-01', content: 'test' })).resolves.toBeUndefined()
  })
})
