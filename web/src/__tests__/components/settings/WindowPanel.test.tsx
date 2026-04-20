import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import { WindowPanel } from '@/components/settings/WindowPanel'
import { render } from '../../test-utils'

describe('WindowPanel', () => {
  it('renders switches', () => {
    render(<WindowPanel />)
    expect(screen.getByText('Window')).toBeInTheDocument()
    expect(screen.getAllByRole('checkbox').length).toBeGreaterThanOrEqual(2)
  })
})
