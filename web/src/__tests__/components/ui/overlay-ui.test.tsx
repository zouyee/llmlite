import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import {
  Dialog,
  DialogTrigger,
  DialogContent,
  DialogHeader,
  DialogFooter,
  DialogTitle,
  DialogDescription,
  DialogClose,
} from '@/components/ui/dialog'
import {
  Sheet,
  SheetTrigger,
  SheetContent,
  SheetHeader,
  SheetFooter,
  SheetTitle,
  SheetDescription,
} from '@/components/ui/sheet'
import {
  Popover,
  PopoverTrigger,
  PopoverContent,
} from '@/components/ui/popover'
import { useState } from 'react'
import {
  Tooltip,
  TooltipTrigger,
} from '@/components/ui/tooltip'
import { Toast, Toaster, useToast, toastFn } from '@/components/ui/toast'

describe('Dialog', () => {
  it('renders dialog when open', () => {
    render(
      <Dialog open={true}>
        <DialogContent data-testid="content">Content</DialogContent>
      </Dialog>
    )
    expect(screen.getByTestId('content')).toBeInTheDocument()
  })

  it('does not render content when closed', () => {
    render(
      <Dialog open={false}>
        <DialogContent data-testid="content">Content</DialogContent>
      </Dialog>
    )
    expect(screen.queryByTestId('content')).not.toBeInTheDocument()
  })

  it('opens via trigger click', () => {
    const onOpenChange = vi.fn()
    render(
      <Dialog onOpenChange={onOpenChange}>
        <DialogTrigger data-testid="trigger">Open</DialogTrigger>
      </Dialog>
    )
    fireEvent.click(screen.getByTestId('trigger'))
    expect(onOpenChange).toHaveBeenCalledWith(true)
  })

  it('closes via DialogClose click', () => {
    const onOpenChange = vi.fn()
    render(
      <Dialog open={true} onOpenChange={onOpenChange}>
        <DialogContent>
          <DialogClose data-testid="close" />
        </DialogContent>
      </Dialog>
    )
    fireEvent.click(screen.getByTestId('close'))
    expect(onOpenChange).toHaveBeenCalledWith(false)
  })

  it('closes on overlay click', () => {
    const onOpenChange = vi.fn()
    const onClose = vi.fn()
    render(
      <Dialog open={true} onOpenChange={onOpenChange}>
        <DialogContent onClose={onClose} data-testid="content">
          <div data-testid="inner">Inner</div>
        </DialogContent>
      </Dialog>
    )
    const overlay = screen.getByTestId('content').parentElement?.firstChild
    if (overlay && overlay instanceof HTMLElement) {
      fireEvent.click(overlay)
    }
    expect(onClose).toHaveBeenCalled()
    expect(onOpenChange).toHaveBeenCalledWith(false)
  })

  it('closes on Escape key', () => {
    const onOpenChange = vi.fn()
    const onClose = vi.fn()
    render(
      <Dialog open={true} onOpenChange={onOpenChange}>
        <DialogContent onClose={onClose}>Content</DialogContent>
      </Dialog>
    )
    fireEvent.keyDown(document, { key: 'Escape' })
    expect(onClose).toHaveBeenCalled()
    expect(onOpenChange).toHaveBeenCalledWith(false)
  })

  it('DialogHeader renders', () => {
    render(<DialogHeader data-testid="header">Header</DialogHeader>)
    expect(screen.getByTestId('header')).toBeInTheDocument()
  })

  it('DialogFooter renders', () => {
    render(<DialogFooter data-testid="footer">Footer</DialogFooter>)
    expect(screen.getByTestId('footer')).toBeInTheDocument()
  })

  it('DialogTitle renders', () => {
    render(<DialogTitle>Title</DialogTitle>)
    expect(screen.getByText('Title')).toBeInTheDocument()
    expect(screen.getByText('Title').tagName).toBe('H2')
  })

  it('DialogDescription renders', () => {
    render(<DialogDescription>Desc</DialogDescription>)
    expect(screen.getByText('Desc')).toBeInTheDocument()
  })
})

