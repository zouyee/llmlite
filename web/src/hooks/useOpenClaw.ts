import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { openclawApi, type OpenClawConfig } from '@/lib/api/openclaw'
import toast from 'react-hot-toast'

export function useOpenClawConfig() {
  return useQuery({
    queryKey: ['openclaw', 'config'],
    queryFn: () => openclawApi.getConfig(),
  })
}

export function useUpdateOpenClawConfig() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (config: Partial<OpenClawConfig>) => openclawApi.updateConfig(config),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['openclaw', 'config'] })
      toast.success('OpenClaw config saved')
    },
    onError: () => {
      toast.error('Failed to save OpenClaw config')
    },
  })
}
