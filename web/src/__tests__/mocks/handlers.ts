import { http, HttpResponse } from 'msw'

// Mock data
const mockProviders = [
  {
    id: 'openai',
    name: 'OpenAI',
    base_url: 'https://api.openai.com/v1',
    auth_type: 'bearer' as const,
    default_model: 'gpt-4o',
    supports: ['chat', 'embeddings'],
    is_official: true,
    enabled: true,
    sort_order: 0,
  },
  {
    id: 'anthropic',
    name: 'Anthropic',
    base_url: 'https://api.anthropic.com',
    auth_type: 'bearer' as const,
    default_model: 'claude-3-5-sonnet-20241022',
    supports: ['chat'],
    is_official: true,
    enabled: true,
    sort_order: 1,
  },
]

const mockSessions = [
  {
    id: 'session-1',
    tool: 'claude_code' as const,
    title: 'Fix authentication bug',
    provider: 'openai',
    model: 'gpt-4o',
    message_count: 42,
    created_at: Date.now() - 86400000,
    updated_at: Date.now() - 3600000,
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
    created_at: Date.now() - 172800000,
    updated_at: Date.now() - 7200000,
    archived: false,
    last_message_preview: 'Starting implementation...',
  },
]

const mockMcpServers = [
  {
    id: 'mcp-1',
    name: 'Filesystem MCP',
    command: 'npx',
    args: ['-y', '@modelcontextprotocol/server-filesystem', '/tmp'],
    env: {},
    state: 'running' as const,
    auto_start: true,
    enabled_for: ['claude_code'],
  },
  {
    id: 'mcp-2',
    name: 'Git MCP',
    command: 'npx',
    args: ['-y', '@modelcontextprotocol/server-git'],
    env: {},
    state: 'stopped' as const,
    auto_start: false,
    enabled_for: ['claude_code'],
  },
]

const mockPrompts = [
  {
    id: 'prompt-1',
    name: 'Code Review',
    content: 'You are a senior code reviewer. Analyze the following code for bugs, performance issues, and best practices violations.',
    tags: ['development', 'review'],
    enabled: true,
    created_at: Date.now(),
    updated_at: Date.now(),
  },
  {
    id: 'prompt-2',
    name: 'Documentation Writer',
    content: 'You are a technical writer. Create clear, concise documentation for the following code.',
    tags: ['documentation'],
    enabled: true,
    created_at: Date.now(),
    updated_at: Date.now(),
  },
]

const mockSkills = [
  {
    id: 'skill-1',
    name: 'Git Assistant',
    description: 'Helps with git operations and workflows',
    version: '1.2.0',
    author: 'llmlite',
    installed: true,
    updated_at: Date.now(),
  },
  {
    id: 'skill-2',
    name: 'Docker Helper',
    description: 'Assists with Docker and container management',
    version: '0.8.0',
    author: 'community',
    installed: false,
    updated_at: Date.now(),
  },
]

const mockUsageOverview = {
  total_requests: 1542,
  total_tokens: 2847291,
  total_cost: 47.23,
  active_providers: 2,
}

const mockUsageTrends = [
  { date: '2024-01-01', requests: 120, tokens: 245000, cost: 3.50 },
  { date: '2024-01-02', requests: 98, tokens: 198000, cost: 2.80 },
  { date: '2024-01-03', requests: 145, tokens: 312000, cost: 4.20 },
]

const mockRequestLogs = [
  {
    id: 'log-1',
    timestamp: Date.now() - 3600000,
    provider: 'openai',
    model: 'gpt-4o',
    status: 'success',
    tokens_in: 150,
    tokens_out: 320,
    latency_ms: 850,
  },
  {
    id: 'log-2',
    timestamp: Date.now() - 7200000,
    provider: 'anthropic',
    model: 'claude-3-5-sonnet',
    status: 'success',
    tokens_in: 200,
    tokens_out: 450,
    latency_ms: 1200,
  },
]

const mockModelStats = [
  { model: 'gpt-4o', requests: 892, tokens_in: 156000, tokens_out: 445000, cost: 28.50 },
  { model: 'claude-3-5-sonnet', requests: 650, tokens_in: 128000, tokens_out: 389000, cost: 18.73 },
]

const mockCostConfig = [
  { model: 'gpt-4o', input_price: 0.005, output_price: 0.015 },
  { model: 'claude-3-5-sonnet', input_price: 0.003, output_price: 0.015 },
]

const mockProxyStatus = {
  running: true,
  port: 4000,
  uptime_seconds: 86400,
}

