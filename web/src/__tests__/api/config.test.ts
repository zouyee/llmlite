import { describe, it, expect } from 'vitest'
import { configApi } from '@/lib/api/config'

describe('configApi', () => {
  it('fetches config', async () => {
    const data = await configApi.get()
    expect(typeof data.port).toBe('number')
  })

  it('updates config', async () => {
    const data = await configApi.update({ port: 5000 })
    expect(data.port).toBe(5000)
  })

  it('reloads config', async () => {
    await expect(configApi.reload()).resolves.toBeUndefined()
  })
})
