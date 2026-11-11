import { createContext, useContext } from 'react'
import type { TreeNode } from '../api/types'

export interface IndexEntry {
  node: TreeNode
  parentId: string | null
  siblings: TreeNode[]
  i: number
}

/** A not-yet-created node being typed. `afterId: null` means first among `parentId`'s children. */
export interface Draft {
  parentId: string | null
  afterId: string | null
}

export interface OutlineApi {
  index: Map<string, IndexEntry>
  /** Ids of rendered rows, in display order (respects collapse). */
  visible: string[]
  collapsed: ReadonlySet<string>
  toggle: (id: string) => void
  expand: (id: string) => void
  actor: string | undefined
  draft: Draft | null
  openDraft: (d: Draft | null) => void
  registerTitle: (id: string, el: HTMLInputElement | null) => void
  registerBody: (id: string, open: (() => void) | null) => void
  focusTitle: (id: string) => void
  focusBody: (id: string) => void
  /** Focus a title once its row (re)mounts, e.g. after a move. */
  requestFocus: (id: string) => void
  refreshTree: () => Promise<void>
  /** Runs an API call; reports failures in the notice (refetching on conflicts). */
  run: <T>(call: () => Promise<T>) => Promise<T | undefined>
}

export const OutlineContext = createContext<OutlineApi | null>(null)

export function useOutline(): OutlineApi {
  const ctx = useContext(OutlineContext)
  if (!ctx) throw new Error('useOutline must be used inside the Outline page')
  return ctx
}

export function buildIndex(nodes: TreeNode[], parentId: string | null = null, into = new Map<string, IndexEntry>()) {
  nodes.forEach((node, i) => {
    into.set(node.id, { node, parentId, siblings: nodes, i })
    buildIndex(node.children, node.id, into)
  })
  return into
}

export function visibleIds(nodes: TreeNode[], collapsed: ReadonlySet<string>): string[] {
  return nodes.flatMap((n) => [n.id, ...(collapsed.has(n.id) ? [] : visibleIds(n.children, collapsed))])
}
