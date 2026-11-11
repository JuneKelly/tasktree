import { screen, waitFor, within } from '@testing-library/react'
import { expect, test } from 'vitest'
import { mockApi } from '../test/mockApi'
import { node, schema } from '../test/fixtures'
import { renderApp } from '../test/render'

test('three sections, queried from the schema rather than hardcoded states', async () => {
  const m = mockApi({
    'GET /api/me': { body: { actor: 'human:june' } },
    'GET /api/schema': { body: schema },
    'GET /api/nodes': (req) => {
      if (req.query.get('claimable')) return { body: { data: [node({ id: 'a', title: 'Free task' })], next_cursor: null } }
      if (req.query.get('state')) return { body: { data: [node({ id: 'b', title: 'Active task', state: 'DOING' })], next_cursor: null } }
      return { body: { data: [node({ id: 'c', title: 'Stuck task', blocked: true })], next_cursor: null } }
    },
  })
  renderApp('/agenda')
  expect(await within(await screen.findByRole('region', { name: 'Claimable' })).findByText('Free task')).toBeInTheDocument()
  expect(await within(screen.getByRole('region', { name: 'In progress' })).findByText('Active task')).toBeInTheDocument()
  expect(await within(screen.getByRole('region', { name: 'Blocked' })).findByText('Stuck task')).toBeInTheDocument()

  const queries = m.of('GET', '/api/nodes').map((r) => r.query.toString())
  expect(queries).toContain('claimable=true')
  expect(queries).toContain('state=DOING') // non-terminal and not actionable, derived from the schema
  expect(queries).toContain('blocked=true')
  await waitFor(() => expect(m.of('GET', '/api/nodes')).toHaveLength(3))
})
