import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { UniversalProviderPanel } from '@/components/providers/UniversalProviderPanel'
import { render } from '../../test-utils'

describe('UniversalProviderPanel', () => {
  it('renders panel with add provider button', async () => {
    render(<UniversalProviderPanel />)
    await waitFor(() => {
      expect(screen.getByText('Add Provider')).toBeInTheDocument()
    })
  })
})
