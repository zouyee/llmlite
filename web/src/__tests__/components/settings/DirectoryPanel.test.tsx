import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import { DirectoryPanel } from '@/components/settings/DirectoryPanel'
import { render } from '../../test-utils'

describe('DirectoryPanel', () => {
  it('renders', () => {
    render(<DirectoryPanel />)
    expect(screen.getByText('Directory')).toBeInTheDocument()
    expect(screen.getByDisplayValue('/workspace')).toBeInTheDocument()
    expect(screen.getByDisplayValue('~/.llmlite/sessions')).toBeInTheDocument()
  })
})
