import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { CircuitBreakerConfig } from '@/components/proxy/CircuitBreakerConfig'
import { render } from '../../test-utils'

describe('CircuitBreakerConfig', () => {
  it('renders circuit breaker config', async () => {
    render(<CircuitBreakerConfig />)
    await waitFor(() => {
      expect(screen.getByText(/Circuit Breaker/i)).toBeInTheDocument()
    }, { timeout: 3000 })
  })
})
