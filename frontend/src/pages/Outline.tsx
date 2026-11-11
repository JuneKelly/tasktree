import { useState } from 'react'
import { useSchema, useTree } from '../api/hooks'
import type { TreeNode } from '../api/types'
import { AddForm } from '../components/AddForm'
import { BlockedIcon, ClaimIndicator, NodeLink, StateBadge } from '../components/Bits'
import { StateMenu } from '../components/StateMenu'

function Row({ node }: { node: TreeNode }) {
  const [collapsed, setCollapsed] = useState(false)
  const [adding, setAdding] = useState<'child' | 'sibling' | null>(null)
  const hasKids = node.children.length > 0

  return (
    <li>
      <div className="row">
        {hasKids ? (
          <button aria-label={`${collapsed ? 'Expand' : 'Collapse'} ${node.title}`} onClick={() => setCollapsed(!collapsed)}>
            {collapsed ? '▸' : '▾'}
          </button>
        ) : (
          <span className="spacer" />
        )}
        <StateBadge state={node.state} /> <NodeLink node={node} />
        {node.tags.map((t) => (
          <span key={t} className="tag">
            #{t}
          </span>
        ))}
        <ClaimIndicator node={node} /> <BlockedIcon node={node} />
        <span className="row-actions">
          <StateMenu node={node} />
          <button onClick={() => setAdding('child')}>+ child</button>
          <button onClick={() => setAdding('sibling')}>+ sibling</button>
        </span>
      </div>
      {adding === 'child' && (
        <AddForm parentId={node.id} label={`New child of ${node.title}`} onDone={() => setAdding(null)} />
      )}
      {adding === 'sibling' && (
        <AddForm
          parentId={node.parent_id}
          afterId={node.id}
          label={`New sibling of ${node.title}`}
          onDone={() => setAdding(null)}
        />
      )}
      {hasKids && !collapsed && (
        <ul>
          {node.children.map((c) => (
            <Row key={c.id} node={c} />
          ))}
        </ul>
      )}
    </li>
  )
}

export default function Outline() {
  const tree = useTree()
  const schema = useSchema()

  if (tree.isPending || schema.isPending) return <p>Loading…</p>
  if (tree.isError) return <p role="alert">Could not load the outline: {tree.error.message}</p>

  return (
    <>
      <AddForm parentId={null} label="New top-level node" />
      {tree.data.data.length === 0 ? (
        <p>No nodes yet.</p>
      ) : (
        <ul className="outline">
          {tree.data.data.map((n) => (
            <Row key={n.id} node={n} />
          ))}
        </ul>
      )}
    </>
  )
}
