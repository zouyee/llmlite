import { describe, it, expect, vi } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { UnifiedMcpPanel } from '@/components/mcp/UnifiedMcpPanel'
import { render } from '../../test-utils'

describe('UnifiedMcpPanel', () => {
  it('renders unified MCP panel', async () => {
    vi.stubGlobal('confirm', () => true)
    render(<UnifiedMcpPanel />)
    await waitFor(() => {
      expect(screen.getByText(/MCP Server Management/i)).toBeInTheDocument()
    }, { timeout: 3000 })
    vi.unstubAllGlobals()
  })
})
