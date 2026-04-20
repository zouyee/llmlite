import { Badge } from '@/components/ui/badge'

interface FailoverPriorityBadgeProps {
  priority: number
}

export function FailoverPriorityBadge({ priority }: FailoverPriorityBadgeProps) {
  return (
    <Badge variant="outline" className="border-blue-500/50 text-blue-400">
      #{priority}
    </Badge>
  )
}
