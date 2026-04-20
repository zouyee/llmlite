import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useOpenClawConfig, useUpdateOpenClawConfig } from '@/hooks/useOpenClaw'
import { Input } from '@/components/ui/input'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Plus, Trash2 } from 'lucide-react'

export function OpenClawEnvPanel() {
  const { t } = useTranslation()
  const { data: config } = useOpenClawConfig()
  const update = useUpdateOpenClawConfig()
  const [newKey, setNewKey] = useState('')
  const [newVal, setNewVal] = useState('')

  if (!config) return null

  const env = config.env_vars || {}

  const handleAdd = () => {
    if (!newKey.trim()) return
    update.mutate({ env_vars: { ...env, [newKey]: newVal } })
    setNewKey('')
    setNewVal('')
  }

  const handleRemove = (key: string) => {
    const next = { ...env }
    delete next[key]
    update.mutate({ env_vars: next })
  }

  const handleUpdate = (key: string, value: string) => {
    update.mutate({ env_vars: { ...env, [key]: value } })
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t('openclaw.env.title', 'Environment Variables')}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {Object.entries(env).map(([key, value]) => (
          <div key={key} className="flex items-center gap-2">
            <Input value={key} readOnly className="w-1/3 bg-gray-900 border-gray-700" />
            <Input
              value={value}
              onChange={(e) => handleUpdate(key, e.target.value)}
              className="flex-1 bg-gray-900 border-gray-700"
            />
            <button
              onClick={() => handleRemove(key)}
              className="p-2 text-red-400 hover:bg-red-900/20 rounded"
            >
              <Trash2 className="w-4 h-4" />
            </button>
          </div>
        ))}
        <div className="flex items-center gap-2 pt-2 border-t border-gray-700">
          <Input
            value={newKey}
            onChange={(e) => setNewKey(e.target.value)}
            placeholder={t('openclaw.env.key', 'Key')}
            className="w-1/3 bg-gray-900 border-gray-700"
          />
          <Input
            value={newVal}
            onChange={(e) => setNewVal(e.target.value)}
            placeholder={t('openclaw.env.value', 'Value')}
            className="flex-1 bg-gray-900 border-gray-700"
          />
          <button
            onClick={handleAdd}
            className="p-2 text-blue-400 hover:bg-blue-900/20 rounded"
          >
            <Plus className="w-4 h-4" />
          </button>
        </div>
      </CardContent>
    </Card>
  )
}
