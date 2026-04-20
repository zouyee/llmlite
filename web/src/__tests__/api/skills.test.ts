import { describe, it, expect } from 'vitest'
import { skillsApi } from '@/lib/api/skills'

describe('skillsApi', () => {
  it('lists skills', async () => {
    const data = await skillsApi.getSkills()
    expect(Array.isArray(data)).toBe(true)
  })

  it('installs a skill', async () => {
    const data = await skillsApi.installSkill('skill-1')
    expect(data.installed).toBe(true)
  })

  it('uninstalls a skill', async () => {
    await expect(skillsApi.uninstallSkill('skill-1')).resolves.toBeUndefined()
  })

  it('updates a skill', async () => {
    const data = await skillsApi.updateSkill('skill-1')
    expect(data).toBeDefined()
  })

  it('lists repos', async () => {
    const data = await skillsApi.getRepos()
    expect(Array.isArray(data)).toBe(true)
  })

  it('adds a repo', async () => {
    const data = await skillsApi.addRepo('https://example.com/skills')
    expect(data).toBeDefined()
  })

  it('removes a repo', async () => {
    await expect(skillsApi.removeRepo('repo-1')).resolves.toBeUndefined()
  })
})
