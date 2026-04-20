import { apiClient } from './client'

export interface ProxyStatus {
  running: boolean
  port: number
  uptime_seconds: number
}

export const proxyApi = {
  status: () => apiClient.get('/api/proxy/status').then((r) => r.data as ProxyStatus),
  start: () => apiClient.post('/api/proxy/start').then((r) => r.data),
  stop: () => apiClient.post('/api/proxy/stop').then((r) => r.data),
}
