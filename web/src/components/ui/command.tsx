import * as React from "react"
import { cn } from "@/lib/utils"

export interface CommandProps extends React.HTMLAttributes<HTMLDivElement> {
  value?: string
  onValueChange?: (value: string) => void
}

const Command: React.FC<CommandProps> = ({ className, value, onValueChange, children, ...props }) => {
  const [inputValue, setInputValue] = React.useState(value ?? "")

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setInputValue(e.target.value)
    onValueChange?.(e.target.value)
  }

  return (
    <div className={cn("", className)} {...props}>
      <div className="flex items-center border-b px-3">
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="mr-2 h-4 w-4 shrink-0 opacity-50">
          <circle cx="11" cy="11" r="8" />
          <line x1="21" y1="21" x2="16.65" y2="16.65" />
        </svg>
        <input
          type="text"
          className="flex h-10 w-full rounded-md bg-transparent py-3 text-sm outline-none placeholder:text-muted-foreground"
          value={inputValue}
          onChange={handleInputChange}
        />
      </div>
      <div className="max-h-[300px] overflow-y-auto p-1">{children}</div>
    </div>
  )
}
Command.displayName = "Command"

export interface CommandInputProps extends React.InputHTMLAttributes<HTMLInputElement> {}

const CommandInput: React.FC<CommandInputProps> = ({ className, ...props }) => (
  <input
    className={cn(
      "flex h-10 w-full rounded-md bg-transparent py-3 text-sm outline-none placeholder:text-muted-foreground",
      className
    )}
    {...props}
  />
)
CommandInput.displayName = "CommandInput"

export interface CommandListProps extends React.HTMLAttributes<HTMLDivElement> {}

const CommandList: React.FC<CommandListProps> = ({ className, ...props }) => (
  <div className={cn("py-2", className)} {...props} />
)
CommandList.displayName = "CommandList"

export interface CommandEmptyProps extends React.HTMLAttributes<HTMLDivElement> {}

const CommandEmpty: React.FC<CommandEmptyProps> = ({ className, ...props }) => (
  <div className={cn("py-6 text-center text-sm", className)} {...props} />
)
CommandEmpty.displayName = "CommandEmpty"

export interface CommandGroupProps extends React.HTMLAttributes<HTMLDivElement> {}

const CommandGroup: React.FC<CommandGroupProps> = ({ className, ...props }) => (
  <div
    className={cn("overflow-hidden p-1 text-foreground", className)}
    {...props}
  />
)
CommandGroup.displayName = "CommandGroup"

export interface CommandItemProps extends React.HTMLAttributes<HTMLDivElement> {
  onSelect?: () => void
}

const CommandItem: React.FC<CommandItemProps> = ({ className, onSelect, children, ...props }) => (
  <div
    className={cn(
      "relative flex cursor-default select-none items-center rounded-sm px-2 py-1.5 text-sm outline-none",
      "focus:bg-accent focus:text-accent-foreground",
      "data-[disabled]:pointer-events-none data-[disabled]:opacity-50",
      className
    )}
    onClick={onSelect}
    {...props}
  >
    {children}
  </div>
)
CommandItem.displayName = "CommandItem"

export interface CommandSeparatorProps extends React.HTMLAttributes<HTMLDivElement> {}

const CommandSeparator: React.FC<CommandSeparatorProps> = ({ className, ...props }) => (
  <div className={cn("-mx-1 h-px bg-border", className)} {...props} />
)
CommandSeparator.displayName = "CommandSeparator"

export {
  Command,
  CommandInput,
  CommandList,
  CommandEmpty,
  CommandGroup,
  CommandItem,
  CommandSeparator,
}
