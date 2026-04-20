import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import { UniversalProviderCard } from '@/components/providers/UniversalProviderCard'
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
  description: 'Official OpenAI provider',
}

describe('UniversalProviderCard', () => {
  it('renders provider name and official badge', () => {
    render(<UniversalProviderCard provider={mockProvider} onEdit={() => {}} onDelete={() => {}} />)
    expect(screen.getByText('OpenAI')).toBeInTheDocument()
    expect(screen.getByText('Official')).toBeInTheDocument()
  })

  it('renders custom badge for unofficial provider', () => {
    const customProvider = { ...mockProvider, is_official: false }
    render(<UniversalProviderCard provider={customProvider} onEdit={() => {}} onDelete={() => {}} />)
    expect(screen.getByText('Custom')).toBeInTheDocument()
  })

  it('renders disabled badge when provider is disabled', () => {
    const disabledProvider = { ...mockProvider, enabled: false }
    render(<UniversalProviderCard provider={disabledProvider} onEdit={() => {}} onDelete={() => {}} />)
    expect(screen.getByText('Disabled')).toBeInTheDocument()
  })

  it('renders edit and delete buttons', () => {
    render(<UniversalProviderCard provider={mockProvider} onEdit={() => {}} onDelete={() => {}} />)
    expect(screen.getByText('Edit')).toBeInTheDocument()
    expect(screen.getByText('Delete')).toBeInTheDocument()
  })
})
