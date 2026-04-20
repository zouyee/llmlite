import { useTranslation } from 'react-i18next'
import { useTheme } from '@/hooks/useTheme'
import HealthStatus from '@/components/HealthStatus'

export default function TopBar() {
  const { t } = useTranslation()
  const { theme, toggleTheme } = useTheme()

  return (
    <header className="h-14 bg-gray-800 border-b border-gray-700 px-4 flex items-center justify-between">
      <div className="flex items-center gap-4">
        <h1 className="text-lg font-bold text-white">{t('app.title')}</h1>
      </div>

      <div className="flex items-center gap-3">
        <HealthStatus />

        <button
          onClick={toggleTheme}
          className="p-2 rounded-lg hover:bg-gray-700 text-gray-400 hover:text-white transition-colors"
          aria-label="Toggle theme"
          title={theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode'}
        >
          {theme === 'dark' ? '☀️' : '🌙'}
        </button>

        <select
          className="bg-gray-700 text-gray-200 text-sm rounded-lg px-3 py-2 border border-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
          defaultValue="en"
          onChange={(e) => {
            localStorage.setItem('llmlite_language', e.target.value)
            window.location.reload()
          }}
        >
          <option value="en">EN</option>
          <option value="zh">中文</option>
          <option value="ja">日本語</option>
        </select>
      </div>
    </header>
  )
}
