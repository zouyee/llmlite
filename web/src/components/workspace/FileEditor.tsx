import { useState, useEffect } from 'react'
import { useTranslation } from 'react-i18next'
import { useSaveFile } from '@/hooks/useWorkspace'
import { Save, FileCode } from 'lucide-react'

interface FileEditorProps {
  path: string
  initialContent: string
}

export function FileEditor({ path, initialContent }: FileEditorProps) {
  const { t } = useTranslation()
  const [content, setContent] = useState(initialContent)
  const saveFile = useSaveFile()

  useEffect(() => {
    setContent(initialContent)
  }, [initialContent, path])

  const handleSave = async () => {
    await saveFile.mutateAsync({ path, content })
  }

  return (
    <div className="flex flex-col h-full">
      <div className="flex items-center justify-between mb-2 px-1">
        <div className="flex items-center gap-2 text-sm text-gray-400">
          <FileCode className="w-4 h-4" />
          <span className="truncate max-w-md">{path}</span>
        </div>
        <button
          onClick={handleSave}
          disabled={saveFile.isPending}
          className="flex items-center gap-1.5 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-500 rounded-lg disabled:opacity-50"
        >
          <Save className="w-3.5 h-3.5" />
          {t('common.save', 'Save')}
        </button>
      </div>
      <textarea
        value={content}
        onChange={(e) => setContent(e.target.value)}
        className="flex-1 w-full px-4 py-3 bg-gray-900 border border-gray-700 rounded-lg text-gray-200 font-mono text-sm focus:outline-none focus:border-blue-500 resize-none"
        spellCheck={false}
      />
    </div>
  )
}
