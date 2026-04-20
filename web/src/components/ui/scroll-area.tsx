import * as React from "react"
import { cn } from "@/lib/utils"

export interface ScrollAreaProps extends React.HTMLAttributes<HTMLDivElement> {
  orientation?: "vertical" | "horizontal" | "both"
}

const ScrollArea: React.FC<ScrollAreaProps> = ({ className, orientation = "vertical", children, ...props }) => {
  const viewportRef = React.useRef<HTMLDivElement>(null)

  return (
    <div className={cn("relative overflow-hidden", className)} {...props}>
      <div
        ref={viewportRef}
        className={cn(
          "h-full w-full rounded-[inherit]",
          orientation === "vertical" || orientation === "both" ? "overflow-y-auto" : "",
          orientation === "horizontal" || orientation === "both" ? "overflow-x-auto" : ""
        )}
        style={{ scrollbarWidth: "thin" }}
      >
        {children}
      </div>
      {orientation !== "horizontal" && (
        <div className="absolute right-0 top-0 bottom-0 w-2 pointer-events-none">
          <div className="h-full min-h-[24px] rounded-full bg-border/40 opacity-0 transition-opacity hover:opacity-100" />
        </div>
      )}
    </div>
  )
}
ScrollArea.displayName = "ScrollArea"

export { ScrollArea }
