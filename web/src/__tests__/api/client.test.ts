import { describe, it, expect } from 'vitest'
import { apiClient } from '@/lib/api/client'
import { http, HttpResponse } from 'msw'
import { server } from '../mocks/server'

describe('apiClient interceptors', () => {
  it('retries on 5xx error once', async () => {
    let calls = 0
    server.use(
      http.get('*/api/test-retry', () => {
        calls++
        if (calls === 1) {
          return new HttpResponse(null, { status: 503 })
        }
        return HttpResponse.json({ success: true })
      })
    )
    const { data } = await apiClient.get('/api/test-retry')
    expect(data).toEqual({ success: true })
    expect(calls).toBe(2)
  })

  it('sets Authorization header from localStorage', async () => {
    localStorage.setItem('llmlite_api_key', 'test-key')
    server.use(
      http.get('*/api/test-auth', ({ request }) => {
        const auth = request.headers.get('Authorization')
        return HttpResponse.json({ auth })
      })
    )
    const { data } = await apiClient.get('/api/test-auth')
    expect(data.auth).toBe('Bearer test-key')
    localStorage.removeItem('llmlite_api_key')
  })
})
