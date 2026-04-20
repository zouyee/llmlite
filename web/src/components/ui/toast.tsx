import * as React from "react"
import toast, { Toaster as Roaster } from "react-hot-toast"

export interface ToastProps {
  id?: string
  title?: string
  description?: string
  variant?: "default" | "success" | "error" | "loading"
  duration?: number
}

const Toast: React.FC<ToastProps> = ({ title, description, variant = "default" }) => {
  const bgColor = {
    default: "bg-background border",
    success: "bg-green-500 text-white",
    error: "bg-red-500 text-white",
    loading: "bg-blue-500 text-white",
  }[variant]

  return (
    <div className={`${bgColor} rounded-lg shadow-lg p-4 min-w-[300px]`}>
      {title && <div className="font-medium">{title}</div>}
      {description && <div className="text-sm opacity-90">{description}</div>}
    </div>
  )
}

const toastFn = {
  show: (options: ToastProps) => {
    if (options.variant === "loading") {
      return toast.loading(options.title ?? "Loading...", { duration: options.duration })
    } else if (options.variant === "success") {
      return toast.success(options.title ?? "Success", { duration: options.duration })
    } else if (options.variant === "error") {
      return toast.error(options.title ?? "Error", { duration: options.duration })
    } else {
      return toast(options.title ?? "", { duration: options.duration })
    }
  },
  dismiss: (id: string) => toast.dismiss(id),
  error: (message: string) => toast.error(message),
  success: (message: string) => toast.success(message),
  loading: (message: string) => toast.loading(message),
}

export const useToast = () => {
  return toastFn
}

export interface ToasterProps {}

const Toaster: React.FC<ToasterProps> = () => {
  return (
    <Roaster
      position="top-right"
      toastOptions={{
        className: "",
        duration: 4000,
        style: {
          background: "#1a1a2e",
          color: "#fff",
          border: "1px solid #333",
        },
      }}
    />
  )
}
Toaster.displayName = "Toaster"

export { Toaster, Toast, toastFn }