describe('Sheet', () => {
  it('renders sheet when open', () => {
    render(
      <Sheet open={true}>
        <SheetContent data-testid="content">Content</SheetContent>
      </Sheet>
    )
    expect(screen.getByTestId('content')).toBeInTheDocument()
  })

  it('does not render content when closed', () => {
    render(
      <Sheet open={false}>
        <SheetContent data-testid="content">Content</SheetContent>
      </Sheet>
    )
    expect(screen.queryByTestId('content')).not.toBeInTheDocument()
  })

  it('opens via trigger click', () => {
    const onOpenChange = vi.fn()
    render(
      <Sheet onOpenChange={onOpenChange}>
        <SheetTrigger data-testid="trigger">Open</SheetTrigger>
      </Sheet>
    )
    fireEvent.click(screen.getByTestId('trigger'))
    expect(onOpenChange).toHaveBeenCalledWith(true)
  })

  it('closes on overlay click', () => {
    const onOpenChange = vi.fn()
    render(
      <Sheet open={true} onOpenChange={onOpenChange}>
        <SheetContent data-testid="content">Content</SheetContent>
      </Sheet>
    )
    const overlay = screen.getByTestId('content').parentElement?.firstChild
    if (overlay && overlay instanceof HTMLElement) {
      fireEvent.click(overlay)
    }
    expect(onOpenChange).toHaveBeenCalledWith(false)
  })

  it('SheetHeader renders', () => {
    render(<SheetHeader data-testid="header">Header</SheetHeader>)
    expect(screen.getByTestId('header')).toBeInTheDocument()
  })

  it('SheetFooter renders', () => {
    render(<SheetFooter data-testid="footer">Footer</SheetFooter>)
    expect(screen.getByTestId('footer')).toBeInTheDocument()
  })

  it('SheetTitle renders', () => {
    render(<SheetTitle>Title</SheetTitle>)
    expect(screen.getByText('Title')).toBeInTheDocument()
  })

  it('SheetDescription renders', () => {
    render(<SheetDescription>Desc</SheetDescription>)
    expect(screen.getByText('Desc')).toBeInTheDocument()
  })
})

describe('Popover', () => {
  it('renders trigger', () => {
    render(
      <Popover>
        <PopoverTrigger data-testid="trigger">Open</PopoverTrigger>
      </Popover>
    )
    expect(screen.getByTestId('trigger')).toBeInTheDocument()
  })

  it('opens via trigger click', () => {
    function ControlledPopover() {
      const [open, setOpen] = useState(false)
      return (
        <Popover open={open} onOpenChange={setOpen}>
          <PopoverTrigger data-testid="trigger">Open</PopoverTrigger>
          <PopoverContent data-testid="content">Content</PopoverContent>
        </Popover>
      )
    }
    render(<ControlledPopover />)
    fireEvent.click(screen.getByTestId('trigger'))
    expect(screen.getByTestId('content')).toBeInTheDocument()
  })

  it('closes on click outside', () => {
    function ControlledPopover() {
      const [open, setOpen] = useState(true)
      return (
        <Popover open={open} onOpenChange={setOpen}>
          <PopoverTrigger>Open</PopoverTrigger>
          <PopoverContent data-testid="content">Content</PopoverContent>
        </Popover>
      )
    }
    render(<ControlledPopover />)
    fireEvent.click(document.body)
    expect(screen.queryByTestId('content')).not.toBeInTheDocument()
  })

  it('closes on Escape key', () => {
    function ControlledPopover() {
      const [open, setOpen] = useState(true)
      return (
        <Popover open={open} onOpenChange={setOpen}>
          <PopoverTrigger>Open</PopoverTrigger>
          <PopoverContent data-testid="content">Content</PopoverContent>
        </Popover>
      )
    }
    render(<ControlledPopover />)
    fireEvent.keyDown(document, { key: 'Escape' })
    expect(screen.queryByTestId('content')).not.toBeInTheDocument()
  })
})

