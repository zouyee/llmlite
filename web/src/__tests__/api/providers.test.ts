import { describe, it, expect } from 'vitest'
import { providerApi, presetApi } from '@/lib/api/providers'

describe('providerApi', () => {
  it('lists providers', async () => {
    const data = await providerApi.list()
    expect(Array.isArray(data)).toBe(true)
    expect(data.length).toBeGreaterThan(0)
  })

  it('gets a provider', async () => {
    const data = await providerApi.get('openai')
    expect(data.id).toBe('openai')
  })

  it('creates a provider', async () => {
    const data = await providerApi.create({
      id: 'test-provider',
      name: 'Test',
      base_url: 'https://test.com',
      auth_type: 'bearer',
      default_model: 'gpt-4',
    })
    expect(data.id).toBeDefined()
  })

  it('updates a provider', async () => {
    const data = await providerApi.update('openai', { name: 'Updated' })
    expect(data).toBeDefined()
  })

  it('deletes a provider', async () => {
    await expect(providerApi.delete('openai')).resolves.toBeUndefined()
  })

  it('switches provider', async () => {
    const data = await providerApi.switch('openai')
    expect(data.switched).toBe(true)
  })

  it('tests provider', async () => {
    const data = await providerApi.test('openai')
    expect(data.success).toBe(true)
  })

  it('sorts providers', async () => {
    await expect(providerApi.sort(['openai', 'anthropic'])).resolves.toBeUndefined()
  })
})

describe('presetApi', () => {
  it('lists presets', async () => {
    const data = await presetApi.list()
    expect(Array.isArray(data)).toBe(true)
  })

  it('imports a preset', async () => {
    const data = await presetApi.import('preset-openai')
    expect(data.imported).toBe(true)
  })
})
