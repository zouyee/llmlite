import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import { BackupPanel } from '@/components/settings/BackupPanel'
import { render } from '../../test-utils'

describe('BackupPanel', () => {
  it('renders export/import buttons', () => {
    render(<BackupPanel />)
    expect(screen.getByText('Backup')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /settings\.export/i })).toBeInTheDocument()
    expect(screen.getByText(/settings\.import/i)).toBeInTheDocument()
  })
})
