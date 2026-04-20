import { describe, it, expect } from 'vitest'
import { failoverApi } from '@/lib/api/failover'

describe('failoverApi', () => {
  it('fetches queue', async () => {
    const data = await failoverApi.getQueue()
    expect(Array.isArray(data.providers)).toBe(true)
  })

  it('updates queue', async () => {
    const data = await failoverApi.updateQueue({ providers: [] })
    expect(data).toBeDefined()
  })

  it('fetches config', async () => {
    const data = await failoverApi.getConfig()
    expect(typeof data.enabled).toBe('boolean')
  })

  it('updates config', async () => {
    const data = await failoverApi.updateConfig({ enabled: true })
    expect(data).toBeDefined()
  })

  it('fetches circuit breaker config', async () => {
    const data = await failoverApi.getCircuitBreaker()
    expect(typeof data.failure_threshold).toBe('number')
  })

  it('updates circuit breaker config', async () => {
    const data = await failoverApi.updateCircuitBreaker({ failure_threshold: 5 })
    expect(data).toBeDefined()
  })
})
