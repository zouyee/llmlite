import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import { UniversalProviderForm } from '@/components/providers/UniversalProviderForm'
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

describe('UniversalProviderForm', () => {
  it('renders form fields for new provider', () => {
    render(<UniversalProviderForm onSubmit={() => {}} onCancel={() => {}} />)
    expect(screen.getByText('Name')).toBeInTheDocument()
    expect(screen.getByText('Base URL')).toBeInTheDocument()
    expect(screen.getByText('Default Model')).toBeInTheDocument()
    expect(screen.getByText('Create')).toBeInTheDocument()
    expect(screen.getByText('Cancel')).toBeInTheDocument()
  })

  it('renders form fields for existing provider with save button', () => {
    render(<UniversalProviderForm provider={mockProvider} onSubmit={() => {}} onCancel={() => {}} />)
    expect(screen.getByDisplayValue('OpenAI')).toBeInTheDocument()
    expect(screen.getByDisplayValue('https://api.openai.com/v1')).toBeInTheDocument()
    expect(screen.getByDisplayValue('gpt-4o')).toBeInTheDocument()
    expect(screen.getByText('Save')).toBeInTheDocument()
  })
})
