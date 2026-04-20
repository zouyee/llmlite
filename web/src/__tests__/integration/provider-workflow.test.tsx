import { describe, it, expect } from 'vitest'
import { screen, waitFor, fireEvent } from '@testing-library/react'
import ProviderList from '@/components/providers/ProviderList'
import { render } from '../test-utils'

describe('Provider Workflow Integration', () => {
  it('renders provider list and allows search filtering', async () => {
    render(<ProviderList />)

    await waitFor(() => {
      expect(screen.getByPlaceholderText(/search providers/i)).toBeInTheDocument()
    })

    const searchInput = screen.getByPlaceholderText(/search providers/i)
    fireEvent.change(searchInput, { target: { value: 'OpenAI' } })

    expect(searchInput).toHaveValue('OpenAI')
  })
})
