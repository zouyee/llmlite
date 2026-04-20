import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { WebDAVPanel } from '@/components/settings/WebDAVPanel'
import { render } from '../../test-utils'

describe('WebDAVPanel', () => {
  it('renders inputs and sync button', async () => {
    render(<WebDAVPanel />)
    await waitFor(() => {
      expect(screen.getByText('WebDAV')).toBeInTheDocument()
    })
    expect(screen.getByPlaceholderText('https://webdav.example.com')).toBeInTheDocument()
    expect(screen.getByRole('checkbox')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /sync/i })).toBeInTheDocument()
  })
})
