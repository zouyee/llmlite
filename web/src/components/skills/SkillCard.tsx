import { useTranslation } from 'react-i18next'
import { useInstallSkill, useUninstallSkill, useUpdateSkill } from '@/hooks/useSkills'
import { Badge } from '@/components/ui/badge'

export function SkillCard({ skill }: { skill: { id: string; name: string; description: string; version: string; author: string; installed: boolean } }) {
  const { t } = useTranslation()
  const installSkill = useInstallSkill()
  const uninstallSkill = useUninstallSkill()
  const updateSkill = useUpdateSkill()

  return (
    <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
      <div className="flex items-start justify-between">
        <div className="flex-1">
          <h3 className="font-medium text-white">{skill.name}</h3>
          <p className="text-sm text-gray-400 mt-1">{skill.description}</p>
          <div className="flex gap-2 mt-2">
            <Badge variant="outline" className="text-xs">{skill.version}</Badge>
            <Badge variant="outline" className="text-xs">{skill.author}</Badge>
          </div>
        </div>
        <div className="flex gap-2">
          {skill.installed ? (
            <>
              <button
                onClick={() => updateSkill.mutate(skill.id)}
                className="px-3 py-1 text-sm bg-blue-700 hover:bg-blue-600 rounded"
              >
                {t('skills.update')}
              </button>
              <button
                onClick={() => uninstallSkill.mutate(skill.id)}
                className="px-3 py-1 text-sm bg-red-700 hover:bg-red-600 rounded"
              >
                {t('skills.uninstall')}
              </button>
            </>
          ) : (
            <button
              onClick={() => installSkill.mutate(skill.id)}
              className="px-3 py-1 text-sm bg-green-700 hover:bg-green-600 rounded"
            >
              {t('skills.install')}
            </button>
          )}
        </div>
      </div>
    </div>
  )
}
