import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import ProxyPage from '@/pages/ProxyPage'
import { render } from '../test-utils'

describe('ProxyPage', () => {
  it('renders proxy control page', async () => {
    render(<ProxyPage />)
    await waitFor(() => {
      expect(screen.getByText(/Proxy Control/i)).toBeInTheDocument()
    }, { timeout: 3000 })
    expect(screen.getByText(/Proxy Status/i)).toBeInTheDocument()
  })
})
