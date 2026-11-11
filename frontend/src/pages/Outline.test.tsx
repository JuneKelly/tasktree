import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test } from 'vitest'
import { apiError, mockApi } from '../test/mockApi'
import { node, schema, treeNode } from '../test/fixtures'
import { renderApp } from '../test/render'

const base = {
  'GET /api/me': { body: { actor: 'human:june' } },
  'GET /api/schema': { body: schema },
}

const tree = [
  treeNode({ id: 'p', title: 'Parent', tags: ['home'], claimed_by: 'agent:x', claim_expires_at: '2026-01-01T12:00:00Z' }, [
    treeNode({ id: 'c', parent_id: 'p', title: 'Child', blocked: true }),
  ]),
]

test('renders badge, tags, claim, blocked icon; collapses children', async () => {
  mockApi({ ...base, 'GET /api/tree': { body: { data: tree } } })
  renderApp('/')
  expect(await screen.findByText('Parent')).toBeInTheDocument()
  expect(screen.getByText('#home')).toBeInTheDocument()
  expect(screen.getByText(/agent:x/)).toBeInTheDocument()
  expect(screen.getByRole('img', { name: 'blocked' })).toBeInTheDocument()

  await userEvent.click(screen.getByRole('button', { name: 'Collapse Parent' }))
  expect(screen.queryByText('Child')).not.toBeInTheDocument()
  await userEvent.click(screen.getByRole('button', { name: 'Expand Parent' }))
  expect(screen.getByText('Child')).toBeInTheDocument()
})

test('the state menu offers exactly the API-provided allowed transitions', async () => {
  mockApi({ ...base, 'GET /api/tree': { body: { data: [treeNode({ allowed_transitions: ['DOING', 'NEXT'] })] } } })
  renderApp('/')
  const menu = await screen.findByRole('combobox', { name: 'Change state of Write docs' })
  expect(within(menu).getAllByRole('option').map((o) => o.textContent)).toEqual(['→ state…', 'DOING', 'NEXT'])
})

test('transition posts the node version in If-Match and refetches', async () => {
  const m = mockApi({
    ...base,
    'GET /api/tree': { body: { data: [treeNode({ version: 4 })] } },
    'POST /api/nodes/n1/transition': { body: node({ state: 'DOING', version: 5 }) },
    'GET /api/nodes/n1': { body: {} },
  })
  renderApp('/')
  await userEvent.selectOptions(await screen.findByRole('combobox', { name: /Change state/ }), 'DOING')
  const [req] = await until(() => m.of('POST', '/api/nodes/n1/transition'))
  expect(req.headers.get('if-match')).toBe('4')
  expect(req.body).toEqual({ to: 'DOING' })
  await until(() => (m.of('GET', '/api/tree').length > 1 ? true : undefined))
})

test('a state that requires fields asks for them, from the schema', async () => {
  const m = mockApi({
    ...base,
    'GET /api/tree': { body: { data: [treeNode({ state: 'DOING', allowed_transitions: ['DONE'] })] } },
    'POST /api/nodes/n1/transition': { body: node({ state: 'DONE' }) },
  })
  renderApp('/')
  await userEvent.selectOptions(await screen.findByRole('combobox', { name: /Change state/ }), 'DONE')
  expect(m.of('POST', '/api/nodes/n1/transition')).toHaveLength(0)
  await userEvent.type(await screen.findByLabelText('outcome'), 'shipped')
  await userEvent.click(screen.getByRole('button', { name: 'Confirm' }))
  const [req] = await until(() => m.of('POST', '/api/nodes/n1/transition'))
  expect(req.body).toEqual({ to: 'DONE', fields: { outcome: 'shipped' } })
})

test('a version conflict refetches and tells the user; nothing is retried', async () => {
  const m = mockApi({
    ...base,
    'GET /api/tree': { body: { data: [treeNode()] } },
    'POST /api/nodes/n1/transition': apiError(409, 'version_conflict', { current: node({ version: 2 }) }),
  })
  renderApp('/')
  await userEvent.selectOptions(await screen.findByRole('combobox', { name: /Change state/ }), 'NEXT')
  expect(await screen.findByRole('alert')).toHaveTextContent(/changed.*review and retry/i)
  await until(() => (m.of('GET', '/api/tree').length > 1 ? true : undefined))
  expect(m.of('POST', '/api/nodes/n1/transition')).toHaveLength(1)
})

test('add child and add sibling send the right parent and anchor', async () => {
  const m = mockApi({
    ...base,
    'GET /api/tree': { body: { data: [treeNode({ id: 'c', parent_id: 'p', title: 'Kid' })] } },
    'POST /api/nodes': { status: 201, body: node() },
  })
  renderApp('/')
  await userEvent.click(await screen.findByRole('button', { name: '+ child' }))
  await userEvent.type(screen.getByLabelText('New child of Kid'), 'grandkid{enter}')
  await userEvent.click(screen.getByRole('button', { name: '+ sibling' }))
  await userEvent.type(screen.getByLabelText('New sibling of Kid'), 'twin{enter}')
  const bodies = (await until(() => (m.of('POST', '/api/nodes').length === 2 ? m.of('POST', '/api/nodes') : undefined))).map((r) => r.body)
  expect(bodies).toEqual([
    { title: 'grandkid', parent_id: 'c' },
    { title: 'twin', parent_id: 'p', after_id: 'c' },
  ])
})

function until<T>(fn: () => T | undefined): Promise<T> {
  return waitFor(() => {
    const v = fn()
    if (v === undefined) throw new Error('not yet')
    return v
  })
}
