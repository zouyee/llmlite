import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useProviders, useCreateProvider, useUpdateProvider, useDeleteProvider } from '@/hooks/useProvider'
import type { Provider } from '@/lib/api/providers'
import { UniversalProviderCard } from './UniversalProviderCard'
import { UniversalProviderForm } from './UniversalProviderForm'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Plus } from 'lucide-react'

export function UniversalProviderPanel() {
  const { t } = useTranslation()
  const { data: providers } = useProviders()
  const createProvider = useCreateProvider()
  const updateProvider = useUpdateProvider()
  const deleteProvider = useDeleteProvider()
  const [editing, setEditing] = useState<Provider | null>(null)
  const [isDialogOpen, setIsDialogOpen] = useState(false)

  const handleSubmit = (data: Record<string, unknown>) => {
    if (editing) {
      updateProvider.mutate({ id: editing.id, config: data as never })
    } else {
      createProvider.mutate(data as never)
    }
    setIsDialogOpen(false)
    setEditing(null)
  }

  return (
    <div className="space-y-4">
      <div className="flex justify-between items-center">
        <h2 className="text-xl font-semibold">{t('provider.title', 'Providers')}</h2>
        <button
          onClick={() => {
            setEditing(null)
            setIsDialogOpen(true)
          }}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded-lg text-sm"
        >
          <Plus className="w-4 h-4" />
          {t('provider.add', 'Add Provider')}
        </button>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {providers?.map((p) => (
          <UniversalProviderCard
            key={p.id}
            provider={p}
            onEdit={() => {
              setEditing(p)
              setIsDialogOpen(true)
            }}
            onDelete={() => deleteProvider.mutate(p.id)}
          />
        ))}
      </div>
      <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
        <DialogContent className="bg-gray-800 border-gray-700 text-gray-100">
          <DialogHeader>
            <DialogTitle>
              {editing ? t('provider.edit', 'Edit Provider') : t('provider.add', 'Add Provider')}
            </DialogTitle>
          </DialogHeader>
          <UniversalProviderForm
            provider={editing}
            onSubmit={handleSubmit}
            onCancel={() => setIsDialogOpen(false)}
          />
        </DialogContent>
      </Dialog>
    </div>
  )
}
