import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useRequestLogs } from '@/hooks/useUsage'

export function RequestLogTable() {
  const { t } = useTranslation()
  const [page, setPage] = useState(1)
  const { data: logs, isLoading } = useRequestLogs(50, (page - 1) * 50)

  if (isLoading) {
    return <div className="text-gray-400">{t('app.loading')}</div>
  }

  const totalPages = 1

  return (
    <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
      <h3 className="text-lg font-medium text-white mb-4">{t('usage.requestLogs')}</h3>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-gray-400 border-b border-gray-700">
              <th className="text-left py-2 px-3">{t('usage.time')}</th>
              <th className="text-left py-2 px-3">{t('usage.provider')}</th>
              <th className="text-left py-2 px-3">{t('usage.model')}</th>
              <th className="text-left py-2 px-3">{t('usage.status')}</th>
              <th className="text-right py-2 px-3">{t('usage.latency')}</th>
              <th className="text-right py-2 px-3">{t('usage.tokens')}</th>
              <th className="text-right py-2 px-3">{t('usage.cost')}</th>
            </tr>
          </thead>
          <tbody>
            {(logs ?? []).map((log) => (
              <tr key={log.id} className="border-b border-gray-700">
                <td className="py-2 px-3 text-gray-300">{new Date(log.timestamp * 1000).toLocaleString()}</td>
                <td className="py-2 px-3 text-white">{log.provider}</td>
                <td className="py-2 px-3 text-gray-300">{log.model}</td>
                <td className="py-2 px-3">
                  <span className={`px-2 py-0.5 rounded text-xs ${
                    log.status === 'success' ? 'bg-green-500/20 text-green-400' :
                    log.status === 'error' ? 'bg-red-500/20 text-red-400' :
                    'bg-yellow-500/20 text-yellow-400'
                  }`}>
                    {log.status}
                  </span>
                </td>
                <td className="py-2 px-3 text-right text-gray-300">{log.latency_ms}ms</td>
                <td className="py-2 px-3 text-right text-gray-300">{log.tokens_in + log.tokens_out}</td>
                <td className="py-2 px-3 text-right text-white">-</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="flex justify-between items-center mt-4">
        <button
          onClick={() => setPage(p => Math.max(1, p - 1))}
          disabled={page === 1}
          className="px-3 py-1 bg-gray-700 rounded disabled:opacity-50"
        >
          {t('common.prev')}
        </button>
        <span className="text-gray-400">{page} / {totalPages}</span>
        <button
          onClick={() => setPage(p => p + 1)}
          disabled={page >= totalPages}
          className="px-3 py-1 bg-gray-700 rounded disabled:opacity-50"
        >
          {t('common.next')}
        </button>
      </div>
    </div>
  )
}
