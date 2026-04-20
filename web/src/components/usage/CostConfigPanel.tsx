import { useTranslation } from 'react-i18next'
import { useCostConfig, useUpdateCostConfig } from '@/hooks/useUsage'
import { Input } from '@/components/ui/input'
import type { CostConfig } from '@/lib/api/usage'

export function CostConfigPanel() {
  const { t } = useTranslation()
  const { data: config, isLoading } = useCostConfig()
  const updateConfig = useUpdateCostConfig()

  if (isLoading) {
    return <div className="text-gray-400">{t('app.loading')}</div>
  }

  const handleInputPriceChange = (item: CostConfig, value: string) => {
    updateConfig.mutate({ ...item, input_price: Number(value) })
  }

  const handleOutputPriceChange = (item: CostConfig, value: string) => {
    updateConfig.mutate({ ...item, output_price: Number(value) })
  }

  return (
    <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
      <h3 className="text-lg font-medium text-white mb-4">{t('usage.costConfig')}</h3>
      <div className="space-y-4">
        {config?.map((item) => (
          <div key={item.model} className="flex items-center gap-4">
            <div className="w-48 text-white">{item.model}</div>
            <div className="flex items-center gap-2">
              <Input
                type="number"
                step="0.0001"
                value={item.input_price}
                onChange={(e) => handleInputPriceChange(item, e.target.value)}
                className="w-24 bg-gray-700 border-gray-600 text-white"
              />
              <span className="text-gray-400">/ 1K in</span>
            </div>
            <div className="flex items-center gap-2">
              <Input
                type="number"
                step="0.0001"
                value={item.output_price}
                onChange={(e) => handleOutputPriceChange(item, e.target.value)}
                className="w-24 bg-gray-700 border-gray-600 text-white"
              />
              <span className="text-gray-400">/ 1K out</span>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
