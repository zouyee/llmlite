import { useFailoverConfig, useUpdateFailoverConfig } from '@/hooks/useFailover'
import { Input } from '@/components/ui/input'

export function AutoFailoverConfig() {
  const { data: config, isLoading } = useFailoverConfig()
  const updateConfig = useUpdateFailoverConfig()

  if (isLoading) {
    return <div className="text-gray-400">Loading...</div>
  }

  return (
    <div className="space-y-4">
      <h3 className="text-lg font-medium text-white">Auto-Failover</h3>
      <div className="grid grid-cols-3 gap-4">
        <div>
          <label className="block text-sm text-gray-400 mb-1">Max Retries</label>
          <Input
            type="number"
            value={config?.max_retries ?? 3}
            onChange={(e) => updateConfig.mutate({ max_retries: Number(e.target.value) })}
            className="bg-gray-800 border-gray-700 text-white"
          />
        </div>
        <div>
          <label className="block text-sm text-gray-400 mb-1">Retry Interval (ms)</label>
          <Input
            type="number"
            value={config?.retry_interval_ms ?? 1000}
            onChange={(e) => updateConfig.mutate({ retry_interval_ms: Number(e.target.value) })}
            className="bg-gray-800 border-gray-700 text-white"
          />
        </div>
        <div>
          <label className="block text-sm text-gray-400 mb-1">Timeout (ms)</label>
          <Input
            type="number"
            value={config?.timeout_ms ?? 30000}
            onChange={(e) => updateConfig.mutate({ timeout_ms: Number(e.target.value) })}
            className="bg-gray-800 border-gray-700 text-white"
          />
        </div>
      </div>
    </div>
  )
}
