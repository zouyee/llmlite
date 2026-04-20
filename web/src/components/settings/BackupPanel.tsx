import { useTranslation } from 'react-i18next'
import { useMutation } from '@tanstack/react-query'
import { settingsApi } from '@/lib/api/settings'
import { Button } from '@/components/ui/button'
import toast from 'react-hot-toast'

export function BackupPanel() {
  const { t } = useTranslation()
  const exportBackup = useMutation({
    mutationFn: settingsApi.exportBackup,
    onSuccess: (data) => {
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `llmlite-backup-${Date.now()}.json`
      a.click()
      URL.revokeObjectURL(url)
      toast.success(t('settings.exportSuccess'))
    },
    onError: () => {
      toast.error(t('settings.exportFailed'))
    },
  })

  const importBackup = useMutation({
    mutationFn: settingsApi.importBackup,
    onSuccess: () => {
      toast.success(t('settings.importSuccess'))
    },
    onError: () => {
      toast.error(t('settings.importFailed'))
    },
  })

  return (
    <div className="space-y-6">
      <h3 className="text-lg font-medium text-white">{t('settings.backup')}</h3>
      
      <div className="flex gap-4">
        <Button
          onClick={() => exportBackup.mutate()}
          disabled={exportBackup.isPending}
        >
          {t('settings.export')}
        </Button>
        <label className="cursor-pointer">
          <input
            type="file"
            accept=".json"
            className="hidden"
            onChange={(e) => {
              const file = e.target.files?.[0]
              if (file) {
                const reader = new FileReader()
                reader.onload = () => {
                  try {
                    const data = JSON.parse(reader.result as string)
                    importBackup.mutate(data)
                  } catch {
                    toast.error(t('settings.invalidBackupFile'))
                  }
                }
                reader.readAsText(file)
              }
            }}
          />
          <span className="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded text-white">
            {t('settings.import')}
          </span>
        </label>
      </div>
    </div>
  )
}
