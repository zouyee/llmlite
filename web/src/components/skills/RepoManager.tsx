import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useSkillRepos, useAddSkillRepo, useRemoveSkillRepo } from '@/hooks/useSkills'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Plus, Trash2, Globe } from 'lucide-react'

export function RepoManager() {
  const { t } = useTranslation()
  const { data: repos } = useSkillRepos()
  const addRepo = useAddSkillRepo()
  const removeRepo = useRemoveSkillRepo()
  const [url, setUrl] = useState('')
  const [isOpen, setIsOpen] = useState(false)

  const handleAdd = () => {
    if (!url.trim()) return
    addRepo.mutate(url, {
      onSuccess: () => {
        setUrl('')
        setIsOpen(false)
      },
    })
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="flex items-center gap-2">
          <Globe className="w-4 h-4" />
          {t('skills.repos.title', 'Skill Repositories')}
        </CardTitle>
        <button
          onClick={() => setIsOpen(true)}
          className="p-2 bg-blue-600 hover:bg-blue-500 rounded-lg"
        >
          <Plus className="w-4 h-4" />
        </button>
      </CardHeader>
      <CardContent className="space-y-2">
        {repos?.length === 0 && (
          <p className="text-gray-500 text-sm">{t('skills.repos.empty', 'No repositories configured')}</p>
        )}
        {repos?.map((repo) => (
          <div key={repo.id} className="flex items-center justify-between py-2 border-b border-gray-700 last:border-0">
            <div>
              <p className="text-sm font-medium text-gray-200">{repo.name}</p>
              <p className="text-xs text-gray-400">{repo.url}</p>
            </div>
            <button
              onClick={() => removeRepo.mutate(repo.id)}
              className="p-1.5 text-red-400 hover:bg-red-900/20 rounded"
            >
              <Trash2 className="w-4 h-4" />
            </button>
          </div>
        ))}
      </CardContent>
      <Dialog open={isOpen} onOpenChange={setIsOpen}>
        <DialogContent className="bg-gray-800 border-gray-700 text-gray-100">
          <DialogHeader>
            <DialogTitle>{t('skills.repos.add', 'Add Repository')}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <label className="block text-sm text-gray-400 mb-1">URL</label>
              <Input
                value={url}
                onChange={(e) => setUrl(e.target.value)}
                placeholder="https://github.com/owner/repo"
                className="bg-gray-900 border-gray-700"
              />
            </div>
            <div className="flex justify-end gap-2">
              <button onClick={() => setIsOpen(false)} className="px-4 py-2 rounded-lg bg-gray-700 hover:bg-gray-600 text-sm">
                {t('common.cancel', 'Cancel')}
              </button>
              <button
                onClick={handleAdd}
                disabled={!url.trim()}
                className="px-4 py-2 rounded-lg bg-blue-600 hover:bg-blue-500 text-sm disabled:opacity-50"
              >
                {t('common.add', 'Add')}
              </button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </Card>
  )
}
