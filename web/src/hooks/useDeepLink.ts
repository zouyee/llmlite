import { useMutation } from '@tanstack/react-query'
import { deeplinkApi, type DeepLinkPayload } from '@/lib/api/deeplink'
import toast from 'react-hot-toast'

export function useParseDeepLink() {
  return useMutation({
    mutationFn: (url: string) => deeplinkApi.parse(url),
  })
}

export function useImportDeepLink() {
  return useMutation({
    mutationFn: (payload: DeepLinkPayload) => deeplinkApi.import(payload),
    onSuccess: () => {
      toast.success('Configuration imported successfully')
    },
    onError: () => {
      toast.error('Failed to import configuration')
    },
  })
}

export function useExportDeepLink() {
  return useMutation({
    mutationFn: ({ type, id }: { type: DeepLinkPayload['type']; id: string }) =>
      deeplinkApi.export(type, id),
    onSuccess: () => {
      toast.success('Export link generated')
    },
    onError: () => {
      toast.error('Failed to generate export link')
    },
  })
}

export function encodeDeepLinkToUrl(payload: DeepLinkPayload): string {
  const json = JSON.stringify(payload)
  const encoded = btoa(json)
  return `${window.location.origin}${window.location.pathname}?deeplink=${encoded}`
}

export function decodeDeepLinkFromUrl(url: string): DeepLinkPayload | null {
  try {
    const parsed = new URL(url)
    const encoded = parsed.searchParams.get('deeplink')
    if (!encoded) return null
    const json = atob(encoded)
    return JSON.parse(json) as DeepLinkPayload
  } catch {
    return null
  }
}
