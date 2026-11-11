import { useState } from 'react'
import Markdown from 'react-markdown'
import { useParams } from 'react-router'
import { api, ApiError } from '../api/client'
import { useActor, useApiMutation, useNode, useNodeEvents, useSchema, useTree } from '../api/hooks'
import type { Edge, FieldValue, NodeDetail, NodeEvent, Schema } from '../api/types'
import { ClaimIndicator, NodeLink, NodePicker, StateBadge } from '../components/Bits'
import { FieldInput } from '../components/FieldInput'
import { StateMenu } from '../components/StateMenu'
import { flattenTree, type FlatNode } from '../treeUtils'

const parseTags = (s: string) => s.split(',').map((t) => t.trim()).filter(Boolean)

function Editor({ node, schema }: { node: NodeDetail; schema: Schema }) {
  const [title, setTitle] = useState(node.title)
  const [body, setBody] = useState(node.body)
  const [tags, setTags] = useState(node.tags.join(', '))
  const [fields, setFields] = useState<Record<string, FieldValue | undefined>>({ ...node.fields })
  const m = useApiMutation((patch: Parameters<typeof api.updateNode>[2]) => api.updateNode(node.id, node.version, patch))

  const patch: Parameters<typeof api.updateNode>[2] = {}
  if (title !== node.title) patch.title = title
  if (body !== node.body) patch.body = body
  if (JSON.stringify(parseTags(tags)) !== JSON.stringify(node.tags)) patch.tags = parseTags(tags)
  const fieldPatch: Record<string, FieldValue | null> = {}
  for (const name of Object.keys(schema.fields)) {
    if (fields[name] !== node.fields[name]) fieldPatch[name] = fields[name] ?? null
  }
  if (Object.keys(fieldPatch).length > 0) patch.fields = fieldPatch
  const dirty = Object.keys(patch).length > 0

  return (
    <form
      aria-label="Edit node"
      onSubmit={(e) => {
        e.preventDefault()
        if (dirty) m.mutate(patch)
      }}
    >
      <p>
        <label htmlFor="title">Title</label> <input id="title" value={title} onChange={(e) => setTitle(e.target.value)} />
      </p>
      <div className="body-edit">
        <div>
          <label htmlFor="body">Body (markdown)</label>
          <textarea id="body" rows={8} value={body} onChange={(e) => setBody(e.target.value)} />
        </div>
        <div aria-label="Preview" className="preview md">
          <Markdown>{body}</Markdown>
        </div>
      </div>
      <p>
        <label htmlFor="tags">Tags (comma separated)</label> <input id="tags" value={tags} onChange={(e) => setTags(e.target.value)} />
      </p>
      <fieldset>
        <legend>Fields</legend>
        {Object.entries(schema.fields).map(([name, def]) => (
          <FieldInput key={name} name={name} def={def} value={fields[name]} onChange={(v) => setFields({ ...fields, [name]: v })} />
        ))}
      </fieldset>
      <button type="submit" disabled={!dirty || m.isPending}>
        Save
      </button>
    </form>
  )
}

function ClaimControls({ node }: { node: NodeDetail }) {
  const actor = useActor()
  const claim = useApiMutation(() => api.claim(node.id))
  const release = useApiMutation((force: boolean) => api.release(node.id, force))
  const mine = node.claimed_by !== null && node.claimed_by === actor.data?.actor
  const isHuman = actor.data?.actor.startsWith('human:') ?? false

  return (
    <p className="controls">
      {node.claimed_by ? <ClaimIndicator node={node} /> : <span className="muted">Unclaimed</span>}{' '}
      {!node.claimed_by || mine ? <button onClick={() => claim.mutate()}>{mine ? 'Renew claim' : 'Claim'}</button> : null}
      {mine && <button onClick={() => release.mutate(false)}>Release</button>}
      {node.claimed_by && !mine && isHuman && (
        <button className="danger" onClick={() => release.mutate(true)}>
          Steal claim
        </button>
      )}
    </p>
  )
}

function MoveControl({ node, flat }: { node: NodeDetail; flat: FlatNode[] }) {
  const [parent, setParent] = useState(node.parent_id ?? '')
  const m = useApiMutation(() => api.move(node.id, node.version, parent || null))
  return (
    <p className="controls">
      <NodePicker label="Move under" options={flat.filter((o) => o.id !== node.id)} value={parent} onChange={setParent} allowRoot />{' '}
      <button onClick={() => m.mutate()}>Move</button>
    </p>
  )
}

type Relation = 'blocks' | 'blocked_by' | 'relates'

