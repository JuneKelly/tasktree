import { useState } from 'react'
import { api } from '../api/client'
import { useApiMutation, useSchema } from '../api/hooks'
import type { FieldValue, Node } from '../api/types'
import { FieldInput } from './FieldInput'

// State picker limited to the node's allowed transitions (from the API). If the target
// state requires fields the node lacks, asks for them first; the form comes from the schema.
export function StateMenu({ node, onChanged }: { node: Node; onChanged?: (n: Node) => void }) {
  const schema = useSchema()
  const [target, setTarget] = useState<string | null>(null)
  const [values, setValues] = useState<Record<string, FieldValue | undefined>>({})
  const m = useApiMutation(
    (v: { to: string; fields?: Record<string, FieldValue> }) => api.transition(node.id, node.version, v.to, v.fields),
    onChanged,
  )

  if (!schema.data || node.allowed_transitions.length === 0) return null
  const sch = schema.data

  const choose = (to: string) => {
    if (!to) return
    const required = sch.states.find((s) => s.name === to)?.require_fields ?? []
    if (required.every((f) => f in node.fields)) {
      m.mutate({ to })
    } else {
      setValues({})
      setTarget(to)
    }
  }

  const required = target ? (sch.states.find((s) => s.name === target)?.require_fields ?? []) : []
  const missing = required.filter((f) => !(f in node.fields))

  const submit = (e: React.SubmitEvent) => {
    e.preventDefault()
    const fields: Record<string, FieldValue> = {}
    for (const f of missing) {
      const v = values[f]
      if (v === undefined) return
      fields[f] = v
    }
    m.mutate({ to: target!, fields })
    setTarget(null)
  }

  return (
    <>
      <select
        aria-label={`Change state of ${node.title}`}
        value=""
        disabled={m.isPending}
        onChange={(e) => choose(e.target.value)}
      >
        <option value="">→ state…</option>
        {node.allowed_transitions.map((s) => (
          <option key={s} value={s}>
            {s}
          </option>
        ))}
      </select>
      {target && (
        <form className="inline-dialog" aria-label={`Move to ${target}`} onSubmit={submit}>
          <strong>{target} requires:</strong>
          {missing.map((f) => (
            <FieldInput
              key={f}
              name={f}
              def={sch.fields[f]}
              value={values[f]}
              onChange={(v) => setValues({ ...values, [f]: v })}
            />
          ))}
          <button type="submit">Confirm</button>
          <button type="button" onClick={() => setTarget(null)}>
            Cancel
          </button>
        </form>
      )}
    </>
  )
}
