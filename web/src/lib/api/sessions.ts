import { apiClient } from './client'

export interface Session {
  id: string
  tool: 'claude_code' | 'codex' | 'gemini_cli' | 'opencode' | 'openclaw'
  title: string
  provider: string
  model: string
  message_count: number
  created_at: number
  updated_at: number
  archived: boolean
  first_user_message?: string
  last_message_preview?: string
}

export const sessionApi = {
  list: async (tool?: string, limit = 50, offset = 0): Promise<Session[]> => {
    const params = new URLSearchParams()
    if (tool) params.append('tool', tool)
    params.append('limit', limit.toString())
    params.append('offset', offset.toString())
    const { data } = await apiClient.get(`/api/sessions?${params}`)
    return data.sessions || []
  },

  get: async (id: string): Promise<Session> => {
    const { data } = await apiClient.get(`/api/sessions/${id}`)
    return data
  },

  delete: async (id: string): Promise<void> => {
    await apiClient.delete(`/api/sessions/${id}`)
  },

  archive: async (id: string): Promise<void> => {
    await apiClient.post(`/api/sessions/${id}/archive`)
  },

  restore: async (id: string): Promise<void> => {
    await apiClient.post(`/api/sessions/${id}/restore`)
  },

  search: async (query: string): Promise<Session[]> => {
    const { data } = await apiClient.post('/api/sessions/search', { query })
    return data.results || []
  },
}
