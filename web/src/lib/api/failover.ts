import { apiClient } from './client'

export interface FailoverConfig {
  max_retries: number
  retry_interval_ms: number
  timeout_ms: number
  enabled: boolean
}

export interface FailoverQueue {
  providers: Array<{
    id: string
    name: string
    priority: number
    healthy: boolean
    circuit_state: 'closed' | 'open' | 'half_open'
  }>
}

export interface CircuitBreakerConfig {
  failure_threshold: number
  recovery_timeout_ms: number
  half_open_max_requests: number
}

export const failoverApi = {
  getQueue: async (): Promise<FailoverQueue> => {
    const { data } = await apiClient.get('/api/failover/queue')
    return data
  },

  updateQueue: async (queue: FailoverQueue): Promise<FailoverQueue> => {
    const { data } = await apiClient.put('/api/failover/queue', queue)
    return data
  },

  getConfig: async (): Promise<FailoverConfig> => {
    const { data } = await apiClient.get('/api/failover/config')
    return data
  },

  updateConfig: async (config: Partial<FailoverConfig>): Promise<FailoverConfig> => {
    const { data } = await apiClient.put('/api/failover/config', config)
    return data
  },

  getCircuitBreaker: async (): Promise<CircuitBreakerConfig> => {
    const { data } = await apiClient.get('/api/circuit-breaker/config')
    return data
  },

  updateCircuitBreaker: async (config: Partial<CircuitBreakerConfig>): Promise<CircuitBreakerConfig> => {
    const { data } = await apiClient.put('/api/circuit-breaker/config', config)
    return data
  },
}
