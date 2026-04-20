import { describe, it, expect } from 'vitest'
import { usageApi } from '@/lib/api/usage'

describe('usageApi', () => {
  it('fetches overview', async () => {
    const data = await usageApi.overview()
    expect(typeof data.total_requests).toBe('number')
  })

  it('fetches trends', async () => {
    const data = await usageApi.trends()
    expect(Array.isArray(data)).toBe(true)
  })

  it('fetches logs', async () => {
    const data = await usageApi.logs()
    expect(Array.isArray(data)).toBe(true)
  })

  it('fetches model stats', async () => {
    const data = await usageApi.models()
    expect(Array.isArray(data)).toBe(true)
  })

  it('fetches cost config', async () => {
    const data = await usageApi.costConfig()
    expect(Array.isArray(data)).toBe(true)
  })

  it('updates cost config', async () => {
    const data = await usageApi.updateCostConfig({ model: 'gpt-4', input_price: 0.01, output_price: 0.03 })
    expect(data).toBeDefined()
  })
})
