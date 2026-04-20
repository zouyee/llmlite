import axios, { AxiosError, InternalAxiosRequestConfig } from 'axios'

const API_BASE = import.meta.env.VITE_API_BASE || 'http://localhost:4000'

export const apiClient = axios.create({
  baseURL: API_BASE,
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json',
  },
})

// Request interceptor for API key
apiClient.interceptors.request.use((config: InternalAxiosRequestConfig) => {
  try {
    const apiKey = localStorage.getItem('llmlite_api_key') || 'sk-default'
    config.headers.Authorization = `Bearer ${apiKey}`
  } catch {
    config.headers.Authorization = 'Bearer sk-default'
  }
  return config
})

// Response interceptor for error handling, retry and re-auth
apiClient.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const originalRequest = error.config as InternalAxiosRequestConfig & { _retry?: boolean }

    if (!originalRequest) {
      console.error('API Error:', error.message)
      return Promise.reject(error)
    }

    // 5xx automatic retry once with 1s delay
    if (
      error.response &&
      error.response.status >= 500 &&
      error.response.status < 600 &&
      !originalRequest._retry
    ) {
      originalRequest._retry = true
      await new Promise((resolve) => setTimeout(resolve, 1000))
      return apiClient.request(originalRequest)
    }

    // 401 trigger re-authentication
    if (error.response && error.response.status === 401) {
      console.error('Authentication required. Redirecting to login...')
      window.location.href = '/login'
      return Promise.reject(error)
    }

    console.error('API Error:', error.response?.data || error.message)
    return Promise.reject(error)
  }
)

export default apiClient
