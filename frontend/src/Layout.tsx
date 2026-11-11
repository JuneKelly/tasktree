import { Link, Navigate, Outlet } from 'react-router'
import { useActor } from './api/hooks'
import { clearToken, useToken } from './auth'
import { useNotice } from './noticeContext'

export function RequireAuth() {
  return useToken() ? <Outlet /> : <Navigate to="/login" replace />
}

export function Layout() {
  const actor = useActor()
  const { notice, dismiss } = useNotice()
  return (
    <>
      <header className="top">
        <h1>Tasktree</h1>
        <nav>
          <Link to="/">Outline</Link> <Link to="/agenda">Agenda</Link>
        </nav>
        <span className="who">{actor.data?.actor}</span>
        <button onClick={clearToken}>Log out</button>
      </header>
      {notice && (
        <div role="alert" className={`notice ${notice.kind}`}>
          {notice.text} <button onClick={dismiss}>Dismiss</button>
        </div>
      )}
      <main>
        <Outlet />
      </main>
    </>
  )
}
