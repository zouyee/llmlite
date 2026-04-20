import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import { SessionTOC } from '@/components/sessions/SessionTOC'
import { render } from '../../test-utils'

const mockSessions = [
  {
    id: 'session-1',
    tool: 'claude_code' as const,
    title: 'Fix authentication bug',
    provider: 'openai',
    model: 'gpt-4o',
    message_count: 42,
    created_at: Math.floor(Date.now() / 1000) - 86400,
    updated_at: Math.floor(Date.now() / 1000) - 3600,
    archived: false,
    last_message_preview: 'The auth token was expired...',
  },
  {
    id: 'session-2',
    tool: 'codex' as const,
    title: 'Implement new feature',
    provider: 'anthropic',
    model: 'claude-3-5-sonnet',
    message_count: 128,
    created_at: Math.floor(Date.now() / 1000) - 172800,
    updated_at: Math.floor(Date.now() / 1000) - 7200,
    archived: false,
    last_message_preview: 'Starting implementation...',
  },
]

describe('SessionTOC', () => {
  it('renders session list with search input', () => {
    render(<SessionTOC sessions={mockSessions} onSelect={() => {}} />)
    expect(screen.getByPlaceholderText(/search/i)).toBeInTheDocument()
    expect(screen.getByText('Fix authentication bug')).toBeInTheDocument()
    expect(screen.getByText('Implement new feature')).toBeInTheDocument()
  })

  it('highlights selected session', () => {
    render(<SessionTOC sessions={mockSessions} selectedId="session-1" onSelect={() => {}} />)
    expect(screen.getByText('Fix authentication bug')).toBeInTheDocument()
  })
})
