import { useTranslation } from 'react-i18next'
import { Input } from '@/components/ui/input'

export function DirectoryPanel() {
  const { t } = useTranslation()

  return (
    <div className="space-y-6">
      <h3 className="text-lg font-medium text-white">{t('settings.directory')}</h3>
      
      <div className="space-y-4">
        <div>
          <label className="block text-sm text-gray-400 mb-1">{t('settings.workspaceDir')}</label>
          <Input
            value="/workspace"
            readOnly
            className="w-80 bg-gray-800 border-gray-700 text-white"
          />
        </div>
        <div>
          <label className="block text-sm text-gray-400 mb-1">{t('settings.sessionDir')}</label>
          <Input
            value="~/.llmlite/sessions"
            readOnly
            className="w-80 bg-gray-800 border-gray-700 text-white"
          />
        </div>
      </div>
    </div>
  )
}
