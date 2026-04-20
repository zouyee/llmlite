import { useTranslation } from 'react-i18next'
import { useModelStats } from '@/hooks/useUsage'

export function ModelStatsTable() {
  const { t } = useTranslation()
  const { data: stats, isLoading } = useModelStats()

  if (isLoading) {
    return <div className="text-gray-400">{t('app.loading')}</div>
  }

  if (!stats?.length) {
    return <div className="text-gray-400">{t('usage.noStats')}</div>
  }

  return (
    <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
      <h3 className="text-lg font-medium text-white mb-4">{t('usage.modelStats')}</h3>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-gray-400 border-b border-gray-700">
              <th className="text-left py-2 px-3">{t('usage.model')}</th>
              <th className="text-right py-2 px-3">{t('usage.requests')}</th>
              <th className="text-right py-2 px-3">{t('usage.inputTokens')}</th>
              <th className="text-right py-2 px-3">{t('usage.outputTokens')}</th>
              <th className="text-right py-2 px-3">{t('usage.totalCost')}</th>
              <th className="text-right py-2 px-3">{t('usage.avgLatency')}</th>
            </tr>
          </thead>
          <tbody>
            {stats.map((stat) => (
              <tr key={stat.model} className="border-b border-gray-700">
                <td className="py-2 px-3 text-white">{stat.model}</td>
                <td className="py-2 px-3 text-right text-gray-300">{stat.requests}</td>
                <td className="py-2 px-3 text-right text-gray-300">{stat.tokens_in}</td>
                <td className="py-2 px-3 text-right text-gray-300">{stat.tokens_out}</td>
                <td className="py-2 px-3 text-right text-white">${stat.cost.toFixed(4)}</td>
                <td className="py-2 px-3 text-right text-gray-300">-</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
