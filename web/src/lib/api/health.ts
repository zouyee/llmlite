import { apiClient } from './client'

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
