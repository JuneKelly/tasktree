import { Fragment, useCallback, useEffect, useState } from 'react'
import Markdown from 'react-markdown'
import { Link } from 'react-router'
import { api } from '../api/client'
import type { TreeNode } from '../api/types'
import { BlockedIcon, ClaimIndicator, StateBadge } from '../components/Bits'
import { StateMenu } from '../components/StateMenu'
import { RawBodyEditor, RichBodyEditor } from '../editor/BodyEditors'
import { richEditable } from '../editor/markdown'
import { useOutline, type Draft } from './context'
import { DraftRow } from './DraftRow'
import { useAutosave } from './useAutosave'

/** Renders a sibling list, with the pending draft row in its place if it belongs here. */
export function NodeList({ nodes, parentId, draft }: { nodes: TreeNode[]; parentId: string | null; draft: Draft | null }) {
  const here = draft && draft.parentId === parentId ? draft : null
  return (
    <>
      {here && here.afterId === null && <DraftRow key="draft" draft={here} />}
      {nodes.map((n) => (
        <Fragment key={n.id}>
          <Row node={n} />
          {here && here.afterId === n.id && <DraftRow draft={here} />}
        </Fragment>
      ))}
    </>
  )
}

function Row({ node }: { node: TreeNode }) {
  const o = useOutline()
  const a = useAutosave(node)
  const [bodyMode, setBodyMode] = useState<'rich' | 'raw' | null>(null)
  const readOnly = node.claimed_by !== null && node.claimed_by !== o.actor
  const collapsed = o.collapsed.has(node.id)
  const draftChild = o.draft?.parentId === node.id
  const hasKids = node.children.length > 0

  const openBody = useCallback(() => {
    if (!readOnly) setBodyMode(richEditable(a.body) ? 'rich' : 'raw')
  }, [readOnly, a.body])

  useEffect(() => {
    o.registerBody(node.id, openBody)
    return () => o.registerBody(node.id, null)
  }, [o, node.id, openBody])

  const move = async (parentId: string | null, anchor: { after_id?: string } = {}) => {
    await a.flush()
    const moved = await o.run(() => api.move(node.id, a.versionNow(), parentId, anchor))
    if (!moved) return
    a.acknowledge(moved)
    if (parentId) o.expand(parentId)
    o.requestFocus(node.id)
    await o.refreshTree()
  }

  const onTitleKey = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.nativeEvent.isComposing) return
    const entry = o.index.get(node.id)
    const pos = o.visible.indexOf(node.id)
    const mod = e.metaKey || e.ctrlKey

    if (e.key === 'Enter') {
      e.preventDefault()
      void a.flush()
      o.openDraft({ parentId: node.parent_id, afterId: node.id })
    } else if (e.key === 'Tab') {
      e.preventDefault()
      if (readOnly || !entry) return
      if (e.shiftKey) {
        if (entry.parentId === null) return
        const parent = o.index.get(entry.parentId)
        if (!parent) return
        void move(parent.parentId, { after_id: entry.parentId })
      } else if (entry.i > 0) {
        void move(entry.siblings[entry.i - 1].id)
      }
    } else if (e.key === 'ArrowDown' && mod) {
      e.preventDefault()
      openBody()
    } else if (e.key === 'ArrowUp' && !mod && pos > 0) {
      e.preventDefault()
      o.focusTitle(o.visible[pos - 1])
    } else if (e.key === 'ArrowDown' && !mod && pos < o.visible.length - 1) {
      e.preventDefault()
      o.focusTitle(o.visible[pos + 1])
    } else if (e.key === 'Escape') {
      e.currentTarget.blur()
    }
  }

  const closeBody = () => {
    a.blur('body')
    setBodyMode(null)
  }

  const bodyProps = {
    label: `Notes for ${node.title}`,
    initial: a.body,
    onChange: (md: string) => a.setField('body', md),
    onFocus: () => a.focus('body'),
    onBlur: closeBody,
  }

  return (
    <li>
      <div className={`row${readOnly ? ' read-only' : ''}`}>
        {hasKids ? (
          <button className="twisty" aria-label={`${collapsed ? 'Expand' : 'Collapse'} ${node.title}`} onClick={() => o.toggle(node.id)}>
            {collapsed ? '▸' : '▾'}
          </button>
        ) : (
          <span className="spacer" />
        )}
        <StateBadge state={node.state} />
        <input
          ref={(el) => o.registerTitle(node.id, el)}
          className="title-input"
          aria-label={`Title of ${node.title}`}
          value={a.title}
          readOnly={readOnly}
          size={Math.max(8, a.title.length + 1)}
          onChange={(e) => a.setField('title', e.target.value)}
          onFocus={() => a.focus('title')}
          onBlur={() => a.blur('title')}
          onKeyDown={onTitleKey}
        />
        {node.tags.map((t) => (
          <span key={t} className="tag">
            #{t}
          </span>
        ))}
        <ClaimIndicator node={node} /> <BlockedIcon node={node} />
        {a.saving && <span className="muted small">Saving…</span>}
        <span className="row-actions">
          <StateMenu node={{ ...node, version: a.version }} onChanged={a.acknowledge} />
          <button
            onClick={() => {
              o.expand(node.id)
              o.openDraft({ parentId: node.id, afterId: node.children.at(-1)?.id ?? null })
            }}
          >
            + child
          </button>
          <Link className="open" to={`/n/${node.id}`} aria-label={`Open ${node.title}`} title="Open node page">
            ↗
          </Link>
        </span>
      </div>

      {a.conflict && (
        <div className="conflict" role="group" aria-label={`Conflict on ${node.title}`}>
          Changed elsewhere (now “{a.conflict.title}”). Your edits are kept.
          <button onClick={a.keepMine}>Keep mine</button>
          <button onClick={a.takeTheirs}>Take theirs</button>
        </div>
      )}

      <div className="body">
        {bodyMode === 'rich' ? (
          <RichBodyEditor {...bodyProps} />
        ) : bodyMode === 'raw' ? (
          <RawBodyEditor {...bodyProps} />
        ) : a.body.trim() ? (
          <div
            className="body-view"
            aria-label={`Notes for ${node.title}`}
            onClick={(e) => {
              if (!(e.target as HTMLElement).closest('a')) openBody()
            }}
          >
            <Markdown>{a.body}</Markdown>
          </div>
        ) : (
          !readOnly && (
            <button className="add-notes" onClick={openBody}>
              Add notes…
            </button>
          )
        )}
      </div>

      {(hasKids || draftChild) && !collapsed && (
        <ul>
          <NodeList nodes={node.children} parentId={node.id} draft={o.draft} />
        </ul>
      )}
    </li>
  )
}
