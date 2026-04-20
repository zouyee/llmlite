import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useExportDeepLink } from '@/hooks/useDeepLink'
import type { DeepLinkPayload } from '@/lib/api/deeplink'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'

export function DeepLinkExport() {
  const { t } = useTranslation()
  const exportDeepLink = useExportDeepLink()
  const [type, setType] = useState<DeepLinkPayload['type']>('mcp')
  const [id, setId] = useState('')
  const [exportedUrl, setExportedUrl] = useState('')

  const handleExport = async () => {
    if (!id.trim()) return
    const result = await exportDeepLink.mutateAsync({ type, id })
    setExportedUrl(result.url)
  }

  const copyToClipboard = () => {
    navigator.clipboard.writeText(exportedUrl)
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t('deeplink.exportTitle', 'Export Configuration')}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div>
          <label className="block text-sm text-gray-400 mb-1">{t('deeplink.type', 'Type')}</label>
          <Select value={type} onValueChange={(v) => setType(v as DeepLinkPayload['type'])}>
            <SelectTrigger className="bg-gray-900 border-gray-700">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="mcp">MCP</SelectItem>
              <SelectItem value="prompt">Prompt</SelectItem>
              <SelectItem value="skill">Skill</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div>
          <label className="block text-sm text-gray-400 mb-1">{t('deeplink.id', 'ID')}</label>
          <Input
            value={id}
            onChange={(e) => setId(e.target.value)}
            placeholder="config-id"
            className="bg-gray-900 border-gray-700"
          />
        </div>
        <button
          onClick={handleExport}
          disabled={!id.trim() || exportDeepLink.isPending}
          className="px-4 py-2 rounded-lg bg-blue-600 hover:bg-blue-500 text-sm disabled:opacity-50"
        >
          {exportDeepLink.isPending
            ? t('deeplink.generating', 'Generating...')
            : t('deeplink.generate', 'Generate Link')}
        </button>
        {exportedUrl && (
          <div className="flex gap-2">
            <Input value={exportedUrl} readOnly className="bg-gray-900 border-gray-700 flex-1" />
            <button
              onClick={copyToClipboard}
              className="px-4 py-2 rounded-lg bg-gray-700 hover:bg-gray-600 text-sm"
            >
              {t('common.copy', 'Copy')}
            </button>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
