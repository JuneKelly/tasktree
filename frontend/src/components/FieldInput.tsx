import type { FieldDef, FieldValue } from '../api/types'

interface Props {
  name: string
  def: FieldDef
  value: FieldValue | undefined
  onChange: (v: FieldValue | undefined) => void
}

// Renders an input for a schema-declared field type; empty input means "unset".
export function FieldInput({ name, def, value, onChange }: Props) {
  const id = `field-${name}`
  const shown = value === undefined ? '' : String(value)

  let input
  if (def.type === 'enum') {
    input = (
      <select id={id} value={shown} onChange={(e) => onChange(e.target.value === '' ? undefined : e.target.value)}>
        <option value="">(none)</option>
        {def.values?.map((v) => (
          <option key={v} value={v}>
            {v}
          </option>
        ))}
      </select>
    )
  } else if (def.type === 'int') {
    input = (
      <input
        id={id}
        type="number"
        step={1}
        value={shown}
        onChange={(e) => onChange(e.target.value === '' ? undefined : Number(e.target.value))}
      />
    )
  } else {
    input = (
      <input
        id={id}
        type={def.type === 'date' ? 'date' : 'text'}
        value={shown}
        onChange={(e) => onChange(e.target.value === '' ? undefined : e.target.value)}
      />
    )
  }

  return (
    <div className="field">
      <label htmlFor={id}>{name}</label> {input}
    </div>
  )
}
