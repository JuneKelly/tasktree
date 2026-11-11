import { useState } from 'react'
import { useNavigate } from 'react-router'
import { useQueryClient } from '@tanstack/react-query'
import { api } from '../api/client'
import { describeError } from '../api/hooks'
import { setToken } from '../auth'

export default function Login() {
  const [token, setTok] = useState('')
  const [error, setError] = useState<string | null>(null)
  const navigate = useNavigate()
  const qc = useQueryClient()

  const submit = async (e: React.SubmitEvent) => {
    e.preventDefault()
    const candidate = token.trim()
    setError(null)
    try {
      await api.me(candidate)
    } catch (err) {
      setError(describeError(err))
      return
    }
    setToken(candidate)
    qc.clear()
    void navigate('/')
  }

  return (
    <main>
      <h1>Tasktree</h1>
      <form onSubmit={submit} aria-label="Log in">
        <label htmlFor="token">API token</label> <input id="token" type="password" value={token} onChange={(e) => setTok(e.target.value)} />
        <button type="submit">Log in</button>
        {error && <p role="alert">{error}</p>}
      </form>
    </main>
  )
}

