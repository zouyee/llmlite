import { describe, it, expect } from 'vitest'
import { useAppStore } from '@/hooks/useAppStore'

describe('useAppStore', () => {
  it('has default state', () => {
    const state = useAppStore.getState()
    expect(state.currentView).toBe('providers')
    expect(state.sidebarCollapsed).toBe(false)
    expect(state.theme).toBe('dark')
  })

  it('sets current view', () => {
    useAppStore.getState().setCurrentView('settings')
    expect(useAppStore.getState().currentView).toBe('settings')
    useAppStore.getState().setCurrentView('providers')
  })

  it('toggles sidebar', () => {
    const initial = useAppStore.getState().sidebarCollapsed
    useAppStore.getState().toggleSidebar()
    expect(useAppStore.getState().sidebarCollapsed).toBe(!initial)
    useAppStore.getState().toggleSidebar()
    expect(useAppStore.getState().sidebarCollapsed).toBe(initial)
  })

  it('sets theme', () => {
    useAppStore.getState().setTheme('light')
    expect(useAppStore.getState().theme).toBe('light')
    useAppStore.getState().setTheme('dark')
  })
})
