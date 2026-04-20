import { apiClient } from './client'

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
