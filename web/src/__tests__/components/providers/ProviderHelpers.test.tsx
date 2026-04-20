import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import {
  ProviderHealthBadge,
  FailoverBadge,
  ProviderActions,
  ProviderEmptyState,
  FeatureBadge,
} from '@/components/providers/ProviderHelpers'
import { render } from '../../test-utils'

const mockProvider = {
  id: 'openai',
  name: 'OpenAI',
  base_url: 'https://api.openai.com/v1',
  auth_type: 'bearer' as const,
  default_model: 'gpt-4o',
  supports: ['chat'],
  is_official: true,
  enabled: true,
}

describe('ProviderHelpers', () => {
  it('ProviderHealthBadge renders unknown when no latency', () => {
    render(<ProviderHealthBadge provider={mockProvider} />)
    expect(screen.getByText('Unknown')).toBeInTheDocument()
  })

  it('ProviderHealthBadge renders latency with color', () => {
    render(<ProviderHealthBadge provider={mockProvider} latencyMs={120} />)
    expect(screen.getByText('120ms')).toBeInTheDocument()
  })

  it('FailoverBadge renders circuit state', () => {
    render(<FailoverBadge circuitState="closed" />)
    expect(screen.getByText('closed')).toBeInTheDocument()
  })

  it('FailoverBadge renders half_open state', () => {
    render(<FailoverBadge circuitState="half_open" />)
    expect(screen.getByText('half open')).toBeInTheDocument()
  })

  it('ProviderActions renders action buttons', () => {
    render(<ProviderActions onEdit={() => {}} onTest={() => {}} onSetActive={() => {}} onDelete={() => {}} />)
    expect(screen.getByText('Test')).toBeInTheDocument()
    expect(screen.getByText('Set Active')).toBeInTheDocument()
    expect(screen.getByText('Edit')).toBeInTheDocument()
    expect(screen.getByText('Delete')).toBeInTheDocument()
  })

  it('ProviderActions hides Set Active when isActive', () => {
    render(
      <ProviderActions
        onEdit={() => {}}
        onTest={() => {}}
        onSetActive={() => {}}
        onDelete={() => {}}
        isActive={true}
      />
    )
    expect(screen.getByText('Test')).toBeInTheDocument()
    expect(screen.queryByText('Set Active')).not.toBeInTheDocument()
    expect(screen.getByText('Edit')).toBeInTheDocument()
    expect(screen.getByText('Delete')).toBeInTheDocument()
  })

  it('ProviderEmptyState renders empty state with buttons', () => {
    render(<ProviderEmptyState onAddProvider={() => {}} onImportPreset={() => {}} />)
    expect(screen.getByText('No providers configured')).toBeInTheDocument()
    expect(screen.getByText('Add Provider')).toBeInTheDocument()
    expect(screen.getByText('Import from Preset')).toBeInTheDocument()
  })

  it('FeatureBadge renders feature name', () => {
    render(<FeatureBadge feature="chat" />)
    expect(screen.getByText('chat')).toBeInTheDocument()
  })
})
