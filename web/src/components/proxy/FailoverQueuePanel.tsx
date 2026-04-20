import { useFailoverQueue } from '@/hooks/useFailover'
import { Badge } from '@/components/ui/badge'
import { HealthStatusBadge } from '@/components/providers/HealthStatusBadge'
import { CircuitBreakerBadge } from '@/components/providers/CircuitBreakerBadge'

export function FailoverQueuePanel() {
  const { data: queue, isLoading } = useFailoverQueue()

  if (isLoading) {
    return <div className="text-gray-400">Loading...</div>
  }

  if (!queue?.providers?.length) {
    return <div className="text-gray-400">No providers in failover queue</div>
  }

  const sortedProviders = [...queue.providers].sort((a, b) => a.priority - b.priority)

  return (
    <div className="space-y-2">
      <h3 className="text-lg font-medium text-white">Failover Queue</h3>
      <div className="space-y-2">
        {sortedProviders.map((provider) => (
          <div
            key={provider.id}
            className="flex items-center justify-between bg-gray-800 rounded-lg p-3 border border-gray-700"
          >
            <div className="flex items-center gap-3">
              <Badge variant="outline" className="border-blue-500/50 text-blue-400">
                #{provider.priority}
              </Badge>
              <span className="text-white font-medium">{provider.name}</span>
            </div>
            <div className="flex items-center gap-2">
              <HealthStatusBadge status={provider.healthy ? 'healthy' : 'unhealthy'} />
              <CircuitBreakerBadge state={provider.circuit_state} />
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
