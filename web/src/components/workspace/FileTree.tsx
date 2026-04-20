import { useState } from 'react'
import { Folder, FileText, ChevronRight, ChevronDown } from 'lucide-react'
import type { FileNode } from '@/lib/api/workspace'

interface FileTreeProps {
  nodes: FileNode[]
  onSelect: (path: string) => void
  selectedPath?: string
}

function FileTreeNode({
  node,
  onSelect,
  selectedPath,
}: {
  node: FileNode
  onSelect: (path: string) => void
  selectedPath?: string
}) {
  const [expanded, setExpanded] = useState(false)
  const isSelected = selectedPath === node.path

  if (node.is_dir) {
    return (
      <div>
        <button
          onClick={() => setExpanded(!expanded)}
          className={`flex items-center gap-1 w-full px-2 py-1 rounded text-left text-sm hover:bg-gray-700 ${
            isSelected ? 'bg-gray-700 text-blue-400' : 'text-gray-300'
          }`}
        >
          {expanded ? (
            <ChevronDown className="w-3.5 h-3.5" />
          ) : (
            <ChevronRight className="w-3.5 h-3.5" />
          )}
          <Folder className="w-4 h-4 text-yellow-500" />
          <span className="truncate">{node.name}</span>
        </button>
        {expanded && node.children && (
          <div className="ml-4 border-l border-gray-700">
            {node.children.map((child) => (
              <FileTreeNode
                key={child.path}
                node={child}
                onSelect={onSelect}
                selectedPath={selectedPath}
              />
            ))}
          </div>
        )}
      </div>
    )
  }

  return (
    <button
      onClick={() => onSelect(node.path)}
      className={`flex items-center gap-2 w-full px-2 py-1 rounded text-left text-sm hover:bg-gray-700 ${
        isSelected ? 'bg-gray-700 text-blue-400' : 'text-gray-300'
      }`}
    >
      <FileText className="w-4 h-4 text-gray-400" />
      <span className="truncate">{node.name}</span>
    </button>
  )
}

export function FileTree({ nodes, onSelect, selectedPath }: FileTreeProps) {
  return (
    <div className="space-y-0.5">
      {nodes.map((node) => (
        <FileTreeNode
          key={node.path}
          node={node}
          onSelect={onSelect}
          selectedPath={selectedPath}
        />
      ))}
    </div>
  )
}
