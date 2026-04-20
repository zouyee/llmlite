import { describe, it, expect } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { LanguagePanel } from '@/components/settings/LanguagePanel'
import { render } from '../../test-utils'

describe('LanguagePanel', () => {
  it('renders language buttons', async () => {
    render(<LanguagePanel />)
    await waitFor(() => {
      expect(screen.getByRole('button', { name: 'English' })).toBeInTheDocument()
    })
    expect(screen.getByRole('button', { name: '中文' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '日本語' })).toBeInTheDocument()
  })
})
