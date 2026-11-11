import { useState } from 'react'
import { api } from '../api/client'
import { useOutline, type Draft } from './context'

/** Title input for a node that doesn't exist yet. Created on Enter or blur if non-empty. */
export function DraftRow({ draft }: { draft: Draft }) {
  const o = useOutline()
  const [title, setTitle] = useState('')
  const [busy, setBusy] = useState(false)

  const create = async (andContinue: boolean) => {
    const t = title.trim()
    if (!t || busy) {
      if (!t) o.openDraft(null)
      return
    }
    setBusy(true)
    const created = await o.run(() =>
      api.createNode({ title: t, parent_id: draft.parentId, ...(draft.afterId ? { after_id: draft.afterId } : {}) }),
    )
    setBusy(false)
    if (!created) return
    await o.refreshTree()
    if (andContinue) {
      setTitle('')
      o.openDraft({ parentId: draft.parentId, afterId: created.id })
    } else {
      o.openDraft(null)
    }
  }

  return (
    <li className="draft">
      <div className="row">
        <span className="spacer" />
        <input
          className="title-input"
          aria-label="New node title"
          placeholder="New node…"
          autoFocus
          value={title}
          disabled={busy}
          onChange={(e) => setTitle(e.target.value)}
          onKeyDown={(e) => {
            if (e.nativeEvent.isComposing) return
            if (e.key === 'Enter') {
              e.preventDefault()
              void create(true)
            } else if (e.key === 'Escape') {
              o.openDraft(null)
            }
          }}
          onBlur={() => void create(false)}
        />
      </div>
    </li>
  )
}
