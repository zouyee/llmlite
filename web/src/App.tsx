import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Toaster } from 'react-hot-toast'
import ProviderList from './components/providers/ProviderList'
import McpServerList from './components/mcp/McpServerList'
import SessionList from './components/sessions/SessionList'
import SettingsPanel from './components/settings/SettingsPanel'
import HealthStatus from './components/HealthStatus'

type View = 'providers' | 'mcp' | 'sessions' | 'settings'

function App() {
  const { t } = useTranslation()
  const [currentView, setCurrentView] = useState<View>('providers')

  const navItems: { key: View; label: string }[] = [
    { key: 'providers', label: t('nav.providers') },
    { key: 'mcp', label: t('nav.mcp') },
    { key: 'sessions', label: t('nav.sessions') },
    { key: 'settings', label: t('nav.settings') },
  ]

  return (
    <div className="min-h-screen bg-gray-900 text-gray-100">
      <Toaster position="top-right" />

      <header className="bg-gray-800 border-b border-gray-700 px-4 py-3">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-bold text-white">{t('app.title')}</h1>
          <HealthStatus />
        </div>

        <nav className="flex gap-1 mt-3">
          {navItems.map(({ key, label }) => (
            <button
              key={key}
              onClick={() => setCurrentView(key)}
              className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                currentView === key
                  ? 'bg-blue-600 text-white'
                  : 'text-gray-400 hover:text-white hover:bg-gray-700'
              }`}
            >
              {label}
            </button>
          ))}
        </nav>
      </header>

      <main className="p-4">
        {currentView === 'providers' && <ProviderList />}
        {currentView === 'mcp' && <McpServerList />}
        {currentView === 'sessions' && <SessionList />}
        {currentView === 'settings' && <SettingsPanel />}
      </main>
    </div>
  )
}

export default App
