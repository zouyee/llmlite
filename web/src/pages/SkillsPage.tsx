import { useTranslation } from 'react-i18next'
import { useSkills } from '@/hooks/useSkills'
import { SkillCard } from '@/components/skills/SkillCard'

export default function SkillsPage() {
  const { t } = useTranslation()
  const { data: skills, isLoading } = useSkills()

  if (isLoading) {
    return <div className="text-gray-400">{t('app.loading')}</div>
  }

  const installedSkills = skills?.filter((s) => s.installed) ?? []
  const availableSkills = skills?.filter((s) => !s.installed) ?? []

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-white">{t('skills.title')}</h1>

      {installedSkills.length > 0 && (
        <section>
          <h2 className="text-lg font-medium text-white mb-3">{t('skills.installed')}</h2>
          <div className="grid gap-4">
            {installedSkills.map((skill) => (
              <SkillCard key={skill.id} skill={skill} />
            ))}
          </div>
        </section>
      )}

      <section>
        <h2 className="text-lg font-medium text-white mb-3">{t('skills.available')}</h2>
        {availableSkills.length === 0 ? (
          <div className="text-gray-400 text-center py-8">{t('skills.noAvailable')}</div>
        ) : (
          <div className="grid gap-4">
            {availableSkills.map((skill) => (
              <SkillCard key={skill.id} skill={skill} />
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
