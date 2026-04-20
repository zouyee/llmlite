import { useSortable } from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'
import { GripVertical, ExternalLink, MoreVertical, Activity, Zap, Shield } from 'lucide-react'
import type { Provider } from '@/lib/api/providers'
import { FeatureBadge } from './ProviderHelpers'
import { HealthStatusBadge } from './HealthStatusBadge'
import { FailoverPriorityBadge } from './FailoverPriorityBadge'
import { CircuitBreakerBadge } from './CircuitBreakerBadge'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'

interface ProviderCardProps {
  provider: Provider
  isActive?: boolean
  healthStatus?: 'healthy' | 'degraded' | 'unhealthy'
  failoverPriority?: number
  circuitState?: 'closed' | 'open' | 'half_open'
  onEdit: () => void
  onTest: () => void
  onSetActive: () => void
  onToggleEnabled: () => void
  onDelete: () => void
}

export function ProviderCard({
  provider,
  isActive,
  healthStatus,
  failoverPriority,
  circuitState,
  onEdit,
  onTest,
  onSetActive,
  onToggleEnabled,
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
      } ${isActive ? 'ring-2 ring-green-500' : ''} ${!provider.enabled ? 'opacity-60' : ''}`}
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
            {!provider.enabled && (
              <span className="px-2 py-0.5 text-xs bg-gray-600 rounded text-white">
                Disabled
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

          {/* Status Badges */}
          <div className="flex gap-2 mt-2 flex-wrap">
            {healthStatus && (
              <HealthStatusBadge status={healthStatus} />
            )}
            {failoverPriority !== undefined && (
              <FailoverPriorityBadge priority={failoverPriority} />
            )}
            {circuitState && (
              <CircuitBreakerBadge state={circuitState} />
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

        <DropdownMenu>
          <DropdownMenuTrigger>
            <button className="p-2 hover:bg-gray-700 rounded">
              <MoreVertical className="w-4 h-4 text-gray-400" />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent className="bg-gray-800 border-gray-700 text-gray-100">
            <DropdownMenuItem onClick={onEdit} className="cursor-pointer hover:bg-gray-700">
              <Activity className="w-4 h-4 mr-2" />
              Edit
            </DropdownMenuItem>
            <DropdownMenuItem onClick={onTest} className="cursor-pointer hover:bg-gray-700">
              <Zap className="w-4 h-4 mr-2" />
              Test Connection
            </DropdownMenuItem>
            {!isActive && (
              <DropdownMenuItem onClick={onSetActive} className="cursor-pointer hover:bg-gray-700">
                <Shield className="w-4 h-4 mr-2" />
                Set Active
              </DropdownMenuItem>
            )}
            <DropdownMenuItem onClick={onToggleEnabled} className="cursor-pointer hover:bg-gray-700">
              {provider.enabled ? 'Disable' : 'Enable'}
            </DropdownMenuItem>
            <DropdownMenuSeparator className="bg-gray-700" />
            <DropdownMenuItem onClick={onDelete} className="cursor-pointer hover:bg-gray-700 text-red-400">
              Delete
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>
  )
}
