import { describe, it, expect } from 'vitest'
import { deeplinkApi } from '@/lib/api/deeplink'

describe('deeplinkApi', () => {
  it('parses deeplink', async () => {
    const data = await deeplinkApi.parse('llmlite://mcp/test')
    expect(data.type).toBeDefined()
  })

  it('imports deeplink', async () => {
    const data = await deeplinkApi.import({ type: 'mcp', data: {} })
    expect(data.success).toBe(true)
  })

  it('exports deeplink', async () => {
    const data = await deeplinkApi.export('mcp', 'test-id')
    expect(data.url).toBeDefined()
  })
})
