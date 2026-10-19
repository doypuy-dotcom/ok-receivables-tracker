import { NavLink, Navigate, Route, Routes } from 'react-router-dom'
import RequireAuth from './auth/RequireAuth.jsx'
import Header from './components/Header.jsx'
import UpdatePrompt from './components/UpdatePrompt.jsx'
import { useLang } from './lib/i18n.js'
import { APP_VERSION } from './lib/version.js'
import LoginPage from './pages/LoginPage.jsx'
import MonthlyReportPage from './pages/MonthlyReportPage.jsx'
import ReceivableDetailPage from './pages/ReceivableDetailPage.jsx'
import ReceivablesPage from './pages/ReceivablesPage.jsx'

// เมนูหน้าจอ (V2): ตารางยอดค้าง / สรุปรายเดือน — ทั้ง owner และ sales เข้าได้ทั้ง 2 หน้า
// หน้ารายละเอียดการ์ด (/r/:id) นับเป็นส่วนของหน้าตาราง จึงให้ลิงก์แรก active ด้วย
function SubNav() {
  const { t } = useLang()
  const cls = ({ isActive }) => 'subnav-link' + (isActive ? ' on' : '')
  return (
    <nav className="subnav" aria-label="sections">
      <NavLink to="/" className={cls} end>
        {t('navList')}
      </NavLink>
      <NavLink to="/report" className={cls}>
        {t('navReport')}
      </NavLink>
    </nav>
  )
}

function AppShell({ children }) {
  return (
    <RequireAuth>
      <Header />
      <main>
        <SubNav />
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
        {/* หน้าสรุปรายเดือน + ส่งออก PDF / JPG (V2) — เข้าได้ทั้ง owner และ sales */}
        <Route
          path="/report"
          element={
            <AppShell>
              <MonthlyReportPage />
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
