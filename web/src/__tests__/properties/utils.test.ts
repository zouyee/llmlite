import { describe, it, expect } from 'vitest'
import fc from 'fast-check'
import { cn } from '@/lib/utils'

describe('Property Tests: Utils', () => {
  it('cn merges Tailwind classes deterministically', () => {
    const tailwindClasses = ['flex', 'hidden', 'block', 'text-sm', 'text-lg', 'bg-red-500', 'bg-blue-500', 'p-4', 'm-4', 'rounded']
    fc.assert(
      fc.property(
        fc.array(fc.constantFrom(...tailwindClasses), { minLength: 1, maxLength: 10 }),
        (classes) => {
          const result = cn(...classes)
          expect(typeof result).toBe('string')
          // Result is deterministic (same input => same output)
          expect(cn(...classes)).toBe(result)
          // No empty strings in parts
          const parts = result.split(/\s+/).filter(Boolean)
          expect(parts.every(p => p.length > 0)).toBe(true)
        }
      ),
      { numRuns: 100 }
    )
  })

  it('cn with empty or whitespace inputs returns empty string', () => {
    fc.assert(
      fc.property(
        fc.array(fc.stringMatching(/^[\s]*$/)),
        (inputs) => {
          const result = cn(...inputs)
          expect(result.trim()).toBe('')
        }
      ),
      { numRuns: 100 }
    )
  })

  it('cn preserves conditional class objects', () => {
    fc.assert(
      fc.property(
        fc.boolean(),
        fc.boolean(),
        (a, b) => {
          const result = cn('base', { active: a, disabled: b })
          expect(result).toContain('base')
          if (a) expect(result).toContain('active')
          if (b) expect(result).toContain('disabled')
        }
      ),
      { numRuns: 100 }
    )
  })

  it('JSON parse/stringify round-trip for primitive values', () => {
    fc.assert(
      fc.property(
        fc.oneof(fc.integer(), fc.string(), fc.boolean(), fc.constant(null)),
        (value) => {
          const serialized = JSON.stringify(value)
          const parsed = JSON.parse(serialized)
          expect(parsed).toEqual(value)
        }
      ),
      { numRuns: 100 }
    )
  })

  it('JSON parse rejects malformed strings', () => {
    fc.assert(
      fc.property(
        fc.string().filter(s => {
          try { JSON.parse(s); return false } catch { return true }
        }),
        (badJson) => {
          expect(() => JSON.parse(badJson)).toThrow()
        }
      ),
      { numRuns: 100 }
    )
  })

  it('URL scheme validation for deeplinks', () => {
    fc.assert(
      fc.property(
        fc.string({ minLength: 2, maxLength: 10 }).filter(s => /^[a-z][a-z0-9+\-.]*$/.test(s)),
        fc.string({ minLength: 1, maxLength: 30 }).filter(s => /^[a-zA-Z0-9\-_.]+$/.test(s)),
        (scheme, path) => {
          const url = `${scheme}://${path}`
          const parsed = new URL(url)
          expect(parsed.protocol).toBe(`${scheme.toLowerCase()}:`)
          expect(parsed.host + parsed.pathname).toBe(path)
        }
      ),
      { numRuns: 100 }
    )
  })

  it('Date ISO string parsing is reversible', () => {
    fc.assert(
      fc.property(
        fc.date({ min: new Date('2000-01-01'), max: new Date('2030-12-31') }),
        (date) => {
          const iso = date.toISOString()
          const parsed = new Date(iso)
          expect(parsed.toISOString()).toBe(iso)
        }
      ),
      { numRuns: 100 }
    )
  })
})
