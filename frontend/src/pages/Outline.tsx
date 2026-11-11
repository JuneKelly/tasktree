import { useQueryClient } from '@tanstack/react-query'
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { ApiError } from '../api/client'
import { describeError, useActor, useSchema, useTree } from '../api/hooks'
import { useNotice } from '../noticeContext'
import { buildIndex, OutlineContext, visibleIds, type Draft, type OutlineApi } from '../outline/context'
import { NodeList } from '../outline/Row'

export default function Outline() {
  const tree = useTree()
  const schema = useSchema()
  const actor = useActor()
  const qc = useQueryClient()
  const { notify } = useNotice()

  const [collapsed, setCollapsed] = useState<ReadonlySet<string>>(new Set())
  const [draft, setDraft] = useState<Draft | null>(null)
  const titles = useRef(new Map<string, HTMLInputElement>())
  const bodies = useRef(new Map<string, () => void>())
  const pendingFocus = useRef<string | null>(null)

  const roots = useMemo(() => tree.data?.data ?? [], [tree.data])
  const index = useMemo(() => buildIndex(roots), [roots])
  const visible = useMemo(() => visibleIds(roots, collapsed), [roots, collapsed])

  // Apply a requested focus once the target row has (re)mounted.
  useEffect(() => {
    const id = pendingFocus.current
    const el = id ? titles.current.get(id) : undefined
    if (el && el.isConnected) {
      pendingFocus.current = null
      el.focus()
    }
  })

  const refreshTree = useCallback(() => qc.invalidateQueries({ queryKey: ['tree'] }), [qc])

  const api = useMemo<OutlineApi>(
    () => ({
      index,
      visible,
      collapsed,
      toggle: (id) =>
        setCollapsed((s) => {
          const next = new Set(s)
          if (!next.delete(id)) next.add(id)
          return next
        }),
      expand: (id) =>
        setCollapsed((s) => {
          if (!s.has(id)) return s
          const next = new Set(s)
          next.delete(id)
          return next
        }),
      actor: actor.data?.actor,
      draft,
      openDraft: setDraft,
      registerTitle: (id, el) => {
        if (el) titles.current.set(id, el)
        else titles.current.delete(id)
      },
      registerBody: (id, open) => {
        if (open) bodies.current.set(id, open)
        else bodies.current.delete(id)
      },
      focusTitle: (id) => titles.current.get(id)?.focus(),
      focusBody: (id) => bodies.current.get(id)?.(),
      requestFocus: (id) => {
        pendingFocus.current = id
      },
      refreshTree,
      run: async (call) => {
        try {
          return await call()
        } catch (e) {
          if (e instanceof ApiError && e.code === 'version_conflict') {
            notify('That node changed since it was loaded. The outline has been refreshed; review and retry.')
            await refreshTree()
          } else {
            notify(describeError(e))
          }
          return undefined
        }
      },
    }),
    [index, visible, collapsed, actor.data, draft, refreshTree, notify],
  )

  if (tree.isPending || schema.isPending) return <p>Loading…</p>
  if (tree.isError) return <p role="alert">Could not load the outline: {tree.error.message}</p>

  return (
    <OutlineContext.Provider value={api}>
      {roots.length === 0 && !draft && <p className="muted">No nodes yet.</p>}
      <ul className="outline">
        <NodeList nodes={roots} parentId={null} draft={draft} />
      </ul>
      <button className="add-top" onClick={() => setDraft({ parentId: null, afterId: roots.at(-1)?.id ?? null })}>
        + New node
      </button>
      <p className="muted small keys">
        Enter: new sibling · Tab / Shift+Tab: indent / outdent · ↑ ↓: move between titles · Ctrl/⌘+↓: edit notes · Esc:
        stop editing
      </p>
    </OutlineContext.Provider>
  )
}
