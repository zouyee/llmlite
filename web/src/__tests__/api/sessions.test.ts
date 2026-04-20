import { describe, it, expect } from 'vitest'
import { sessionApi } from '@/lib/api/sessions'

describe('sessionApi', () => {
  it('lists sessions', async () => {
    const data = await sessionApi.list()
    expect(Array.isArray(data)).toBe(true)
  })

  it('lists sessions with tool filter', async () => {
    const data = await sessionApi.list('claude_code')
    expect(Array.isArray(data)).toBe(true)
  })

  it('gets a session', async () => {
    const data = await sessionApi.get('session-1')
    expect(data.id).toBe('session-1')
  })

  it('deletes a session', async () => {
    await expect(sessionApi.delete('session-1')).resolves.toBeUndefined()
  })

  it('archives a session', async () => {
    await expect(sessionApi.archive('session-1')).resolves.toBeUndefined()
  })

  it('restores a session', async () => {
    await expect(sessionApi.restore('session-1')).resolves.toBeUndefined()
  })

  it('searches sessions', async () => {
    const data = await sessionApi.search('Fix')
    expect(Array.isArray(data)).toBe(true)
  })
})
