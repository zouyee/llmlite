import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { AddProviderDialog } from '@/components/providers/AddProviderDialog'
import { render } from '../../test-utils'

describe('AddProviderDialog', () => {
  it('renders dialog when open', async () => {
    render(<AddProviderDialog isOpen={true} onClose={() => {}} />)
    await waitFor(() => {
      expect(screen.getByText('Add Provider')).toBeInTheDocument()
    })
    expect(screen.getByText('Manual')).toBeInTheDocument()
    expect(screen.getByText('From Presets')).toBeInTheDocument()
  })

  it('does not render when closed', () => {
    const { container } = render(<AddProviderDialog isOpen={false} onClose={() => {}} />)
    expect(container).toBeEmptyDOMElement()
  })
})
