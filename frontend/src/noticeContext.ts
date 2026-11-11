import { createContext, useContext } from 'react'

export interface Notice {
  text: string
  kind: 'error' | 'info'
}

export interface NoticeApi {
  notice: Notice | null
  notify: (text: string, kind?: Notice['kind']) => void
  dismiss: () => void
}

export const NoticeContext = createContext<NoticeApi | null>(null)

export function useNotice(): NoticeApi {
  const ctx = useContext(NoticeContext)
  if (!ctx) throw new Error('useNotice must be used inside NoticeProvider')
  return ctx
}
