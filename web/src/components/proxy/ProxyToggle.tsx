import { Switch } from '@/components/ui/switch'
import { useProxyStatus, useStartProxy, useStopProxy } from '@/hooks/useProxy'

export function ProxyToggle() {
  const { data: status, isLoading } = useProxyStatus()
  const startProxy = useStartProxy()
  const stopProxy = useStopProxy()

  const handleToggle = (checked: boolean) => {
    if (checked) {
      startProxy.mutate(undefined)
    } else {
      stopProxy.mutate(undefined)
    }
  }

  if (isLoading) {
    return <div className="h-6 w-12 bg-gray-700 rounded animate-pulse" />
  }

  return (
    <div className="flex items-center gap-3">
      <Switch
        checked={status?.running ?? false}
        onCheckedChange={handleToggle}
        disabled={startProxy.isPending || stopProxy.isPending}
      />
      <span className="text-sm text-gray-300">
        {status?.running ? 'Running' : 'Stopped'}
      </span>
    </div>
  )
}
