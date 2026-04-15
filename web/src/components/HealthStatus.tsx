import { useTranslation } from 'react-i18next'
import { useQuery, useMutation } from '@tanstack/react-query'
import { configApi, healthApi } from '@/lib/api/llmlite'
import toast from 'react-hot-toast'

export default function HealthStatus() {
  const { data: health } = useQuery({
    queryKey: ['health'],
    queryFn: healthApi.full,
    refetchInterval: 30000,
  })

  const getStatusColor = (status?: string) => {
    switch (status) {
      case 'healthy':
        return 'bg-green-500'
      case 'degraded':
        return 'bg-yellow-500'
      case 'unhealthy':
        return 'bg-red-500'
      default:
        return 'bg-gray-500'
    }
  }

  const formatUptime = (seconds: number) => {
    const days = Math.floor(seconds / 86400)
    const hours = Math.floor((seconds % 86400) / 3600)
    const mins = Math.floor((seconds % 3600) / 60)
    if (days > 0) return `${days}d ${hours}h`
    if (hours > 0) return `${hours}h ${mins}m`
    return `${mins}m`
  }

  if (!health) {
    return <div className="w-3 h-3 rounded-full bg-gray-500" />
  }

  return (
    <div className="flex items-center gap-4">
      <div className="flex items-center gap-2">
        <div className={`w-3 h-3 rounded-full ${getStatusColor(health.status)}`} />
        <span className="text-sm text-gray-300">{health.status}</span>
      </div>
      <span className="text-sm text-gray-500">v{health.version}</span>
      <span className="text-sm text-gray-500">Up: {formatUptime(health.uptime_seconds)}</span>
    </div>
  )
}
