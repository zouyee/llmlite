import { useEffect } from 'react'
import { decodeDeepLinkFromUrl } from '@/hooks/useDeepLink'

export function DeepLinkHandler() {
  useEffect(() => {
    const payload = decodeDeepLinkFromUrl(window.location.href)
    if (payload) {
      window.location.href = `/?view=deeplink&payload=${btoa(JSON.stringify(payload))}`
    }
  }, [])

  return null
}
