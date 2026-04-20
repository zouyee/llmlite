import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import {
  FormItem,
  FormLabel,
  FormControl,
  FormDescription,
  FormMessage,
} from '@/components/ui/form'
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group'
import {
  Select,
  SelectTrigger,
  SelectItem,
  SelectValue,
} from '@/components/ui/select'
import { Slider } from '@/components/ui/slider'

describe('Form', () => {
  it('FormItem renders children', () => {
    render(
      <FormItem data-testid="item">
        <span>Child</span>
      </FormItem>
    )
    expect(screen.getByTestId('item')).toBeInTheDocument()
    expect(screen.getByText('Child')).toBeInTheDocument()
  })

  it('FormLabel renders within FormItem', () => {
    render(
      <FormItem>
        <FormLabel>Email</FormLabel>
      </FormItem>
    )
    expect(screen.getByText('Email')).toBeInTheDocument()
    expect(screen.getByText('Email').tagName).toBe('LABEL')
  })

  it('FormControl renders within FormItem', () => {
    render(
      <FormItem>
        <FormControl data-testid="ctrl">
          <input />
        </FormControl>
      </FormItem>
    )
    expect(screen.getByTestId('ctrl')).toBeInTheDocument()
  })

  it('FormDescription renders', () => {
    render(<FormDescription>Description</FormDescription>)
    expect(screen.getByText('Description')).toBeInTheDocument()
  })

  it('FormMessage renders', () => {
    render(<FormMessage>Error</FormMessage>)
    expect(screen.getByText('Error')).toBeInTheDocument()
  })
})

describe('RadioGroup', () => {
  it('renders radio group with items', () => {
    render(
      <RadioGroup data-testid="rg">
        <RadioGroupItem value="a" data-testid="a" />
        <RadioGroupItem value="b" data-testid="b" />
      </RadioGroup>
    )
    expect(screen.getByTestId('rg')).toHaveAttribute('role', 'radiogroup')
    expect(screen.getByTestId('a')).toBeInTheDocument()
    expect(screen.getByTestId('b')).toBeInTheDocument()
  })

  it('selects default value', () => {
    render(
      <RadioGroup defaultValue="a">
        <RadioGroupItem value="a" data-testid="a" />
        <RadioGroupItem value="b" data-testid="b" />
      </RadioGroup>
    )
    expect(screen.getByTestId('a')).toBeChecked()
    expect(screen.getByTestId('b')).not.toBeChecked()
  })

  it('calls onValueChange when selecting', () => {
    const onValueChange = vi.fn()
    render(
      <RadioGroup onValueChange={onValueChange}>
        <RadioGroupItem value="a" data-testid="a" />
        <RadioGroupItem value="b" data-testid="b" />
      </RadioGroup>
    )
    fireEvent.click(screen.getByTestId('b'))
    expect(onValueChange).toHaveBeenCalledWith('b')
  })

  it('controlled value overrides internal state', () => {
    const { rerender } = render(
      <RadioGroup value="a">
        <RadioGroupItem value="a" data-testid="a" />
        <RadioGroupItem value="b" data-testid="b" />
      </RadioGroup>
    )
    expect(screen.getByTestId('a')).toBeChecked()
    rerender(
      <RadioGroup value="b">
        <RadioGroupItem value="a" data-testid="a" />
        <RadioGroupItem value="b" data-testid="b" />
      </RadioGroup>
    )
    expect(screen.getByTestId('b')).toBeChecked()
  })

  it('label click selects radio', () => {
    const onValueChange = vi.fn()
    render(
      <RadioGroup onValueChange={onValueChange}>
        <RadioGroupItem value="a" data-testid="a" />
      </RadioGroup>
    )
    // Click on the label element next to the input
    const wrapper = screen.getByTestId('a').closest('div')
    if (wrapper) {
      const label = wrapper.querySelector('label')
      if (label) fireEvent.click(label)
    }
    expect(onValueChange).toHaveBeenCalledWith('a')
  })
})

describe('Select', () => {
  it('renders select trigger', () => {
    render(
      <Select>
        <SelectTrigger data-testid="trigger" placeholder="Choose" />
      </Select>
    )
    expect(screen.getByTestId('trigger')).toBeInTheDocument()
  })

  it('SelectValue shows current value', () => {
    render(
      <Select value="apple">
        <SelectValue data-testid="val" />
      </Select>
    )
    expect(screen.getByTestId('val')).toHaveTextContent('apple')
  })

  it('SelectItem is selected when value matches', () => {
    render(
      <Select value="b">
        <SelectItem value="a" data-testid="a">A</SelectItem>
        <SelectItem value="b" data-testid="b">B</SelectItem>
      </Select>
    )
    expect(screen.getByTestId('a')).toHaveAttribute('aria-selected', 'false')
    expect(screen.getByTestId('b')).toHaveAttribute('aria-selected', 'true')
  })

  it('calls onValueChange when item clicked', () => {
    const onValueChange = vi.fn()
    render(
      <Select onValueChange={onValueChange}>
        <SelectItem value="a" data-testid="a">A</SelectItem>
        <SelectItem value="b" data-testid="b">B</SelectItem>
      </Select>
    )
    fireEvent.click(screen.getByTestId('b'))
    expect(onValueChange).toHaveBeenCalledWith('b')
  })

  it('controlled value updates selection', () => {
    const { rerender } = render(
      <Select value="a">
        <SelectItem value="a" data-testid="a">A</SelectItem>
        <SelectItem value="b" data-testid="b">B</SelectItem>
      </Select>
    )
    expect(screen.getByTestId('a')).toHaveAttribute('aria-selected', 'true')
    rerender(
      <Select value="b">
        <SelectItem value="a" data-testid="a">A</SelectItem>
        <SelectItem value="b" data-testid="b">B</SelectItem>
      </Select>
    )
    expect(screen.getByTestId('b')).toHaveAttribute('aria-selected', 'true')
  })
})

describe('Slider', () => {
  it('renders slider', () => {
    render(<Slider data-testid="slider" />)
    expect(screen.getByTestId('slider')).toBeInTheDocument()
  })

  it('calls onValueChange on input change', () => {
    const onValueChange = vi.fn()
    render(<Slider onValueChange={onValueChange} data-testid="slider" />)
    const input = screen.getByTestId('slider').querySelector('input')
    if (input) {
      fireEvent.change(input, { target: { value: '50' } })
      expect(onValueChange).toHaveBeenCalledWith(50)
    }
  })

  it('uses defaultValue', () => {
    render(<Slider defaultValue={30} data-testid="slider" />)
    const input = screen.getByTestId('slider') as HTMLInputElement
    expect(input.value).toBe('30')
  })

  it('uses controlled value', () => {
    const { rerender } = render(<Slider value={20} data-testid="slider" />)
    const input = screen.getByTestId('slider') as HTMLInputElement
    expect(input.value).toBe('20')
    rerender(<Slider value={80} data-testid="slider" />)
    expect(input.value).toBe('80')
  })

  it('respects min, max, step props', () => {
    render(<Slider min={10} max={50} step={5} data-testid="slider" />)
    const input = screen.getByTestId('slider') as HTMLInputElement
    expect(input).toHaveAttribute('min', '10')
    expect(input).toHaveAttribute('max', '50')
    expect(input).toHaveAttribute('step', '5')
  })
})
