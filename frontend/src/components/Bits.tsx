import { Link } from 'react-router'
import type { Node } from '../api/types'
import type { FlatNode } from '../treeUtils'

export const StateBadge = ({ state }: { state: string }) => (
  <span className="badge" data-state={state}>
    {state}
  </span>
)

export function ClaimIndicator({ node }: { node: Node }) {
  if (!node.claimed_by) return null
  const until = node.claim_expires_at ? new Date(node.claim_expires_at).toLocaleTimeString() : '?'
  return (
    <span className="claim" title={`until ${until}`}>
      🔒 {node.claimed_by}
    </span>
  )
}

export const BlockedIcon = ({ node }: { node: Node }) =>
  node.blocked ? (
    <span role="img" aria-label="blocked" title="blocked">
      ⛔
    </span>
  ) : null

export const NodeLink = ({ node }: { node: Pick<Node, 'id' | 'title'> }) => (
  <Link to={`/n/${node.id}`}>{node.title}</Link>
)

interface PickerProps {
  label: string
  options: FlatNode[]
  value: string
  onChange: (id: string) => void
  allowRoot?: boolean
}

export function NodePicker({ label, options, value, onChange, allowRoot }: PickerProps) {
  return (
    <select aria-label={label} value={value} onChange={(e) => onChange(e.target.value)}>
      <option value="">{allowRoot ? '(root)' : 'choose a node…'}</option>
      {options.map((o) => (
        <option key={o.id} value={o.id}>
          {'— '.repeat(o.depth)}
          {o.title}
        </option>
      ))}
    </select>
  )
}
