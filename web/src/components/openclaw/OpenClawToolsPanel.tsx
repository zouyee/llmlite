import { useTranslation } from 'react-i18next'
import { useOpenClawConfig, useUpdateOpenClawConfig } from '@/hooks/useOpenClaw'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Switch } from '@/components/ui/switch'

export function OpenClawToolsPanel() {
  const { t } = useTranslation()
  const { data: config } = useOpenClawConfig()
  const update = useUpdateOpenClawConfig()

  if (!config) return null

  const tools = config.available_tools || []
  const enabled = config.enabled_tools || []

  const toggleTool = (tool: string) => {
    const next = enabled.includes(tool)
      ? enabled.filter((t) => t !== tool)
      : [...enabled, tool]
    update.mutate({ enabled_tools: next })
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t('openclaw.tools.title', 'Tools')}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {tools.length === 0 && (
          <p className="text-gray-500 text-sm">{t('openclaw.tools.empty', 'No tools available')}</p>
        )}
        {tools.map((tool) => (
          <div key={tool} className="flex items-center justify-between py-2 border-b border-gray-700 last:border-0">
            <span className="text-sm text-gray-300">{tool}</span>
            <Switch
              checked={enabled.includes(tool)}
              onCheckedChange={() => toggleTool(tool)}
            />
          </div>
        ))}
      </CardContent>
    </Card>
  )
}
