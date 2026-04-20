import { render as rtlRender } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { I18nextProvider } from 'react-i18next'
import { MemoryRouter } from 'react-router-dom'
import i18n from '@/i18n'

const createTestQueryClient = () =>
  new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: 0 },
      mutations: { retry: false },
    },
  })

export function render(ui: React.ReactElement, { route = '/' } = {}) {
  const queryClient = createTestQueryClient()
  return rtlRender(
    <MemoryRouter initialEntries={[route]}>
      <QueryClientProvider client={queryClient}>
        <I18nextProvider i18n={i18n}>{ui}</I18nextProvider>
      </QueryClientProvider>
    </MemoryRouter>
  )
}
