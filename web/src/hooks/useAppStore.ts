import { create } from 'zustand'

export type ViewType =
  | 'providers'
  | 'proxy'
  | 'sessions'
  | 'mcp'
  | 'skills'
  | 'prompts'
  | 'usage'
  | 'workspace'
  | 'settings'
  | 'openclaw'

interface AppState {
  currentView: ViewType
  sidebarCollapsed: boolean
  theme: 'dark' | 'light'
  setCurrentView: (view: ViewType) => void
  toggleSidebar: () => void
  setTheme: (theme: 'dark' | 'light') => void
}

export const useAppStore = create<AppState>((set) => ({
  currentView: 'providers',
  sidebarCollapsed: false,
  theme: 'dark',
  setCurrentView: (view) => set({ currentView: view }),
  toggleSidebar: () => set((state) => ({ sidebarCollapsed: !state.sidebarCollapsed })),
  setTheme: (theme) => set({ theme }),
}))
