import { Badge } from '@/components/ui/badge'

interface HealthStatusBadgeProps {
  status: 'healthy' | 'degraded' | 'unhealthy' | 'unknown'
}

const statusConfig = {
  healthy: { label: 'Healthy', className: 'bg-green-500/20 text-green-400 border-green-500/50' },
  degraded: { label: 'Degraded', className: 'bg-yellow-500/20 text-yellow-400 border-yellow-500/50' },
  unhealthy: { label: 'Unhealthy', className: 'bg-red-500/20 text-red-400 border-red-500/50' },
  unknown: { label: 'Unknown', className: 'bg-gray-500/20 text-gray-400 border-gray-500/50' },
}

export function HealthStatusBadge({ status }: HealthStatusBadgeProps) {
  const config = statusConfig[status] ?? statusConfig.unknown
  return (
    <Badge className={config.className}>
      <span className="mr-1">●</span>
      {config.label}
    </Badge>
  )
}
