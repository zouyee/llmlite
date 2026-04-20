import { describe, it, expect } from 'vitest'
import { settingsApi } from '@/lib/api/settings'

describe('settingsApi', () => {
  it('fetches theme', async () => {
    const data = await settingsApi.getTheme()
    expect(data.theme).toBeDefined()
  })

  it('updates theme', async () => {
    const data = await settingsApi.updateTheme({ theme: 'dark' })
    expect(data.theme).toBeDefined()
  })

  it('fetches webdav', async () => {
    const data = await settingsApi.getWebDAV()
    expect(typeof data.url).toBe('string')
  })

  it('updates webdav', async () => {
    const data = await settingsApi.updateWebDAV({ url: 'https://example.com' })
    expect(data).toBeDefined()
  })

  it('syncs webdav', async () => {
    await expect(settingsApi.syncWebDAV()).resolves.toBeDefined()
  })

  it('exports backup', async () => {
    const data = await settingsApi.exportBackup()
    expect(data.version).toBeDefined()
  })

  it('imports backup', async () => {
    const data = await settingsApi.importBackup({ version: '1.0.0' } as never)
    expect(data.success).toBe(true)
  })
})
