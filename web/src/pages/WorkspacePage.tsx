import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useFileTree, useFileContent } from '@/hooks/useWorkspace'
import { FileTree } from '@/components/workspace/FileTree'
import { FileEditor } from '@/components/workspace/FileEditor'
import { DailyMemoryPanel } from '@/components/workspace/DailyMemoryPanel'
import { FolderOpen } from 'lucide-react'

export default function WorkspacePage() {
  const { t } = useTranslation()
  const { data: tree, isLoading } = useFileTree()
  const [selectedPath, setSelectedPath] = useState('')
  const { data: fileData } = useFileContent(selectedPath)

  return (
    <div className="flex h-[calc(100vh-8rem)] gap-4">
      <div className="w-64 flex-shrink-0 bg-gray-800 border border-gray-700 rounded-xl p-3 overflow-auto">
        <h3 className="text-sm font-medium text-gray-300 mb-3 flex items-center gap-2">
          <FolderOpen className="w-4 h-4" />
          {t('workspace.files', 'Files')}
        </h3>
        {isLoading ? (
          <p className="text-gray-500 text-sm">{t('app.loading', 'Loading...')}</p>
        ) : tree ? (
          <FileTree nodes={tree} onSelect={setSelectedPath} selectedPath={selectedPath} />
        ) : (
          <p className="text-gray-500 text-sm">{t('workspace.noFiles', 'No files')}</p>
        )}
      </div>
      <div className="flex-1 bg-gray-800 border border-gray-700 rounded-xl p-4 overflow-auto">
        {selectedPath && fileData ? (
          <FileEditor path={selectedPath} initialContent={fileData.content} />
        ) : (
          <DailyMemoryPanel />
        )}
      </div>
    </div>
  )
}
