import { Routes, Route, Navigate } from 'react-router-dom'
import { Toaster } from 'react-hot-toast'
import AppLayout from './components/layout/AppLayout'
import ProviderList from './components/providers/ProviderList'
import McpServerList from './components/mcp/McpServerList'
import SessionList from './components/sessions/SessionList'
import ProxyPage from './pages/ProxyPage'
import SettingsPage from './pages/SettingsPage'
import SkillsPage from './pages/SkillsPage'
import PromptPanel from './pages/PromptPanel'
import UsageDashboard from './pages/UsageDashboard'
import WorkspacePage from './pages/WorkspacePage'
import OpenClawPage from './pages/OpenClawPage'
import { RouteSync } from './components/layout/RouteSync'

export default function App() {
  return (
    <>
      <RouteSync />
      <AppLayout>
        <Routes>
          <Route path="/" element={<Navigate to="/providers" replace />} />
          <Route path="/providers" element={<ProviderList />} />
          <Route path="/proxy" element={<ProxyPage />} />
          <Route path="/sessions" element={<SessionList />} />
          <Route path="/mcp" element={<McpServerList />} />
          <Route path="/skills" element={<SkillsPage />} />
          <Route path="/prompts" element={<PromptPanel />} />
          <Route path="/usage" element={<UsageDashboard />} />
          <Route path="/workspace" element={<WorkspacePage />} />
          <Route path="/settings" element={<SettingsPage />} />
          <Route path="/openclaw" element={<OpenClawPage />} />
        </Routes>
        <Toaster position="top-right" />
      </AppLayout>
    </>
  )
}
