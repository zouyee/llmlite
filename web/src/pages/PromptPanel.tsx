import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { PromptList } from '@/components/prompts/PromptList'
import { PromptEditDialog } from '@/components/prompts/PromptEditDialog'

export default function PromptPanel() {
  const { t } = useTranslation()
  const [showEditDialog, setShowEditDialog] = useState(false)

  return (
    <div>
      <div className="flex justify-between items-center mb-4">
        <h1 className="text-2xl font-bold text-white">{t('prompts.title')}</h1>
        <button
          onClick={() => setShowEditDialog(true)}
          className="px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded text-white"
        >
          {t('prompts.create')}
        </button>
      </div>
      <PromptList />
      {showEditDialog && <PromptEditDialog onClose={() => setShowEditDialog(false)} />}
    </div>
  )
}
