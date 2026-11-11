import { beforeEach, describe, expect, test } from 'vitest'
import { getToken, setToken } from '../auth'
import { apiError, mockApi } from '../test/mockApi'
import { api, ApiError } from './client'

beforeEach(() => setToken('tok'))

describe('api client', () => {
  test('sends the bearer token, repeated query keys, and If-Match', async () => {
    const m = mockApi({
      'GET /api/nodes': { body: { data: [], next_cursor: null } },
      'PATCH /api/nodes/x': { body: {} },
    })
    await api.listNodes({ state: ['A', 'B'], claimable: 'true', skipped: undefined })
    await api.updateNode('x', 7, { title: 't' })

    const [list, patch] = m.calls
    expect(list.headers.get('authorization')).toBe('Bearer tok')
    expect(list.query.getAll('state')).toEqual(['A', 'B'])
    expect(list.query.has('skipped')).toBe(false)
    expect(patch.headers.get('if-match')).toBe('7')
    expect(patch.body).toEqual({ title: 't' })
  })

  test('maps the error contract to ApiError, keeping code and details', async () => {
    mockApi({ 'POST /api/nodes/x/claim': apiError(409, 'claimed', { claimed_by: 'agent:a' }) })
    const err = await api.claim('x').catch((e) => e)
    expect(err).toBeInstanceOf(ApiError)
    expect(err).toMatchObject({ status: 409, code: 'claimed', details: { claimed_by: 'agent:a' } })
  })

  test('401 clears the stored token', async () => {
    mockApi({ 'GET /api/schema': apiError(401, 'unauthorized') })
    await expect(api.schema()).rejects.toMatchObject({ code: 'unauthorized' })
    expect(getToken()).toBeNull()
  })

  test('a 401 while validating a candidate token does not clear the stored one', async () => {
    mockApi({ 'GET /api/me': apiError(401, 'unauthorized') })
    await expect(api.me('other')).rejects.toBeInstanceOf(ApiError)
    expect(getToken()).toBe('tok')
  })

  test('204 resolves with no body', async () => {
    mockApi({ 'DELETE /api/edges/e': { status: 204 } })
    await expect(api.removeEdge('e')).resolves.toBeUndefined()
  })

  test('a non-contract error body is surfaced, not defaulted', async () => {
    mockApi({ 'GET /api/schema': { status: 500, body: { oops: true } } })
    await expect(api.schema()).rejects.toMatchObject({ code: 'bad_response', status: 500 })
  })

  test('no token means no request', async () => {
    localStorage.clear()
    const m = mockApi({})
    await expect(api.schema()).rejects.toMatchObject({ code: 'unauthorized' })
    expect(m.calls).toHaveLength(0)
  })
})
