import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test } from 'vitest'
import type { NodeDetail } from '../api/types'
import { apiError, mockApi } from '../test/mockApi'
import { node, schema, treeNode } from '../test/fixtures'
import { renderApp } from '../test/render'

const detail = (over: Partial<NodeDetail> = {}): NodeDetail => ({
  ...node({ body: 'Hello **world**' }),
  children: [],
  edges: { out: [], in: [] },
  ...over,
})

const base = (actor: string, d: NodeDetail = detail()) => ({
  'GET /api/me': { body: { actor } },
  'GET /api/schema': { body: schema },
  'GET /api/tree': { body: { data: [treeNode(), treeNode({ id: 'n2', title: 'Other' })] } },
  'GET /api/nodes/n1': { body: d },
  'GET /api/nodes/n1/events': {
    body: { data: [{ seq: 1, node_id: 'n1', actor: 'agent:a', op: 'update', payload: { before: {}, after: { title: 'x' } }, at: '2026-01-01T00:00:00Z' }] },
  },
})

test('shows markdown preview, schema-generated fields, and the event timeline', async () => {
  mockApi(base('human:june'))
  renderApp('/n/n1')
  expect(await screen.findByLabelText('Title')).toHaveValue('Write docs')
  expect(within(screen.getByLabelText('Preview')).getByText('world').tagName).toBe('STRONG')
  for (const f of ['outcome', 'effort', 'priority']) expect(screen.getByLabelText(f)).toBeInTheDocument()
  expect(await screen.findByText(/agent:a · update changed title/)).toBeInTheDocument()
})

test('the preview renders GFM tables', async () => {
  mockApi(base('human:june', detail({ body: '| h |\n|---|\n| v |' })))
  renderApp('/n/n1')
  expect(within(await screen.findByLabelText('Preview')).getByRole('cell', { name: 'v' })).toBeInTheDocument()
})

test('save sends only changed attributes with If-Match; clearing a field sends null', async () => {
  const m = mockApi({
    ...base('human:june', detail({ version: 3, fields: { effort: 5 } })),
    'PATCH /api/nodes/n1': { body: node({ version: 4 }) },
  })
  renderApp('/n/n1')
  const save = await screen.findByRole('button', { name: 'Save' })
  expect(save).toBeDisabled()
  await userEvent.type(screen.getByLabelText('Title'), '!')
  await userEvent.clear(screen.getByLabelText('effort'))
  await userEvent.click(save)
  const [req] = await waitFor(() => {
    const r = m.of('PATCH', '/api/nodes/n1')
    if (!r.length) throw new Error('not yet')
    return r
  })
  expect(req.headers.get('if-match')).toBe('3')
  expect(req.body).toEqual({ title: 'Write docs!', fields: { effort: null } })
})

test('"Steal claim" is offered to humans only, as a forced release', async () => {
  const claimed = detail({ claimed_by: 'agent:x', claim_expires_at: '2030-01-01T00:00:00Z' })
  const m = mockApi({ ...base('human:june', claimed), 'POST /api/nodes/n1/release': { body: node() } })
  renderApp('/n/n1')
  await userEvent.click(await screen.findByRole('button', { name: 'Steal claim' }))
  await waitFor(() => expect(m.of('POST', '/api/nodes/n1/release')[0]?.body).toEqual({ force: true }))
})

test('agents are not offered "Steal claim"', async () => {
  mockApi(base('agent:y', detail({ claimed_by: 'agent:x', claim_expires_at: '2030-01-01T00:00:00Z' })))
  renderApp('/n/n1')
  await screen.findByLabelText('Title')
  await screen.findByText('agent:y')
  expect(screen.queryByRole('button', { name: 'Steal claim' })).not.toBeInTheDocument()
  expect(screen.queryByRole('button', { name: 'Claim' })).not.toBeInTheDocument()
})

test('add and remove edges', async () => {
  const d = detail({ edges: { out: [{ id: 'e1', from_id: 'n1', to_id: 'n2', kind: 'blocks', inserted_at: '' }], in: [] } })
  const m = mockApi({
    ...base('human:june', d),
    'POST /api/edges': { status: 201, body: {} },
    'DELETE /api/edges/e1': { status: 204 },
  })
  renderApp('/n/n1')
  const edges = await screen.findByRole('region', { name: 'Edges' })
  expect(within(edges).getByRole('link', { name: 'Other' })).toBeInTheDocument()

  await userEvent.selectOptions(within(edges).getByLabelText('Relation'), 'blocked_by')
  await userEvent.selectOptions(within(edges).getByLabelText('Other node'), 'n2')
  await userEvent.click(within(edges).getByRole('button', { name: 'Add edge' }))
  await waitFor(() => expect(m.of('POST', '/api/edges')[0]?.body).toEqual({ from_id: 'n2', to_id: 'n1', kind: 'blocks' }))

  await userEvent.click(within(edges).getByRole('button', { name: 'Remove blocks Other' }))
  await waitFor(() => expect(m.of('DELETE', '/api/edges/e1')).toHaveLength(1))
})

test('move posts the chosen parent with If-Match', async () => {
  const m = mockApi({ ...base('human:june', detail({ version: 2 })), 'POST /api/nodes/n1/move': { body: node() } })
  renderApp('/n/n1')
  await userEvent.selectOptions(await screen.findByLabelText('Move under'), 'n2')
  await userEvent.click(screen.getByRole('button', { name: 'Move' }))
  await waitFor(() => {
    const [r] = m.of('POST', '/api/nodes/n1/move')
    expect(r.body).toEqual({ parent_id: 'n2' })
    expect(r.headers.get('if-match')).toBe('2')
  })
})

test('a conflict on save refreshes the form and notifies', async () => {
  let version = 1
  mockApi({
    ...base('human:june'),
    'GET /api/nodes/n1': () => ({ body: detail({ version, title: version === 1 ? 'Write docs' : 'Changed elsewhere' }) }),
    'PATCH /api/nodes/n1': () => {
      version = 2
      return apiError(409, 'version_conflict', { current: node({ version: 2 }) })
    },
  })
  renderApp('/n/n1')
  await userEvent.type(await screen.findByLabelText('Title'), '!')
  await userEvent.click(screen.getByRole('button', { name: 'Save' }))
  expect(await screen.findByRole('alert')).toHaveTextContent(/review and retry/i)
  await waitFor(() => expect(screen.getByLabelText('Title')).toHaveValue('Changed elsewhere'))
})

test('unknown node', async () => {
  mockApi({ ...base('human:june'), 'GET /api/nodes/nope': apiError(404, 'not_found') })
  renderApp('/n/nope')
  expect(await screen.findByText('Node not found.')).toBeInTheDocument()
})
