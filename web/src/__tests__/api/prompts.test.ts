import { describe, it, expect } from 'vitest'
import { promptsApi } from '@/lib/api/prompts'

describe('promptsApi', () => {
  it('lists prompts', async () => {
    const data = await promptsApi.getPrompts()
    expect(Array.isArray(data)).toBe(true)
  })

  it('creates a prompt', async () => {
    const data = await promptsApi.create({
      name: 'Test Prompt',
      content: 'Test content',
      tags: ['test'],
      enabled: true,
    })
    expect(data.id).toBeDefined()
  })

  it('updates a prompt', async () => {
    const data = await promptsApi.update('prompt-1', { name: 'Updated' })
    expect(data).toBeDefined()
  })

  it('deletes a prompt', async () => {
    await expect(promptsApi.delete('prompt-1')).resolves.toBeUndefined()
  })
})
