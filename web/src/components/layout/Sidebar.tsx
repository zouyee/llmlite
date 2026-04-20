import { useTranslation } from 'react-i18next'
import { Link, useLocation } from 'react-router-dom'
import { useAppStore, type ViewType } from '@/hooks/useAppStore'
import { cn } from '@/lib/utils'

const navItems: { key: ViewType; path: string; icon: string; labelKey: string }[] = [
  { key: 'providers', path: '/providers', icon: '⚡', labelKey: 'nav.providers' },
  { key: 'proxy', path: '/proxy', icon: '🔄', labelKey: 'nav.proxy' },
  { key: 'sessions', path: '/sessions', icon: '💬', labelKey: 'nav.sessions' },
  { key: 'mcp', path: '/mcp', icon: '🔧', labelKey: 'nav.mcp' },
  { key: 'skills', path: '/skills', icon: '⭐', labelKey: 'nav.skills' },
  { key: 'prompts', path: '/prompts', icon: '📝', labelKey: 'nav.prompts' },
  { key: 'usage', path: '/usage', icon: '📊', labelKey: 'nav.usage' },
  { key: 'workspace', path: '/workspace', icon: '📁', labelKey: 'nav.workspace' },
  { key: 'settings', path: '/settings', icon: '⚙️', labelKey: 'nav.settings' },
  { key: 'openclaw', path: '/openclaw', icon: '🦄', labelKey: 'nav.openclaw' },
]

export default function Sidebar() {
  const { t } = useTranslation()
  const { sidebarCollapsed, toggleSidebar } = useAppStore()
  const location = useLocation()

  return (
    <aside
      className={cn(
        'h-full bg-gray-800 border-r border-gray-700 transition-all duration-300 flex flex-col',
        sidebarCollapsed ? 'w-16' : 'w-64'
      )}
    >
      <div className="p-4 border-b border-gray-700 flex items-center justify-between">
        {!sidebarCollapsed && <span className="font-bold text-white">llmlite</span>}
        <button
          onClick={toggleSidebar}
          className="p-2 rounded-lg hover:bg-gray-700 text-gray-400 hover:text-white transition-colors"
          aria-label={sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}
        >
          {sidebarCollapsed ? '→' : '←'}
        </button>
      </div>

      <nav className="flex-1 py-4 overflow-y-auto">
        <ul className="space-y-1 px-2">
          {navItems.map(({ path, icon, labelKey }) => (
            <li key={path}>
              <Link
                to={path}
                className={cn(
                  'w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors',
                  location.pathname === path
                    ? 'bg-blue-600 text-white'
                    : 'text-gray-400 hover:text-white hover:bg-gray-700'
                )}
                title={sidebarCollapsed ? t(labelKey) : undefined}
              >
                <span className="text-lg">{icon}</span>
                {!sidebarCollapsed && <span>{t(labelKey)}</span>}
              </Link>
            </li>
          ))}
        </ul>
      </nav>

      {!sidebarCollapsed && (
        <div className="p-4 border-t border-gray-700">
          <div className="text-xs text-gray-500">llmlite v0.2.0</div>
        </div>
      )}
    </aside>
  )
}
