import { apiClient } from './client'

export interface DeepLinkPayload {
  type: 'mcp' | 'prompt' | 'skill'
  data: Record<string, unknown>
}

export const deeplinkApi = {
  parse: async (url: string): Promise<DeepLinkPayload> => {
    const { data } = await apiClient.post('/api/deeplink/parse', { url })
    return data
  },

  import: async (payload: DeepLinkPayload): Promise<{ success: boolean; message?: string }> => {
    const { data } = await apiClient.post('/api/deeplink/import', payload)
    return data
  },

  export: async (type: DeepLinkPayload['type'], id: string): Promise<{ url: string }> => {
    const { data } = await apiClient.post('/api/deeplink/export', { type, id })
    return data
  },
}
