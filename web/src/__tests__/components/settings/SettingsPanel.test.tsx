import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import SettingsPanel from '@/components/settings/SettingsPanel'
import { render } from '../../test-utils'

describe('SettingsPanel', () => {
  it('renders settings sections', async () => {
    render(<SettingsPanel />)
    await waitFor(() => {
      expect(screen.getByText(/API Key/i)).toBeInTheDocument()
    })
  })
})
