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
import { Plus, Download } from 'lucide-react'
import {
  useProviders,
  useDeleteProvider,
  useSwitchProvider,
  useTestProvider,
  useUpdateProvider,
  useImportPreset,
  usePresets,
} from '@/hooks/useProvider'
import { useHealth } from '@/hooks/useHealth'
import { useDragSort } from '@/hooks/useDragSort'
import toast from 'react-hot-toast'
import type { Provider } from '@/lib/api/providers'
import { ProviderCard } from './ProviderCard'
import { AddProviderDialog } from './AddProviderDialog'
import { EditProviderDialog } from './EditProviderDialog'

export default function ProviderList() {
  const { t } = useTranslation()
  const { data: providers, isLoading } = useProviders()
  const { data: health } = useHealth()
  const { data: presets } = usePresets()
  const deleteProvider = useDeleteProvider()
  const switchProvider = useSwitchProvider()
  const testProvider = useTestProvider()
  const updateProvider = useUpdateProvider()
  const importPreset = useImportPreset()

  const [search, setSearch] = useState('')
  const [isAddDialogOpen, setIsAddDialogOpen] = useState(false)
  const [editingProvider, setEditingProvider] = useState<Provider | null>(null)
  const [showPresets, setShowPresets] = useState(false)

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
    try {
      await deleteProvider.mutateAsync(id)
      toast.success('Provider deleted')
    } catch {
      toast.error('Failed to delete provider')
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

  const handleToggleEnabled = async (provider: Provider) => {
    try {
      await updateProvider.mutateAsync({
        id: provider.id,
        config: { enabled: !provider.enabled },
      })
      toast.success(provider.enabled ? 'Provider disabled' : 'Provider enabled')
    } catch {
      toast.error('Failed to update provider')
    }
  }

  const handleImportPreset = async (presetId: string) => {
    try {
      await importPreset.mutateAsync(presetId)
      toast.success('Preset imported')
    } catch {
      toast.error('Failed to import preset')
    }
  }

  const getProviderHealth = (id: string) => {
    const p = health?.providers[id]
    if (!p) return undefined
    return p.healthy ? 'healthy' : ('degraded' as const)
  }

  const getCircuitState = (id: string) => {
    return health?.providers[id]?.circuit_state
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
        <div className="text-center py-12 space-y-4">
          <p className="text-gray-400">{t('provider.noProviders')}</p>
          <div className="flex justify-center gap-3">
            <button
              onClick={() => setIsAddDialogOpen(true)}
              className="px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded-lg text-white"
            >
              {t('provider.addFirst', 'Add Your First Provider')}
            </button>
            <button
              onClick={() => setShowPresets(!showPresets)}
              className="flex items-center gap-2 px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg text-white"
            >
              <Download className="w-4 h-4" />
              {t('provider.importPreset', 'Import Preset')}
            </button>
          </div>
          {showPresets && presets && (
            <div className="mt-4 grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3 max-w-2xl mx-auto">
              {presets.map((preset) => (
                <button
                  key={preset.id}
                  onClick={() => handleImportPreset(preset.id)}
                  className="text-left px-4 py-3 bg-gray-800 border border-gray-700 rounded-lg hover:border-blue-500 transition-colors"
                >
                  <div className="font-medium text-sm">{preset.name}</div>
                  <div className="text-xs text-gray-400 mt-1">{preset.description}</div>
                </button>
              ))}
            </div>
          )}
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
              {filteredProviders.map((provider, index) => (
                <ProviderCard
                  key={provider.id}
                  provider={provider}
                  isActive={index === 0}
                  healthStatus={getProviderHealth(provider.id)}
                  failoverPriority={index}
                  circuitState={getCircuitState(provider.id)}
                  onEdit={() => setEditingProvider(provider)}
                  onTest={() => handleTest(provider.id)}
                  onSetActive={() => handleSetActive(provider.id)}
                  onToggleEnabled={() => handleToggleEnabled(provider)}
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
