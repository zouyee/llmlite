import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useSessions, useDeleteSession, useArchiveSession, useRestoreSession } from '@/hooks/useSession'
import { ConfirmDialog } from '@/components/common/ConfirmDialog'
import toast from 'react-hot-toast'

const TOOL_LABELS: Record<string, string> = {
  claude_code: 'Claude Code',
  codex: 'Codex',
  gemini_cli: 'Gemini CLI',
  opencode: 'OpenCode',
  openclaw: 'OpenClaw',
}

export default function SessionList() {
  const { t } = useTranslation()
  const [toolFilter, setToolFilter] = useState<string | undefined>()
  const [search, setSearch] = useState('')
  const { data: sessions, isLoading } = useSessions(toolFilter)
  const deleteSession = useDeleteSession()
  const archiveSession = useArchiveSession()
  const restoreSession = useRestoreSession()
  const [confirmDelete, setConfirmDelete] = useState<string | null>(null)

  const filteredSessions = sessions?.filter((s) => {
    const q = search.toLowerCase()
    return (
      s.title.toLowerCase().includes(q) ||
      (s.last_message_preview && s.last_message_preview.toLowerCase().includes(q)) ||
      (s.first_user_message && s.first_user_message.toLowerCase().includes(q))
    )
  })

  const handleDelete = async (id: string) => {
    try {
      await deleteSession.mutateAsync(id)
      toast.success('Session deleted')
    } catch {
      toast.error('Failed to delete session')
    }
  }

  const handleArchive = async (id: string) => {
    try {
      await archiveSession.mutateAsync(id)
      toast.success('Session archived')
    } catch {
      toast.error('Failed to archive session')
    }
  }

  const handleRestore = async (id: string) => {
    try {
      await restoreSession.mutateAsync(id)
      toast.success('Session restored')
    } catch {
      toast.error('Failed to restore session')
    }
  }

  const formatDate = (timestamp: number) => {
    return new Date(timestamp * 1000).toLocaleDateString()
  }

  if (isLoading) {
    return <div className="text-gray-400">{t('app.loading')}</div>
  }

  return (
    <div>
      <div className="flex gap-4 mb-4">
        <input
          type="text"
          placeholder={t('session.searchPlaceholder')}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="flex-1 px-4 py-2 bg-gray-800 border border-gray-700 rounded-lg text-white placeholder-gray-500 focus:outline-none focus:border-blue-500"
        />
        <select
          value={toolFilter || ''}
          onChange={(e) => setToolFilter(e.target.value || undefined)}
          className="px-4 py-2 bg-gray-800 border border-gray-700 rounded-lg text-white focus:outline-none focus:border-blue-500"
        >
          <option value="">All Tools</option>
          {Object.entries(TOOL_LABELS).map(([key, label]) => (
            <option key={key} value={key}>{label}</option>
          ))}
        </select>
      </div>

      {!filteredSessions?.length ? (
        <div className="text-gray-400 text-center py-8">{t('session.noSessions')}</div>
      ) : (
        <div className="grid gap-4">
          {filteredSessions.map((session) => (
            <div
              key={session.id}
              className="bg-gray-800 rounded-lg p-4 border border-gray-700"
            >
              <div className="flex items-start justify-between">
                <div className="flex-1">
                  <div className="flex items-center gap-2 flex-wrap">
                    <h3 className="font-medium text-white">{session.title}</h3>
                    <span className="px-2 py-0.5 text-xs bg-gray-700 rounded">
                      {TOOL_LABELS[session.tool] || session.tool}
                    </span>
                    <span className="px-2 py-0.5 text-xs bg-gray-700 rounded">
                      {session.provider}
                    </span>
                    <span className="px-2 py-0.5 text-xs bg-gray-700 rounded">
                      {session.model}
                    </span>
                    {session.archived && (
                      <span className="px-2 py-0.5 text-xs bg-yellow-600 rounded">
                        {t('session.archived')}
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-gray-500 mt-1">
                    {session.message_count} messages | {formatDate(session.created_at)}
                  </p>
                  {session.last_message_preview && (
                    <p className="text-sm text-gray-300 mt-2 truncate">
                      {session.last_message_preview}
                    </p>
                  )}
                </div>

                <div className="flex gap-2">
                  {session.archived ? (
                    <button
                      onClick={() => handleRestore(session.id)}
                      className="px-3 py-1 text-sm bg-green-700 hover:bg-green-600 rounded"
                    >
                      Restore
                    </button>
                  ) : (
                    <button
                      onClick={() => handleArchive(session.id)}
                      className="px-3 py-1 text-sm bg-yellow-700 hover:bg-yellow-600 rounded"
                    >
                      Archive
                    </button>
                  )}
                  <button
                    onClick={() => setConfirmDelete(session.id)}
                    className="px-3 py-1 text-sm bg-red-700 hover:bg-red-600 rounded"
                  >
                    {t('session.delete')}
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      <ConfirmDialog
        isOpen={!!confirmDelete}
        title={t('session.confirmDeleteTitle', 'Delete Session')}
        content={t('session.confirmDeleteContent', 'Are you sure you want to delete this session? This action cannot be undone.')}
        confirmText={t('common.delete', 'Delete')}
        cancelText={t('common.cancel', 'Cancel')}
        variant="destructive"
        onConfirm={() => {
          if (confirmDelete) handleDelete(confirmDelete)
          setConfirmDelete(null)
        }}
        onCancel={() => setConfirmDelete(null)}
      />
    </div>
  )
}
