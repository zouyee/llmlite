import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useMcpServers, useStartMcpServer, useStopMcpServer, useDeleteMcpServer } from '@/hooks/useMcp'
import toast from 'react-hot-toast'

export default function McpServerList() {
  const { t } = useTranslation()
  const { data: servers, isLoading } = useMcpServers()
  const startServer = useStartMcpServer()
  const stopServer = useStopMcpServer()
  const deleteServer = useDeleteMcpServer()

  const getStateColor = (state: string) => {
    switch (state) {
      case 'running':
        return 'bg-green-600'
      case 'error':
        return 'bg-red-600'
      default:
        return 'bg-gray-600'
    }
  }

  const handleStart = async (id: string) => {
    try {
      await startServer.mutateAsync(id)
      toast.success('Server started')
    } catch {
      toast.error('Failed to start server')
    }
  }

  const handleStop = async (id: string) => {
    try {
      await stopServer.mutateAsync(id)
      toast.success('Server stopped')
    } catch {
      toast.error('Failed to stop server')
    }
  }

  const handleDelete = async (id: string) => {
    if (confirm('Delete this MCP server?')) {
      try {
        await deleteServer.mutateAsync(id)
        toast.success('Server deleted')
      } catch {
        toast.error('Failed to delete server')
      }
    }
  }

  if (isLoading) {
    return <div className="text-gray-400">{t('app.loading')}</div>
  }

  return (
    <div>
      <div className="flex justify-between items-center mb-4">
        <h2 className="text-lg font-medium">{t('mcp.title')}</h2>
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
                    <span className={`px-2 py-0.5 text-xs rounded text-white ${getStateColor(server.state)}`}>
                      {server.state}
                    </span>
                  </div>
                  <p className="text-sm text-gray-400 mt-1">
                    {server.command} {server.args.join(' ')}
                  </p>
                  <div className="flex gap-2 mt-2">
                    {server.enabled_for.map((tool) => (
                      <span key={tool} className="px-2 py-0.5 text-xs bg-gray-700 rounded">
                        {tool}
                      </span>
                    ))}
                  </div>
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
    </div>
  )
}