describe('Tooltip', () => {
  it('renders trigger', () => {
    render(
      <Tooltip content="tip">
        <TooltipTrigger data-testid="trigger">Hover</TooltipTrigger>
      </Tooltip>
    )
    expect(screen.getByTestId('trigger')).toBeInTheDocument()
  })

  it('shows tooltip on mouse enter after delay', async () => {
    render(
      <Tooltip content="tip" delayDuration={0}>
        <TooltipTrigger data-testid="trigger">Hover</TooltipTrigger>
      </Tooltip>
    )
    fireEvent.mouseEnter(screen.getByTestId('trigger'))
    await waitFor(() => expect(screen.getByRole('tooltip')).toHaveTextContent('tip'))
  })

  it('hides tooltip on mouse leave', async () => {
    render(
      <Tooltip content="tip" delayDuration={0}>
        <TooltipTrigger data-testid="trigger">Hover</TooltipTrigger>
      </Tooltip>
    )
    fireEvent.mouseEnter(screen.getByTestId('trigger'))
    await waitFor(() => expect(screen.getByRole('tooltip')).toBeInTheDocument())
    fireEvent.mouseLeave(screen.getByTestId('trigger'))
    await waitFor(() => expect(screen.queryByRole('tooltip')).not.toBeInTheDocument())
  })

  it('shows tooltip on focus after delay', async () => {
    render(
      <Tooltip content="tip" delayDuration={0}>
        <TooltipTrigger data-testid="trigger">Hover</TooltipTrigger>
      </Tooltip>
    )
    fireEvent.focus(screen.getByTestId('trigger'))
    await waitFor(() => expect(screen.getByRole('tooltip')).toHaveTextContent('tip'))
  })

  it('hides tooltip on blur', async () => {
    render(
      <Tooltip content="tip" delayDuration={0}>
        <TooltipTrigger data-testid="trigger">Hover</TooltipTrigger>
      </Tooltip>
    )
    fireEvent.focus(screen.getByTestId('trigger'))
    await waitFor(() => expect(screen.getByRole('tooltip')).toBeInTheDocument())
    fireEvent.blur(screen.getByTestId('trigger'))
    await waitFor(() => expect(screen.queryByRole('tooltip')).not.toBeInTheDocument())
  })
})

describe('Toast', () => {
  it('renders default toast', () => {
    render(<Toast title="Hello" description="World" />)
    expect(screen.getByText('Hello')).toBeInTheDocument()
    expect(screen.getByText('World')).toBeInTheDocument()
  })

  it('renders success variant', () => {
    render(<Toast title="OK" variant="success" />)
    expect(screen.getByText('OK')).toBeInTheDocument()
  })

  it('renders error variant', () => {
    render(<Toast title="Err" variant="error" />)
    expect(screen.getByText('Err')).toBeInTheDocument()
  })

  it('renders loading variant', () => {
    render(<Toast title="Loading" variant="loading" />)
    expect(screen.getByText('Loading')).toBeInTheDocument()
  })

  it('renders Toaster component', () => {
    const { container } = render(<Toaster />)
    expect(container.firstChild).toBeInTheDocument()
  })

  it('useToast returns toast functions', () => {
    const { show, dismiss, error, success, loading } = useToast()
    expect(typeof show).toBe('function')
    expect(typeof dismiss).toBe('function')
    expect(typeof error).toBe('function')
    expect(typeof success).toBe('function')
    expect(typeof loading).toBe('function')
  })

  it('toastFn exports are functions', () => {
    expect(typeof toastFn.show).toBe('function')
    expect(typeof toastFn.dismiss).toBe('function')
    expect(typeof toastFn.error).toBe('function')
    expect(typeof toastFn.success).toBe('function')
    expect(typeof toastFn.loading).toBe('function')
  })
})
