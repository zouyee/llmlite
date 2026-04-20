import { describe, it, expect } from 'vitest'
import { workspaceApi } from '@/lib/api/workspace'

describe('workspaceApi', () => {
  it('fetches file tree', async () => {
    const data = await workspaceApi.files()
    expect(Array.isArray(data)).toBe(true)
  })

  it('fetches file content', async () => {
    const data = await workspaceApi.file('/README.md')
    expect(data.content).toBeDefined()
  })

  it('saves file', async () => {
    await expect(workspaceApi.saveFile('/test.txt', 'hello')).resolves.toBeUndefined()
  })

  it('fetches daily memory', async () => {
    const data = await workspaceApi.memory('2024-01-01')
    expect(data.content).toBeDefined()
  })

  it('saves daily memory', async () => {
    await expect(workspaceApi.saveMemory('2024-01-01', 'test')).resolves.toBeUndefined()
  })
})
