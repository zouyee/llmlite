import { useTranslation } from 'react-i18next'
import { useSettingsTheme, useUpdateSettingsTheme } from '@/hooks/useSettings'
import { Skeleton } from '@/components/ui/skeleton'

const languages = [
  { code: 'en', label: 'English' },
  { code: 'zh', label: '中文' },
  { code: 'ja', label: '日本語' },
]

export function LanguagePanel() {
  const { t, i18n } = useTranslation()
  const { isLoading } = useSettingsTheme()
  const updateTheme = useUpdateSettingsTheme()

  const handleLanguageChange = (lang: string) => {
    i18n.changeLanguage(lang)
    localStorage.setItem('llmlite_language', lang)
    updateTheme.mutate({})
  }

  if (isLoading) {
    return <Skeleton className="h-32 w-full" />
  }

  return (
    <div className="space-y-6">
      <h3 className="text-lg font-medium text-white">{t('settings.language')}</h3>

      <div className="flex gap-2">
        {languages.map((lang) => (
          <button
            key={lang.code}
            onClick={() => handleLanguageChange(lang.code)}
            className={`px-4 py-2 rounded ${
              i18n.language === lang.code ? 'bg-blue-600 text-white' : 'bg-gray-700 text-gray-300'
            }`}
          >
            {lang.label}
          </button>
        ))}
      </div>
    </div>
  )
}
