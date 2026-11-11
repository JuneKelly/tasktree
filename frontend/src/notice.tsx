import { useCallback, useMemo, useState, type ReactNode } from 'react'
import { NoticeContext, type Notice } from './noticeContext'

export function NoticeProvider({ children }: { children: ReactNode }) {
  const [notice, setNotice] = useState<Notice | null>(null)
  const notify = useCallback((text: string, kind: Notice['kind'] = 'error') => setNotice({ text, kind }), [])
  const dismiss = useCallback(() => setNotice(null), [])
  const value = useMemo(() => ({ notice, notify, dismiss }), [notice, notify, dismiss])
  return <NoticeContext.Provider value={value}>{children}</NoticeContext.Provider>
}
