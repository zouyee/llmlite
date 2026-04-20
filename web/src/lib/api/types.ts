export interface ProxyStatus {
  running: boolean
  port: number
  uptime_seconds: number
  active_connections: number
  total_requests: number
}

export interface FailoverConfig {
  enabled: boolean
  max_retries: number
  retry_interval_ms: number
  timeout_ms: number
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
