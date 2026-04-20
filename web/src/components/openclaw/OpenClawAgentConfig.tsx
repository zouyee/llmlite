import { useTranslation } from 'react-i18next'
import { useOpenClawConfig, useUpdateOpenClawConfig } from '@/hooks/useOpenClaw'
import { Input } from '@/components/ui/input'
import { Slider } from '@/components/ui/slider'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'

export function OpenClawAgentConfig() {
  const { t } = useTranslation()
  const { data: config } = useOpenClawConfig()
  const update = useUpdateOpenClawConfig()

  if (!config) return null

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t('openclaw.agent.title', 'Agent Defaults')}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div>
          <label className="block text-sm text-gray-400 mb-1">
            {t('openclaw.agent.model', 'Default Model')}
          </label>
          <Input
            value={config.default_model}
            onChange={(e) => update.mutate({ default_model: e.target.value })}
            className="bg-gray-900 border-gray-700"
          />
        </div>
        <div>
          <label className="block text-sm text-gray-400 mb-1">
            {t('openclaw.agent.temperature', 'Temperature')}: {config.temperature}
          </label>
          <Slider
            value={config.temperature}
            onValueChange={(v) => update.mutate({ temperature: v })}
            min={0}
            max={2}
            step={0.1}
          />
        </div>
        <div>
          <label className="block text-sm text-gray-400 mb-1">
            {t('openclaw.agent.maxTokens', 'Max Tokens')}
          </label>
          <Input
            type="number"
            value={config.max_tokens}
            onChange={(e) => update.mutate({ max_tokens: parseInt(e.target.value) })}
            className="bg-gray-900 border-gray-700"
          />
        </div>
      </CardContent>
    </Card>
  )
}