function EdgesPanel({ node, flat }: { node: NodeDetail; flat: FlatNode[] }) {
  const [relation, setRelation] = useState<Relation>('blocks')
  const [other, setOther] = useState('')
  const titles = new Map(flat.map((f) => [f.id, f.title]))
  const add = useApiMutation(() => {
    const kind = relation === 'relates' ? 'relates' : 'blocks'
    return relation === 'blocked_by'
      ? api.addEdge({ from_id: other, to_id: node.id, kind })
      : api.addEdge({ from_id: node.id, to_id: other, kind })
  }, () => setOther(''))
  const remove = useApiMutation((id: string) => api.removeEdge(id))

  const item = (e: Edge, label: string, otherId: string) => (
    <li key={e.id}>
      {label} <NodeLink node={{ id: otherId, title: titles.get(otherId) ?? otherId }} />{' '}
      <button aria-label={`Remove ${label} ${titles.get(otherId) ?? otherId}`} onClick={() => remove.mutate(e.id)}>
        Remove
      </button>
    </li>
  )

  return (
    <section aria-label="Edges">
      <h2>Edges</h2>
      <ul>
        {node.edges.out.map((e) => item(e, e.kind === 'blocks' ? 'blocks' : 'relates to', e.to_id))}
        {node.edges.in.map((e) => item(e, e.kind === 'blocks' ? 'blocked by' : 'related from', e.from_id))}
      </ul>
      <select aria-label="Relation" value={relation} onChange={(e) => setRelation(e.target.value as Relation)}>
        <option value="blocks">this blocks</option>
        <option value="blocked_by">this is blocked by</option>
        <option value="relates">relates to</option>
      </select>{' '}
      <NodePicker label="Other node" options={flat.filter((o) => o.id !== node.id)} value={other} onChange={setOther} />{' '}
      <button disabled={!other} onClick={() => add.mutate()}>
        Add edge
      </button>
    </section>
  )
}

function summarize(e: NodeEvent): string {
  if (e.payload.edge) return `${e.payload.edge.kind} ${e.payload.edge.from_id} → ${e.payload.edge.to_id}`
  const keys = Object.keys(e.payload.after ?? {})
  return keys.length ? `changed ${keys.join(', ')}` : ''
}

function Timeline({ id }: { id: string }) {
  const events = useNodeEvents(id)
  return (
    <section aria-label="History">
      <h2>History</h2>
      {events.isPending ? (
        <p>Loading…</p>
      ) : events.isError ? (
        <p role="alert">Could not load history: {events.error.message}</p>
      ) : (
        <ol>
          {events.data.data.map((e) => (
            <li key={e.seq}>
              {new Date(e.at).toLocaleString()} · {e.actor} · {e.op} {summarize(e)}
            </li>
          ))}
        </ol>
      )}
    </section>
  )
}

export default function NodePage() {
  const { id } = useParams()
  if (!id) throw new Error('route /n/:id rendered without an id')
  return <NodeView id={id} />
}

function NodeView({ id }: { id: string }) {
  const node = useNode(id)
  const schema = useSchema()
  const tree = useTree()

  if (node.isError) {
    return node.error instanceof ApiError && node.error.status === 404 ? (
      <p>Node not found.</p>
    ) : (
      <p role="alert">Could not load node: {node.error.message}</p>
    )
  }
  if (schema.isError) return <p role="alert">Could not load the schema: {schema.error.message}</p>
  if (node.isPending || schema.isPending) return <p>Loading…</p>

  const flat = flattenTree(tree.data?.data ?? [])
  const n = node.data

  return (
    <div className="node-page">
      <header className="node-head">
        {n.parent_id && (
          <p className="crumb">
            ↑ <NodeLink node={{ id: n.parent_id, title: flat.find((f) => f.id === n.parent_id)?.title ?? 'parent' }} />
          </p>
        )}
        <h2>
          <StateBadge state={n.state} /> {n.title} <StateMenu node={n} />
          {n.blocked && <span className="pill blocked">blocked</span>}
        </h2>
      </header>
      <div className="node-main">
        {/* Remounting on version resets the form to server state after a save or a conflict refetch. */}
        <Editor key={n.version} node={n} schema={schema.data} />
      </div>
      <aside className="node-side">
        <section aria-label="Claim">
          <h2>Claim</h2>
          <ClaimControls node={n} />
        </section>
        <section aria-label="Move">
          <h2>Move</h2>
          <MoveControl key={`move-${n.version}`} node={n} flat={flat} />
        </section>
        <EdgesPanel node={n} flat={flat} />
      </aside>
      <div className="node-history">
        <Timeline id={n.id} />
      </div>
    </div>
  )
}
