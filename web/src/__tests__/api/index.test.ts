import { describe, it, expect } from 'vitest'
import * as api from '@/lib/api'

describe('api index exports', () => {
  it('exports apiClient', () => {
    expect(api.apiClient).toBeDefined()
  })

  it('exports providerApi', () => {
    expect(api.providerApi).toBeDefined()
    expect(typeof api.providerApi.list).toBe('function')
  })

  it('exports sessionApi', () => {
    expect(api.sessionApi).toBeDefined()
    expect(typeof api.sessionApi.list).toBe('function')
  })

  it('exports mcpApi', () => {
    expect(api.mcpApi).toBeDefined()
    expect(typeof api.mcpApi.list).toBe('function')
  })

  it('exports configApi', () => {
    expect(api.configApi).toBeDefined()
    expect(typeof api.configApi.get).toBe('function')
  })

  it('exports healthApi', () => {
    expect(api.healthApi).toBeDefined()
    expect(typeof api.healthApi.live).toBe('function')
  })

  it('exports proxyApi', () => {
    expect(api.proxyApi).toBeDefined()
    expect(typeof api.proxyApi.status).toBe('function')
  })

  it('exports failoverApi', () => {
    expect(api.failoverApi).toBeDefined()
    expect(typeof api.failoverApi.getQueue).toBe('function')
  })

  it('exports usageApi', () => {
    expect(api.usageApi).toBeDefined()
    expect(typeof api.usageApi.overview).toBe('function')
  })

  it('exports skillsApi', () => {
    expect(api.skillsApi).toBeDefined()
    expect(typeof api.skillsApi.getSkills).toBe('function')
  })

  it('exports promptsApi', () => {
    expect(api.promptsApi).toBeDefined()
    expect(typeof api.promptsApi.getPrompts).toBe('function')
  })

  it('exports deeplinkApi', () => {
    expect(api.deeplinkApi).toBeDefined()
    expect(typeof api.deeplinkApi.parse).toBe('function')
  })

  it('exports workspaceApi', () => {
    expect(api.workspaceApi).toBeDefined()
    expect(typeof api.workspaceApi.files).toBe('function')
  })

  it('exports openclawApi', () => {
    expect(api.openclawApi).toBeDefined()
    expect(typeof api.openclawApi.getConfig).toBe('function')
  })

  it('exports settingsApi', () => {
    expect(api.settingsApi).toBeDefined()
    expect(typeof api.settingsApi.getTheme).toBe('function')
  })
})
