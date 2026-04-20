import { useState } from 'react'
import { X } from 'lucide-react'
import { usePresets, useCreateProvider, useImportPreset } from '@/hooks/useProvider'
import type { CreateProviderRequest } from '@/lib/api/providers'

interface AddProviderDialogProps {
  isOpen: boolean
  onClose: () => void
}

export function AddProviderDialog({ isOpen, onClose }: AddProviderDialogProps) {
  const { data: presets } = usePresets()
  const createProvider = useCreateProvider()
  const importPreset = useImportPreset()

  const [tab, setTab] = useState<'manual' | 'presets'>('manual')
  const [formData, setFormData] = useState<CreateProviderRequest>({
    id: '',
    name: '',
    base_url: '',
    auth_type: 'bearer',
    api_key: '',
    default_model: '',
    supports: [],
    enabled: true,
  })

  if (!isOpen) return null

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    try {
      await createProvider.mutateAsync(formData)
      onClose()
      setFormData({
        id: '',
        name: '',
        base_url: '',
        auth_type: 'bearer',
        api_key: '',
        default_model: '',
        supports: [],
        enabled: true,
      })
    } catch (error) {
      console.error('Failed to create provider:', error)
    }
  }

  const handleImportPreset = async (presetId: string) => {
    try {
      await importPreset.mutateAsync(presetId)
      onClose()
    } catch (error) {
      console.error('Failed to import preset:', error)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-gray-800 rounded-lg w-full max-w-2xl max-h-[90vh] overflow-hidden">
        <div className="flex items-center justify-between p-4 border-b border-gray-700">
          <h2 className="text-lg font-medium text-white">Add Provider</h2>
          <button
            onClick={onClose}
            className="p-1 hover:bg-gray-700 rounded"
          >
            <X className="w-5 h-5 text-gray-400" />
          </button>
        </div>

        <div className="flex border-b border-gray-700">
          <button
            onClick={() => setTab('manual')}
            className={`px-4 py-2 text-sm ${
              tab === 'manual'
                ? 'text-white border-b-2 border-blue-500'
                : 'text-gray-400 hover:text-white'
            }`}
          >
            Manual
          </button>
          <button
            onClick={() => setTab('presets')}
            className={`px-4 py-2 text-sm ${
              tab === 'presets'
                ? 'text-white border-b-2 border-blue-500'
                : 'text-gray-400 hover:text-white'
            }`}
          >
            From Presets
          </button>
        </div>

        <div className="p-4 overflow-y-auto max-h-[calc(90vh-120px)]">
          {tab === 'manual' ? (
            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label className="block text-sm text-gray-400 mb-1">
                  Provider ID (unique)
                </label>
                <input
                  type="text"
                  value={formData.id}
                  onChange={(e) => setFormData({ ...formData, id: e.target.value })}
                  className="w-full px-3 py-2 bg-gray-900 border border-gray-700 rounded text-white focus:outline-none focus:border-blue-500"
                  required
                />
              </div>

              <div>
                <label className="block text-sm text-gray-400 mb-1">Name</label>
                <input
                  type="text"
                  value={formData.name}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                  className="w-full px-3 py-2 bg-gray-900 border border-gray-700 rounded text-white focus:outline-none focus:border-blue-500"
                  required
                />
              </div>

              <div>
                <label className="block text-sm text-gray-400 mb-1">Base URL</label>
                <input
                  type="url"
                  value={formData.base_url}
                  onChange={(e) => setFormData({ ...formData, base_url: e.target.value })}
                  className="w-full px-3 py-2 bg-gray-900 border border-gray-700 rounded text-white focus:outline-none focus:border-blue-500"
                  placeholder="https://api.example.com"
                  required
                />
              </div>

              <div>
                <label className="block text-sm text-gray-400 mb-1">Auth Type</label>
                <select
                  value={formData.auth_type}
                  onChange={(e) =>
                    setFormData({
                      ...formData,
                      auth_type: e.target.value as CreateProviderRequest['auth_type'],
                    })
                  }
                  className="w-full px-3 py-2 bg-gray-900 border border-gray-700 rounded text-white focus:outline-none focus:border-blue-500"
                >
                  <option value="bearer">Bearer Token</option>
                  <option value="api_key">API Key</option>
                  <option value="none">None</option>
                </select>
              </div>

              <div>
                <label className="block text-sm text-gray-400 mb-1">API Key</label>
                <input
                  type="password"
                  value={formData.api_key || ''}
                  onChange={(e) => setFormData({ ...formData, api_key: e.target.value })}
                  className="w-full px-3 py-2 bg-gray-900 border border-gray-700 rounded text-white focus:outline-none focus:border-blue-500"
                />
              </div>

              <div>
                <label className="block text-sm text-gray-400 mb-1">Default Model</label>
                <input
                  type="text"
                  value={formData.default_model}
                  onChange={(e) => setFormData({ ...formData, default_model: e.target.value })}
                  className="w-full px-3 py-2 bg-gray-900 border border-gray-700 rounded text-white focus:outline-none focus:border-blue-500"
                  placeholder="gpt-4o"
                  required
                />
              </div>

              <div className="flex justify-end gap-3 pt-4">
                <button
                  type="button"
                  onClick={onClose}
                  className="px-4 py-2 text-sm bg-gray-700 hover:bg-gray-600 rounded text-white"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={createProvider.isPending}
                  className="px-4 py-2 text-sm bg-blue-600 hover:bg-blue-500 rounded text-white disabled:opacity-50"
                >
                  {createProvider.isPending ? 'Creating...' : 'Create'}
                </button>
              </div>
            </form>
          ) : (
            <div className="grid gap-3">
              {presets?.map((preset) => (
                <div
                  key={preset.id}
                  className="bg-gray-900 rounded-lg p-4 border border-gray-700 flex items-center justify-between"
                >
                  <div>
                    <h4 className="font-medium text-white">{preset.name}</h4>
                    <p className="text-xs text-gray-500 mt-0.5">{preset.base_url}</p>
                    <div className="flex gap-1 mt-1">
                      {preset.features.map((f) => (
                        <span key={f} className="px-1.5 py-0.5 text-xs bg-gray-700 rounded">
                          {f}
                        </span>
                      ))}
                    </div>
                  </div>
                  <button
                    onClick={() => handleImportPreset(preset.id)}
                    disabled={importPreset.isPending}
                    className="px-3 py-1 text-sm bg-green-600 hover:bg-green-500 rounded text-white disabled:opacity-50"
                  >
                    Import
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}