import { useTranslation } from 'react-i18next'
import { useQuery, useMutation } from '@tanstack/react-query'
import { configApi } from '@/lib/api/config'
import { Input } from '@/components/ui/input'
import { Switch } from '@/components/ui/switch'
import toast from 'react-hot-toast'

export function ProxyConfigPanel() {
  const { t } = useTranslation()
  const { data: config, isLoading } = useQuery({
    queryKey: ['config'],
    queryFn: configApi.get,
  })
  const updateConfig = useMutation({
    mutationFn: configApi.update,
    onSuccess: () => {
      toast.success(t('settings.saved'))
    },
    onError: () => {
      toast.error(t('settings.saveFailed'))
    },
  })

  if (isLoading) {
    return <div className="text-gray-400">{t('app.loading')}</div>
  }

  return (
    <div className="space-y-6">
      <h3 className="text-lg font-medium text-white">{t('settings.proxy')}</h3>
      
      <div className="space-y-4">
        <div>
          <label className="block text-sm text-gray-400 mb-1">{t('settings.port')}</label>
          <Input
            type="number"
            value={config?.port ?? 4000}
            onChange={(e) => updateConfig.mutate({ port: Number(e.target.value) })}
            className="w-48 bg-gray-800 border-gray-700 text-white"
          />
        </div>

        <div className="flex items-center justify-between">
          <div>
            <label className="text-sm text-gray-300">{t('settings.healthCheck')}</label>
            <p className="text-xs text-gray-500">{t('settings.healthCheckDesc')}</p>
          </div>
          <Switch
            checked={config?.enable_health_checker ?? true}
            onCheckedChange={(checked) => updateConfig.mutate({ enable_health_checker: checked })}
          />
        </div>

        <div>
          <label className="block text-sm text-gray-400 mb-1">{t('settings.healthCheckInterval')}</label>
          <Input
            type="number"
            value={config?.health_check_interval_ms ?? 30000}
            onChange={(e) => updateConfig.mutate({ health_check_interval_ms: Number(e.target.value) })}
            className="w-48 bg-gray-800 border-gray-700 text-white"
          />
        </div>

        <div>
          <label className="block text-sm text-gray-400 mb-1">{t('settings.latencyWindowSize')}</label>
          <Input
            type="number"
            value={config?.latency_window_size ?? 100}
            onChange={(e) => updateConfig.mutate({ latency_window_size: Number(e.target.value) })}
            className="w-48 bg-gray-800 border-gray-700 text-white"
          />
        </div>
      </div>
    </div>
  )
}
