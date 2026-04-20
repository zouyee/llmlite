import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import type { Session } from '@/lib/api/sessions'

interface SessionTOCProps {
  sessions: Session[]
  selectedId?: string
  onSelect: (id: string) => void
}

export function SessionTOC({ sessions, selectedId, onSelect }: SessionTOCProps) {
  const { t } = useTranslation()
  const [searchQuery, setSearchQuery] = useState('')

  const filteredSessions = sessions.filter(
    (s) =>
      s.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
      s.last_message_preview?.toLowerCase().includes(searchQuery.toLowerCase())
  )

  return (
    <div className="w-64 bg-gray-800 border-r border-gray-700 flex flex-col h-full">
      <div className="p-3 border-b border-gray-700">
        <input
          type="text"
          placeholder={t('sessions.search') || 'Search sessions...'}
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded text-sm text-white placeholder:text-gray-400"
        />
      </div>
      <div className="flex-1 overflow-y-auto">
        {filteredSessions.map((session) => (
          <button
            key={session.id}
            onClick={() => onSelect(session.id)}
            className={`w-full text-left px-3 py-2 border-b border-gray-700 hover:bg-gray-700 transition-colors ${
              selectedId === session.id ? 'bg-gray-700 border-l-2 border-l-blue-500' : ''
            }`}
          >
            <div className="text-sm font-medium text-white truncate">{session.title}</div>
            <div className="text-xs text-gray-400 truncate mt-1">
              {session.last_message_preview || t('sessions.noMessages')}
            </div>
            <div className="text-xs text-gray-500 mt-1">
              {new Date(session.created_at * 1000).toLocaleDateString()}
            </div>
          </button>
        ))}
      </div>
    </div>
  )
}
