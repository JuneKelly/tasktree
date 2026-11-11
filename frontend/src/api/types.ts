export type FieldType = 'string' | 'date' | 'int' | 'enum'
export interface FieldDef {
  type: FieldType
  values?: string[]
}
export type FieldValue = string | number

export interface Schema {
  initial: string
  states: { name: string; terminal: boolean; require_fields: string[] }[]
  transitions: Record<string, string[]>
  fields: Record<string, FieldDef>
  actionable: string[]
}

export interface Node {
  id: string
  parent_id: string | null
  position: string
  title: string
  body: string
  state: string
  fields: Record<string, FieldValue>
  tags: string[]
  claimed_by: string | null
  claim_expires_at: string | null
  version: number
  inserted_at: string
  updated_at: string
  allowed_transitions: string[]
  blocked?: boolean
  claimable?: boolean
}

export interface TreeNode extends Node {
  children: TreeNode[]
}

export interface Edge {
  id: string
  from_id: string
  to_id: string
  kind: 'blocks' | 'relates'
  inserted_at: string
}

export interface NodeDetail extends Node {
  children: string[]
  edges: { out: Edge[]; in: Edge[] }
}

export interface NodeEvent {
  seq: number
  node_id: string
  actor: string
  op: string
  payload: {
    before?: Record<string, unknown>
    after?: Record<string, unknown>
    edge?: { id: string; from_id: string; to_id: string; kind: string }
  }
  at: string
}
