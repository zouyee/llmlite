import { apiClient } from './client'

export interface ProxyConfig {
  port: number
  enable_connection_pool: boolean
  enable_health_checker: boolean
  health_check_interval_ms: number
  health_check_timeout_ms: number
  latency_window_size: number
}

export const configApi = {
  get: async (): Promise<ProxyConfig> => {
    const { data } = await apiClient.get('/api/config')
    return data
  },

  update: async (config: Partial<ProxyConfig>): Promise<ProxyConfig> => {
    const { data } = await apiClient.put('/api/config', config)
    return data
  },

  reload: async (): Promise<void> => {
    await apiClient.post('/api/config/reload')
  },
}
