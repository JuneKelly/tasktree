import { useState } from 'react'
import { api } from '../api/client'
import { useApiMutation } from '../api/hooks'

interface Props {
  parentId: string | null
  afterId?: string
  label: string
  onDone?: () => void
}

export function AddForm({ parentId, afterId, label, onDone }: Props) {
  const [title, setTitle] = useState('')
  const m = useApiMutation(
    () => api.createNode({ title, parent_id: parentId, ...(afterId ? { after_id: afterId } : {}) }),
    () => {
      setTitle('')
      onDone?.()
    },
  )

  return (
    <form
      className="add-form"
      onSubmit={(e) => {
        e.preventDefault()
        if (title.trim()) m.mutate()
      }}
    >
      <input aria-label={label} placeholder={label} value={title} onChange={(e) => setTitle(e.target.value)} />
      <button type="submit" disabled={m.isPending}>
        Add
      </button>
      {onDone && (
        <button type="button" onClick={onDone}>
          Cancel
        </button>
      )}
    </form>
  )
}
