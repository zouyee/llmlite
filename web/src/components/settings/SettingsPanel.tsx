import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useQuery, useMutation } from '@tanstack/react-query'
import { configApi } from '@/lib/api/llmlite'
import toast from 'react-hot-toast'

export default function SettingsPanel() {
  const { t, i18n } = useTranslation()
  const [apiKey, setApiKey] = useState(localStorage.getItem('llmlite_api_key') || '')

  const { data: config } = useQuery({
    queryKey: ['config'],
    queryFn: configApi.get,
  })

  const updateConfig = useMutation({
    mutationFn: configApi.update,
    onSuccess: () => {
      toast.success('Settings saved')
    },
    onError: () => {
      toast.error('Failed to save settings')
    },
  })

  const reloadConfig = useMutation({
    mutationFn: configApi.reload,
    onSuccess: () => {
      toast.success('Config reloaded')
    },
    onError: () => {
      toast.error('Failed to reload config')
    },
  })

  const handleSaveApiKey = () => {
    localStorage.setItem('llmlite_api_key', apiKey)
    toast.success('API Key saved')
  }

  const handleLanguageChange = (lang: string) => {
    i18n.changeLanguage(lang)
    localStorage.setItem('llmlite_language', lang)
  }

  return (
    <div className="max-w-2xl">
      <h2 className="text-lg font-medium mb-4">{t('settings.title')}</h2>

      <div className="space-y-6">
        <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
          <h3 className="font-medium mb-3">{t('settings.apiKey')}</h3>
          <div className="flex gap-2">
            <input
              type="password"
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              placeholder="sk-..."
              className="flex-1 px-4 py-2 bg-gray-900 border border-gray-700 rounded-lg text-white placeholder-gray-500 focus:outline-none focus:border-blue-500"
            />
            <button
              onClick={handleSaveApiKey}
              className="px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded-lg"
            >
              {t('settings.save')}
            </button>
          </div>
        </div>

        {config && (
          <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <h3 className="font-medium mb-3">Proxy Configuration</h3>
            <div className="grid gap-4">
              <div>
                <label className="block text-sm text-gray-400 mb-1">{t('settings.port')}</label>
                <input
                  type="number"
                  value={config.port}
                  onChange={(e) =>
                    updateConfig.mutate({ port: parseInt(e.target.value) })
                  }
                  className="w-full px-4 py-2 bg-gray-900 border border-gray-700 rounded-lg text-white focus:outline-none focus:border-blue-500"
                />
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-gray-300">Connection Pool</span>
                <button
                  onClick={() =>
                    updateConfig.mutate({ enable_connection_pool: !config.enable_connection_pool })
                  }
                  className={`px-4 py-1 rounded ${
                    config.enable_connection_pool ? 'bg-green-600' : 'bg-gray-700'
                  }`}
                >
                  {config.enable_connection_pool ? 'ON' : 'OFF'}
                </button>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-gray-300">Health Checker</span>
                <button
                  onClick={() =>
                    updateConfig.mutate({ enable_health_checker: !config.enable_health_checker })
                  }
                  className={`px-4 py-1 rounded ${
                    config.enable_health_checker ? 'bg-green-600' : 'bg-gray-700'
                  }`}
                >
                  {config.enable_health_checker ? 'ON' : 'OFF'}
                </button>
              </div>
              <div>
                <label className="block text-sm text-gray-400 mb-1">Health Check Interval (ms)</label>
                <input
                  type="number"
                  value={config.health_check_interval_ms}
                  onChange={(e) =>
                    updateConfig.mutate({ health_check_interval_ms: parseInt(e.target.value) })
                  }
                  className="w-full px-4 py-2 bg-gray-900 border border-gray-700 rounded-lg text-white focus:outline-none focus:border-blue-500"
                />
              </div>
            </div>
            <button
              onClick={() => reloadConfig.mutate()}
              className="mt-4 px-4 py-2 bg-yellow-600 hover:bg-yellow-500 rounded-lg"
            >
              {t('settings.reload')}
            </button>
          </div>
        )}

        <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
          <h3 className="font-medium mb-3">Language</h3>
          <div className="flex gap-2">
            {['en', 'zh', 'ja'].map((lang) => (
              <button
                key={lang}
                onClick={() => handleLanguageChange(lang)}
                className={`px-4 py-2 rounded-lg ${
                  i18n.language === lang ? 'bg-blue-600' : 'bg-gray-700 hover:bg-gray-600'
                }`}
              >
                {lang === 'en' ? 'English' : lang === 'zh' ? '中文' : '日本語'}
              </button>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}
