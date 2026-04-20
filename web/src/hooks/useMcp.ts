import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { mcpApi, type McpServer } from '@/lib/api/mcp'

export function useMcpServers() {
  return useQuery({
    queryKey: ['mcp'],
    queryFn: mcpApi.list,
  })
}

export function useCreateMcpServer() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (config: Omit<McpServer, 'id' | 'state'>) => mcpApi.create(config),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['mcp'] })
    },
  })
}

export function useUpdateMcpServer() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, config }: { id: string; config: Partial<McpServer> }) =>
      mcpApi.update(id, config),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['mcp'] })
    },
  })
}

export function useDeleteMcpServer() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: mcpApi.delete,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['mcp'] })
    },
  })
}

export function useStartMcpServer() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: mcpApi.start,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['mcp'] })
    },
  })
}

export function useStopMcpServer() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: mcpApi.stop,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['mcp'] })
    },
  })
}
