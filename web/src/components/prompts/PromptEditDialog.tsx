import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useCreatePrompt } from '@/hooks/usePrompts'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import toast from 'react-hot-toast'

export function PromptEditDialog({ onClose }: { onClose: () => void }) {
  const { t } = useTranslation()
  const [name, setName] = useState('')
  const [content, setContent] = useState('')
  const [tags, setTags] = useState('')
  const createPrompt = useCreatePrompt()

  const handleSubmit = () => {
    if (!name.trim() || !content.trim()) {
      toast.error(t('prompts.fillRequired'))
      return
    }
    createPrompt.mutate(
      { name, content, tags: tags.split(',').map((t) => t.trim()).filter(Boolean), enabled: true },
      {
        onSuccess: () => {
          toast.success(t('prompts.created'))
          onClose()
        },
      }
    )
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-gray-800 rounded-lg p-6 w-full max-w-lg border border-gray-700">
        <h2 className="text-xl font-bold text-white mb-4">{t('prompts.create')}</h2>
        <div className="space-y-4">
          <div>
            <label className="block text-sm text-gray-400 mb-1">{t('prompts.name')}</label>
            <Input value={name} onChange={(e) => setName(e.target.value)} className="bg-gray-700 border-gray-600 text-white" />
          </div>
          <div>
            <label className="block text-sm text-gray-400 mb-1">{t('prompts.content')}</label>
            <textarea
              value={content}
              onChange={(e) => setContent(e.target.value)}
              className="w-full h-32 px-3 py-2 bg-gray-700 border border-gray-600 rounded text-white resize-none"
            />
          </div>
          <div>
            <label className="block text-sm text-gray-400 mb-1">{t('prompts.tags')}</label>
            <Input value={tags} onChange={(e) => setTags(e.target.value)} placeholder="tag1,tag2" className="bg-gray-700 border-gray-600 text-white" />
          </div>
        </div>
        <div className="flex justify-end gap-2 mt-6">
          <Button variant="outline" onClick={onClose}>{t('common.cancel')}</Button>
          <Button onClick={handleSubmit} disabled={createPrompt.isPending}>{t('common.save')}</Button>
        </div>
      </div>
    </div>
  )
}
