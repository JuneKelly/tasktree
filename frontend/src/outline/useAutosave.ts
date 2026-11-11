import { useQueryClient } from '@tanstack/react-query'
import { useCallback, useEffect, useRef, useState } from 'react'
import { api, ApiError } from '../api/client'
import { describeError } from '../api/hooks'
import type { Node } from '../api/types'
import { useNotice } from '../noticeContext'

export type Field = 'title' | 'body'
type Snapshot = { title: string; body: string; version: number }

export const AUTOSAVE_DEBOUNCE_MS = 1000

export interface Autosave {
  title: string
  body: string
  /** Latest version this client knows about (advances with its own saves). */
  version: number
  versionNow: () => number
  conflict: Node | null
  saving: boolean
  setField: (f: Field, value: string) => void
  focus: (f: Field) => void
  /** Leaving a field saves immediately. An emptied title reverts instead of saving. */
  blur: (f: Field) => void
  flush: () => Promise<void>
  /** Re-save the local edits on top of the version that won the conflict. */
  keepMine: () => void
  /** Drop local edits and adopt the version that won the conflict. */
  takeTheirs: () => void
  /** Record a newer node returned by another mutation this client made (move, transition). */
  acknowledge: (n: Node) => void
}

/**
 * Inline title/body editing with autosave. Every save sends If-Match with the latest known
 * version and chains on the response's version. Server state from polling is adopted only
 * while nothing is focused, dirty or in flight, so a field being edited is never replaced
 * and a stale draft can never silently overwrite someone else's change: the save gets a
 * version_conflict instead, and the user picks Keep mine or Take theirs.
 */
export function useAutosave(node: Node): Autosave {
  const qc = useQueryClient()
  const { notify } = useNotice()

  const [draft, setDraft] = useState({ title: node.title, body: node.body })
  const draftRef = useRef(draft)
  const base = useRef<Snapshot>({ title: node.title, body: node.body, version: node.version })
  const [version, setVersion] = useState(node.version)
  const dirty = useRef(new Set<Field>())
  const [focused, setFocused] = useState<ReadonlySet<Field>>(new Set())
  const [conflict, setConflict] = useState<Node | null>(null)
  const conflictRef = useRef<Node | null>(null)
  const [saving, setSaving] = useState(false)
  const inFlight = useRef(false)
  const again = useRef(false)
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined)

  const setDraftBoth = (d: { title: string; body: string }) => {
    draftRef.current = d
    setDraft(d)
  }
  const setBase = (s: Snapshot) => {
    base.current = { title: s.title, body: s.body, version: s.version }
    setVersion(s.version)
  }
  const setConflictBoth = (c: Node | null) => {
    conflictRef.current = c
    setConflict(c)
  }

  // Adopt newer server state from polling only when the user has nothing in progress.
  useEffect(() => {
    if (node.version <= base.current.version) return
    if (focused.size > 0 || dirty.current.size > 0 || inFlight.current || conflictRef.current) return
    setBase(node)
    setDraftBoth({ title: node.title, body: node.body })
  }, [node, focused, saving, conflict])

  const flush = async (): Promise<void> => {
    clearTimeout(timer.current)
    if (conflictRef.current) return
    if (inFlight.current) {
      again.current = true
      return
    }

    const patch: { title?: string; body?: string } = {}
    for (const f of [...dirty.current]) {
      const value = draftRef.current[f]
      if (value === base.current[f]) {
        dirty.current.delete(f)
      } else if (!(f === 'title' && value.trim() === '')) {
        patch[f] = value
        dirty.current.delete(f)
      }
    }
    if (Object.keys(patch).length === 0) return

    inFlight.current = true
    setSaving(true)
    try {
      const saved = await api.updateNode(node.id, base.current.version, patch)
      setBase(saved)
      void qc.invalidateQueries({ queryKey: ['node', node.id] })
      void qc.invalidateQueries({ queryKey: ['events', node.id] })
    } catch (e) {
      for (const f of Object.keys(patch) as Field[]) dirty.current.add(f)
      if (e instanceof ApiError && e.code === 'version_conflict') {
        setConflictBoth(e.details.current as Node)
        notify(`"${base.current.title}" was changed elsewhere. Your edits are kept: choose Keep mine or Take theirs.`)
      } else {
        notify(describeError(e))
      }
    } finally {
      inFlight.current = false
      setSaving(false)
      if (again.current) {
        again.current = false
        void flushRef.current()
      }
    }
  }
  const flushRef = useRef(flush)
  useEffect(() => {
    flushRef.current = flush
  })

  // Don't lose a pending edit if the row unmounts (e.g. its parent is collapsed).
  useEffect(() => () => void (dirty.current.size > 0 && flushRef.current()), [])

  const setField = useCallback((f: Field, value: string) => {
    setDraftBoth({ ...draftRef.current, [f]: value })
    dirty.current.add(f)
    clearTimeout(timer.current)
    timer.current = setTimeout(() => void flushRef.current(), AUTOSAVE_DEBOUNCE_MS)
  }, [])

  const focus = useCallback((f: Field) => setFocused((s) => new Set(s).add(f)), [])

  const blur = useCallback((f: Field) => {
    setFocused((s) => {
      const next = new Set(s)
      next.delete(f)
      return next
    })
    if (f === 'title' && draftRef.current.title.trim() === '') {
      setDraftBoth({ ...draftRef.current, title: base.current.title })
      dirty.current.delete('title')
    }
    void flushRef.current()
  }, [])

  const keepMine = () => {
    const theirs = conflictRef.current
    if (!theirs) return
    setBase(theirs)
    const d = draftRef.current
    setDraftBoth({
      title: dirty.current.has('title') ? d.title : theirs.title,
      body: dirty.current.has('body') ? d.body : theirs.body,
    })
    setConflictBoth(null)
    void flushRef.current()
  }

  const takeTheirs = () => {
    const theirs = conflictRef.current
    if (!theirs) return
    dirty.current.clear()
    setBase(theirs)
    setDraftBoth({ title: theirs.title, body: theirs.body })
    setConflictBoth(null)
  }

  const acknowledge = (n: Node) => {
    if (n.version <= base.current.version) return
    setBase(n)
    const d = draftRef.current
    setDraftBoth({
      title: dirty.current.has('title') ? d.title : n.title,
      body: dirty.current.has('body') ? d.body : n.body,
    })
  }

  return {
    title: draft.title,
    body: draft.body,
    version,
    versionNow: () => base.current.version,
    conflict,
    saving,
    setField,
    focus,
    blur,
    flush: () => flushRef.current(),
    keepMine,
    takeTheirs,
    acknowledge,
  }
}
