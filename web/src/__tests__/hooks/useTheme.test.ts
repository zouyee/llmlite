import { describe, it, expect, beforeEach } from 'vitest'
import { renderHook, act } from '@testing-library/react'
import { useTheme } from '@/hooks/useTheme'
import { useAppStore } from '@/hooks/useAppStore'

describe('useTheme', () => {
  beforeEach(() => {
    useAppStore.setState({ theme: 'dark' })
  })

  it('returns current theme from store', () => {
    const { result } = renderHook(() => useTheme())
    expect(result.current.theme).toBe('dark')
  })

  it('toggles theme', () => {
    const { result } = renderHook(() => useTheme())
    act(() => {
      result.current.toggleTheme()
    })
    expect(useAppStore.getState().theme).toBe('light')
    act(() => {
      result.current.toggleTheme()
    })
    expect(useAppStore.getState().theme).toBe('dark')
  })

  it('sets theme directly', () => {
    const { result } = renderHook(() => useTheme())
    act(() => {
      result.current.setTheme('light')
    })
    expect(useAppStore.getState().theme).toBe('light')
  })
})
