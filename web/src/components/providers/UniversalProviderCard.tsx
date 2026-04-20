import { useTranslation } from 'react-i18next'
import type { Provider } from '@/lib/api/providers'
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'

interface ProviderTypeConfig {
  icon: string
  fields: string[]
}

const typeConfigs: Record<string, ProviderTypeConfig> = {
  openai: { icon: '🤖', fields: ['organization', 'default_model'] },
  anthropic: { icon: '🧠', fields: ['default_model', 'api_key_env'] },
  gemini: { icon: '✨', fields: ['default_model'] },
  default: { icon: '🔌', fields: ['base_url', 'default_model'] },
}

interface UniversalProviderCardProps {
  provider: Provider
  onEdit: () => void
  onDelete: () => void
}

export function UniversalProviderCard({ provider, onEdit, onDelete }: UniversalProviderCardProps) {
  const { t } = useTranslation()
  const config = typeConfigs[provider.name.toLowerCase()] || typeConfigs.default

  return (
    <Card className="relative">
      <CardHeader className="pb-2">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="text-lg">{config.icon}</span>
            <CardTitle className="text-base">{provider.name}</CardTitle>
          </div>
          <div className="flex gap-2">
            {!provider.enabled && (
              <Badge variant="secondary">{t('provider.disabled', 'Disabled')}</Badge>
            )}
            <Badge variant={provider.is_official ? 'default' : 'outline'}>
              {provider.is_official ? t('provider.official', 'Official') : t('provider.custom', 'Custom')}
            </Badge>
          </div>
        </div>
        <CardDescription>{provider.description || provider.base_url}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-2">
        {config.fields.map((field) => {
          const value = (provider as unknown as Record<string, unknown>)[field]
          if (!value) return null
          return (
            <div key={field} className="flex justify-between text-sm">
              <span className="text-gray-400">{field}</span>
              <span className="text-gray-200">{String(value)}</span>
            </div>
          )
        })}
        <div className="flex justify-end gap-2 pt-2">
          <button
            onClick={onEdit}
            className="px-3 py-1 text-xs bg-gray-700 hover:bg-gray-600 rounded"
          >
            {t('common.edit', 'Edit')}
          </button>
          <button
            onClick={onDelete}
            className="px-3 py-1 text-xs bg-red-900/30 text-red-400 hover:bg-red-900/50 rounded"
          >
            {t('common.delete', 'Delete')}
          </button>
        </div>
      </CardContent>
    </Card>
  )
}
