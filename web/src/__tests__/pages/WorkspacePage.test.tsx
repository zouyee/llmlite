import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import WorkspacePage from '@/pages/WorkspacePage'
import { render } from '../test-utils'

describe('WorkspacePage', () => {
  it('renders workspace page', async () => {
    render(<WorkspacePage />)
    await waitFor(() => {
      expect(screen.getByText(/Files/i)).toBeInTheDocument()
    }, { timeout: 3000 })
  })
})
