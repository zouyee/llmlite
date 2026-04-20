import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import SessionManagerPage from '@/pages/SessionManagerPage'
import { render } from '../test-utils'

describe('SessionManagerPage', () => {
  it('renders session manager page', async () => {
    render(<SessionManagerPage />)
    await waitFor(() => {
      expect(screen.getByRole('heading', { name: /Session/i })).toBeInTheDocument()
    }, { timeout: 3000 })
  })
})
