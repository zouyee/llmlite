import { useTranslation } from 'react-i18next'
import { UsageOverview } from '@/components/usage/UsageOverview'
import { UsageTrendChart } from '@/components/usage/UsageTrendChart'
import { RequestLogTable } from '@/components/usage/RequestLogTable'
import { ModelStatsTable } from '@/components/usage/ModelStatsTable'
import { CostConfigPanel } from '@/components/usage/CostConfigPanel'
import { useExportUsage } from '@/hooks/useUsage'

export default function UsageDashboard() {
  const { t } = useTranslation()
  const exportUsage = useExportUsage()

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold text-white">{t('usage.title')}</h1>
        <button
          onClick={() => exportUsage.mutate('csv')}
          disabled={exportUsage.isPending}
          className="px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded text-white"
        >
          {t('usage.exportCSV')}
        </button>
      </div>

      <UsageOverview />

      <UsageTrendChart />

      <RequestLogTable />

      <ModelStatsTable />

      <CostConfigPanel />
    </div>
  )
}
