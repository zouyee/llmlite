import * as React from "react"
import { cn } from "@/lib/utils"

export interface PopoverProps {
  children?: React.ReactNode
  open?: boolean
  onOpenChange?: (open: boolean) => void
}

const Popover: React.FC<PopoverProps> = ({ children, open, onOpenChange }) => {
  return (
    <PopoverContext.Provider value={{ open: open ?? false, onOpenChange: onOpenChange ?? (() => {}) }}>
      {children}
    </PopoverContext.Provider>
  )
}

const PopoverContext = React.createContext<{ open: boolean; onOpenChange: (open: boolean) => void }>({
  open: false,
  onOpenChange: () => {},
})

export interface PopoverTriggerProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {}

const PopoverTrigger = React.forwardRef<HTMLButtonElement, PopoverTriggerProps>(
  ({ className, children, ...props }, ref) => {
    const { onOpenChange } = React.useContext(PopoverContext)

    return (
      <button
        ref={ref}
        className={cn("", className)}
        onClick={() => onOpenChange(true)}
        type="button"
        {...props}
      >
        {children}
      </button>
    )
  }
)
PopoverTrigger.displayName = "PopoverTrigger"

export interface PopoverContentProps extends React.HTMLAttributes<HTMLDivElement> {
  align?: "center" | "start" | "end"
  sideOffset?: number
}

const PopoverContent = React.forwardRef<HTMLDivElement, PopoverContentProps>(
  ({ className, align, sideOffset, children, ...props }, _ref) => {
    const { open, onOpenChange } = React.useContext(PopoverContext)
    const contentRef = React.useRef<HTMLDivElement>(null)

    React.useEffect(() => {
      if (!open) return
      const handleClickOutside = (e: MouseEvent) => {
        if (contentRef.current && !contentRef.current.contains(e.target as Node)) {
          onOpenChange(false)
        }
      }
      const handleEscape = (e: KeyboardEvent) => {
        if (e.key === "Escape") onOpenChange(false)
      }
      document.addEventListener("click", handleClickOutside)
      document.addEventListener("keydown", handleEscape)
      return () => {
        document.removeEventListener("click", handleClickOutside)
        document.removeEventListener("keydown", handleEscape)
      }
    }, [open, onOpenChange])

    if (!open) return null

    return (
      <div
        ref={contentRef}
        className={cn(
          "z-50 w-72 rounded-md border bg-popover p-4 text-popover-foreground shadow-md outline-none",
          "data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:zoom-out-95",
          "data-[side=bottom]:slide-in-from-top-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2",
          className
        )}
        {...props}
      >
        {children}
      </div>
    )
  }
)
PopoverContent.displayName = "PopoverContent"

export { Popover, PopoverTrigger, PopoverContent }
