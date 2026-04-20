import { ProxyToggle } from '@/components/proxy/ProxyToggle'
import { FailoverToggle } from '@/components/proxy/FailoverToggle'
import { FailoverQueuePanel } from '@/components/proxy/FailoverQueuePanel'
import { AutoFailoverConfig } from '@/components/proxy/AutoFailoverConfig'
import { CircuitBreakerConfig } from '@/components/proxy/CircuitBreakerConfig'

export default function ProxyPage() {
  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-white">Proxy Control</h1>
      
      <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <h2 className="text-lg font-medium text-white mb-3">Proxy Status</h2>
        <ProxyToggle />
      </div>

      <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <h2 className="text-lg font-medium text-white mb-3">Auto-Failover</h2>
        <FailoverToggle />
      </div>

      <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <FailoverQueuePanel />
      </div>

      <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <AutoFailoverConfig />
      </div>

      <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <CircuitBreakerConfig />
      </div>
    </div>
  )
}
