import { apiClient } from './client'

export interface ThemeConfig {
  theme: 'dark' | 'light'
  primary_color: string
}

export interface WebDAVConfig {
  url: string
  username: string
  password: string
  auto_sync: boolean
  sync_interval_ms: number
}

export interface BackupData {
  version: string
  timestamp: number
  providers: unknown[]
  mcp_servers: unknown[]
  prompts: unknown[]
  skills: unknown[]
  config: unknown
}

export const settingsApi = {
  getTheme: async (): Promise<ThemeConfig> => {
    const { data } = await apiClient.get('/api/settings/theme')
    return data
  },

  updateTheme: async (config: Partial<ThemeConfig>): Promise<ThemeConfig> => {
    const { data } = await apiClient.put('/api/settings/theme', config)
    return data
  },

  getWebDAV: async (): Promise<WebDAVConfig> => {
    const { data } = await apiClient.get('/api/settings/webdav')
    return data
  },

  updateWebDAV: async (config: Partial<WebDAVConfig>): Promise<WebDAVConfig> => {
    const { data } = await apiClient.put('/api/settings/webdav', config)
    return data
  },

  syncWebDAV: async (): Promise<{ success: boolean; message?: string }> => {
    const { data } = await apiClient.post('/api/settings/webdav/sync')
    return data
  },

  exportBackup: async (): Promise<BackupData> => {
    const { data } = await apiClient.post('/api/settings/backup/export')
    return data
  },

  importBackup: async (data: BackupData): Promise<{ success: boolean }> => {
    const { data: result } = await apiClient.post('/api/settings/backup/import', data)
    return result
  },
}
