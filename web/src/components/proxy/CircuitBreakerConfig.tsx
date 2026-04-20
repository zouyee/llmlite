import { useCircuitBreakerConfig, useUpdateCircuitBreakerConfig } from '@/hooks/useFailover'
import { Input } from '@/components/ui/input'

export function CircuitBreakerConfig() {
  const { data: config, isLoading } = useCircuitBreakerConfig()
  const updateConfig = useUpdateCircuitBreakerConfig()

  if (isLoading) {
    return <div className="text-gray-400">Loading...</div>
  }

  return (
    <div className="space-y-4">
      <h3 className="text-lg font-medium text-white">Circuit Breaker</h3>
      <div className="grid grid-cols-3 gap-4">
        <div>
          <label className="block text-sm text-gray-400 mb-1">Failure Threshold</label>
          <Input
            type="number"
            value={config?.failure_threshold ?? 5}
            onChange={(e) => updateConfig.mutate({ failure_threshold: Number(e.target.value) })}
            className="bg-gray-800 border-gray-700 text-white"
          />
        </div>
        <div>
          <label className="block text-sm text-gray-400 mb-1">Recovery Timeout (ms)</label>
          <Input
            type="number"
            value={config?.recovery_timeout_ms ?? 60000}
            onChange={(e) => updateConfig.mutate({ recovery_timeout_ms: Number(e.target.value) })}
            className="bg-gray-800 border-gray-700 text-white"
          />
        </div>
        <div>
          <label className="block text-sm text-gray-400 mb-1">Half-Open Max Requests</label>
          <Input
            type="number"
            value={config?.half_open_max_requests ?? 3}
            onChange={(e) => updateConfig.mutate({ half_open_max_requests: Number(e.target.value) })}
            className="bg-gray-800 border-gray-700 text-white"
          />
        </div>
      </div>
    </div>
  )
}
