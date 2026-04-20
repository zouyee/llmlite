import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useMutation } from '@tanstack/react-query'
import { mcpApi } from '@/lib/api/mcp'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import toast from 'react-hot-toast'

interface AddMcpDialogProps {
  onClose: () => void
  onSuccess: () => void
}

export function AddMcpDialog({ onClose, onSuccess }: AddMcpDialogProps) {
  const { t } = useTranslation()
  const [name, setName] = useState('')
  const [command, setCommand] = useState('')
  const [args, setArgs] = useState('')
  const [envVars, setEnvVars] = useState('')
  const [enabledFor, setEnabledFor] = useState('')
  const [autoStart, setAutoStart] = useState(false)

  const createServer = useMutation({
    mutationFn: () => mcpApi.create({
      name,
      command,
      args: args.split(' ').filter(Boolean),
      env: envVars.split(',').reduce((acc, kv) => {
        const [k, v] = kv.split('=')
        if (k) acc[k] = v || ''
        return acc
      }, {} as Record<string, string>),
      enabled_for: enabledFor.split(',').filter(Boolean),
      auto_start: autoStart,
    }),
    onSuccess: () => {
      toast.success(t('mcp.serverCreated'))
      onSuccess()
      onClose()
    },
    onError: () => {
      toast.error(t('mcp.createFailed'))
    },
  })

  const isValid = name.trim() && command.trim()

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-gray-800 rounded-lg p-6 w-full max-w-md border border-gray-700">
        <h2 className="text-xl font-bold text-white mb-4">{t('mcp.addServer')}</h2>
        
        <div className="space-y-4">
          <div>
            <label className="block text-sm text-gray-400 mb-1">{t('mcp.name')}</label>
            <Input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="My MCP Server"
              className="bg-gray-700 border-gray-600 text-white"
            />
          </div>
          <div>
            <label className="block text-sm text-gray-400 mb-1">{t('mcp.command')}</label>
            <Input
              value={command}
              onChange={(e) => setCommand(e.target.value)}
              placeholder="npx"
              className="bg-gray-700 border-gray-600 text-white"
            />
          </div>
          <div>
            <label className="block text-sm text-gray-400 mb-1">{t('mcp.args')}</label>
            <Input
              value={args}
              onChange={(e) => setArgs(e.target.value)}
              placeholder="--flag value"
              className="bg-gray-700 border-gray-600 text-white"
            />
          </div>
          <div>
            <label className="block text-sm text-gray-400 mb-1">{t('mcp.envVars')}</label>
            <Input
              value={envVars}
              onChange={(e) => setEnvVars(e.target.value)}
              placeholder="KEY1=val1,KEY2=val2"
              className="bg-gray-700 border-gray-600 text-white"
            />
          </div>
          <div>
            <label className="block text-sm text-gray-400 mb-1">{t('mcp.enabledFor')}</label>
            <Input
              value={enabledFor}
              onChange={(e) => setEnabledFor(e.target.value)}
              placeholder="claude_code,opencode"
              className="bg-gray-700 border-gray-600 text-white"
            />
          </div>
          <div className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={autoStart}
              onChange={(e) => setAutoStart(e.target.checked)}
              id="auto-start"
            />
            <label htmlFor="auto-start" className="text-sm text-gray-300">{t('mcp.autoStart')}</label>
          </div>
        </div>

        <div className="flex justify-end gap-2 mt-6">
          <Button variant="outline" onClick={onClose}>
            {t('common.cancel')}
          </Button>
          <Button
            onClick={() => createServer.mutate()}
            disabled={!isValid || createServer.isPending}
          >
            {t('mcp.create')}
          </Button>
        </div>
      </div>
    </div>
  )
}
