import * as React from "react"
import { cn } from "@/lib/utils"

export interface RadioGroupProps extends React.HTMLAttributes<HTMLDivElement> {
  value?: string
  defaultValue?: string
  onValueChange?: (value: string) => void
}

const RadioGroup: React.FC<RadioGroupProps> = ({ className, value, defaultValue, onValueChange, children, ...props }) => {
  const [selectedValue, setSelectedValue] = React.useState(defaultValue ?? "")

  const handleValueChange = (newValue: string) => {
    setSelectedValue(newValue)
    onValueChange?.(newValue)
  }

  return (
    <RadioGroupContext.Provider value={{ value: value ?? selectedValue, onValueChange: handleValueChange }}>
      <div className={cn("grid gap-2", className)} role="radiogroup" {...props}>
        {children}
      </div>
    </RadioGroupContext.Provider>
  )
}

const RadioGroupContext = React.createContext<{ value: string; onValueChange: (value: string) => void }>({
  value: "",
  onValueChange: () => {},
})

export interface RadioGroupItemProps extends React.InputHTMLAttributes<HTMLInputElement> {
  value: string
}

const RadioGroupItem = React.forwardRef<HTMLInputElement, RadioGroupItemProps>(
  ({ className, value, ...props }, ref) => {
    const { value: selectedValue, onValueChange } = React.useContext(RadioGroupContext)
    const isSelected = selectedValue === value

    return (
      <div className="flex items-center space-x-2">
        <input
          ref={ref}
          type="radio"
          className="peer h-4 w-4 cursor-pointer border border-primary text-primary focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
          checked={isSelected}
          onChange={() => onValueChange(value)}
          value={value}
          {...props}
        />
        <label
          className={cn(
            "cursor-pointer text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
          )}
          onClick={() => onValueChange(value)}
        >
          {props.children}
        </label>
      </div>
    )
  }
)
RadioGroupItem.displayName = "RadioGroupItem"

export { RadioGroup, RadioGroupItem }
