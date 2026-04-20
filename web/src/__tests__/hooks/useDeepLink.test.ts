import { describe, it, expect } from 'vitest'
import { decodeDeepLinkFromUrl, encodeDeepLinkToUrl } from '@/hooks/useDeepLink'

describe('useDeepLink', () => {
  it('decodes valid deeplink from URL param', () => {
    const encoded = btoa(JSON.stringify({ type: 'mcp' as const, data: { id: 'test' } }))
    const payload = decodeDeepLinkFromUrl(`http://localhost/?deeplink=${encoded}`)
    expect(payload).toBeDefined()
    expect(payload?.type).toBe('mcp')
  })

  it('returns null for missing deeplink param', () => {
    const payload = decodeDeepLinkFromUrl('http://localhost/')
    expect(payload).toBeNull()
  })

  it('encodes payload to url', () => {
    const url = encodeDeepLinkToUrl({ type: 'mcp', data: { id: 'test' } })
    expect(url.includes('deeplink=')).toBe(true)
  })
})
