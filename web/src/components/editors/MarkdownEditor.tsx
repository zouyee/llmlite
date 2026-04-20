import { useState } from 'react'
import ReactMarkdown from 'react-markdown'
import { cn } from '@/lib/utils'

interface MarkdownEditorProps {
  value: string
  onChange: (value: string) => void
  className?: string
  height?: string
}

export function MarkdownEditor({
  value,
  onChange,
  className,
  height = '300px',
}: MarkdownEditorProps) {
  const [preview, setPreview] = useState(false)

  return (
    <div className={cn('space-y-2', className)}>
      <div className="flex gap-2">
        <button
          onClick={() => setPreview(false)}
          className={`px-3 py-1 text-xs rounded ${
            !preview
              ? 'bg-blue-600 text-white'
              : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
          }`}
        >
          Edit
        </button>
        <button
          onClick={() => setPreview(true)}
          className={`px-3 py-1 text-xs rounded ${
            preview
              ? 'bg-blue-600 text-white'
              : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
          }`}
        >
          Preview
        </button>
      </div>
      {preview ? (
        <div
          className="prose prose-invert max-w-none bg-gray-900 border border-gray-700 rounded-lg p-4 overflow-auto"
          style={{ height }}
        >
          <ReactMarkdown>{value}</ReactMarkdown>
        </div>
      ) : (
        <textarea
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="w-full px-4 py-3 bg-gray-900 border border-gray-700 rounded-lg text-gray-200 font-mono text-sm focus:outline-none focus:border-blue-500 resize-none"
          style={{ height }}
        />
      )}
    </div>
  )
}
