import { useRef, useEffect } from 'react'
import { cn } from '@/lib/utils'

interface ConfirmDialogProps {
  isOpen: boolean
  title: string
  content: React.ReactNode
  confirmText?: string
  cancelText?: string
  onConfirm: () => void
  onCancel: () => void
  variant?: 'default' | 'destructive'
}

export function ConfirmDialog({
  isOpen,
  title,
  content,
  confirmText = 'Confirm',
  cancelText = 'Cancel',
  onConfirm,
  onCancel,
  variant = 'default',
}: ConfirmDialogProps) {
  const dialogRef = useRef<HTMLDialogElement>(null)

  useEffect(() => {
    const dialog = dialogRef.current
    if (!dialog) return
    if (typeof dialog.showModal !== 'function' || typeof dialog.close !== 'function') return
    if (isOpen) {
      dialog.showModal()
    } else {
      dialog.close()
    }
  }, [isOpen])

  return (
    <dialog
      ref={dialogRef}
      className="backdrop:bg-black/60 rounded-xl bg-gray-800 border border-gray-700 p-0 text-gray-100 shadow-xl w-full max-w-md"
      onClick={(e) => {
        if (e.target === dialogRef.current) onCancel()
      }}
    >
      <div className="p-6">
        <h3 className="text-lg font-semibold mb-2">{title}</h3>
        <div className="text-gray-300 text-sm mb-6">{content}</div>
        <div className="flex justify-end gap-3">
          <button
            onClick={onCancel}
            className="px-4 py-2 rounded-lg bg-gray-700 hover:bg-gray-600 text-sm font-medium transition-colors"
          >
            {cancelText}
          </button>
          <button
            onClick={onConfirm}
            className={cn(
              'px-4 py-2 rounded-lg text-sm font-medium transition-colors',
              variant === 'destructive'
                ? 'bg-red-600 hover:bg-red-500 text-white'
                : 'bg-blue-600 hover:bg-blue-500 text-white'
            )}
          >
            {confirmText}
          </button>
        </div>
      </div>
    </dialog>
  )
}
