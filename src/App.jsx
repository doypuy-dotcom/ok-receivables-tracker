import { Navigate, Route, Routes } from 'react-router-dom'
import RequireAuth from './auth/RequireAuth.jsx'
import Header from './components/Header.jsx'
import LoginPage from './pages/LoginPage.jsx'
import ReceivableDetailPage from './pages/ReceivableDetailPage.jsx'
import ReceivablesPage from './pages/ReceivablesPage.jsx'

function AppShell({ children }) {
  return (
    <RequireAuth>
      <Header />
      <main>{children}</main>
    </RequireAuth>
  )
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route
        path="/"
        element={
          <AppShell>
            <ReceivablesPage />
          </AppShell>
        }
      />
      <Route
        path="/r/:id"
        element={
          <AppShell>
            <ReceivableDetailPage />
          </AppShell>
        }
      />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}
