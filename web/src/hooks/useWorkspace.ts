import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { workspaceApi } from '@/lib/api/workspace'
import toast from 'react-hot-toast'

export function useFileTree(path = '') {
  return useQuery({
    queryKey: ['workspace', 'files', path],
    queryFn: () => workspaceApi.files(path),
  })
}

export function useFileContent(path: string) {
  return useQuery({
    queryKey: ['workspace', 'file', path],
    queryFn: () => workspaceApi.file(path),
    enabled: !!path,
  })
}

export function useSaveFile() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ path, content }: { path: string; content: string }) =>
      workspaceApi.saveFile(path, content),
    onSuccess: () => {
      toast.success('File saved')
      queryClient.invalidateQueries({ queryKey: ['workspace'] })
    },
    onError: () => {
      toast.error('Failed to save file')
    },
  })
}

export function useDailyMemory(date: string) {
  return useQuery({
    queryKey: ['workspace', 'memory', date],
    queryFn: () => workspaceApi.memory(date),
    enabled: !!date,
  })
}

export function useSaveDailyMemory() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ date, content }: { date: string; content: string }) =>
      workspaceApi.saveMemory(date, content),
    onSuccess: () => {
      toast.success('Daily memory saved')
      queryClient.invalidateQueries({ queryKey: ['workspace', 'memory'] })
    },
    onError: () => {
      toast.error('Failed to save daily memory')
    },
  })
}
