import { useTranslation } from 'react-i18next'
import { useUsageOverview } from '@/hooks/useUsage'

export function UsageOverview() {
  const { t } = useTranslation()
  const { data: overview, isLoading } = useUsageOverview()

  if (isLoading) {
    return <div className="text-gray-400">{t('app.loading')}</div>
  }

  return (
    <div className="grid grid-cols-4 gap-4">
      <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <div className="text-2xl font-bold text-white">{overview?.total_requests ?? 0}</div>
        <div className="text-sm text-gray-400">{t('usage.totalRequests')}</div>
      </div>
      <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <div className="text-2xl font-bold text-white">{overview?.total_tokens ?? 0}</div>
        <div className="text-sm text-gray-400">{t('usage.totalTokens')}</div>
      </div>
      <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <div className="text-2xl font-bold text-white">${overview?.total_cost?.toFixed(2) ?? '0.00'}</div>
        <div className="text-sm text-gray-400">{t('usage.totalCost')}</div>
      </div>
      <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <div className="text-2xl font-bold text-white">{overview?.active_providers ?? 0}</div>
        <div className="text-sm text-gray-400">{t('usage.activeProviders')}</div>
      </div>
    </div>
  )
}
