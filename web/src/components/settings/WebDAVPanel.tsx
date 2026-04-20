import { useTranslation } from 'react-i18next'
import { useQuery, useMutation } from '@tanstack/react-query'
import { settingsApi } from '@/lib/api/settings'
import { Input } from '@/components/ui/input'
import { Switch } from '@/components/ui/switch'
import { Button } from '@/components/ui/button'
import toast from 'react-hot-toast'

export function WebDAVPanel() {
  const { t } = useTranslation()
  const { data: config, isLoading } = useQuery({
    queryKey: ['settings', 'webdav'],
    queryFn: settingsApi.getWebDAV,
  })
  const updateConfig = useMutation({
    mutationFn: settingsApi.updateWebDAV,
    onSuccess: () => {
      toast.success(t('settings.saved'))
    },
    onError: () => {
      toast.error(t('settings.saveFailed'))
    },
  })
  const syncWebDAV = useMutation({
    mutationFn: settingsApi.syncWebDAV,
    onSuccess: () => {
      toast.success(t('settings.syncSuccess'))
    },
    onError: () => {
      toast.error(t('settings.syncFailed'))
    },
  })

  if (isLoading) {
    return <div className="text-gray-400">{t('app.loading')}</div>
  }

  return (
    <div className="space-y-6">
      <h3 className="text-lg font-medium text-white">WebDAV</h3>
      
      <div className="space-y-4">
        <div>
          <label className="block text-sm text-gray-400 mb-1">{t('settings.serverUrl')}</label>
          <Input
            value={config?.url ?? ''}
            onChange={(e) => updateConfig.mutate({ url: e.target.value })}
            placeholder="https://webdav.example.com"
            className="w-80 bg-gray-800 border-gray-700 text-white"
          />
        </div>
        <div>
          <label className="block text-sm text-gray-400 mb-1">{t('settings.username')}</label>
          <Input
            value={config?.username ?? ''}
            onChange={(e) => updateConfig.mutate({ username: e.target.value })}
            className="w-80 bg-gray-800 border-gray-700 text-white"
          />
        </div>
        <div>
          <label className="block text-sm text-gray-400 mb-1">{t('settings.password')}</label>
          <Input
            type="password"
            value={config?.password ?? ''}
            onChange={(e) => updateConfig.mutate({ password: e.target.value })}
            className="w-80 bg-gray-800 border-gray-700 text-white"
          />
        </div>
        <div className="flex items-center justify-between">
          <div>
            <label className="text-sm text-gray-300">{t('settings.autoSync')}</label>
          </div>
          <Switch
            checked={config?.auto_sync ?? false}
            onCheckedChange={(checked) => updateConfig.mutate({ auto_sync: checked })}
          />
        </div>
        <Button
          onClick={() => syncWebDAV.mutate()}
          disabled={syncWebDAV.isPending}
        >
          {t('settings.syncNow')}
        </Button>
      </div>
    </div>
  )
}
