import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import UsageDashboard from '@/pages/UsageDashboard'
import { render } from '../test-utils'

describe('UsageDashboard', () => {
  it('renders usage dashboard', async () => {
    render(<UsageDashboard />)
    await waitFor(() => {
      expect(screen.getByRole('heading', { name: /Usage/i })).toBeInTheDocument()
    }, { timeout: 3000 })
  })
})
