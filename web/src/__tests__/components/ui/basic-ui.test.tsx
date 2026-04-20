import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { Checkbox } from '@/components/ui/checkbox'
import { Label } from '@/components/ui/label'
import { Separator } from '@/components/ui/separator'
import { Skeleton } from '@/components/ui/skeleton'
import { Textarea } from '@/components/ui/textarea'
import { Switch } from '@/components/ui/switch'

describe('Checkbox', () => {
  it('renders checkbox', () => {
    render(<Checkbox data-testid="cb" />)
    expect(screen.getByTestId('cb')).toBeInTheDocument()
    expect(screen.getByTestId('cb')).toHaveAttribute('type', 'checkbox')
  })

  it('forwards ref', () => {
    const ref = { current: null as HTMLInputElement | null }
    render(<Checkbox ref={ref} data-testid="cb" />)
    expect(ref.current).toBeInstanceOf(HTMLInputElement)
  })

  it('applies custom className', () => {
    render(<Checkbox className="my-class" data-testid="cb" />)
    expect(screen.getByTestId('cb').closest('div')).toHaveClass('my-class')
  })

  it('handles change event', () => {
    const onChange = vi.fn()
    render(<Checkbox onChange={onChange} data-testid="cb" />)
    fireEvent.click(screen.getByTestId('cb'))
    expect(onChange).toHaveBeenCalled()
  })
})

describe('Label', () => {
  it('renders label', () => {
    render(<Label>Email</Label>)
    expect(screen.getByText('Email')).toBeInTheDocument()
    expect(screen.getByText('Email').tagName).toBe('LABEL')
  })

  it('forwards ref', () => {
    const ref = { current: null as HTMLLabelElement | null }
    render(<Label ref={ref}>Label</Label>)
    expect(ref.current).toBeInstanceOf(HTMLLabelElement)
  })

  it('applies custom className', () => {
    render(<Label className="my-label">Label</Label>)
    expect(screen.getByText('Label')).toHaveClass('my-label')
  })
})

describe('Separator', () => {
  it('renders horizontal separator by default', () => {
    render(<Separator data-testid="sep" />)
    const sep = screen.getByTestId('sep')
    expect(sep).toHaveAttribute('role', 'none')
    expect(sep).toHaveClass('h-[1px]')
  })

  it('renders vertical separator', () => {
    render(<Separator orientation="vertical" data-testid="sep" />)
    expect(screen.getByTestId('sep')).toHaveClass('w-[1px]')
    expect(screen.getByTestId('sep')).toHaveAttribute('role', 'none')
  })

  it('renders non-decorative separator with aria', () => {
    render(<Separator decorative={false} data-testid="sep" />)
    const sep = screen.getByTestId('sep')
    expect(sep).toHaveAttribute('role', 'separator')
    expect(sep).toHaveAttribute('aria-orientation', 'horizontal')
  })

  it('forwards ref', () => {
    const ref = { current: null as HTMLDivElement | null }
    render(<Separator ref={ref} />)
    expect(ref.current).toBeInstanceOf(HTMLDivElement)
  })
})

describe('Skeleton', () => {
  it('renders skeleton', () => {
    render(<Skeleton data-testid="sk" />)
    expect(screen.getByTestId('sk')).toBeInTheDocument()
    expect(screen.getByTestId('sk')).toHaveClass('animate-pulse')
  })

  it('applies custom className', () => {
    render(<Skeleton className="my-skeleton" data-testid="sk" />)
    expect(screen.getByTestId('sk')).toHaveClass('my-skeleton')
  })
})

describe('Textarea', () => {
  it('renders textarea', () => {
    render(<Textarea data-testid="ta" />)
    expect(screen.getByTestId('ta')).toBeInTheDocument()
    expect(screen.getByTestId('ta').tagName).toBe('TEXTAREA')
  })

  it('forwards ref', () => {
    const ref = { current: null as HTMLTextAreaElement | null }
    render(<Textarea ref={ref} data-testid="ta" />)
    expect(ref.current).toBeInstanceOf(HTMLTextAreaElement)
  })

  it('applies custom className', () => {
    render(<Textarea className="my-ta" data-testid="ta" />)
    expect(screen.getByTestId('ta')).toHaveClass('my-ta')
  })

  it('handles value changes', () => {
    render(<Textarea data-testid="ta" />)
    fireEvent.change(screen.getByTestId('ta'), { target: { value: 'hello' } })
    expect(screen.getByTestId('ta')).toHaveValue('hello')
  })
})

describe('Switch', () => {
  it('renders switch', () => {
    render(<Switch data-testid="sw" />)
    expect(screen.getByTestId('sw')).toBeInTheDocument()
    expect(screen.getByTestId('sw')).toHaveAttribute('type', 'checkbox')
  })

  it('calls onCheckedChange when toggled', () => {
    const onCheckedChange = vi.fn()
    render(<Switch onCheckedChange={onCheckedChange} data-testid="sw" />)
    fireEvent.click(screen.getByTestId('sw'))
    expect(onCheckedChange).toHaveBeenCalledWith(true)
  })

  it('respects checked prop', () => {
    render(<Switch checked={true} data-testid="sw" />)
    expect(screen.getByTestId('sw')).toBeChecked()
  })

  it('forwards ref', () => {
    const ref = { current: null as HTMLInputElement | null }
    render(<Switch ref={ref} data-testid="sw" />)
    expect(ref.current).toBeInstanceOf(HTMLInputElement)
  })
})
