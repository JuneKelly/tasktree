import { vi } from 'vitest'

export interface Req {
  method: string
  path: string
  query: URLSearchParams
  body: unknown
  headers: Headers
}
export type Reply = { status?: number; body?: unknown }
export type Handler = Reply | ((req: Req) => Reply)

export interface Mock {
  calls: Req[]
  of: (method: string, path: string) => Req[]
}

/** Stubs fetch. Routes are keyed "METHOD /api/path". Unrouted requests fail the test loudly. */
export function mockApi(routes: Record<string, Handler>): Mock {
  const calls: Req[] = []
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init: RequestInit = {}) => {
      const u = new URL(url, 'http://localhost')
      const req: Req = {
        method: init.method ?? 'GET',
        path: u.pathname,
        query: u.searchParams,
        body: init.body ? JSON.parse(init.body as string) : undefined,
        headers: new Headers(init.headers),
      }
      calls.push(req)
      const h = routes[`${req.method} ${req.path}`]
      if (!h) throw new Error(`unmocked request: ${req.method} ${req.path}`)
      const reply = typeof h === 'function' ? h(req) : h
      const status = reply.status ?? 200
      return new Response(status === 204 ? null : JSON.stringify(reply.body), { status })
    }),
  )
  return { calls, of: (m, p) => calls.filter((c) => c.method === m && c.path === p) }
}

export const apiError = (status: number, code: string, details: Record<string, unknown> = {}): Reply => ({
  status,
  body: { error: { code, message: code.replace(/_/g, ' '), details } },
})
