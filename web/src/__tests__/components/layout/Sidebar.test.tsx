import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import Sidebar from '@/components/layout/Sidebar'
import { render } from '../../test-utils'

describe('Sidebar', () => {
  it('renders all navigation items', () => {
    render(<Sidebar />)
    expect(screen.getByText(/Providers/i)).toBeInTheDocument()
    expect(screen.getByText(/Sessions/i)).toBeInTheDocument()
    expect(screen.getByText(/Settings/i)).toBeInTheDocument()
  })
})
