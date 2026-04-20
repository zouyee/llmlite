import { useAppStore, type ViewType } from '@/hooks/useAppStore'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'

const viewLabels: Record<ViewType, string> = {
  providers: 'Providers',
  proxy: 'Proxy Control',
  sessions: 'Sessions',
  mcp: 'MCP Servers',
  skills: 'Skills',
  prompts: 'Prompts',
  usage: 'Usage',
  workspace: 'Workspace',
  settings: 'Settings',
  openclaw: 'OpenClaw',
}

export default function AppSwitcher() {
  const { currentView, setCurrentView } = useAppStore()

  return (
    <Select value={currentView} onValueChange={(v) => setCurrentView(v as ViewType)}>
      <SelectTrigger className="w-[200px] bg-gray-700 border-gray-600 text-white">
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {Object.entries(viewLabels).map(([key, label]) => (
          <SelectItem key={key} value={key}>
            {label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}
