import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { ProxyConfigPanel } from '@/components/settings/ProxyConfigPanel'
import { render } from '../../test-utils'

describe('ProxyConfigPanel', () => {
  it('renders with inputs and switch', async () => {
    render(<ProxyConfigPanel />)
    await waitFor(() => {
      expect(screen.getByText('settings.proxy')).toBeInTheDocument()
    })
    expect(screen.getAllByRole('spinbutton').length).toBeGreaterThanOrEqual(1)
    expect(screen.getByRole('checkbox')).toBeInTheDocument()
  })
})
