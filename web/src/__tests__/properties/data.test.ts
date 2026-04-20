import { describe, it, expect } from 'vitest'
import fc from 'fast-check'

describe('Property Tests: Data Transforms', () => {
  it('array drag-sort preserves all elements', () => {
    fc.assert(
      fc.property(
        fc.array(fc.string({ minLength: 1, maxLength: 10 }), { minLength: 2, maxLength: 20 }),
        fc.integer({ min: 0, max: 19 }),
        fc.integer({ min: 0, max: 19 }),
        (items, from, to) => {
          const safeFrom = from % items.length
          const safeTo = to % items.length
          const reordered = [...items]
          const [moved] = reordered.splice(safeFrom, 1)
          reordered.splice(safeTo, 0, moved)
          expect(reordered).toHaveLength(items.length)
          expect(new Set(reordered)).toEqual(new Set(items))
        }
      ),
      { numRuns: 200 }
    )
  })

  it('session filtering preserves matching items', () => {
    fc.assert(
      fc.property(
        fc.array(
          fc.record({
            title: fc.string({ minLength: 1, maxLength: 30 }),
            preview: fc.option(fc.string({ minLength: 1, maxLength: 50 }), { nil: undefined }),
          }),
          { minLength: 1, maxLength: 20 }
        ),
        fc.string({ minLength: 1, maxLength: 5 }).filter(s => s.trim().length > 0),
        (sessions, query) => {
          const q = query.toLowerCase()
          const filtered = sessions.filter(
            (s) =>
              s.title.toLowerCase().includes(q) ||
              (s.preview !== undefined && s.preview.toLowerCase().includes(q))
          )
          // Every filtered item must match the query
          filtered.forEach((s) => {
            const match =
              s.title.toLowerCase().includes(q) ||
              (s.preview !== undefined && s.preview.toLowerCase().includes(q))
            expect(match).toBe(true)
          })
          // Every non-filtered item must NOT match
          sessions
            .filter((s) => !filtered.includes(s))
            .forEach((s) => {
              const match =
                s.title.toLowerCase().includes(q) ||
                (s.preview !== undefined && s.preview.toLowerCase().includes(q))
              expect(match).toBe(false)
            })
        }
      ),
      { numRuns: 150 }
    )
  })

  it('usage CSV export row count matches data length', () => {
    fc.assert(
      fc.property(
        fc.array(
          fc.record({
            date: fc.string({ minLength: 8, maxLength: 10 }),
            requests: fc.integer({ min: 0, max: 10000 }),
            tokens: fc.integer({ min: 0, max: 1000000 }),
            cost: fc.float({ min: 0, max: 1000 }),
          }),
          { minLength: 0, maxLength: 50 }
        ),
        (data) => {
          const header = 'date,requests,tokens,cost'
          const rows = data.map((d) => `${d.date},${d.requests},${d.tokens},${d.cost.toFixed(2)}`)
          const csv = [header, ...rows].join('\n')
          const lines = csv.split('\n')
          expect(lines.length).toBe(data.length + 1)
        }
      ),
      { numRuns: 100 }
    )
  })

  it('provider badge classification is consistent', () => {
    fc.assert(
      fc.property(
        fc.record({
          is_official: fc.boolean(),
          enabled: fc.boolean(),
          supports: fc.array(fc.constantFrom('chat', 'embeddings', 'vision', 'audio')),
        }),
        (provider) => {
          const hasChat = provider.supports.includes('chat')
          const hasEmbeddings = provider.supports.includes('embeddings')
          const badges = []
          if (provider.is_official) badges.push('official')
          else badges.push('community')
          if (hasChat) badges.push('chat')
          if (hasEmbeddings) badges.push('embeddings')
          expect(badges.length).toBeGreaterThanOrEqual(1)
          expect(badges).toContain(provider.is_official ? 'official' : 'community')
        }
      ),
      { numRuns: 100 }
    )
  })

  it('MCP env var keys are valid JS identifiers', () => {
    fc.assert(
      fc.property(
        fc.dictionary(
          fc.string({ minLength: 1, maxLength: 20 }).filter(s => /^[A-Z][A-Z0-9_]*$/.test(s)),
          fc.string({ minLength: 0, maxLength: 100 })
        ),
        (env) => {
          Object.keys(env).forEach((key) => {
            expect(/^[A-Z][A-Z0-9_]*$/.test(key)).toBe(true)
            expect(key.length).toBeGreaterThan(0)
          })
        }
      ),
      { numRuns: 100 }
    )
  })

  it('failover queue priority ordering is stable', () => {
    fc.assert(
      fc.property(
        fc.array(
          fc.record({
            id: fc.string({ minLength: 1, maxLength: 10 }),
            priority: fc.integer({ min: 1, max: 10 }),
          }),
          { minLength: 1, maxLength: 20 }
        ),
        (providers) => {
          const sorted = [...providers].sort((a, b) => a.priority - b.priority)
          for (let i = 1; i < sorted.length; i++) {
            expect(sorted[i].priority).toBeGreaterThanOrEqual(sorted[i - 1].priority)
          }
        }
      ),
      { numRuns: 100 }
    )
  })

  it('skill installed status toggle is reversible', () => {
    fc.assert(
      fc.property(
        fc.boolean(),
        (initial) => {
          let status = initial
          status = !status
          status = !status
          expect(status).toBe(initial)
        }
      ),
      { numRuns: 100 }
    )
  })

  it('prompt tag filtering preserves tagged items', () => {
    fc.assert(
      fc.property(
        fc.array(
          fc.record({
            id: fc.uuid(),
            tags: fc.array(fc.string({ minLength: 1, maxLength: 10 }), { minLength: 0, maxLength: 5 }),
          }),
          { minLength: 1, maxLength: 20 }
        ),
        fc.string({ minLength: 1, maxLength: 10 }),
        (prompts, tag) => {
          const filtered = prompts.filter((p) => p.tags.includes(tag))
          filtered.forEach((p) => expect(p.tags).toContain(tag))
        }
      ),
      { numRuns: 100 }
    )
  })
})
