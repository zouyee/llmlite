import * as React from 'react'
import { cn } from '@/lib/utils'
import { Label } from './label'

interface FormItemContextValue {
  id: string
}

const FormItemContext = React.createContext<FormItemContextValue>({ id: '' })

const FormItem = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => {
  const id = React.useId()
  return (
    <FormItemContext.Provider value={{ id }}>
      <div ref={ref} className={cn('space-y-2', className)} {...props} />
    </FormItemContext.Provider>
  )
})
FormItem.displayName = 'FormItem'

const FormLabel = React.forwardRef<
  HTMLLabelElement,
  React.LabelHTMLAttributes<HTMLLabelElement>
>(({ className, ...props }, ref) => {
  const { id } = React.useContext(FormItemContext)
  return <Label ref={ref} htmlFor={id} className={className} {...props} />
})
FormLabel.displayName = 'FormLabel'

const FormControl = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ ...props }, ref) => {
  const { id } = React.useContext(FormItemContext)
  return <div ref={ref} id={id} {...props} />
})
FormControl.displayName = 'FormControl'

const FormDescription = React.forwardRef<
  HTMLParagraphElement,
  React.HTMLAttributes<HTMLParagraphElement>
>(({ className, ...props }, ref) => (
  <p
    ref={ref}
    className={cn('text-sm text-gray-400', className)}
    {...props}
  />
))
FormDescription.displayName = 'FormDescription'

const FormMessage = React.forwardRef<
  HTMLParagraphElement,
  React.HTMLAttributes<HTMLParagraphElement>
>(({ className, children, ...props }, ref) => (
  <p
    ref={ref}
    className={cn('text-sm font-medium text-red-400', className)}
    {...props}
  >
    {children}
  </p>
))
FormMessage.displayName = 'FormMessage'

export { FormItem, FormLabel, FormControl, FormDescription, FormMessage }
