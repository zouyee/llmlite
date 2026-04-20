import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import SessionList from '@/components/sessions/SessionList'
import { render } from '../../test-utils'

describe('SessionList', () => {
  it('renders search and filter controls', async () => {
    render(<SessionList />)
    await waitFor(() => {
      expect(screen.getByPlaceholderText(/search sessions/i)).toBeInTheDocument()
    })
    expect(screen.getByText('All Tools')).toBeInTheDocument()
  })
})
