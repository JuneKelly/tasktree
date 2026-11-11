import { clearToken, getToken } from '../auth'
import type { Edge, FieldValue, Node, NodeDetail, NodeEvent, Schema, TreeNode } from './types'

export class ApiError extends Error {
  status: number
  code: string
  details: Record<string, unknown>

  constructor(status: number, code: string, message: string, details: Record<string, unknown>) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.code = code
    this.details = details
  }
}

type Query = Record<string, string | string[] | undefined>

function qs(query?: Query): string {
  const params = new URLSearchParams()
  for (const [k, v] of Object.entries(query ?? {})) {
    if (v === undefined) continue
    for (const item of Array.isArray(v) ? v : [v]) params.append(k, item)
  }
  const s = params.toString()
  return s ? `?${s}` : ''
}

interface Opts {
  body?: unknown
  version?: number
  query?: Query
  token?: string
}

async function request<T>(method: string, path: string, opts: Opts = {}): Promise<T> {
  const token = opts.token ?? getToken()
  if (!token) throw new ApiError(401, 'unauthorized', 'Not logged in', {})

  const headers: Record<string, string> = { Authorization: `Bearer ${token}` }
  if (opts.version !== undefined) headers['If-Match'] = String(opts.version)
  if (opts.body !== undefined) headers['Content-Type'] = 'application/json'

  const res = await fetch(`/api${path}${qs(opts.query)}`, {
    method,
    headers,
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  })
  if (res.status === 204) return undefined as T

  const text = await res.text()
  let parsed: unknown
  try {
    parsed = JSON.parse(text)
  } catch {
    throw new ApiError(res.status, 'bad_response', `Unparseable response (HTTP ${res.status})`, {})
  }

  if (!res.ok) {
    const err = (parsed as { error?: { code: string; message: string; details: Record<string, unknown> } }).error
    if (!err) throw new ApiError(res.status, 'bad_response', `Unexpected error body (HTTP ${res.status})`, {})
    if (res.status === 401 && opts.token === undefined) clearToken()
    throw new ApiError(res.status, err.code, err.message, err.details)
  }
  return parsed as T
}

export interface ListResult {
  data: Node[]
  next_cursor: string | null
}

export const api = {
  me: (token?: string) => request<{ actor: string }>('GET', '/me', { token }),
  schema: () => request<Schema>('GET', '/schema'),
  tree: (query?: Query) => request<{ data: TreeNode[] }>('GET', '/tree', { query }),
  listNodes: (query?: Query) => request<ListResult>('GET', '/nodes', { query }),
  getNode: (id: string) => request<NodeDetail>('GET', `/nodes/${id}`),
  nodeEvents: (id: string) => request<{ data: NodeEvent[] }>('GET', `/nodes/${id}/events`),
  createNode: (body: { title: string; parent_id?: string | null; after_id?: string }) =>
    request<Node>('POST', '/nodes', { body }),
  updateNode: (
    id: string,
    version: number,
    patch: { title?: string; body?: string; tags?: string[]; fields?: Record<string, FieldValue | null> },
  ) => request<Node>('PATCH', `/nodes/${id}`, { body: patch, version }),
  transition: (id: string, version: number, to: string, fields?: Record<string, FieldValue>) =>
    request<Node>('POST', `/nodes/${id}/transition`, { body: { to, ...(fields ? { fields } : {}) }, version }),
  move: (id: string, version: number, parentId: string | null) =>
    request<Node>('POST', `/nodes/${id}/move`, { body: { parent_id: parentId }, version }),
  claim: (id: string) => request<Node>('POST', `/nodes/${id}/claim`, { body: {} }),
  release: (id: string, force: boolean) => request<Node>('POST', `/nodes/${id}/release`, { body: { force } }),
  addEdge: (body: { from_id: string; to_id: string; kind: 'blocks' | 'relates' }) =>
    request<Edge>('POST', '/edges', { body }),
  removeEdge: (id: string) => request<void>('DELETE', `/edges/${id}`),
}
