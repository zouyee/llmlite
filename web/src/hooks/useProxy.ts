import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { proxyApi } from '@/lib/api/proxy'
import toast from 'react-hot-toast'

export function useProxyStatus() {
  return useQuery({
    queryKey: ['proxy', 'status'],
    queryFn: proxyApi.status,
    refetchInterval: 3000,
  })
}

export function useStartProxy() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: proxyApi.start,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['proxy', 'status'] })
      toast.success('Proxy started')
    },
    onError: () => {
      toast.error('Failed to start proxy')
    },
  })
}

export function useStopProxy() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: proxyApi.stop,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['proxy', 'status'] })
      toast.success('Proxy stopped')
    },
    onError: () => {
      toast.error('Failed to stop proxy')
    },
  })
}
