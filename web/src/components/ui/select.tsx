import * as React from "react"
import { cn } from "@/lib/utils"

export interface SelectProps extends React.HTMLAttributes<HTMLDivElement> {
  value?: string
  defaultValue?: string
  onValueChange?: (value: string) => void
}

const Select: React.FC<SelectProps> = ({ className, value, defaultValue, onValueChange, children, ...props }) => {
  const [selectedValue, setSelectedValue] = React.useState(defaultValue ?? "")

  const handleValueChange = (newValue: string) => {
    setSelectedValue(newValue)
    onValueChange?.(newValue)
  }

  return (
    <SelectContext.Provider value={{ value: value ?? selectedValue, onValueChange: handleValueChange }}>
      <div className={cn("", className)} {...props}>{children}</div>
    </SelectContext.Provider>
  )
}

const SelectContext = React.createContext<{ value: string; onValueChange: (value: string) => void }>({
  value: "",
  onValueChange: () => {},
})

export interface SelectTriggerProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  placeholder?: string
}

const SelectTrigger = React.forwardRef<HTMLButtonElement, SelectTriggerProps>(
  ({ className, placeholder, children, ...props }, _ref) => {
    const { value } = React.useContext(SelectContext)
    const [open, setOpen] = React.useState(false)

    return (
      <button
        type="button"
        className={cn(
          "flex h-10 w-full items-center justify-between rounded-md border border-input bg-background px-3 py-2 text-sm",
          "ring-offset-background placeholder:text-muted-foreground",
          "focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2",
          "disabled:cursor-not-allowed disabled:opacity-50",
          className
        )}
        onClick={() => setOpen(!open)}
        {...props}
      >
        {children || <span className={cn(!value && "text-muted-foreground")}>{value ? children : placeholder}</span>}
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="h-4 w-4 opacity-50">
          <polyline points="6 9 12 15 18 9" />
        </svg>
      </button>
    )
  }
)
SelectTrigger.displayName = "SelectTrigger"

export interface SelectValueProps extends React.HTMLAttributes<HTMLSpanElement> {}

const SelectValue: React.FC<SelectValueProps> = ({ className, ...props }) => {
  const { value } = React.useContext(SelectContext)
  return <span className={cn("", className)} {...props}>{value}</span>
}
SelectValue.displayName = "SelectValue"

export interface SelectContentProps extends React.HTMLAttributes<HTMLDivElement> {}

const SelectContent = React.forwardRef<HTMLDivElement, SelectContentProps>(
  ({ className, children, ...props }, ref) => {
    const [open, setOpen] = React.useState(false)

    React.useEffect(() => {
      const handleClickOutside = () => setOpen(false)
      if (open) {
        document.addEventListener("click", handleClickOutside)
      }
      return () => document.removeEventListener("click", handleClickOutside)
    }, [open])

    if (!open) return null

    return (
      <div
        ref={ref}
        className={cn(
          "relative z-50 min-w-[8rem] overflow-hidden rounded-md border bg-popover p-1 text-popover-foreground shadow-md",
          className
        )}
        {...props}
      >
        {children}
      </div>
    )
  }
)
SelectContent.displayName = "SelectContent"

export interface SelectItemProps extends React.HTMLAttributes<HTMLDivElement> {
  value: string
}

const SelectItem = React.forwardRef<HTMLDivElement, SelectItemProps>(
  ({ className, value, children, ...props }, ref) => {
    const { value: selectedValue, onValueChange } = React.useContext(SelectContext)
    const isSelected = selectedValue === value

    return (
      <div
        ref={ref}
        className={cn(
          "relative flex w-full cursor-default select-none items-center rounded-sm py-1.5 pl-8 pr-2 text-sm outline-none",
          "focus:bg-accent focus:text-accent-foreground",
          isSelected ? "bg-accent/50" : "",
          className
        )}
        onClick={() => {
          onValueChange(value)
        }}
        role="option"
        aria-selected={isSelected}
        {...props}
      >
        <span className="absolute left-2 flex h-3.5 w-3.5 items-center justify-center">
          {isSelected && (
            <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="h-4 w-4">
              <polyline points="20 6 9 17 4 12" />
            </svg>
          )}
        </span>
        {children}
      </div>
    )
  }
)
SelectItem.displayName = "SelectItem"

export { Select, SelectTrigger, SelectContent, SelectItem, SelectValue }
