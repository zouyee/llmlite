import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import { TerminalPanel } from '@/components/settings/TerminalPanel'
import { render } from '../../test-utils'

describe('TerminalPanel', () => {
  it('renders', () => {
    render(<TerminalPanel />)
    expect(screen.getByText('Terminal')).toBeInTheDocument()
    expect(screen.getByDisplayValue('/bin/bash')).toBeInTheDocument()
  })
})
