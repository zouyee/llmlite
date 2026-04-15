import { useState, useCallback } from 'react'
import { useSortProviders } from './useProvider'

interface UseDragSortOptions<T> {
  items: T[]
  getId: (item: T) => string
  onSortEnd?: (items: T[]) => void
}

export function useDragSort<T>({ items, getId, onSortEnd }: UseDragSortOptions<T>) {
  const [localItems, setLocalItems] = useState(items)
  const sortProviders = useSortProviders()

  const handleDragEnd = useCallback(
    (activeId: string, overId: string) => {
      if (activeId === overId) return

      const oldIndex = localItems.findIndex((item) => getId(item) === activeId)
      const newIndex = localItems.findIndex((item) => getId(item) === overId)

      if (oldIndex === -1 || newIndex === -1) return

      const newItems = [...localItems]
      const [removed] = newItems.splice(oldIndex, 1)
      newItems.splice(newIndex, 0, removed)

      setLocalItems(newItems)
      onSortEnd?.(newItems)

      const ids = newItems.map(getId)
      sortProviders.mutate(ids)
    },
    [localItems, getId, onSortEnd, sortProviders]
  )

  return {
    localItems,
    setLocalItems,
    handleDragEnd,
    isSorting: sortProviders.isPending,
  }
}