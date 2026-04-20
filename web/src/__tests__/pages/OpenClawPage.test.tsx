import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import OpenClawPage from '@/pages/OpenClawPage'
import { render } from '../test-utils'

describe('OpenClawPage', () => {
  it('renders openclaw page', async () => {
    render(<OpenClawPage />)
    await waitFor(() => {
      expect(screen.getByText(/OpenClaw/i)).toBeInTheDocument()
    }, { timeout: 3000 })
  })
})
