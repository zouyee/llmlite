import { describe, it, expect } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useSkills, useInstallSkill, useUninstallSkill, useUpdateSkill, useSkillRepos, useAddSkillRepo, useRemoveSkillRepo } from '@/hooks/useSkills'

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: false } },
})

const wrapper = ({ children }: { children: React.ReactNode }) => (
  <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
)

describe('useSkills', () => {
  it('fetches skills', async () => {
    const { result } = renderHook(() => useSkills(), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 })
    expect(Array.isArray(result.current.data)).toBe(true)
  })
})

describe('useInstallSkill', () => {
  it('installs a skill', async () => {
    const { result } = renderHook(() => useInstallSkill(), { wrapper })
    const data = await result.current.mutateAsync('skill-1')
    expect(data.installed).toBe(true)
  })
})

describe('useUninstallSkill', () => {
  it('uninstalls a skill', async () => {
    const { result } = renderHook(() => useUninstallSkill(), { wrapper })
    await expect(result.current.mutateAsync('skill-1')).resolves.toBeUndefined()
  })
})

describe('useUpdateSkill', () => {
  it('updates a skill', async () => {
    const { result } = renderHook(() => useUpdateSkill(), { wrapper })
    const data = await result.current.mutateAsync('skill-1')
    expect(data).toBeDefined()
  })
})

describe('useSkillRepos', () => {
  it('fetches repos', async () => {
    const { result } = renderHook(() => useSkillRepos(), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 })
    expect(Array.isArray(result.current.data)).toBe(true)
  })
})

describe('useAddSkillRepo', () => {
  it('adds a repo', async () => {
    const { result } = renderHook(() => useAddSkillRepo(), { wrapper })
    const data = await result.current.mutateAsync('https://example.com')
    expect(data).toBeDefined()
  })
})

describe('useRemoveSkillRepo', () => {
  it('removes a repo', async () => {
    const { result } = renderHook(() => useRemoveSkillRepo(), { wrapper })
    await expect(result.current.mutateAsync('repo-1')).resolves.toBeUndefined()
  })
})
