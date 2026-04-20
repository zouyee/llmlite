import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { AutoFailoverConfig } from '@/components/proxy/AutoFailoverConfig'
import { render } from '../../test-utils'

describe('AutoFailoverConfig', () => {
  it('renders auto-failover config', async () => {
    render(<AutoFailoverConfig />)
    await waitFor(() => {
      expect(screen.getByText(/Auto-Failover/i)).toBeInTheDocument()
    }, { timeout: 3000 })
  })
})
