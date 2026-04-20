import { useTranslation } from 'react-i18next'
import { useUsageTrends } from '@/hooks/useUsage'
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'

export function UsageTrendChart() {
  const { t } = useTranslation()
  const { data: trends, isLoading } = useUsageTrends()

  if (isLoading) {
    return <div className="text-gray-400">{t('app.loading')}</div>
  }

  const chartData = trends?.map((trend) => ({
    date: trend.date,
    requests: trend.requests,
    tokens: trend.tokens,
    cost: trend.cost,
  })) ?? []

  return (
    <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
      <h3 className="text-lg font-medium text-white mb-4">{t('usage.trends')}</h3>
      <div className="h-64">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={chartData}>
            <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
            <XAxis dataKey="date" stroke="#9CA3AF" />
            <YAxis stroke="#9CA3AF" />
            <Tooltip
              contentStyle={{ backgroundColor: '#1F2937', border: '1px solid #374151' }}
              labelStyle={{ color: '#F9FAFB' }}
            />
            <Line type="monotone" dataKey="requests" stroke="#6366F1" strokeWidth={2} />
            <Line type="monotone" dataKey="tokens" stroke="#10B981" strokeWidth={2} />
            <Line type="monotone" dataKey="cost" stroke="#F59E0B" strokeWidth={2} />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  )
}
