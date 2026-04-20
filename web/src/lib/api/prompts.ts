import { apiClient } from './client'

export interface Prompt {
  id: string
  name: string
  content: string
  tags: string[]
  enabled: boolean
  created_at: number
  updated_at: number
}

export const promptsApi = {
  getPrompts: async (): Promise<Prompt[]> => {
    const { data } = await apiClient.get('/api/prompts')
    return data
  },

  create: async (prompt: Omit<Prompt, 'id' | 'created_at' | 'updated_at'>): Promise<Prompt> => {
    const { data } = await apiClient.post('/api/prompts', prompt)
    return data
  },

  update: async (id: string, prompt: Partial<Prompt>): Promise<Prompt> => {
    const { data } = await apiClient.put(`/api/prompts/${id}`, prompt)
    return data
  },

  delete: async (id: string): Promise<void> => {
    await apiClient.delete(`/api/prompts/${id}`)
  },
}
