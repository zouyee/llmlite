import { Switch } from '@/components/ui/switch'
import { useFailoverConfig, useUpdateFailoverConfig } from '@/hooks/useFailover'

export function FailoverToggle() {
  const { data: config, isLoading } = useFailoverConfig()
  const updateConfig = useUpdateFailoverConfig()

  const handleToggle = (checked: boolean) => {
    updateConfig.mutate({ enabled: checked })
  }

  if (isLoading) {
    return <div className="h-6 w-12 bg-gray-700 rounded animate-pulse" />
  }

  return (
    <div className="flex items-center gap-3">
      <Switch
        checked={config?.enabled ?? false}
        onCheckedChange={handleToggle}
        disabled={updateConfig.isPending}
      />
      <span className="text-sm text-gray-300">
        {config?.enabled ? 'Enabled' : 'Disabled'}
      </span>
    </div>
  )
}
