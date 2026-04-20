import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import { McpWizardDialog } from '@/components/mcp/McpWizardDialog'
import { render } from '../../test-utils'

describe('McpWizardDialog', () => {
  it('renders MCP wizard dialog', () => {
    render(<McpWizardDialog isOpen={true} onClose={() => {}} />)
    expect(screen.getByText(/MCP Server Wizard/i)).toBeInTheDocument()
  })
})
