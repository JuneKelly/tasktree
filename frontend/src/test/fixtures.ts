import type { Node, Schema, TreeNode } from '../api/types'

export const schema: Schema = {
  initial: 'TODO',
  states: [
    { name: 'CANCELLED', terminal: true, require_fields: [] },
    { name: 'DOING', terminal: false, require_fields: [] },
    { name: 'DONE', terminal: true, require_fields: ['outcome'] },
    { name: 'NEXT', terminal: false, require_fields: [] },
    { name: 'TODO', terminal: false, require_fields: [] },
  ],
  transitions: {},
  fields: {
    outcome: { type: 'string' },
    effort: { type: 'int' },
    priority: { type: 'enum', values: ['A', 'B', 'C'] },
  },
  actionable: ['NEXT', 'TODO'],
}

export const node = (over: Partial<Node> = {}): Node => ({
  id: 'n1',
  parent_id: null,
  position: 'V',
  title: 'Write docs',
  body: '',
  state: 'TODO',
  fields: {},
  tags: [],
  claimed_by: null,
  claim_expires_at: null,
  version: 1,
  inserted_at: '2026-01-01T00:00:00Z',
  updated_at: '2026-01-01T00:00:00Z',
  allowed_transitions: ['NEXT', 'DOING', 'CANCELLED'],
  blocked: false,
  claimable: true,
  ...over,
})

export const treeNode = (over: Partial<Node> = {}, children: TreeNode[] = []): TreeNode => ({
  ...node(over),
  children,
})
