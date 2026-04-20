import { useState, useEffect } from 'react'
import { X } from 'lucide-react'
import { useUpdateProvider } from '@/hooks/useProvider'
import type { Provider, UpdateProviderRequest } from '@/lib/api/providers'

interface EditProviderDialogProps {
  isOpen: boolean
  onClose: () => void
  provider: Provider | null
}

export function EditProviderDialog({ isOpen, onClose, provider }: EditProviderDialogProps) {
  const updateProvider = useUpdateProvider()

  const [formData, setFormData] = useState<UpdateProviderRequest>({})

  useEffect(() => {
    if (provider) {
      setFormData({
        name: provider.name,
        base_url: provider.base_url,
        auth_type: provider.auth_type,
        default_model: provider.default_model,
        supports: provider.supports,
        enabled: provider.enabled,
      })
    }
  }, [provider])

  if (!isOpen || !provider) return null

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    try {
      await updateProvider.mutateAsync({ id: provider.id, config: formData })
      onClose()
    } catch (error) {
      console.error('Failed to update provider:', error)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-gray-800 rounded-lg w-full max-w-2xl max-h-[90vh] overflow-hidden">
        <div className="flex items-center justify-between p-4 border-b border-gray-700">
          <h2 className="text-lg font-medium text-white">Edit Provider</h2>
          <button onClick={onClose} className="p-1 hover:bg-gray-700 rounded">
            <X className="w-5 h-5 text-gray-400" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-4 space-y-4 overflow-y-auto max-h-[calc(90vh-120px)]">
          <div>
            <label className="block text-sm text-gray-400 mb-1">Name</label>
            <input
              type="text"
              value={formData.name || ''}
              onChange={(e) => setFormData({ ...formData, name: e.target.value })}
              className="w-full px-3 py-2 bg-gray-900 border border-gray-700 rounded text-white focus:outline-none focus:border-blue-500"
              required
            />
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-1">Base URL</label>
            <input
              type="url"
              value={formData.base_url || ''}
              onChange={(e) => setFormData({ ...formData, base_url: e.target.value })}
              className="w-full px-3 py-2 bg-gray-900 border border-gray-700 rounded text-white focus:outline-none focus:border-blue-500"
              required
            />
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-1">Auth Type</label>
            <select
              value={formData.auth_type || 'bearer'}
              onChange={(e) =>
                setFormData({
                  ...formData,
                  auth_type: e.target.value as UpdateProviderRequest['auth_type'],
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
            <label className="block text-sm text-gray-400 mb-1">API Key (leave blank to keep current)</label>
            <input
              type="password"
              value={formData.api_key || ''}
              onChange={(e) => setFormData({ ...formData, api_key: e.target.value })}
              className="w-full px-3 py-2 bg-gray-900 border border-gray-700 rounded text-white focus:outline-none focus:border-blue-500"
              placeholder="••••••••"
            />
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-1">Default Model</label>
            <input
              type="text"
              value={formData.default_model || ''}
              onChange={(e) => setFormData({ ...formData, default_model: e.target.value })}
              className="w-full px-3 py-2 bg-gray-900 border border-gray-700 rounded text-white focus:outline-none focus:border-blue-500"
              required
            />
          </div>

          <div className="flex items-center gap-2">
            <input
              type="checkbox"
              id="enabled"
              checked={formData.enabled ?? true}
              onChange={(e) => setFormData({ ...formData, enabled: e.target.checked })}
              className="w-4 h-4"
            />
            <label htmlFor="enabled" className="text-sm text-gray-400">
              Enabled
            </label>
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
              disabled={updateProvider.isPending}
              className="px-4 py-2 text-sm bg-blue-600 hover:bg-blue-500 rounded text-white disabled:opacity-50"
            >
              {updateProvider.isPending ? 'Saving...' : 'Save'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}