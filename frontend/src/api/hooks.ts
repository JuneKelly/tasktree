import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useNotice } from '../noticeContext'
import { api, ApiError } from './client'

export const POLL_MS = 5000

export const useActor = () => useQuery({ queryKey: ['me'], queryFn: () => api.me(), staleTime: Infinity })
export const useSchema = () => useQuery({ queryKey: ['schema'], queryFn: api.schema, staleTime: Infinity })

// Depth is generous: the outline is collapsible client-side, and the tree response
// carries no "has more children" marker at the cutoff.
export const useTree = () =>
  useQuery({ queryKey: ['tree'], queryFn: () => api.tree({ depth: '50' }), refetchInterval: POLL_MS })

export const useNodes = (key: string, params: Record<string, string | string[]>, enabled = true) =>
  useQuery({
    queryKey: ['nodes', key, params],
    queryFn: () => api.listNodes(params),
    refetchInterval: POLL_MS,
    enabled,
  })

export const useNode = (id: string) => useQuery({ queryKey: ['node', id], queryFn: () => api.getNode(id) })
export const useNodeEvents = (id: string) =>
  useQuery({ queryKey: ['events', id], queryFn: () => api.nodeEvents(id) })

export function describeError(e: unknown): string {
  if (e instanceof ApiError) {
    const details = Object.entries(e.details)
      .map(([k, v]) => `${k}: ${typeof v === 'string' ? v : JSON.stringify(v)}`)
      .join('; ')
    return details ? `${e.message} (${details})` : e.message
  }
  return e instanceof Error ? e.message : String(e)
}

/**
 * Mutation that refetches everything on success. On `version_conflict` it refetches and
 * tells the user to review and retry; it never retries or overwrites on its own.
 */
export function useApiMutation<V, R>(fn: (v: V) => Promise<R>, onDone?: (r: R) => void) {
  const qc = useQueryClient()
  const { notify } = useNotice()
  const refetch = () =>
    qc.invalidateQueries({ predicate: (q) => q.queryKey[0] !== 'schema' && q.queryKey[0] !== 'me' })

  return useMutation({
    mutationFn: fn,
    onSuccess: (r) => {
      void refetch()
      onDone?.(r)
    },
    onError: (e) => {
      if (e instanceof ApiError && e.code === 'version_conflict') {
        notify('This node changed since you loaded it. It has been refreshed; review and retry.')
        void refetch()
      } else {
        notify(describeError(e))
      }
    },
  })
}
