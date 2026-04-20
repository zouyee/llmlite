import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import App from '@/App'
import { render } from '../test-utils'

describe('Navigation Flow Integration', () => {
  it('renders App with sidebar navigation', async () => {
    render(<App />)
    await waitFor(() => {
      expect(screen.getAllByText(/llmlite/i).length).toBeGreaterThan(0)
    }, { timeout: 3000 })
  })
})
