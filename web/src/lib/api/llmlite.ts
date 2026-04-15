import axios from 'axios'

const API_BASE = import.meta.env.VITE_API_BASE || 'http://localhost:4000'

const apiClient = axios.create({
  baseURL: API_BASE,
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json',
  },
})

// Request interceptor for API key
apiClient.interceptors.request.use((config) => {
  const apiKey = localStorage.getItem('llmlite_api_key') || 'sk-default'
  config.headers.Authorization = `Bearer ${apiKey}`
  return config
})

// Response interceptor for error handling
apiClient.interceptors.response.use(
  (response) => response,
  (error) => {
    console.error('API Error:', error.response?.data || error.message)
    return Promise.reject(error)
  }
)

export default apiClient

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

// ==================== Provider API ====================

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

// ==================== Provider Presets API ====================

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

// ==================== MCP Server API ====================

export interface McpServer {
  id: string
  name: string
  command: string
  args: string[]
  env: Record<string, string>
  state: 'stopped' | 'running' | 'error'
  auto_start: boolean
  enabled_for: string[]
}

export const mcpApi = {
  list: async (): Promise<McpServer[]> => {
    const { data } = await apiClient.get('/api/mcp')
    return data.servers || []
  },

  get: async (id: string): Promise<McpServer> => {
    const { data } = await apiClient.get(`/api/mcp/${id}`)
    return data
  },

  create: async (config: Omit<McpServer, 'id' | 'state'>): Promise<McpServer> => {
    const { data } = await apiClient.post('/api/mcp', config)
    return data
  },

  update: async (id: string, config: Partial<McpServer>): Promise<McpServer> => {
    const { data } = await apiClient.put(`/api/mcp/${id}`, config)
    return data
  },

  delete: async (id: string): Promise<void> => {
    await apiClient.delete(`/api/mcp/${id}`)
  },

  start: async (id: string): Promise<void> => {
    await apiClient.post(`/api/mcp/${id}/start`)
  },

  stop: async (id: string): Promise<void> => {
    await apiClient.post(`/api/mcp/${id}/stop`)
  },

  restart: async (id: string): Promise<void> => {
    await apiClient.post(`/api/mcp/${id}/restart`)
  },
}

// ==================== Session API ====================

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

// ==================== Config API ====================

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

// ==================== Health API ====================

export interface HealthStatus {
  status: 'healthy' | 'degraded' | 'unhealthy'
  uptime_seconds: number
  version: string
  providers: Record<string, {
    healthy: boolean
    latency_p50_ms?: number
    latency_p95_ms?: number
    latency_p99_ms?: number
    circuit_state: 'closed' | 'open' | 'half_open'
  }>
}

export const healthApi = {
  live: async (): Promise<{ status: string }> => {
    const { data } = await apiClient.get('/health/live')
    return data
  },

  ready: async (): Promise<{ status: string }> => {
    const { data } = await apiClient.get('/health/ready')
    return data
  },

  full: async (): Promise<HealthStatus> => {
    const { data } = await apiClient.get('/health')
    return data
  },

  metrics: async (): Promise<string> => {
    const { data } = await apiClient.get('/metrics')
    return data
  },

  latency: async (): Promise<Record<string, { p50: number; p95: number; p99: number }>> => {
    const { data } = await apiClient.get('/metrics/latency')
    return data
  },
}
