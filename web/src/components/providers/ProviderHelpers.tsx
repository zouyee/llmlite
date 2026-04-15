import type { Provider } from '@/lib/api/llmlite'

interface ProviderHealthBadgeProps {
  provider: Provider
  latencyMs?: number
}

export function ProviderHealthBadge({ latencyMs }: ProviderHealthBadgeProps) {
  if (latencyMs === undefined) {
    return (
      <span className="px-2 py-0.5 text-xs bg-gray-700 rounded text-gray-400">
        Unknown
      </span>
    )
  }

  const getHealthColor = (ms: number) => {
    if (ms < 100) return 'bg-green-600'
    if (ms < 500) return 'bg-yellow-600'
    return 'bg-red-600'
  }

  return (
    <span className={`px-2 py-0.5 text-xs rounded text-white ${getHealthColor(latencyMs)}`}>
      {latencyMs}ms
    </span>
  )
}

interface FailoverBadgeProps {
  circuitState: 'closed' | 'open' | 'half_open'
}

export function FailoverBadge({ circuitState }: FailoverBadgeProps) {
  const getStateColor = (state: string) => {
    switch (state) {
      case 'closed':
        return 'bg-green-600'
      case 'half_open':
        return 'bg-yellow-600'
      case 'open':
        return 'bg-red-600'
      default:
        return 'bg-gray-600'
    }
  }

  return (
    <span className={`px-2 py-0.5 text-xs rounded text-white ${getStateColor(circuitState)}`}>
      {circuitState.replace('_', ' ')}
    </span>
  )
}

interface ProviderActionsProps {
  onEdit: () => void
  onTest: () => void
  onSetActive: () => void
  onDelete: () => void
  isActive?: boolean
}

export function ProviderActions({
  onEdit,
  onTest,
  onSetActive,
  onDelete,
  isActive,
}: ProviderActionsProps) {
  return (
    <div className="flex gap-2">
      <button
        onClick={onTest}
        className="px-3 py-1 text-sm bg-gray-700 hover:bg-gray-600 rounded"
      >
        Test
      </button>
      {!isActive && (
        <button
          onClick={onSetActive}
          className="px-3 py-1 text-sm bg-green-700 hover:bg-green-600 rounded"
        >
          Set Active
        </button>
      )}
      <button
        onClick={onEdit}
        className="px-3 py-1 text-sm bg-blue-700 hover:bg-blue-600 rounded"
      >
        Edit
      </button>
      <button
        onClick={onDelete}
        className="px-3 py-1 text-sm bg-red-700 hover:bg-red-600 rounded"
      >
        Delete
      </button>
    </div>
  )
}

interface ProviderEmptyStateProps {
  onAddProvider: () => void
  onImportPreset: () => void
}

export function ProviderEmptyState({ onAddProvider, onImportPreset }: ProviderEmptyStateProps) {
  return (
    <div className="text-center py-12">
      <p className="text-gray-400 mb-4">No providers configured</p>
      <div className="flex gap-4 justify-center">
        <button
          onClick={onAddProvider}
          className="px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded-lg text-white"
        >
          Add Provider
        </button>
        <button
          onClick={onImportPreset}
          className="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg text-white"
        >
          Import from Preset
        </button>
      </div>
    </div>
  )
}

interface FeatureBadgeProps {
  feature: string
}

export function FeatureBadge({ feature }: FeatureBadgeProps) {
  return (
    <span className="px-2 py-0.5 text-xs bg-gray-700 rounded text-gray-300">
      {feature}
    </span>
  )
}