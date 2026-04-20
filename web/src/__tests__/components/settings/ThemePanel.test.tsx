import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { ThemePanel } from '@/components/settings/ThemePanel'
import { render } from '../../test-utils'

describe('ThemePanel', () => {
  it('renders with dark/light buttons', async () => {
    render(<ThemePanel />)
    await waitFor(() => {
      expect(screen.getByRole('button', { name: /dark/i })).toBeInTheDocument()
    })
    expect(screen.getByRole('button', { name: /light/i })).toBeInTheDocument()
  })
})
