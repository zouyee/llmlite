import { useState, useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import {
  DndContext,
  closestCenter,
  KeyboardSensor,
  PointerSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from '@dnd-kit/core'
import {
  SortableContext,
  sortableKeyboardCoordinates,
  verticalListSortingStrategy,
} from '@dnd-kit/sortable'
import { Plus } from 'lucide-react'
import {
  useProviders,
  useDeleteProvider,
  useSwitchProvider,
  useTestProvider,
} from '@/hooks/useProvider'
import { useDragSort } from '@/hooks/useDragSort'
import toast from 'react-hot-toast'
import type { Provider } from '@/lib/api/llmlite'
import { ProviderCard } from './ProviderCard'
import { AddProviderDialog } from './AddProviderDialog'
import { EditProviderDialog } from './EditProviderDialog'

export default function ProviderList() {
  const { t } = useTranslation()
  const { data: providers, isLoading } = useProviders()
  const deleteProvider = useDeleteProvider()
  const switchProvider = useSwitchProvider()
  const testProvider = useTestProvider()

  const [search, setSearch] = useState('')
  const [isAddDialogOpen, setIsAddDialogOpen] = useState(false)
  const [editingProvider, setEditingProvider] = useState<Provider | null>(null)

  const sensors = useSensors(
    useSensor(PointerSensor),
    useSensor(KeyboardSensor, {
      coordinateGetter: sortableKeyboardCoordinates,
    })
  )

  const { localItems: sortedProviders, handleDragEnd } = useDragSort({
    items: providers || [],
    getId: (p) => p.id,
  })

  const filteredProviders = useMemo(() => {
    if (!sortedProviders) return []
    return sortedProviders.filter(
      (p) =>
        p.name.toLowerCase().includes(search.toLowerCase()) ||
        p.organization?.toLowerCase().includes(search.toLowerCase())
    )
  }, [sortedProviders, search])

  const handleDragEndEvent = (event: DragEndEvent) => {
    const { active, over } = event
    if (over && active.id !== over.id) {
      handleDragEnd(String(active.id), String(over.id))
    }
  }

  const handleDelete = async (id: string) => {
    if (confirm('Delete this provider?')) {
      try {
        await deleteProvider.mutateAsync(id)
        toast.success('Provider deleted')
      } catch {
        toast.error('Failed to delete provider')
      }
    }
  }

  const handleSetActive = async (id: string) => {
    try {
      await switchProvider.mutateAsync(id)
      toast.success('Provider set as active')
    } catch {
      toast.error('Failed to set active provider')
    }
  }

  const handleTest = async (id: string) => {
    try {
      const result = await testProvider.mutateAsync(id)
      if (result.success) {
        toast.success(`Latency: ${result.latency_ms}ms`)
      } else {
        toast.error(result.error || 'Test failed')
      }
    } catch {
      toast.error('Test failed')
    }
  }

  if (isLoading) {
    return <div className="text-gray-400">{t('app.loading')}</div>
  }

  return (
    <div>
      <div className="flex justify-between items-center mb-4 gap-4">
        <input
          type="text"
          placeholder={t('provider.searchPlaceholder')}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="flex-1 px-4 py-2 bg-gray-800 border border-gray-700 rounded-lg text-white placeholder-gray-500 focus:outline-none focus:border-blue-500"
        />
        <button
          onClick={() => setIsAddDialogOpen(true)}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded-lg text-white"
        >
          <Plus className="w-4 h-4" />
          Add Provider
        </button>
      </div>

      {!filteredProviders.length ? (
        <div className="text-center py-12">
          <p className="text-gray-400 mb-4">No providers configured</p>
          <button
            onClick={() => setIsAddDialogOpen(true)}
            className="px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded-lg text-white"
          >
            Add Your First Provider
          </button>
        </div>
      ) : (
        <DndContext
          sensors={sensors}
          collisionDetection={closestCenter}
          onDragEnd={handleDragEndEvent}
        >
          <SortableContext
            items={filteredProviders.map((p) => p.id)}
            strategy={verticalListSortingStrategy}
          >
            <div className="grid gap-3">
              {filteredProviders.map((provider) => (
                <ProviderCard
                  key={provider.id}
                  provider={provider}
                  onEdit={() => setEditingProvider(provider)}
                  onTest={() => handleTest(provider.id)}
                  onSetActive={() => handleSetActive(provider.id)}
                  onDelete={() => handleDelete(provider.id)}
                />
              ))}
            </div>
          </SortableContext>
        </DndContext>
      )}

      <AddProviderDialog
        isOpen={isAddDialogOpen}
        onClose={() => setIsAddDialogOpen(false)}
      />

      <EditProviderDialog
        isOpen={!!editingProvider}
        onClose={() => setEditingProvider(null)}
        provider={editingProvider}
      />
    </div>
  )
}
