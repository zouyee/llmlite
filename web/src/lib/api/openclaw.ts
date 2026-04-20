import { apiClient } from './client'

export interface OpenClawConfig {
  default_model: string
  temperature: number
  max_tokens: number
  env_vars: Record<string, string>
  enabled_tools: string[]
  available_tools: string[]
}

export const openclawApi = {
  getConfig: async (): Promise<OpenClawConfig> => {
    const { data } = await apiClient.get('/api/openclaw/config')
    return data
  },

  updateConfig: async (config: Partial<OpenClawConfig>): Promise<OpenClawConfig> => {
    const { data } = await apiClient.put('/api/openclaw/config', config)
    return data
  },
}
