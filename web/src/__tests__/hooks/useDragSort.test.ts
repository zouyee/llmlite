import { describe, it, expect, vi } from 'vitest'
import { renderHook, act } from '@testing-library/react'
import { useDragSort } from '@/hooks/useDragSort'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import * as React from 'react'

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: false } },
})

const wrapper = ({ children }: { children: React.ReactNode }) => {
  return React.createElement(QueryClientProvider, { client: queryClient }, children)
}

describe('useDragSort', () => {
  it('initializes with given items', () => {
    const { result } = renderHook(
      () => useDragSort({ items: [{ id: 'a' }, { id: 'b' }], getId: (item) => item.id }),
      { wrapper }
    )
    expect(result.current.localItems).toHaveLength(2)
    expect(result.current.localItems[0].id).toBe('a')
  })

  it('reorders items on drag end', () => {
    const onSortEnd = vi.fn()
    const { result } = renderHook(
      () => useDragSort({ items: [{ id: 'a' }, { id: 'b' }, { id: 'c' }], getId: (item) => item.id, onSortEnd }),
      { wrapper }
    )

    act(() => {
      result.current.handleDragEnd('a', 'c')
    })

    expect(result.current.localItems.map((i) => i.id)).toEqual(['b', 'c', 'a'])
    expect(onSortEnd).toHaveBeenCalled()
  })

  it('does nothing when dragging to same position', () => {
    const onSortEnd = vi.fn()
    const { result } = renderHook(
      () => useDragSort({ items: [{ id: 'a' }, { id: 'b' }], getId: (item) => item.id, onSortEnd }),
      { wrapper }
    )

    act(() => {
      result.current.handleDragEnd('a', 'a')
    })

    expect(result.current.localItems.map((i) => i.id)).toEqual(['a', 'b'])
    expect(onSortEnd).not.toHaveBeenCalled()
  })

  it('does nothing when id not found', () => {
    const onSortEnd = vi.fn()
    const { result } = renderHook(
      () => useDragSort({ items: [{ id: 'a' }, { id: 'b' }], getId: (item) => item.id, onSortEnd }),
      { wrapper }
    )

    act(() => {
      result.current.handleDragEnd('x', 'y')
    })

    expect(result.current.localItems.map((i) => i.id)).toEqual(['a', 'b'])
    expect(onSortEnd).not.toHaveBeenCalled()
  })
})
