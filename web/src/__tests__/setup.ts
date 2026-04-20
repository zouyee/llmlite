import '@testing-library/jest-dom'
import { server } from './mocks/server'
import { beforeAll, afterEach, afterAll } from 'vitest'

// jsdom localStorage mock — vitest's jsdom may not provide a functional one
const store: Record<string, string> = {}
Object.defineProperty(globalThis, 'localStorage', {
  value: {
    getItem: (key: string) => store[key] ?? null,
    setItem: (key: string, value: string) => { store[key] = value },
    removeItem: (key: string) => { delete store[key] },
    clear: () => { Object.keys(store).forEach((k) => delete store[k]) },
  },
  writable: true,
})

if (typeof globalThis.URL.createObjectURL === 'undefined') {
  Object.defineProperty(globalThis.URL, 'createObjectURL', {
    value: () => 'blob:mock-url',
    writable: true,
  })
  Object.defineProperty(globalThis.URL, 'revokeObjectURL', {
    value: () => {},
    writable: true,
  })
}

beforeAll(() => server.listen({ onUnhandledRequest: 'warn' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
