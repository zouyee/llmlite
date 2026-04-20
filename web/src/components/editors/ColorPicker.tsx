import { HexColorPicker } from 'react-colorful'
import { useState } from 'react'
import { cn } from '@/lib/utils'

interface ColorPickerProps {
  color: string
  onChange: (color: string) => void
  className?: string
}

export function ColorPicker({ color, onChange, className }: ColorPickerProps) {
  const [format, setFormat] = useState<'hex' | 'rgb' | 'hsl'>('hex')

  const toRgb = (hex: string) => {
    const r = parseInt(hex.slice(1, 3), 16)
    const g = parseInt(hex.slice(3, 5), 16)
    const b = parseInt(hex.slice(5, 7), 16)
    return `rgb(${r}, ${g}, ${b})`
  }

  const toHsl = (hex: string) => {
    const r = parseInt(hex.slice(1, 3), 16) / 255
    const g = parseInt(hex.slice(3, 5), 16) / 255
    const b = parseInt(hex.slice(5, 7), 16) / 255
    const max = Math.max(r, g, b)
    const min = Math.min(r, g, b)
    const l = (max + min) / 2
    const d = max - min
    const h = d === 0 ? 0 : max === r ? ((g - b) / d + 6) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4
    const s = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1))
    return `hsl(${Math.round(h * 60)}, ${Math.round(s * 100)}%, ${Math.round(l * 100)}%)`
  }

  const displayValue =
    format === 'hex' ? color : format === 'rgb' ? toRgb(color) : toHsl(color)

  return (
    <div className={cn('space-y-3', className)}>
      <HexColorPicker color={color} onChange={onChange} className="!w-full" />
      <div className="flex items-center gap-2">
        <div
          className="w-8 h-8 rounded border border-gray-600"
          style={{ backgroundColor: color }}
        />
        <input
          value={displayValue}
          readOnly
          className="flex-1 px-3 py-1.5 bg-gray-900 border border-gray-700 rounded text-sm text-gray-200"
        />
        <div className="flex gap-1">
          {(['hex', 'rgb', 'hsl'] as const).map((f) => (
            <button
              key={f}
              onClick={() => setFormat(f)}
              className={`px-2 py-1 text-xs rounded ${
                format === f
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
              }`}
            >
              {f.toUpperCase()}
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}
