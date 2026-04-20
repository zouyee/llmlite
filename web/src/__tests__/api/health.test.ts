import { describe, it, expect } from 'vitest'
import { healthApi } from '@/lib/api/health'

describe('healthApi', () => {
  it('fetches live status', async () => {
    const data = await healthApi.live()
    expect(data.status).toBeDefined()
  })

  it('fetches ready status', async () => {
    const data = await healthApi.ready()
    expect(data.status).toBeDefined()
  })

  it('fetches full health', async () => {
    const data = await healthApi.full()
    expect(data.status).toBeDefined()
    expect(data.providers).toBeDefined()
  })

  it('fetches metrics', async () => {
    const data = await healthApi.metrics()
    expect(data).toBeDefined()
  })

  it('fetches latency', async () => {
    const data = await healthApi.latency()
    expect(typeof data).toBe('object')
  })
})
