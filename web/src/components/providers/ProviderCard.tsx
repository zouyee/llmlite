import { useSortable } from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'
import { GripVertical, ExternalLink } from 'lucide-react'
import type { Provider } from '@/lib/api/llmlite'
import { FeatureBadge } from './ProviderHelpers'

interface ProviderCardProps {
  provider: Provider
  isActive?: boolean
  onEdit: () => void
  onTest: () => void
  onSetActive: () => void
  onDelete: () => void
}

export function ProviderCard({
  provider,
  isActive,
  onEdit,
  onTest,
  onSetActive,
  onDelete,
}: ProviderCardProps) {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: provider.id })

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  }

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={`bg-gray-800 rounded-lg p-4 border ${
        isDragging ? 'border-blue-500 shadow-lg' : 'border-gray-700'
      } ${isActive ? 'ring-2 ring-green-500' : ''}`}
    >
      <div className="flex items-start gap-3">
        <button
          className="mt-1 p-1 hover:bg-gray-700 rounded cursor-grab active:cursor-grabbing"
          {...attributes}
          {...listeners}
        >
          <GripVertical className="w-5 h-5 text-gray-500" />
        </button>

        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <h3 className="font-medium text-white">{provider.name}</h3>
            {provider.is_official && (
              <span className="px-2 py-0.5 text-xs bg-blue-600 rounded text-white">
                Official
              </span>
            )}
            {isActive && (
              <span className="px-2 py-0.5 text-xs bg-green-600 rounded text-white">
                Active
              </span>
            )}
          </div>

          {provider.organization && (
            <p className="text-sm text-gray-400 mt-0.5">{provider.organization}</p>
          )}

          <div className="flex items-center gap-2 mt-1">
            <p className="text-xs text-gray-500 truncate max-w-md">{provider.base_url}</p>
            {provider.website && (
              <a
                href={provider.website}
                target="_blank"
                rel="noopener noreferrer"
                className="text-gray-400 hover:text-white"
              >
                <ExternalLink className="w-3 h-3" />
              </a>
            )}
          </div>

          {provider.description && (
            <p className="text-sm text-gray-300 mt-2">{provider.description}</p>
          )}

          <div className="flex gap-2 mt-2 flex-wrap">
            {provider.supports.map((s) => (
              <FeatureBadge key={s} feature={s} />
            ))}
          </div>
        </div>

        <div className="flex gap-2 flex-shrink-0">
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
      </div>
    </div>
  )
}