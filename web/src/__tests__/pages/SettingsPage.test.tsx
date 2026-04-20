import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import SettingsPage from '@/pages/SettingsPage'
import { render } from '../test-utils'

describe('SettingsPage', () => {
  it('renders settings page', async () => {
    render(<SettingsPage />)
    await waitFor(() => {
      expect(screen.getByRole('heading', { name: /Settings/i })).toBeInTheDocument()
    }, { timeout: 3000 })
  })
})
