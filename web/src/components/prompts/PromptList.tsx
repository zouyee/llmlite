import { useTranslation } from 'react-i18next'
import { usePrompts, useDeletePrompt, useUpdatePrompt } from '@/hooks/usePrompts'
import { Switch } from '@/components/ui/switch'
import { Badge } from '@/components/ui/badge'

export function PromptList() {
  const { t } = useTranslation()
  const { data: prompts, isLoading } = usePrompts()
  const deletePrompt = useDeletePrompt()
  const updatePrompt = useUpdatePrompt()

  if (isLoading) {
    return <div className="text-gray-400">{t('app.loading')}</div>
  }

  if (!prompts?.length) {
    return <div className="text-gray-400 text-center py-8">{t('prompts.noPrompts')}</div>
  }

  return (
    <div className="grid gap-4">
      {prompts.map((prompt) => (
        <div key={prompt.id} className="bg-gray-800 rounded-lg p-4 border border-gray-700">
          <div className="flex items-start justify-between">
            <div className="flex-1">
              <h3 className="font-medium text-white">{prompt.name}</h3>
              <p className="text-sm text-gray-400 mt-1 line-clamp-2">{prompt.content}</p>
              <div className="flex gap-2 mt-2">
                {prompt.tags.map((tag) => (
                  <Badge key={tag} variant="outline" className="text-xs">{tag}</Badge>
                ))}
              </div>
            </div>
            <div className="flex items-center gap-3">
              <div className="flex items-center gap-2">
                <span className="text-xs text-gray-400">{prompt.enabled ? 'Enabled' : 'Disabled'}</span>
                <Switch
                  checked={prompt.enabled}
                  onCheckedChange={(checked) => updatePrompt.mutate({ id: prompt.id, prompt: { enabled: checked } })}
                />
              </div>
              <button
                onClick={() => deletePrompt.mutate(prompt.id)}
                className="px-3 py-1 text-sm bg-red-700 hover:bg-red-600 rounded"
              >
                {t('prompts.delete')}
              </button>
            </div>
          </div>
        </div>
      ))}
    </div>
  )
}
