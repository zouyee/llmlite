import { useState, useEffect } from 'react'
import { useTranslation } from 'react-i18next'
import { useAppStore } from '@/hooks/useAppStore'
import { useSettingsTheme, useUpdateSettingsTheme } from '@/hooks/useSettings'
import { ColorPicker } from '@/components/editors/ColorPicker'
import { Skeleton } from '@/components/ui/skeleton'

export function ThemePanel() {
  const { t } = useTranslation()
  const { theme, setTheme } = useAppStore()
  const { data: themeConfig, isLoading } = useSettingsTheme()
  const updateTheme = useUpdateSettingsTheme()
  const [color, setColor] = useState('#6366f1')

  useEffect(() => {
    if (themeConfig?.primary_color) {
      setColor(themeConfig.primary_color)
    }
  }, [themeConfig])

  const handleThemeChange = (newTheme: 'dark' | 'light') => {
    setTheme(newTheme)
    updateTheme.mutate({ theme: newTheme })
  }

  const handleColorChange = (newColor: string) => {
    setColor(newColor)
    updateTheme.mutate({ primary_color: newColor })
  }

  if (isLoading) {
    return <Skeleton className="h-40 w-full" />
  }

  return (
    <div className="space-y-6">
      <h3 className="text-lg font-medium text-white">{t('settings.theme')}</h3>

      <div className="space-y-4">
        <div>
          <label className="block text-sm text-gray-400 mb-2">{t('settings.mode')}</label>
          <div className="flex gap-2">
            <button
              onClick={() => handleThemeChange('dark')}
              className={`px-4 py-2 rounded ${
                theme === 'dark' ? 'bg-blue-600 text-white' : 'bg-gray-700 text-gray-300'
              }`}
            >
              {t('settings.dark')}
            </button>
            <button
              onClick={() => handleThemeChange('light')}
              className={`px-4 py-2 rounded ${
                theme === 'light' ? 'bg-blue-600 text-white' : 'bg-gray-700 text-gray-300'
              }`}
            >
              {t('settings.light')}
            </button>
          </div>
        </div>

        <div>
          <label className="block text-sm text-gray-400 mb-2">{t('settings.primaryColor')}</label>
          <ColorPicker color={color} onChange={handleColorChange} />
        </div>
      </div>
    </div>
  )
}
