import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { providerApi, presetApi, type CreateProviderRequest, type UpdateProviderRequest } from '@/lib/api/providers'

export function useProviders() {
  return useQuery({
    queryKey: ['providers'],
    queryFn: providerApi.list,
  })
}

export function useProvider(id: string) {
  return useQuery({
    queryKey: ['providers', id],
    queryFn: () => providerApi.get(id),
    enabled: !!id,
  })
}

export function usePresets() {
  return useQuery({
    queryKey: ['presets'],
    queryFn: presetApi.list,
  })
}

export function useCreateProvider() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (config: CreateProviderRequest) => providerApi.create(config),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['providers'] })
    },
  })
}

export function useUpdateProvider() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, config }: { id: string; config: UpdateProviderRequest }) =>
      providerApi.update(id, config),
    onSuccess: (_, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['providers'] })
      queryClient.invalidateQueries({ queryKey: ['providers', id] })
    },
  })
}

export function useDeleteProvider() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: providerApi.delete,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['providers'] })
    },
  })
}

export function useSwitchProvider() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: providerApi.switch,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['providers'] })
    },
  })
}

export function useTestProvider() {
  return useMutation({
    mutationFn: providerApi.test,
  })
}

export function useSortProviders() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: providerApi.sort,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['providers'] })
    },
  })
}

export function useImportPreset() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: presetApi.import,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['providers'] })
    },
  })
}
