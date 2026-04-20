import { describe, it, expect } from 'vitest'
import { openclawApi } from '@/lib/api/openclaw'

describe('openclawApi', () => {
  it('fetches config', async () => {
    const data = await openclawApi.getConfig()
    expect(data.default_model).toBeDefined()
  })

  it('updates config', async () => {
    const data = await openclawApi.updateConfig({ temperature: 0.5 })
    expect(data).toBeDefined()
  })
})
