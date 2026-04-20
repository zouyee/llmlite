import Sidebar from './Sidebar'
import TopBar from './TopBar'

interface AppLayoutProps {
  children?: React.ReactNode
}

export default function AppLayout({ children }: AppLayoutProps) {
  return (
    <div className="flex h-screen bg-gray-900 text-gray-100">
      <Sidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <TopBar />
        <main className="flex-1 overflow-auto p-6 bg-gray-900">
          {children}
        </main>
      </div>
    </div>
  )
}
