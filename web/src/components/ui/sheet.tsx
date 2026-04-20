import * as React from "react"
import { cn } from "@/lib/utils"

export interface SheetProps {
  children?: React.ReactNode
  open?: boolean
  onOpenChange?: (open: boolean) => void
}

const Sheet: React.FC<SheetProps> = ({ children, open, onOpenChange }) => {
  return (
    <SheetContext.Provider value={{ open: open ?? false, onOpenChange: onOpenChange ?? (() => {}) }}>
      {children}
    </SheetContext.Provider>
  )
}

const SheetContext = React.createContext<{ open: boolean; onOpenChange: (open: boolean) => void }>({
  open: false,
  onOpenChange: () => {},
})

export interface SheetTriggerProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {}

const SheetTrigger = React.forwardRef<HTMLButtonElement, SheetTriggerProps>(
  ({ className, children, ...props }, ref) => {
    const { onOpenChange } = React.useContext(SheetContext)
    return (
      <button ref={ref} className={cn("", className)} onClick={() => onOpenChange(true)} {...props}>
        {children}
      </button>
    )
  }
)
SheetTrigger.displayName = "SheetTrigger"

export interface SheetContentProps extends React.HTMLAttributes<HTMLDivElement> {
  side?: "top" | "bottom" | "left" | "right"
}

const SheetContent = React.forwardRef<HTMLDivElement, SheetContentProps>(
  ({ className, side = "right", children, ...props }, ref) => {
    const { open, onOpenChange } = React.useContext(SheetContext)

    React.useEffect(() => {
      if (open) {
        document.body.style.overflow = "hidden"
      }
      return () => {
        document.body.style.overflow = ""
      }
    }, [open])

    if (!open) return null

    return (
      <div className="fixed inset-0 z-50">
        <div
          className="fixed inset-0 bg-black/50"
          onClick={() => onOpenChange(false)}
        />
        <div
          ref={ref}
          className={cn(
            "fixed z-50 gap-4 bg-background p-6 shadow-lg transition ease-in-out",
            "data-[state=open]:animate-in data-[state=closed]:animate-out",
            side === "right" && "inset-y-0 right-0 h-full w-3/4 border-l data-[state=closed]:slide-out-to-right data-[state=open]:slide-in-from-right",
            side === "left" && "inset-y-0 left-0 h-full w-3/4 border-r data-[state=closed]:slide-out-to-left data-[state=open]:slide-in-from-left",
            side === "top" && "inset-x-0 top-0 h-1/2 border-b data-[state=closed]:slide-out-to-top data-[state=open]:slide-in-from-top",
            side === "bottom" && "inset-x-0 bottom-0 h-1/2 border-t data-[state=closed]:slide-out-to-bottom data-[state=open]:slide-in-from-bottom",
            className
          )}
          {...props}
        >
          {children}
        </div>
      </div>
    )
  }
)
SheetContent.displayName = "SheetContent"

export interface SheetHeaderProps extends React.HTMLAttributes<HTMLDivElement> {}

const SheetHeader: React.FC<SheetHeaderProps> = ({ className, ...props }) => (
  <div className={cn("flex flex-col space-y-2 text-center sm:text-left", className)} {...props} />
)
SheetHeader.displayName = "SheetHeader"

export interface SheetFooterProps extends React.HTMLAttributes<HTMLDivElement> {}

const SheetFooter: React.FC<SheetFooterProps> = ({ className, ...props }) => (
  <div className={cn("flex flex-col-reverse sm:flex-row sm:justify-end sm:space-x-2", className)} {...props} />
)
SheetFooter.displayName = "SheetFooter"

export interface SheetTitleProps extends React.HTMLAttributes<HTMLHeadingElement> {}

const SheetTitle: React.FC<SheetTitleProps> = ({ className, ...props }) => (
  <h2 className={cn("text-lg font-semibold text-foreground", className)} {...props} />
)
SheetTitle.displayName = "SheetTitle"

export interface SheetDescriptionProps extends React.HTMLAttributes<HTMLParagraphElement> {}

const SheetDescription: React.FC<SheetDescriptionProps> = ({ className, ...props }) => (
  <p className={cn("text-sm text-muted-foreground", className)} {...props} />
)
SheetDescription.displayName = "SheetDescription"

export { Sheet, SheetTrigger, SheetContent, SheetHeader, SheetFooter, SheetTitle, SheetDescription }
