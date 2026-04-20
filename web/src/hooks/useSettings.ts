import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { settingsApi, type ThemeConfig, type WebDAVConfig } from '@/lib/api/settings'
import toast from 'react-hot-toast'

export function useSettingsTheme() {
  return useQuery({
    queryKey: ['settings', 'theme'],
    queryFn: () => settingsApi.getTheme(),
  })
}

export function useUpdateSettingsTheme() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (config: Partial<ThemeConfig>) => settingsApi.updateTheme(config),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'theme'] })
    },
    onError: () => {
      toast.error('Failed to save theme settings')
    },
  })
}

export function useWebDAVConfig() {
  return useQuery({
    queryKey: ['settings', 'webdav'],
    queryFn: () => settingsApi.getWebDAV(),
  })
}

export function useUpdateWebDAV() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (config: Partial<WebDAVConfig>) => settingsApi.updateWebDAV(config),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'webdav'] })
      toast.success('WebDAV settings saved')
    },
    onError: () => {
      toast.error('Failed to save WebDAV settings')
    },
  })
}

export function useSyncWebDAV() {
  return useMutation({
    mutationFn: () => settingsApi.syncWebDAV(),
    onSuccess: () => {
      toast.success('WebDAV sync started')
    },
    onError: () => {
      toast.error('Failed to sync WebDAV')
    },
  })
}

export function useExportBackup() {
  return useMutation({
    mutationFn: () => settingsApi.exportBackup(),
    onSuccess: (data) => {
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `llmlite-backup-${Date.now()}.json`
      a.click()
      URL.revokeObjectURL(url)
      toast.success('Backup exported')
    },
    onError: () => {
      toast.error('Failed to export backup')
    },
  })
}

export function useImportBackup() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: Record<string, unknown>) => settingsApi.importBackup(data as never),
    onSuccess: () => {
      queryClient.invalidateQueries()
      toast.success('Backup imported')
    },
    onError: () => {
      toast.error('Failed to import backup')
    },
  })
}
