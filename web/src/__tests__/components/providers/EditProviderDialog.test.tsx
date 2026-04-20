import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { EditProviderDialog } from '@/components/providers/EditProviderDialog'
import { render } from '../../test-utils'

const mockProvider = {
  id: 'openai',
  name: 'OpenAI',
  base_url: 'https://api.openai.com/v1',
  auth_type: 'bearer' as const,
  default_model: 'gpt-4o',
  supports: ['chat', 'embeddings'],
  is_official: true,
  enabled: true,
}

describe('EditProviderDialog', () => {
  it('renders dialog with provider data when open', async () => {
    render(<EditProviderDialog isOpen={true} onClose={() => {}} provider={mockProvider} />)
    await waitFor(() => {
      expect(screen.getByText('Edit Provider')).toBeInTheDocument()
    })
    expect(screen.getByDisplayValue('OpenAI')).toBeInTheDocument()
    expect(screen.getByDisplayValue('https://api.openai.com/v1')).toBeInTheDocument()
  })

  it('does not render when closed', () => {
    const { container } = render(<EditProviderDialog isOpen={false} onClose={() => {}} provider={mockProvider} />)
    expect(container).toBeEmptyDOMElement()
  })

  it('does not render when provider is null', () => {
    const { container } = render(<EditProviderDialog isOpen={true} onClose={() => {}} provider={null} />)
    expect(container).toBeEmptyDOMElement()
  })
})
