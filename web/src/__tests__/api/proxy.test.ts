import { describe, it, expect } from 'vitest'
import { proxyApi } from '@/lib/api/proxy'

describe('proxyApi', () => {
  it('fetches proxy status', async () => {
    const data = await proxyApi.status()
    expect(data.running).toBe(true)
    expect(data.port).toBe(4000)
    expect(data.uptime_seconds).toBeDefined()
  })

  it('starts proxy', async () => {
    const data = await proxyApi.start()
    expect(data.success).toBe(true)
  })

  it('stops proxy', async () => {
    const data = await proxyApi.stop()
    expect(data.success).toBe(true)
  })
})
