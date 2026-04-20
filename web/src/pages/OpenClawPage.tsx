import { useTranslation } from 'react-i18next'
import { OpenClawAgentConfig } from '@/components/openclaw/OpenClawAgentConfig'
import { OpenClawEnvPanel } from '@/components/openclaw/OpenClawEnvPanel'
import { OpenClawToolsPanel } from '@/components/openclaw/OpenClawToolsPanel'

export default function OpenClawPage() {
  const { t } = useTranslation()

  return (
    <div className="space-y-4">
      <h2 className="text-xl font-semibold text-white">
        {t('openclaw.title', 'OpenClaw Configuration')}
      </h2>
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <OpenClawAgentConfig />
        <OpenClawToolsPanel />
      </div>
      <OpenClawEnvPanel />
    </div>
  )
}
