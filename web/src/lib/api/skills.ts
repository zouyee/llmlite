import { apiClient } from './client'

export interface Skill {
  id: string
  name: string
  description: string
  version: string
  author: string
  installed: boolean
  repo_url?: string
  updated_at: number
}

export interface SkillRepo {
  id: string
  url: string
  name: string
  skill_count: number
}

export const skillsApi = {
  getSkills: async (): Promise<Skill[]> => {
    const { data } = await apiClient.get('/api/skills')
    return data
  },

  installSkill: async (id: string): Promise<Skill> => {
    const { data } = await apiClient.post(`/api/skills/${id}/install`)
    return data
  },

  uninstallSkill: async (id: string): Promise<void> => {
    await apiClient.delete(`/api/skills/${id}`)
  },

  updateSkill: async (id: string): Promise<Skill> => {
    const { data } = await apiClient.post(`/api/skills/${id}/update`)
    return data
  },

  getRepos: async (): Promise<SkillRepo[]> => {
    const { data } = await apiClient.get('/api/skills/repos')
    return data
  },

  addRepo: async (url: string): Promise<SkillRepo> => {
    const { data } = await apiClient.post('/api/skills/repos', { url })
    return data
  },

  removeRepo: async (id: string): Promise<void> => {
    await apiClient.delete(`/api/skills/repos/${id}`)
  },
}
