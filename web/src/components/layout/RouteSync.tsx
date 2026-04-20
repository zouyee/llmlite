import { useEffect } from 'react'
import { useLocation } from 'react-router-dom'
import { useAppStore, type ViewType } from '@/hooks/useAppStore'

const pathToView: Record<string, ViewType> = {
  '/providers': 'providers',
  '/proxy': 'proxy',
  '/sessions': 'sessions',
  '/mcp': 'mcp',
  '/skills': 'skills',
  '/prompts': 'prompts',
  '/usage': 'usage',
  '/workspace': 'workspace',
  '/settings': 'settings',
  '/openclaw': 'openclaw',
}

export function RouteSync() {
  const location = useLocation()
  const setCurrentView = useAppStore((s) => s.setCurrentView)

  useEffect(() => {
    const view = pathToView[location.pathname]
    if (view) {
      setCurrentView(view)
    }
  }, [location.pathname, setCurrentView])

  return null
}
