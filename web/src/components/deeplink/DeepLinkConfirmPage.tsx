import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useImportDeepLink } from '@/hooks/useDeepLink'
import type { DeepLinkPayload } from '@/lib/api/deeplink'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { JsonEditor } from '@/components/editors/JsonEditor'

interface DeepLinkConfirmPageProps {
  payload: DeepLinkPayload
  onComplete: () => void
}

export function DeepLinkConfirmPage({ payload, onComplete }: DeepLinkConfirmPageProps) {
  const { t } = useTranslation()
  const importDeepLink = useImportDeepLink()
  const [json, setJson] = useState(JSON.stringify(payload.data, null, 2))

  const handleConfirm = async () => {
    try {
      const data = JSON.parse(json)
      await importDeepLink.mutateAsync({ type: payload.type, data })
      onComplete()
    } catch {
      // JSON parse error shown by JsonEditor
    }
  }

  return (
    <div className="max-w-2xl mx-auto p-4">
      <Card>
        <CardHeader>
          <CardTitle>{t('deeplink.confirmTitle', 'Confirm Import')}</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="text-gray-300">
            {t('deeplink.importType', 'Importing')}: <span className="font-semibold text-blue-400">{payload.type}</span>
          </p>
          <JsonEditor value={json} onChange={setJson} height="200px" />
          <div className="flex justify-end gap-3">
            <button
              onClick={onComplete}
              className="px-4 py-2 rounded-lg bg-gray-700 hover:bg-gray-600 text-sm"
            >
              {t('common.cancel', 'Cancel')}
            </button>
            <button
              onClick={handleConfirm}
              disabled={importDeepLink.isPending}
              className="px-4 py-2 rounded-lg bg-blue-600 hover:bg-blue-500 text-sm disabled:opacity-50"
            >
              {importDeepLink.isPending
                ? t('common.importing', 'Importing...')
                : t('common.confirmImport', 'Confirm Import')}
            </button>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
