import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import {
  Command,
  CommandInput,
  CommandList,
  CommandEmpty,
  CommandGroup,
  CommandItem,
  CommandSeparator,
} from '@/components/ui/command'
import { ScrollArea } from '@/components/ui/scroll-area'

describe('Command', () => {
  it('renders command with input and list area', () => {
    render(
      <Command data-testid="cmd">
        <CommandList>Items</CommandList>
      </Command>
    )
    expect(screen.getByTestId('cmd')).toBeInTheDocument()
    expect(screen.getByRole('textbox')).toBeInTheDocument()
  })

  it('calls onValueChange when typing', () => {
    const onValueChange = vi.fn()
    render(<Command onValueChange={onValueChange} data-testid="cmd" />)
    fireEvent.change(screen.getByRole('textbox'), { target: { value: 'hello' } })
    expect(onValueChange).toHaveBeenCalledWith('hello')
  })

  it('uses controlled value', () => {
    render(<Command value="test" data-testid="cmd" />)
    expect(screen.getByRole('textbox')).toHaveValue('test')
  })
})

describe('CommandInput', () => {
  it('renders input', () => {
    render(<CommandInput data-testid="inp" />)
    expect(screen.getByTestId('inp')).toBeInTheDocument()
  })
})

describe('CommandList', () => {
  it('renders list', () => {
    render(<CommandList data-testid="list">Items</CommandList>)
    expect(screen.getByTestId('list')).toBeInTheDocument()
  })
})

describe('CommandEmpty', () => {
  it('renders empty state', () => {
    render(<CommandEmpty data-testid="empty">No results</CommandEmpty>)
    expect(screen.getByTestId('empty')).toBeInTheDocument()
    expect(screen.getByText('No results')).toBeInTheDocument()
  })
})

describe('CommandGroup', () => {
  it('renders group', () => {
    render(<CommandGroup data-testid="group">Group</CommandGroup>)
    expect(screen.getByTestId('group')).toBeInTheDocument()
  })
})

describe('CommandItem', () => {
  it('renders item', () => {
    render(<CommandItem data-testid="item">Item</CommandItem>)
    expect(screen.getByTestId('item')).toBeInTheDocument()
  })

  it('calls onSelect when clicked', () => {
    const onSelect = vi.fn()
    render(<CommandItem onSelect={onSelect} data-testid="item">Item</CommandItem>)
    fireEvent.click(screen.getByTestId('item'))
    expect(onSelect).toHaveBeenCalled()
  })
})

describe('CommandSeparator', () => {
  it('renders separator', () => {
    render(<CommandSeparator data-testid="sep" />)
    expect(screen.getByTestId('sep')).toBeInTheDocument()
  })
})

describe('ScrollArea', () => {
  it('renders vertical scroll area by default', () => {
    render(
      <ScrollArea data-testid="sa">
        <div>Content</div>
      </ScrollArea>
    )
    expect(screen.getByTestId('sa')).toBeInTheDocument()
    expect(screen.getByText('Content')).toBeInTheDocument()
  })

  it('renders horizontal scroll area', () => {
    const { container } = render(
      <ScrollArea orientation="horizontal" data-testid="sa">
        <div>Content</div>
      </ScrollArea>
    )
    const viewport = container.querySelector('.overflow-x-auto')
    expect(viewport).toBeInTheDocument()
    expect(viewport).not.toHaveClass('overflow-y-auto')
  })

  it('renders both orientations', () => {
    const { container } = render(
      <ScrollArea orientation="both" data-testid="sa">
        <div>Content</div>
      </ScrollArea>
    )
    const viewport = container.querySelector('.overflow-y-auto.overflow-x-auto') || container.querySelector('.overflow-x-auto.overflow-y-auto')
    expect(viewport).toBeInTheDocument()
  })
})
