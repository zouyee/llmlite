import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { failoverApi } from '@/lib/api/failover'
import toast from 'react-hot-toast'

export function useFailoverQueue() {
  return useQuery({
    queryKey: ['failover', 'queue'],
    queryFn: failoverApi.getQueue,
  })
}

export function useUpdateFailoverQueue() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: failoverApi.updateQueue,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['failover', 'queue'] })
      toast.success('Failover queue updated')
    },
    onError: () => {
      toast.error('Failed to update failover queue')
    },
  })
}

export function useFailoverConfig() {
  return useQuery({
    queryKey: ['failover', 'config'],
    queryFn: failoverApi.getConfig,
  })
}

export function useUpdateFailoverConfig() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: failoverApi.updateConfig,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['failover', 'config'] })
      toast.success('Failover config updated')
    },
    onError: () => {
      toast.error('Failed to update failover config')
    },
  })
}

export function useCircuitBreakerConfig() {
  return useQuery({
    queryKey: ['circuit-breaker', 'config'],
    queryFn: failoverApi.getCircuitBreaker,
  })
}

export function useUpdateCircuitBreakerConfig() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: failoverApi.updateCircuitBreaker,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['circuit-breaker', 'config'] })
      toast.success('Circuit breaker config updated')
    },
    onError: () => {
      toast.error('Failed to update circuit breaker config')
    },
  })
}
