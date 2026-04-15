import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { sessionApi } from '@/lib/api/llmlite'

export function useSessions(tool?: string) {
  return useQuery({
    queryKey: ['sessions', tool],
    queryFn: () => sessionApi.list(tool),
  })
}

export function useSession(id: string) {
  return useQuery({
    queryKey: ['sessions', 'detail', id],
    queryFn: () => sessionApi.get(id),
    enabled: !!id,
  })
}

export function useDeleteSession() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: sessionApi.delete,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['sessions'] })
    },
  })
}

export function useArchiveSession() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: sessionApi.archive,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['sessions'] })
    },
  })
}

export function useSearchSessions() {
  return useMutation({
    mutationFn: sessionApi.search,
  })
}
