import { Link } from 'react-router'
import { useSchema } from '../api/hooks'
import type { Node, Schema } from '../api/types'
import type { FlatNode } from '../treeUtils'

// Colour comes from the state's kind in the schema, never from its name.
function stateKind(schema: Schema | undefined, state: string): string | undefined {
  if (!schema) return undefined
  const s = schema.states.find((x) => x.name === state)
  if (!s) return 'unknown'
  if (s.terminal) return 'terminal'
  return schema.actionable.includes(state) ? 'actionable' : 'active'
}

export function StateBadge({ state }: { state: string }) {
  const schema = useSchema()
  return (
    <span className="badge" data-state={state} data-kind={stateKind(schema.data, state)}>
      {state}
    </span>
  )
}

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
