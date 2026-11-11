import { Route, Routes } from 'react-router'
import { Layout, RequireAuth } from './Layout'
import { NoticeProvider } from './notice'
import Agenda from './pages/Agenda'
import Login from './pages/Login'
import NodePage from './pages/NodePage'
import Outline from './pages/Outline'

// Expects QueryClientProvider and a Router above it (see main.tsx).
export default function App() {
  return (
    <NoticeProvider>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route element={<RequireAuth />}>
          <Route element={<Layout />}>
            <Route index element={<Outline />} />
            <Route path="n/:id" element={<NodePage />} />
            <Route path="agenda" element={<Agenda />} />
            <Route path="*" element={<p>Page not found.</p>} />
          </Route>
        </Route>
      </Routes>
    </NoticeProvider>
  )
}
