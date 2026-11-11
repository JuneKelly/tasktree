import { useSyncExternalStore } from 'react'

const KEY = 'tasktree.token'
const listeners = new Set<() => void>()

export const getToken = (): string | null => localStorage.getItem(KEY)

export function setToken(token: string) {
  localStorage.setItem(KEY, token)
  listeners.forEach((l) => l())
}

export function clearToken() {
  localStorage.removeItem(KEY)
  listeners.forEach((l) => l())
}

function subscribe(listener: () => void) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export const useToken = () => useSyncExternalStore(subscribe, getToken)
