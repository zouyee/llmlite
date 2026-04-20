import { apiClient } from './client'

export interface FileNode {
  path: string
  name: string
  is_dir: boolean
  children?: FileNode[]
}

export interface DailyMemory {
  date: string
  content: string
}

export const workspaceApi = {
  files: async (path = ''): Promise<FileNode[]> => {
    const { data } = await apiClient.get(`/api/workspace/files?path=${encodeURIComponent(path)}`)
    return data
  },

  file: async (path: string): Promise<{ content: string }> => {
    const { data } = await apiClient.get(`/api/workspace/file?path=${encodeURIComponent(path)}`)
    return data
  },

  saveFile: async (path: string, content: string): Promise<void> => {
    await apiClient.put('/api/workspace/file', { path, content })
  },

  memory: async (date: string): Promise<DailyMemory> => {
    const { data } = await apiClient.get(`/api/workspace/memory?date=${date}`)
    return data
  },

  saveMemory: async (date: string, content: string): Promise<void> => {
    await apiClient.post('/api/workspace/memory', { date, content })
  },
}
