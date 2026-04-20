import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Switch } from '@/components/ui/switch'

export function WindowPanel() {
  const { t } = useTranslation()
  const [alwaysOnTop, setAlwaysOnTop] = useState(false)
  const [showInDock, setShowInDock] = useState(true)

  return (
    <div className="space-y-6">
      <h3 className="text-lg font-medium text-white">{t('settings.window')}</h3>

      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <div>
            <label className="text-sm text-gray-300">{t('settings.alwaysOnTop')}</label>
          </div>
          <Switch
            checked={alwaysOnTop}
            onCheckedChange={setAlwaysOnTop}
          />
        </div>
        <div className="flex items-center justify-between">
          <div>
            <label className="text-sm text-gray-300">{t('settings.showInDock')}</label>
          </div>
          <Switch
            checked={showInDock}
            onCheckedChange={setShowInDock}
          />
        </div>
      </div>
    </div>
  )
}
