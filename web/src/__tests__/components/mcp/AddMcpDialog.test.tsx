import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import { AddMcpDialog } from '@/components/mcp/AddMcpDialog'
import { render } from '../../test-utils'

describe('AddMcpDialog', () => {
  it('renders add MCP dialog', () => {
    render(<AddMcpDialog onClose={() => {}} onSuccess={() => {}} />)
    expect(screen.getByPlaceholderText(/My MCP Server/i)).toBeInTheDocument()
  })
})
