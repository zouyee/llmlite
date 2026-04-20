import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useMcpServers, useStartMcpServer, useStopMcpServer, useDeleteMcpServer } from '@/hooks/useMcp'
import { AddMcpDialog } from '@/components/mcp/AddMcpDialog'
import { HealthStatusBadge } from '@/components/providers/HealthStatusBadge'
import toast from 'react-hot-toast'

export function UnifiedMcpPanel() {
  const { t } = useTranslation()
  const { data: servers, isLoading } = useMcpServers()
  const startServer = useStartMcpServer()
  const stopServer = useStopMcpServer()
  const deleteServer = useDeleteMcpServer()
  const [showAddDialog, setShowAddDialog] = useState(false)

  const handleStart = async (id: string) => {
    try {
      await startServer.mutateAsync(id)
      toast.success(t('mcp.serverStarted'))
    } catch {
      toast.error(t('mcp.startFailed'))
    }
  }

  const handleStop = async (id: string) => {
    try {
      await stopServer.mutateAsync(id)
      toast.success(t('mcp.serverStopped'))
    } catch {
      toast.error(t('mcp.stopFailed'))
    }
  }

  const handleDelete = async (id: string) => {
    if (confirm(t('mcp.confirmDelete'))) {
      try {
        await deleteServer.mutateAsync(id)
        toast.success(t('mcp.serverDeleted'))
      } catch {
        toast.error(t('mcp.deleteFailed'))
      }
    }
  }

  if (isLoading) {
    return <div className="text-gray-400">{t('app.loading')}</div>
  }

  return (
    <div>
      <div className="flex justify-between items-center mb-4">
        <h2 className="text-lg font-medium text-white">{t('mcp.title')}</h2>
        <button
          onClick={() => setShowAddDialog(true)}
          className="px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded text-white"
        >
          {t('mcp.addServer')}
        </button>
      </div>

      {!servers?.length ? (
        <div className="text-gray-400 text-center py-8">{t('mcp.noServers')}</div>
      ) : (
        <div className="grid gap-4">
          {servers.map((server) => (
            <div
              key={server.id}
              className="bg-gray-800 rounded-lg p-4 border border-gray-700"
            >
              <div className="flex items-start justify-between">
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <h3 className="font-medium text-white">{server.name}</h3>
                    <HealthStatusBadge
                      status={server.state === 'running' ? 'healthy' : server.state === 'error' ? 'unhealthy' : 'unknown'}
                    />
                  </div>
                  <p className="text-sm text-gray-400 mt-1">
                    {server.command} {server.args?.join(' ')}
                  </p>
                  {server.env && Object.keys(server.env).length > 0 && (
                    <div className="flex gap-2 mt-2">
                      {Object.entries(server.env).map(([k, v]) => (
                        <span key={k} className="px-2 py-0.5 text-xs bg-gray-700 rounded">
                          {k}={v}
                        </span>
                      ))}
                    </div>
                  )}
                </div>

                <div className="flex gap-2">
                  {server.state === 'running' ? (
                    <button
                      onClick={() => handleStop(server.id)}
                      className="px-3 py-1 text-sm bg-yellow-600 hover:bg-yellow-500 rounded"
                    >
                      {t('mcp.stop')}
                    </button>
                  ) : (
                    <button
                      onClick={() => handleStart(server.id)}
                      className="px-3 py-1 text-sm bg-green-700 hover:bg-green-600 rounded"
                    >
                      {t('mcp.start')}
                    </button>
                  )}
                  <button
                    onClick={() => handleDelete(server.id)}
                    className="px-3 py-1 text-sm bg-red-700 hover:bg-red-600 rounded"
                  >
                    {t('provider.delete')}
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {showAddDialog && (
        <AddMcpDialog
          onClose={() => setShowAddDialog(false)}
          onSuccess={() => {}}
        />
      )}
    </div>
  )
}
