import * as React from "react"
import { cn } from "@/lib/utils"

export interface SliderProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, "onChange"> {
  value?: number
  defaultValue?: number
  onValueChange?: (value: number) => void
  min?: number
  max?: number
  step?: number
}

const Slider: React.FC<SliderProps> = ({
  className,
  value,
  defaultValue = 0,
  onValueChange,
  min = 0,
  max = 100,
  step = 1,
  ...props
}) => {
  const [internalValue, setInternalValue] = React.useState(defaultValue)
  const currentValue = value ?? internalValue

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newValue = Number(e.target.value)
    setInternalValue(newValue)
    onValueChange?.(newValue)
  }

  const percentage = ((currentValue - min) / (max - min)) * 100

  return (
    <div className={cn("relative flex w-full touch-none select-none items-center", className)}>
      <div className="relative h-2 w-full grow overflow-hidden rounded-full bg-secondary">
        <div className="absolute h-full bg-primary" style={{ width: `${percentage}%` }} />
      </div>
      <input
        type="range"
        className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
        value={currentValue}
        onChange={handleChange}
        min={min}
        max={max}
        step={step}
        {...props}
      />
    </div>
  )
}
Slider.displayName = "Slider"

export { Slider }
