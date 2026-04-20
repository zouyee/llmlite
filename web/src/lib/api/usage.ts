import { apiClient } from './client'

export interface UsageOverview {
  total_requests: number
  total_tokens: number
  total_cost: number
  active_providers: number
}

export interface UsageTrend {
  date: string
  requests: number
  tokens: number
  cost: number
}

export interface RequestLog {
  id: string
  timestamp: number
  provider: string
  model: string
  status: string
  tokens_in: number
  tokens_out: number
  latency_ms: number
}

export interface ModelStats {
  model: string
  requests: number
  tokens_in: number
  tokens_out: number
  cost: number
}

export interface CostConfig {
  model: string
  input_price: number
  output_price: number
}

export const usageApi = {
  overview: async (): Promise<UsageOverview> => {
    const { data } = await apiClient.get('/api/usage/overview')
    return data
  },

  trends: async (days = 30): Promise<UsageTrend[]> => {
    const { data } = await apiClient.get(`/api/usage/trends?days=${days}`)
    return data
  },

  logs: async (limit = 50, offset = 0): Promise<RequestLog[]> => {
    const { data } = await apiClient.get(`/api/usage/logs?limit=${limit}&offset=${offset}`)
    return data
  },

  models: async (): Promise<ModelStats[]> => {
    const { data } = await apiClient.get('/api/usage/models')
    return data
  },

  costConfig: async (): Promise<CostConfig[]> => {
    const { data } = await apiClient.get('/api/usage/cost-config')
    return data
  },

  updateCostConfig: async (config: CostConfig): Promise<CostConfig> => {
    const { data } = await apiClient.put('/api/usage/cost-config', config)
    return data
  },

  export: async (format: 'csv' | 'json' = 'json'): Promise<Blob> => {
    const { data } = await apiClient.get(`/api/usage/export?format=${format}`, {
      responseType: 'blob',
    })
    return data
  },
}
