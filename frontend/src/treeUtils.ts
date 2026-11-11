import type { TreeNode } from './api/types'

export interface FlatNode {
  id: string
  title: string
  depth: number
}

export function flattenTree(nodes: TreeNode[], depth = 0): FlatNode[] {
  return nodes.flatMap((n) => [{ id: n.id, title: n.title, depth }, ...flattenTree(n.children, depth + 1)])
}
