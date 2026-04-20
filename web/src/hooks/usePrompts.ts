import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { promptsApi } from '@/lib/api/prompts'
import type { Prompt } from '@/lib/api/prompts'
import toast from 'react-hot-toast'

export function usePrompts() {
  return useQuery({
    queryKey: ['prompts'],
    queryFn: promptsApi.getPrompts,
  })
}

export function useCreatePrompt() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (prompt: Omit<Prompt, 'id' | 'created_at' | 'updated_at'>) => promptsApi.create(prompt),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['prompts'] })
      toast.success('Prompt created')
    },
    onError: () => {
      toast.error('Failed to create prompt')
    },
  })
}

export function useUpdatePrompt() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, prompt }: { id: string; prompt: Partial<Prompt> }) => promptsApi.update(id, prompt),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['prompts'] })
      toast.success('Prompt updated')
    },
    onError: () => {
      toast.error('Failed to update prompt')
    },
  })
}

export function useDeletePrompt() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: promptsApi.delete,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['prompts'] })
      toast.success('Prompt deleted')
    },
    onError: () => {
      toast.error('Failed to delete prompt')
    },
  })
}
