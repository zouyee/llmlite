import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useCreateMcpServer } from '@/hooks/useMcp'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { ChevronRight, ChevronLeft, Check } from 'lucide-react'

interface McpWizardDialogProps {
  isOpen: boolean
  onClose: () => void
}

const presets = [
  { name: 'Filesystem', command: 'npx', args: ['-y', '@modelcontextprotocol/server-filesystem', '.'] },
  { name: 'GitHub', command: 'npx', args: ['-y', '@modelcontextprotocol/server-github'] },
  { name: 'SQLite', command: 'uvx', args: ['mcp-server-sqlite'] },
]

export function McpWizardDialog({ isOpen, onClose }: McpWizardDialogProps) {
  const { t } = useTranslation()
  const createMcp = useCreateMcpServer()
  const [step, setStep] = useState(0)
  const [, setPreset] = useState<typeof presets[0] | null>(null)
  const [name, setName] = useState('')
  const [command, setCommand] = useState('')
  const [args, setArgs] = useState('')
  const [autoStart, setAutoStart] = useState(false)

  const reset = () => {
    setStep(0)
    setPreset(null)
    setName('')
    setCommand('')
    setArgs('')
    setAutoStart(false)
  }

  const handleClose = () => {
    reset()
    onClose()
  }

  const handleFinish = () => {
    if (!name.trim() || !command.trim()) return
    createMcp.mutate({
      name,
      command,
      args: args.split(' ').filter(Boolean),
      env: {},
      auto_start: autoStart,
      enabled_for: [],
    })
    handleClose()
  }

  const steps = [
    {
      title: t('mcp.wizard.step1', 'Select Preset'),
      content: (
        <div className="space-y-2">
          <button
            onClick={() => {
              setPreset(null)
              setStep(1)
            }}
            className="w-full text-left px-4 py-3 rounded-lg bg-gray-700 hover:bg-gray-600 border border-gray-600"
          >
            {t('mcp.wizard.custom', 'Custom Configuration')}
          </button>
          {presets.map((p) => (
            <button
              key={p.name}
              onClick={() => {
                setPreset(p)
                setName(p.name)
                setCommand(p.command)
                setArgs(p.args.join(' '))
                setStep(1)
              }}
              className="w-full text-left px-4 py-3 rounded-lg bg-gray-700 hover:bg-gray-600 border border-gray-600"
            >
              <div className="font-medium">{p.name}</div>
              <div className="text-xs text-gray-400">{p.command} {p.args.join(' ')}</div>
            </button>
          ))}
        </div>
      ),
    },
    {
      title: t('mcp.wizard.step2', 'Configure Server'),
      content: (
        <div className="space-y-4">
          <div>
            <Label className="text-gray-300">{t('mcp.name', 'Name')}</Label>
            <Input value={name} onChange={(e) => setName(e.target.value)} className="bg-gray-900 border-gray-700 mt-1" />
          </div>
          <div>
            <Label className="text-gray-300">{t('mcp.command', 'Command')}</Label>
            <Input value={command} onChange={(e) => setCommand(e.target.value)} className="bg-gray-900 border-gray-700 mt-1" />
          </div>
          <div>
            <Label className="text-gray-300">{t('mcp.args', 'Arguments')}</Label>
            <Input value={args} onChange={(e) => setArgs(e.target.value)} placeholder="arg1 arg2" className="bg-gray-900 border-gray-700 mt-1" />
          </div>
          <div className="flex items-center gap-2">
            <Switch checked={autoStart} onCheckedChange={setAutoStart} />
            <Label className="text-gray-300">{t('mcp.autoStart', 'Auto Start')}</Label>
          </div>
        </div>
      ),
    },
    {
      title: t('mcp.wizard.step3', 'Review'),
      content: (
        <div className="space-y-3 text-sm">
          <div className="flex justify-between"><span className="text-gray-400">{t('mcp.name', 'Name')}</span><span>{name}</span></div>
          <div className="flex justify-between"><span className="text-gray-400">{t('mcp.command', 'Command')}</span><span>{command}</span></div>
          <div className="flex justify-between"><span className="text-gray-400">{t('mcp.args', 'Arguments')}</span><span>{args}</span></div>
          <div className="flex justify-between"><span className="text-gray-400">{t('mcp.autoStart', 'Auto Start')}</span><span>{autoStart ? 'Yes' : 'No'}</span></div>
        </div>
      ),
    },
  ]

  return (
    <Dialog open={isOpen} onOpenChange={handleClose}>
      <DialogContent className="bg-gray-800 border-gray-700 text-gray-100 max-w-lg">
        <DialogHeader>
          <DialogTitle>{t('mcp.wizard.title', 'MCP Server Wizard')}</DialogTitle>
        </DialogHeader>
        <div className="mb-4 flex items-center gap-2 text-xs text-gray-400">
          {steps.map((s, i) => (
            <span key={i} className={`flex items-center gap-1 ${i === step ? 'text-blue-400' : ''}`}>
              {i > 0 && <ChevronRight className="w-3 h-3" />}
              {s.title}
            </span>
          ))}
        </div>
        <div className="min-h-[200px]">{steps[step].content}</div>
        <div className="flex justify-between pt-4">
          <button
            onClick={() => setStep((s) => s - 1)}
            disabled={step === 0}
            className="flex items-center gap-1 px-3 py-2 rounded-lg bg-gray-700 hover:bg-gray-600 text-sm disabled:opacity-30"
          >
            <ChevronLeft className="w-4 h-4" />
            {t('common.back', 'Back')}
          </button>
          {step < steps.length - 1 ? (
            <button
              onClick={() => setStep((s) => s + 1)}
              className="flex items-center gap-1 px-3 py-2 rounded-lg bg-blue-600 hover:bg-blue-500 text-sm"
            >
              {t('common.next', 'Next')}
              <ChevronRight className="w-4 h-4" />
            </button>
          ) : (
            <button
              onClick={handleFinish}
              disabled={!name.trim() || !command.trim()}
              className="flex items-center gap-1 px-3 py-2 rounded-lg bg-green-600 hover:bg-green-500 text-sm disabled:opacity-30"
            >
              <Check className="w-4 h-4" />
              {t('common.finish', 'Finish')}
            </button>
          )}
        </div>
      </DialogContent>
    </Dialog>
  )
}
