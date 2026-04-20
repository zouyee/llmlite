import { Badge } from '@/components/ui/badge'

interface CircuitBreakerBadgeProps {
  state: 'closed' | 'open' | 'half_open' | 'unknown'
}

const stateConfig = {
  closed: { label: 'Closed', className: 'bg-green-500/20 text-green-400 border-green-500/50' },
  open: { label: 'Open', className: 'bg-red-500/20 text-red-400 border-red-500/50' },
  half_open: { label: 'Half-Open', className: 'bg-yellow-500/20 text-yellow-400 border-yellow-500/50' },
  unknown: { label: 'Unknown', className: 'bg-gray-500/20 text-gray-400 border-gray-500/50' },
}

export function CircuitBreakerBadge({ state }: CircuitBreakerBadgeProps) {
  const config = stateConfig[state] ?? stateConfig.unknown
  return (
    <Badge className={config.className}>
      ⚡ {config.label}
    </Badge>
  )
}
