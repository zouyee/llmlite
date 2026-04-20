import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { FailoverQueuePanel } from '@/components/proxy/FailoverQueuePanel'
import { render } from '../../test-utils'

describe('FailoverQueuePanel', () => {
  it('renders failover queue', async () => {
    render(<FailoverQueuePanel />)
    await waitFor(() => {
      expect(screen.getByText(/Failover Queue/i)).toBeInTheDocument()
    }, { timeout: 3000 })
  })
})
