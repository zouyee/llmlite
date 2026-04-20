import * as React from "react"
import { cn } from "@/lib/utils"

export interface DropdownMenuProps {
  children?: React.ReactNode
}

const DropdownMenu: React.FC<DropdownMenuProps> = ({ children }) => {
  const [open, setOpen] = React.useState(false)
  const [position, setPosition] = React.useState<{ x: number; y: number }>({ x: 0, y: 0 })
  const triggerRef = React.useRef<HTMLButtonElement>(null)

  const handleOpenChange = (open: boolean) => {
    setOpen(open)
    if (open && triggerRef.current) {
      const rect = triggerRef.current.getBoundingClientRect()
      setPosition({ x: rect.left, y: rect.bottom + 4 })
    }
  }

  return (
    <DropdownMenuContext.Provider value={{ open, onOpenChange: handleOpenChange, position }}>
      {children}
    </DropdownMenuContext.Provider>
  )
}

const DropdownMenuContext = React.createContext<{
  open: boolean
  onOpenChange: (open: boolean) => void
  position: { x: number; y: number }
}>({ open: false, onOpenChange: () => {}, position: { x: 0, y: 0 } })

export interface DropdownMenuTriggerProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {}

const DropdownMenuTrigger = React.forwardRef<HTMLButtonElement, DropdownMenuTriggerProps>(
  ({ className, children, ...props }, ref) => {
    const { onOpenChange } = React.useContext(DropdownMenuContext)

    return (
      <button
        ref={ref}
        className={cn("", className)}
        onClick={() => onOpenChange(true)}
        {...props}
      >
        {children}
      </button>
    )
  }
)
DropdownMenuTrigger.displayName = "DropdownMenuTrigger"

export interface DropdownMenuContentProps extends React.HTMLAttributes<HTMLDivElement> {}

const DropdownMenuContent = React.forwardRef<HTMLDivElement, DropdownMenuContentProps>(
  ({ className, children, ...props }, _ref) => {
    const { open, onOpenChange, position } = React.useContext(DropdownMenuContext)
    const contentRef = React.useRef<HTMLDivElement>(null)

    React.useEffect(() => {
      if (!open) return
      const handleClickOutside = (e: MouseEvent) => {
        if (contentRef.current && !contentRef.current.contains(e.target as Node)) {
          onOpenChange(false)
        }
      }
      document.addEventListener("click", handleClickOutside)
      return () => document.removeEventListener("click", handleClickOutside)
    }, [open, onOpenChange])

    if (!open) return null

    return (
      <div
        ref={contentRef}
        className={cn(
          "fixed z-50 min-w-[8rem] overflow-hidden rounded-md border bg-popover p-1 text-popover-foreground shadow-md",
          className
        )}
        style={{ left: position.x, top: position.y }}
        {...props}
      >
        {children}
      </div>
    )
  }
)
DropdownMenuContent.displayName = "DropdownMenuContent"

export interface DropdownMenuItemProps extends React.HTMLAttributes<HTMLDivElement> {
  inset?: boolean
}

const DropdownMenuItem = React.forwardRef<HTMLDivElement, DropdownMenuItemProps>(
  ({ className, inset, ...props }, ref) => (
    <div
      ref={ref}
      className={cn(
        "relative flex cursor-default select-none items-center rounded-sm px-2 py-1.5 text-sm outline-none",
        "focus:bg-accent focus:text-accent-foreground",
        "data-[disabled]:pointer-events-none data-[disabled]:opacity-50",
        inset && "pl-8",
        className
      )}
      role="menuitem"
      {...props}
    />
  )
)
DropdownMenuItem.displayName = "DropdownMenuItem"

export interface DropdownMenuLabelProps extends React.HTMLAttributes<HTMLDivElement> {
  inset?: boolean
}

const DropdownMenuLabel = React.forwardRef<HTMLDivElement, DropdownMenuLabelProps>(
  ({ className, inset, ...props }, ref) => (
    <div
      ref={ref}
      className={cn("px-2 py-1.5 text-sm font-semibold", inset && "pl-8", className)}
      {...props}
    />
  )
)
DropdownMenuLabel.displayName = "DropdownMenuLabel"

export interface DropdownMenuSeparatorProps extends React.HTMLAttributes<HTMLDivElement> {}

const DropdownMenuSeparator: React.FC<DropdownMenuSeparatorProps> = ({ className, ...props }) => (
  <div className={cn("-mx-1 my-1 h-px bg-muted", className)} role="separator" {...props} />
)
DropdownMenuSeparator.displayName = "DropdownMenuSeparator"

const DropdownMenuGroup: React.FC<React.HTMLAttributes<HTMLDivElement>> = ({ className, ...props }) => (
  <div className={cn("", className)} role="group" {...props} />
)

const DropdownMenuRadioGroup: React.FC<React.HTMLAttributes<HTMLDivElement>> = ({ className, ...props }) => (
  <div className={cn("", className)} role="radiogroup" {...props} />
)

export {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuGroup,
  DropdownMenuRadioGroup,
}
