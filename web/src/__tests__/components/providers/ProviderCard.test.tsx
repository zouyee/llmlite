import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import { ProviderCard } from '@/components/providers/ProviderCard'
import { render } from '../../test-utils'

const mockProvider = {
  id: 'test-1',
  name: 'OpenAI',
  base_url: 'https://api.openai.com',
  auth_type: 'bearer' as const,
  default_model: 'gpt-4',
  supports: ['chat'],
  is_official: true,
  enabled: true,
}

describe('ProviderCard', () => {
  it('renders provider name and badges', () => {
    render(
      <ProviderCard
        provider={mockProvider}
        onEdit={() => {}}
        onTest={() => {}}
        onSetActive={() => {}}
        onToggleEnabled={() => {}}
        onDelete={() => {}}
      />
    )
    expect(screen.getByText('OpenAI')).toBeInTheDocument()
    expect(screen.getByText('Official')).toBeInTheDocument()
  })
})
