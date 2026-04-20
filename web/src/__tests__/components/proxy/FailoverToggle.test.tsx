import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { FailoverToggle } from '@/components/proxy/FailoverToggle'
import { render } from '../../test-utils'

describe('FailoverToggle', () => {
  it('renders failover toggle', async () => {
    render(<FailoverToggle />)
    await waitFor(() => {
      expect(screen.getByText(/Enabled|Disabled/i)).toBeInTheDocument()
    }, { timeout: 3000 })
  })
})
