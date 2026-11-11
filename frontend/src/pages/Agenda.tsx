import { useNodes, useSchema } from '../api/hooks'
import { BlockedIcon, ClaimIndicator, NodeLink, StateBadge } from '../components/Bits'

function Section({ title, queryKey, params, enabled = true }: {
  title: string
  queryKey: string
  params: Record<string, string | string[]>
  enabled?: boolean
}) {
  const q = useNodes(queryKey, params, enabled)
  return (
    <section aria-label={title}>
      <h2>{title}</h2>
      {!enabled ? (
        <p>None.</p>
      ) : q.isPending ? (
        <p>Loading…</p>
      ) : q.isError ? (
        <p role="alert">Could not load: {q.error.message}</p>
      ) : q.data.data.length === 0 ? (
        <p>Nothing here.</p>
      ) : (
        <ul>
          {q.data.data.map((n) => (
            <li key={n.id}>
              <StateBadge state={n.state} /> <NodeLink node={n} /> <ClaimIndicator node={n} /> <BlockedIcon node={n} />
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}

export default function Agenda() {
  const schema = useSchema()
  if (schema.isPending) return <p>Loading…</p>
  if (schema.isError) return <p role="alert">Could not load the schema: {schema.error.message}</p>

  // "In progress" = live states that are neither terminal nor merely available to start.
  const sch = schema.data
  const inProgress = sch.states.filter((s) => !s.terminal && !sch.actionable.includes(s.name)).map((s) => s.name)

  return (
    <div className="agenda">
      <Section title="Claimable" queryKey="claimable" params={{ claimable: 'true' }} />
      <Section title="In progress" queryKey="in-progress" params={{ state: inProgress }} enabled={inProgress.length > 0} />
      <Section title="Blocked" queryKey="blocked" params={{ blocked: 'true' }} />
    </div>
  )
}
