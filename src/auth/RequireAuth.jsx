// ป้องกันหน้าที่ต้องล็อกอิน: ไม่มี session → /login, มี session → รอ profile ก่อนแสดงหน้า
import { Navigate, useLocation } from 'react-router-dom'
import { useLang } from '../lib/i18n.js'
import { useAuth } from './useAuth.js'

export default function RequireAuth({ children }) {
  const { session, profileStatus, retryProfile, signOut } = useAuth()
  const { t } = useLang()
  const location = useLocation()

  if (session === null) {
    return <Navigate to="/login" replace state={{ from: location.pathname }} />
  }

  if (profileStatus === 'error') {
    return (
      <div className="center-screen">
        <div className="login-box">
          <p className="err" role="alert">
            {t('eProfile')}
          </p>
          <div className="actions">
            <button className="btn primary" type="button" onClick={retryProfile}>
              {t('retry')}
            </button>
            <button className="btn" type="button" onClick={signOut}>
              {t('logout')}
            </button>
          </div>
        </div>
      </div>
    )
  }

  if (profileStatus !== 'ready') {
    return (
      <div className="center-screen" role="status" aria-live="polite">
        <p className="loading">{t('loading')}</p>
      </div>
    )
  }

  return children
}
