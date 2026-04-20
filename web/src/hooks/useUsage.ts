import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { usageApi } from '@/lib/api/usage'
import type { CostConfig } from '@/lib/api/usage'
import toast from 'react-hot-toast'

export function useUsageOverview() {
  return useQuery({
    queryKey: ['usage', 'overview'],
    queryFn: () => usageApi.overview(),
    refetchInterval: 5000,
  })
}

export function useUsageTrends(days = 30) {
  return useQuery({
    queryKey: ['usage', 'trends', days],
    queryFn: () => usageApi.trends(days),
  })
}

export function useRequestLogs(limit = 50, offset = 0) {
  return useQuery({
    queryKey: ['usage', 'logs', limit, offset],
    queryFn: () => usageApi.logs(limit, offset),
  })
}

export function useModelStats() {
  return useQuery({
    queryKey: ['usage', 'models'],
    queryFn: usageApi.models,
  })
}

export function useCostConfig() {
  return useQuery({
    queryKey: ['usage', 'cost-config'],
    queryFn: usageApi.costConfig,
  })
}

export function useUpdateCostConfig() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (config: CostConfig) => usageApi.updateCostConfig(config),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['usage', 'cost-config'] })
      toast.success('Cost config updated')
    },
    onError: () => {
      toast.error('Failed to update cost config')
    },
  })
}

export function useExportUsage() {
  return useMutation({
    mutationFn: (format: 'csv' | 'json' = 'json') => usageApi.export(format),
    onSuccess: (blob) => {
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `llmlite-usage-${Date.now()}.csv`
      a.click()
      URL.revokeObjectURL(url)
      toast.success('Usage exported')
    },
    onError: () => {
      toast.error('Failed to export usage')
    },
  })
}
