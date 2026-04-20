import * as React from "react"
import { cn } from "@/lib/utils"

export interface SwitchProps
  extends Omit<React.InputHTMLAttributes<HTMLInputElement>, "type"> {
  checked?: boolean
  onCheckedChange?: (checked: boolean) => void
}

const Switch = React.forwardRef<HTMLInputElement, SwitchProps>(
  ({ className, checked, onCheckedChange, ...props }, ref) => {
    return (
      <label
        className={cn(
          "relative inline-flex h-6 w-11 cursor-pointer items-center",
          className
        )}
      >
        <input
          type="checkbox"
          className="peer sr-only"
          ref={ref}
          checked={checked}
          onChange={(e) => onCheckedChange?.(e.target.checked)}
          {...props}
        />
        <span
          className={cn(
            "h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent bg-input transition-colors peer-checked:bg-primary peer-focus-visible:outline-none peer-focus-visible:ring-2 peer-focus-visible:ring-ring peer-focus-visible:ring-offset-2 peer-disabled:cursor-not-allowed peer-disabled:opacity-50"
          )}
        />
        <span
          className={cn(
            "pointer-events-none absolute left-0.5 top-0.5 block h-5 w-5 rounded-full bg-background shadow-lg ring-0 transition-transform peer-checked:translate-x-5"
          )}
        />
      </label>
    )
  }
)
Switch.displayName = "Switch"

export { Switch }
