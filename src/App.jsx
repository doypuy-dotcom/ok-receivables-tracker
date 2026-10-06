import { Navigate, Route, Routes } from 'react-router-dom'
import RequireAuth from './auth/RequireAuth.jsx'
import Header from './components/Header.jsx'
import UpdatePrompt from './components/UpdatePrompt.jsx'
import { APP_VERSION } from './lib/version.js'
import LoginPage from './pages/LoginPage.jsx'
import ReceivableDetailPage from './pages/ReceivableDetailPage.jsx'
import ReceivablesPage from './pages/ReceivablesPage.jsx'

function AppShell({ children }) {
  return (
    <RequireAuth>
      <Header />
      <main>
        {children}
        {/* เลขเวอร์ชันท้ายหน้า — ค่าเดียวจาก src/lib/version.js */}
        <p className="app-ver">{APP_VERSION}</p>
      </main>
    </RequireAuth>
  )
}

export default function App() {
  return (
    <>
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
      {/* แจ้งเวอร์ชันใหม่ — อยู่นอก Routes จึงขึ้นได้ทุกหน้า รวมหน้า login */}
      <UpdatePrompt />
    </>
  )
}
