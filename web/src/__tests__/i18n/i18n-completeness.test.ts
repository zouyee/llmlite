import { describe, it, expect } from 'vitest'
import en from '@/i18n/locales/en.json'
import zh from '@/i18n/locales/zh.json'
import ja from '@/i18n/locales/ja.json'

function collectKeys(obj: Record<string, unknown>, prefix = ''): string[] {
  const keys: string[] = []
  for (const [key, value] of Object.entries(obj)) {
    const fullKey = prefix ? `${prefix}.${key}` : key
    if (typeof value === 'object' && value !== null) {
      keys.push(...collectKeys(value as Record<string, unknown>, fullKey))
    } else {
      keys.push(fullKey)
    }
  }
  return keys
}

function getValue(obj: Record<string, unknown>, path: string): unknown {
  const parts = path.split('.')
  let current: unknown = obj
  for (const part of parts) {
    if (current === null || typeof current !== 'object') return undefined
    current = (current as Record<string, unknown>)[part]
  }
  return current
}

describe('i18n completeness', () => {
  const enKeys = collectKeys(en)
  const zhKeys = collectKeys(zh)
  const jaKeys = collectKeys(ja)

  it('all en keys exist in zh', () => {
    const missing = enKeys.filter((k) => !zhKeys.includes(k))
    expect(missing).toEqual([])
  })

  it('all en keys exist in ja', () => {
    const missing = enKeys.filter((k) => !jaKeys.includes(k))
    expect(missing).toEqual([])
  })

  it('all zh keys exist in en', () => {
    const missing = zhKeys.filter((k) => !enKeys.includes(k))
    expect(missing).toEqual([])
  })

  it('all ja keys exist in en', () => {
    const missing = jaKeys.filter((k) => !enKeys.includes(k))
    expect(missing).toEqual([])
  })

  it('all en keys have non-empty string values', () => {
    for (const key of enKeys) {
      const value = getValue(en, key)
      expect(typeof value === 'string' && value.length > 0, `Key "${key}" is empty in en`).toBe(true)
    }
  })

  it('all zh keys have non-empty string values', () => {
    for (const key of zhKeys) {
      const value = getValue(zh, key)
      expect(typeof value === 'string' && value.length > 0, `Key "${key}" is empty in zh`).toBe(true)
    }
  })

  it('all ja keys have non-empty string values', () => {
    for (const key of jaKeys) {
      const value = getValue(ja, key)
      expect(typeof value === 'string' && value.length > 0, `Key "${key}" is empty in ja`).toBe(true)
    }
  })
})
