import * as React from "react"
import { cn } from "@/lib/utils"

export interface TooltipProps {
  children?: React.ReactNode
  content: React.ReactNode
  side?: "top" | "right" | "bottom" | "left"
  delayDuration?: number
}

const Tooltip: React.FC<TooltipProps> = ({ children, content, side = "top", delayDuration = 300 }) => {
  const [open, setOpen] = React.useState(false)
  const timeoutRef = React.useRef<NodeJS.Timeout>()

  const handleOpenChange = (open: boolean) => {
    clearTimeout(timeoutRef.current)
    if (open) {
      timeoutRef.current = setTimeout(() => setOpen(true), delayDuration)
    } else {
      setOpen(false)
    }
  }

  return (
    <TooltipContext.Provider value={{ open, onOpenChange: handleOpenChange }}>
      <div className="relative inline-block">{children}</div>
      {open && (
        <div
          className={cn(
            "z-50 overflow-hidden rounded-md border bg-popover px-3 py-1.5 text-sm text-popover-foreground shadow-md animate-in fade-in-0 zoom-in-95",
            "data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:zoom-out-95",
            side === "top" && "bottom-full mb-2",
            side === "bottom" && "top-full mt-2",
            side === "left" && "right-full mr-2",
            side === "right" && "left-full ml-2"
          )}
          role="tooltip"
        >
          {content}
        </div>
      )}
    </TooltipContext.Provider>
  )
}

const TooltipContext = React.createContext<{ open: boolean; onOpenChange: (open: boolean) => void }>({
  open: false,
  onOpenChange: () => {},
})

export interface TooltipTriggerProps extends React.HTMLAttributes<HTMLButtonElement> {}

const TooltipTrigger = React.forwardRef<HTMLButtonElement, TooltipTriggerProps>(
  ({ className, children, ...props }, ref) => {
    const { onOpenChange } = React.useContext(TooltipContext)

    return (
      <button
        ref={ref}
        className={cn("", className)}
        onMouseEnter={() => onOpenChange(true)}
        onMouseLeave={() => onOpenChange(false)}
        onFocus={() => onOpenChange(true)}
        onBlur={() => onOpenChange(false)}
        {...props}
      >
        {children}
      </button>
    )
  }
)
TooltipTrigger.displayName = "TooltipTrigger"

export { Tooltip, TooltipTrigger }
