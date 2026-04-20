import { apiClient } from './client'

export interface Provider {
  id: string
  name: string
  base_url: string
  auth_type: 'bearer' | 'api_key' | 'none'
  default_model: string
  supports: string[]
  api_key_env?: string
  is_official: boolean
  organization?: string
  website?: string
  description?: string
  enabled?: boolean
  sort_order?: number
  created_at?: number
  updated_at?: number
  metadata?: string | null
}

export interface ProviderPreset {
  id: string
  name: string
  provider_type: string
  base_url: string
  auth_type: string
  default_models: string[]
  features: string[]
  website: string
  description: string
}

export interface CreateProviderRequest {
  id: string
  name: string
  base_url: string
  auth_type: 'bearer' | 'api_key' | 'none'
  api_key?: string
  default_model: string
  supports?: string[]
  enabled?: boolean
}

export interface UpdateProviderRequest {
  name?: string
  base_url?: string
  auth_type?: 'bearer' | 'api_key' | 'none'
  api_key?: string
  default_model?: string
  supports?: string[]
  enabled?: boolean
}

export interface SortProvidersRequest {
  ids: string[]
}

export const providerApi = {
  list: async (): Promise<Provider[]> => {
    const { data } = await apiClient.get('/api/providers')
    return data.data || []
  },

  get: async (id: string): Promise<Provider> => {
    const { data } = await apiClient.get(`/api/providers/${id}`)
    return data
  },

  create: async (config: CreateProviderRequest): Promise<Provider> => {
    const { data } = await apiClient.post('/api/providers', config)
    return data
  },

  update: async (id: string, config: UpdateProviderRequest): Promise<Provider> => {
    const { data } = await apiClient.put(`/api/providers/${id}`, config)
    return data
  },

  delete: async (id: string): Promise<void> => {
    await apiClient.delete(`/api/providers/${id}`)
  },

  switch: async (id: string): Promise<{ switched: boolean; provider: Provider }> => {
    const { data } = await apiClient.post(`/api/providers/switch/${id}`)
    return data
  },

  test: async (id: string): Promise<{ success: boolean; latency_ms?: number; provider_id?: string; error?: string }> => {
    const { data } = await apiClient.post(`/api/providers/test/${id}`)
    return data
  },

  sort: async (ids: string[]): Promise<void> => {
    await apiClient.post('/api/providers/sort', { ids })
  },
}

export const presetApi = {
  list: async (): Promise<ProviderPreset[]> => {
    const { data } = await apiClient.get('/api/providers/presets')
    return data.data || []
  },

  get: async (id: string): Promise<ProviderPreset> => {
    const { data } = await apiClient.get(`/api/providers/presets/${id}`)
    return data
  },

  import: async (presetId: string): Promise<{ imported: boolean; provider: Provider }> => {
    const { data } = await apiClient.post(`/api/providers/presets/${presetId}/import`)
    return data
  },
}
