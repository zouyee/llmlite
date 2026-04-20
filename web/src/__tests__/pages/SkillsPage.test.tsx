import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import SkillsPage from '@/pages/SkillsPage'
import { render } from '../test-utils'

describe('SkillsPage', () => {
  it('renders skills page', async () => {
    render(<SkillsPage />)
    await waitFor(() => {
      expect(screen.getByText(/Skills/i)).toBeInTheDocument()
    }, { timeout: 3000 })
  })
})