const mockFailoverQueue = {
  providers: [
    { id: 'openai', name: 'OpenAI', priority: 1, healthy: true, circuit_state: 'closed' as const },
    { id: 'anthropic', name: 'Anthropic', priority: 2, healthy: true, circuit_state: 'closed' as const },
  ],
}

const mockFailoverConfig = {
  enabled: true,
  max_retries: 3,
  retry_interval_ms: 1000,
  timeout_ms: 30000,
}

const mockCircuitBreakerConfig = {
  failure_threshold: 5,
  recovery_timeout_ms: 60000,
  half_open_max_requests: 3,
}

const mockConfig = {
  port: 4000,
  enable_connection_pool: true,
  enable_health_checker: true,
  health_check_interval_ms: 30000,
  health_check_timeout_ms: 5000,
  latency_window_size: 100,
}

export const handlers = [
  // Provider API
  http.get('*/api/providers', () => {
    return HttpResponse.json({ data: mockProviders })
  }),

  // Provider Presets API
  http.get('*/api/providers/presets', () => {
    return HttpResponse.json({
      data: [
        {
          id: 'preset-openai',
          name: 'OpenAI Official',
          provider_type: 'openai',
          base_url: 'https://api.openai.com/v1',
          auth_type: 'bearer',
          default_models: ['gpt-4o', 'gpt-4o-mini', 'gpt-3.5-turbo'],
          features: ['chat', 'embeddings'],
          website: 'https://openai.com',
          description: 'Official OpenAI provider',
        },
      ],
    })
  }),

  http.post('*/api/providers/presets/:id/import', ({ params }) => {
    const provider = mockProviders.find((p) => p.id === params.id)
    return HttpResponse.json({ imported: true, provider: provider || mockProviders[0] })
  }),

  http.post('*/api/providers/sort', async ({ request }) => {
    const body = await request.json() as { ids: string[] }
    return HttpResponse.json({ sorted: body.ids })
  }),

  http.post('*/api/providers/switch/:id', ({ params }) => {
    const provider = mockProviders.find((p) => p.id === params.id)
    if (!provider) {
      return new HttpResponse(null, { status: 404 })
    }
    return HttpResponse.json({ switched: true, provider })
  }),

  http.post('*/api/providers/test/:id', () => {
    return HttpResponse.json({ success: true, latency_ms: 120 })
  }),

  http.get('*/api/providers/:id', ({ params }) => {
    const provider = mockProviders.find((p) => p.id === params.id)
    if (!provider) {
      return new HttpResponse(null, { status: 404 })
    }
    return HttpResponse.json(provider)
  }),

  http.post('*/api/providers', async ({ request }) => {
    const body = await request.json() as Record<string, unknown>
    return HttpResponse.json({ ...body, id: `provider-${Date.now()}` })
  }),

  http.put('*/api/providers/:id', async ({ request }) => {
    const body = await request.json()
    return HttpResponse.json(body)
  }),

  http.delete('*/api/providers/:id', () => {
    return new HttpResponse(null, { status: 204 })
  }),

  // Sessions API
  http.get('*/api/sessions', () => {
    return HttpResponse.json({ sessions: mockSessions })
  }),

  http.post('*/api/sessions/search', async ({ request }) => {
    const body = await request.json() as { query: string }
    const results = mockSessions.filter(
      (s) =>
        s.title.toLowerCase().includes(body.query.toLowerCase()) ||
        s.last_message_preview?.toLowerCase().includes(body.query.toLowerCase())
    )
    return HttpResponse.json({ results })
  }),

  http.get('*/api/sessions/:id', ({ params }) => {
    const session = mockSessions.find((s) => s.id === params.id)
    if (!session) {
      return new HttpResponse(null, { status: 404 })
    }
    return HttpResponse.json(session)
  }),

  http.delete('*/api/sessions/:id', () => {
    return new HttpResponse(null, { status: 204 })
  }),

  http.post('*/api/sessions/:id/archive', () => {
    return new HttpResponse(null, { status: 204 })
  }),

  http.post('*/api/sessions/:id/restore', () => {
    return new HttpResponse(null, { status: 204 })
  }),

  // MCP API
  http.get('*/api/mcp', () => {
    return HttpResponse.json({ servers: mockMcpServers })
  }),

  http.get('*/api/mcp/:id', ({ params }) => {
    const server = mockMcpServers.find((s) => s.id === params.id)
    if (!server) {
      return new HttpResponse(null, { status: 404 })
    }
    return HttpResponse.json(server)
  }),

  http.post('*/api/mcp', async ({ request }) => {
    const body = await request.json() as Record<string, unknown>
    return HttpResponse.json({ ...body, id: `mcp-${Date.now()}`, state: 'stopped' })
  }),

  http.put('*/api/mcp/:id', async ({ request }) => {
    const body = await request.json()
    return HttpResponse.json(body)
  }),

  http.delete('*/api/mcp/:id', () => {
    return new HttpResponse(null, { status: 204 })
  }),

  http.post('*/api/mcp/:id/start', () => {
    return HttpResponse.json({ success: true })
  }),

  http.post('*/api/mcp/:id/stop', () => {
    return HttpResponse.json({ success: true })
  }),

  http.post('*/api/mcp/:id/restart', () => {
    return HttpResponse.json({ success: true })
  }),

  // Config API
  http.get('*/api/config', () => {
    return HttpResponse.json(mockConfig)
  }),

  http.put('*/api/config', async ({ request }) => {
    const body = await request.json() as Record<string, unknown>
    return HttpResponse.json({ ...mockConfig, ...body })
  }),

  http.post('*/api/config/reload', () => {
    return new HttpResponse(null, { status: 204 })
  }),

  // Health API
  http.get('*/health/live', () => {
    return HttpResponse.json({ status: 'ok' })
  }),

  http.get('*/health/ready', () => {
    return HttpResponse.json({ status: 'ready' })
  }),

  http.get('*/health', () => {
    return HttpResponse.json({
      status: 'healthy',
      uptime_seconds: 86400,
      version: '0.2.0',
      providers: {
        openai: { healthy: true, circuit_state: 'closed' },
        anthropic: { healthy: true, circuit_state: 'closed' },
      },
    })
  }),

  http.get('*/metrics', () => {
    return HttpResponse.json({ total_requests: 1542 })
  }),

  http.get('*/metrics/latency', () => {
    return HttpResponse.json({
      openai: { p50: 120, p95: 450, p99: 890 },
      anthropic: { p50: 180, p95: 560, p99: 1200 },
    })
  }),

  // Proxy API
  http.get('*/api/proxy/status', () => {
    return HttpResponse.json(mockProxyStatus)
  }),

  http.post('*/api/proxy/start', () => {
    return HttpResponse.json({ success: true })
  }),

  http.post('*/api/proxy/stop', () => {
    return HttpResponse.json({ success: true })
  }),

  // Failover API
  http.get('*/api/failover/queue', () => {
    return HttpResponse.json(mockFailoverQueue)
  }),

  http.put('*/api/failover/queue', async ({ request }) => {
    const body = await request.json() as { providers: unknown[] }
    return HttpResponse.json({ ...mockFailoverQueue, providers: body.providers })
  }),

  http.get('*/api/failover/config', () => {
    return HttpResponse.json(mockFailoverConfig)
  }),

  http.put('*/api/failover/config', async ({ request }) => {
    const body = await request.json() as Record<string, unknown>
    return HttpResponse.json({ ...mockFailoverConfig, ...body })
  }),

  http.get('*/api/circuit-breaker/config', () => {
    return HttpResponse.json(mockCircuitBreakerConfig)
  }),

  http.put('*/api/circuit-breaker/config', async ({ request }) => {
    const body = await request.json() as Record<string, unknown>
    return HttpResponse.json({ ...mockCircuitBreakerConfig, ...body })
  }),

  // Usage API
  http.get('*/api/usage/overview', () => {
    return HttpResponse.json(mockUsageOverview)
  }),

  http.get('*/api/usage/trends', () => {
    return HttpResponse.json(mockUsageTrends)
  }),

  http.get('*/api/usage/logs', () => {
    return HttpResponse.json(mockRequestLogs)
  }),

  http.get('*/api/usage/models', () => {
    return HttpResponse.json(mockModelStats)
  }),

  http.get('*/api/usage/cost-config', () => {
    return HttpResponse.json(mockCostConfig)
  }),

  http.put('*/api/usage/cost-config', async ({ request }) => {
    const body = await request.json()
    return HttpResponse.json(body)
  }),

  http.get('*/api/usage/export', () => {
    return HttpResponse.json(mockUsageOverview)
  }),

  // Skills API
  http.get('*/api/skills', () => {
    return HttpResponse.json(mockSkills)
  }),

  http.post('*/api/skills/:id/install', ({ params }) => {
    const skill = mockSkills.find((s) => s.id === params.id)
    if (!skill) {
      return new HttpResponse(null, { status: 404 })
    }
    return HttpResponse.json({ ...skill, installed: true })
  }),

  http.delete('*/api/skills/:id', () => {
    return new HttpResponse(null, { status: 204 })
  }),

  http.post('*/api/skills/:id/update', ({ params }) => {
    const skill = mockSkills.find((s) => s.id === params.id)
    if (!skill) {
      return new HttpResponse(null, { status: 404 })
    }
    return HttpResponse.json(skill)
  }),

  http.get('*/api/skills/repos', () => {
    return HttpResponse.json([
      { url: 'https://example.com/skills', name: 'Official Skills' },
    ])
  }),

  http.post('*/api/skills/repos', async ({ request }) => {
    const body = await request.json()
    return HttpResponse.json(body)
  }),

  http.delete('*/api/skills/repos/:id', () => {
    return new HttpResponse(null, { status: 204 })
  }),

  // Prompts API
  http.get('*/api/prompts', () => {
    return HttpResponse.json(mockPrompts)
  }),

  http.post('*/api/prompts', async ({ request }) => {
    const body = await request.json() as Record<string, unknown>
    return HttpResponse.json({ ...body, id: `prompt-${Date.now()}` })
  }),

  http.put('*/api/prompts/:id', async ({ request }) => {
    const body = await request.json() as Record<string, unknown>
    return HttpResponse.json(body)
  }),

  http.delete('*/api/prompts/:id', () => {
    return new HttpResponse(null, { status: 204 })
  }),

  // Settings API
  http.get('*/api/settings/theme', () => {
    return HttpResponse.json({ theme: 'dark', primary_color: '#6366f1' })
  }),

  http.put('*/api/settings/theme', async ({ request }) => {
    const body = await request.json() as Record<string, unknown>
    return HttpResponse.json(body)
  }),

  http.get('*/api/settings/webdav', () => {
    return HttpResponse.json({
      url: '',
      username: '',
      password: '',
      auto_sync: false,
      sync_interval_ms: 300000,
    })
  }),

  http.put('*/api/settings/webdav', async ({ request }) => {
    const body = await request.json() as Record<string, unknown>
    return HttpResponse.json(body)
  }),

  http.post('*/api/settings/webdav/sync', () => {
    return HttpResponse.json({ success: true })
  }),

  http.post('*/api/settings/backup/export', () => {
    return HttpResponse.json({
      version: '1.0.0',
      timestamp: Date.now(),
      providers: mockProviders,
      mcp_servers: mockMcpServers,
      prompts: mockPrompts,
      skills: mockSkills,
      config: mockConfig,
    })
  }),

  http.post('*/api/settings/backup/import', async () => {
    return HttpResponse.json({ success: true })
  }),

  // DeepLink API
  http.post('*/api/deeplink/parse', async ({ request }) => {
    const body = await request.json() as { url: string }
    if (!body.url.startsWith('llmlite://')) {
      return HttpResponse.json({ error: 'Invalid URL scheme' }, { status: 400 })
    }
    return HttpResponse.json({ type: 'mcp', data: mockMcpServers[0] })
  }),

  http.post('*/api/deeplink/import', async () => {
    return HttpResponse.json({ success: true })
  }),

  http.post('*/api/deeplink/export', async () => {
    return HttpResponse.json({ url: 'llmlite://mcp/server-1' })
  }),

  // Workspace API
  http.get('*/api/workspace/files', () => {
    return HttpResponse.json([
      {
        name: 'root',
        path: '/',
        is_dir: true,
        children: [
          { name: 'src', path: '/src', is_dir: true, children: [] },
          { name: 'README.md', path: '/README.md', is_dir: false },
        ],
      },
    ])
  }),

  http.get('*/api/workspace/file', ({ request }) => {
    const url = new URL(request.url)
    return HttpResponse.json({ content: '// file content here', path: url.searchParams.get('path') })
  }),

  http.put('*/api/workspace/file', async () => {
    return HttpResponse.json({ success: true })
  }),

  http.get('*/api/workspace/memory', () => {
    return HttpResponse.json({
      date: new Date().toISOString().split('T')[0],
      content: 'Today I worked on...',
      updated_at: Date.now(),
    })
  }),

  http.put('*/api/workspace/memory', async ({ request }) => {
    const body = await request.json() as Record<string, unknown>
    return HttpResponse.json(body)
  }),

  http.post('*/api/workspace/memory', async ({ request }) => {
    const body = await request.json() as Record<string, unknown>
    return HttpResponse.json(body)
  }),

  // OpenClaw API
  http.get('*/api/openclaw/config', () => {
    return HttpResponse.json({
      default_model: 'claude-3-5-sonnet',
      temperature: 0.7,
      max_tokens: 4096,
      env_vars: { OPENAI_API_KEY: 'sk-...' },
      enabled_tools: ['read', 'write', 'bash'],
      available_tools: ['read', 'write', 'bash', 'grep', 'edit'],
    })
  }),

  http.put('*/api/openclaw/config', async ({ request }) => {
    const body = await request.json()
    return HttpResponse.json(body)
  }),
]
