import { screen } from '@testing-library/react'
import { expect, test } from 'vitest'
import { mockApi } from './test/mockApi'
import { renderApp } from './test/render'

test('without a token, any page redirects to the login screen', async () => {
  mockApi({})
  renderApp('/agenda', { token: null })
  expect(await screen.findByRole('form', { name: 'Log in' })).toBeInTheDocument()
  expect(screen.getByRole('heading', { name: 'Tasktree' })).toBeInTheDocument()
})
