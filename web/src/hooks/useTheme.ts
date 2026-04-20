import { useEffect } from 'react'
import { useAppStore } from './useAppStore'

export function useTheme() {
  const { theme, setTheme } = useAppStore()

  useEffect(() => {
    document.documentElement.classList.remove('light', 'dark')
    document.documentElement.classList.add(theme)
    localStorage.setItem('llmlite_theme', theme)
  }, [theme])

  useEffect(() => {
    const savedTheme = localStorage.getItem('llmlite_theme') as 'dark' | 'light' | null
    if (savedTheme && (savedTheme === 'dark' || savedTheme === 'light')) {
      setTheme(savedTheme)
    }
  }, [])

  const toggleTheme = () => {
    setTheme(theme === 'dark' ? 'light' : 'dark')
  }

  return { theme, setTheme, toggleTheme }
}
