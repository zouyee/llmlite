import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { ProxyToggle } from '@/components/proxy/ProxyToggle'
import { render } from '../../test-utils'

describe('ProxyToggle', () => {
  it('renders proxy status', async () => {
    render(<ProxyToggle />)
    await waitFor(() => {
      expect(screen.getByText(/Running|Stopped/i)).toBeInTheDocument()
    }, { timeout: 3000 })
  })
})
