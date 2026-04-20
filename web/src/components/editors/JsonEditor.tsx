import { useState, useCallback } from 'react'
import CodeMirror from '@uiw/react-codemirror'
import { json } from '@codemirror/lang-json'
import { oneDark } from '@codemirror/theme-one-dark'
import { cn } from '@/lib/utils'

interface JsonEditorProps {
  value: string
  onChange: (value: string) => void
  className?: string
  height?: string
}

export function JsonEditor({
  value,
  onChange,
  className,
  height = '300px',
}: JsonEditorProps) {
  const [parseError, setParseError] = useState<string | null>(null)

  const validateJson = useCallback((text: string) => {
    if (!text.trim()) {
      setParseError(null)
      return
    }
    try {
      JSON.parse(text)
      setParseError(null)
    } catch (e) {
      setParseError((e as Error).message)
    }
  }, [])

  const handleChange = useCallback(
    (text: string) => {
      onChange(text)
      validateJson(text)
    },
    [onChange, validateJson]
  )

  const formatJson = () => {
    try {
      const parsed = JSON.parse(value)
      onChange(JSON.stringify(parsed, null, 2))
      setParseError(null)
    } catch (e) {
      setParseError((e as Error).message)
    }
  }

  return (
    <div className={cn('space-y-2', className)}>
      <div className="flex justify-end gap-2">
        <button
          onClick={formatJson}
          className="px-3 py-1 text-xs bg-gray-700 hover:bg-gray-600 rounded text-gray-200"
        >
          Format
        </button>
      </div>
      <CodeMirror
        value={value}
        height={height}
        extensions={[json()]}
        theme={oneDark}
        onChange={handleChange}
        className="rounded-lg overflow-hidden border border-gray-700"
        basicSetup={{ lineNumbers: true, foldGutter: true }}
      />
      {parseError && (
        <p className="text-sm text-red-400 bg-red-900/20 px-3 py-2 rounded border border-red-800">
          {parseError}
        </p>
      )}
    </div>
  )
}
