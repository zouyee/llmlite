import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useSessions, useDeleteSession, useRestoreSession } from '@/hooks/useSession'
import { SessionTOC } from '@/components/sessions/SessionTOC'
import toast from 'react-hot-toast'

export default function SessionManagerPage() {
  const { t } = useTranslation()
  const { data: sessions, isLoading } = useSessions()
  const deleteSession = useDeleteSession()
  const restoreSession = useRestoreSession()
  const [selectedId, setSelectedId] = useState<string | undefined>()
  const [searchQuery, setSearchQuery] = useState('')

  const filteredSessions = sessions?.filter(
    (s) =>
      s.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
      s.last_message_preview?.toLowerCase().includes(searchQuery.toLowerCase())
  ) ?? []

  const handleDelete = async (id: string) => {
    if (confirm(t('sessions.confirmDelete'))) {
      try {
        await deleteSession.mutateAsync(id)
        toast.success(t('sessions.deleted'))
        if (selectedId === id) setSelectedId(undefined)
      } catch {
        toast.error(t('sessions.deleteFailed'))
      }
    }
  }

  const handleRestore = async (id: string) => {
    try {
      await restoreSession.mutateAsync(id)
      toast.success(t('sessions.restored'))
    } catch {
      toast.error(t('sessions.restoreFailed'))
    }
  }

  if (isLoading) {
    return <div className="text-gray-400">{t('app.loading')}</div>
  }

  return (
    <div className="flex h-full">
      <SessionTOC
        sessions={filteredSessions}
        selectedId={selectedId}
        onSelect={setSelectedId}
      />
      <div className="flex-1 p-6 overflow-y-auto">
        <h1 className="text-2xl font-bold text-white mb-6">{t('sessions.title')}</h1>
        
        <div className="mb-4">
          <input
            type="text"
            placeholder={t('sessions.searchPlaceholder') || 'Search by title or content...'}
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full max-w-md px-4 py-2 bg-gray-800 border border-gray-700 rounded text-white placeholder:text-gray-400"
          />
        </div>

        {!filteredSessions.length ? (
          <div className="text-gray-400 text-center py-8">{t('sessions.noSessions')}</div>
        ) : (
          <div className="grid gap-4">
            {filteredSessions.map((session) => (
              <div
                key={session.id}
                className={`bg-gray-800 rounded-lg p-4 border border-gray-700 ${
                  selectedId === session.id ? 'ring-2 ring-blue-500' : ''
                }`}
                onClick={() => setSelectedId(session.id)}
              >
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <h3 className="font-medium text-white">{session.title}</h3>
                    <div className="flex gap-2 mt-1">
                      <span className="px-2 py-0.5 text-xs bg-gray-700 rounded">{session.tool}</span>
                      <span className="px-2 py-0.5 text-xs bg-gray-700 rounded">{session.provider}</span>
                      <span className="px-2 py-0.5 text-xs bg-gray-700 rounded">{session.model}</span>
                    </div>
                    <p className="text-sm text-gray-400 mt-2 line-clamp-2">
                      {session.last_message_preview || t('sessions.noMessages')}
                    </p>
                    <div className="text-xs text-gray-500 mt-2">
                      {session.message_count} {t('sessions.messages')} •{' '}
                      {new Date(session.created_at * 1000).toLocaleString()}
                    </div>
                  </div>
                  <div className="flex gap-2 ml-4">
                    {!session.archived ? (
                      <button
                        onClick={(e) => {
                          e.stopPropagation()
                          handleDelete(session.id)
                        }}
                        className="px-3 py-1 text-sm bg-red-700 hover:bg-red-600 rounded"
                      >
                        {t('sessions.delete')}
                      </button>
                    ) : (
                      <button
                        onClick={(e) => {
                          e.stopPropagation()
                          handleRestore(session.id)
                        }}
                        className="px-3 py-1 text-sm bg-green-700 hover:bg-green-600 rounded"
                      >
                        {t('sessions.restore')}
                      </button>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
