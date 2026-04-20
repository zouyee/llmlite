import { useState, useEffect } from 'react'
import { useTranslation } from 'react-i18next'
import { useDailyMemory, useSaveDailyMemory } from '@/hooks/useWorkspace'
import { Save, Calendar } from 'lucide-react'

export function DailyMemoryPanel() {
  const { t } = useTranslation()
  const today = new Date().toISOString().split('T')[0]
  const { data: memory } = useDailyMemory(today)
  const [content, setContent] = useState('')
  const saveMemory = useSaveDailyMemory()

  useEffect(() => {
    if (memory) setContent(memory.content)
  }, [memory])

  const handleSave = async () => {
    await saveMemory.mutateAsync({ date: today, content })
  }

  return (
    <div className="flex flex-col h-full">
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2 text-sm text-gray-400">
          <Calendar className="w-4 h-4" />
          <span>
            {t('workspace.dailyMemory', 'Daily Memory')}: {today}
          </span>
        </div>
        <button
          onClick={handleSave}
          disabled={saveMemory.isPending}
          className="flex items-center gap-1.5 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-500 rounded-lg disabled:opacity-50"
        >
          <Save className="w-3.5 h-3.5" />
          {t('common.save', 'Save')}
        </button>
      </div>
      <textarea
        value={content}
        onChange={(e) => setContent(e.target.value)}
        placeholder={t('workspace.memoryPlaceholder', 'Record your work today...')}
        className="flex-1 w-full px-4 py-3 bg-gray-900 border border-gray-700 rounded-lg text-gray-200 text-sm focus:outline-none focus:border-blue-500 resize-none"
      />
    </div>
  )
}
