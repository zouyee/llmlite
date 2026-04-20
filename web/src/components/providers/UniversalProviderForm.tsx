import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import type { Provider } from '@/lib/api/providers'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'

interface ProviderTypeField {
  name: string
  label: string
  type: 'text' | 'number' | 'url' | 'select'
  options?: string[]
  required?: boolean
}

const typeFieldRegistry: Record<string, ProviderTypeField[]> = {
  default: [
    { name: 'name', label: 'Name', type: 'text', required: true },
    { name: 'base_url', label: 'Base URL', type: 'url', required: true },
    { name: 'default_model', label: 'Default Model', type: 'text', required: true },
    { name: 'api_key_env', label: 'API Key Env Var', type: 'text' },
  ],
}

interface UniversalProviderFormProps {
  provider?: Provider | null
  onSubmit: (data: Record<string, unknown>) => void
  onCancel: () => void
}

export function UniversalProviderForm({ provider, onSubmit, onCancel }: UniversalProviderFormProps) {
  const { t } = useTranslation()
  const [form, setForm] = useState<Record<string, unknown>>(() => {
    if (provider) {
      return { ...provider }
    }
    return { enabled: true, auth_type: 'bearer' }
  })

  const fields = typeFieldRegistry.default

  const handleChange = (name: string, value: unknown) => {
    setForm((prev) => ({ ...prev, [name]: value }))
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    onSubmit(form)
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      {fields.map((field) => (
        <div key={field.name}>
          <Label className="text-gray-300">
            {field.label}
            {field.required && <span className="text-red-400 ml-1">*</span>}
          </Label>
          {field.type === 'select' ? (
            <select
              value={String(form[field.name] || '')}
              onChange={(e) => handleChange(field.name, e.target.value)}
              className="w-full mt-1 px-3 py-2 bg-gray-900 border border-gray-700 rounded-lg text-gray-200"
            >
              {field.options?.map((opt) => (
                <option key={opt} value={opt}>
                  {opt}
                </option>
              ))}
            </select>
          ) : (
            <Input
              type={field.type === 'number' ? 'number' : 'text'}
              value={String(form[field.name] || '')}
              onChange={(e) => handleChange(field.name, e.target.value)}
              className="mt-1 bg-gray-900 border-gray-700"
            />
          )}
        </div>
      ))}
      <div className="flex items-center gap-2">
        <Switch
          checked={!!form.enabled}
          onCheckedChange={(v) => handleChange('enabled', v)}
        />
        <Label className="text-gray-300">{t('provider.enabled', 'Enabled')}</Label>
      </div>
      <div className="flex justify-end gap-3 pt-2">
        <button
          type="button"
          onClick={onCancel}
          className="px-4 py-2 rounded-lg bg-gray-700 hover:bg-gray-600 text-sm"
        >
          {t('common.cancel', 'Cancel')}
        </button>
        <button
          type="submit"
          className="px-4 py-2 rounded-lg bg-blue-600 hover:bg-blue-500 text-sm"
        >
          {provider ? t('common.save', 'Save') : t('common.create', 'Create')}
        </button>
      </div>
    </form>
  )
}
