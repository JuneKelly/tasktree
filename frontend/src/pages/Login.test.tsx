import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test } from 'vitest'
import { getToken } from '../auth'
import { apiError, mockApi } from '../test/mockApi'
import { schema, treeNode } from '../test/fixtures'
import { renderApp } from '../test/render'

test('a valid token is stored and leads to the outline', async () => {
  mockApi({
    'GET /api/me': { body: { actor: 'human:june' } },
    'GET /api/schema': { body: schema },
    'GET /api/tree': { body: { data: [] } },
  })
  renderApp('/login', { token: null })
  await userEvent.type(await screen.findByLabelText('API token'), 'good')
  await userEvent.click(screen.getByRole('button', { name: 'Log in' }))
  expect(await screen.findByText('No nodes yet.')).toBeInTheDocument()
  expect(getToken()).toBe('good')
  expect(await screen.findByText('human:june')).toBeInTheDocument()
})

test('an invalid token shows the error and is not stored', async () => {
  mockApi({ 'GET /api/me': apiError(401, 'unauthorized') })
  renderApp('/login', { token: null })
  await userEvent.type(await screen.findByLabelText('API token'), 'bad')
  await userEvent.click(screen.getByRole('button', { name: 'Log in' }))
  expect(await screen.findByRole('alert')).toHaveTextContent(/unauthorized/)
  expect(getToken()).toBeNull()
})

test('logging out returns to the login screen', async () => {
  mockApi({
    'GET /api/me': { body: { actor: 'human:june' } },
    'GET /api/schema': { body: schema },
    'GET /api/tree': { body: { data: [treeNode()] } },
  })
  renderApp('/')
  await userEvent.click(await screen.findByRole('button', { name: 'Log out' }))
  await waitFor(() => expect(screen.getByRole('form', { name: 'Log in' })).toBeInTheDocument())
  expect(getToken()).toBeNull()
})
