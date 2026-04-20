import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import PromptPanel from '@/pages/PromptPanel'
import { render } from '../test-utils'

describe('PromptPanel', () => {
  it('renders prompts page', async () => {
    render(<PromptPanel />)
    await waitFor(() => {
      expect(screen.getByRole('heading', { name: /Prompts/i })).toBeInTheDocument()
    }, { timeout: 3000 })
  })
})
