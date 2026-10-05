// หน้า login: อีเมล + รหัสผ่าน (ไม่มีหน้าสมัครสมาชิก — สร้างบัญชีจาก Supabase dashboard)
import { useState } from 'react'
import { Navigate, useLocation } from 'react-router-dom'
import { useAuth } from '../auth/useAuth.js'
import LangToggle from '../components/LangToggle.jsx'
import { useLang } from '../lib/i18n.js'
import { isConfigured } from '../lib/supabase.js'

function errorKey(error) {
  if (typeof navigator !== 'undefined' && navigator.onLine === false) return 'eOffline'
  if (error.code === 'invalid_credentials') return 'eInvalid'
  if (error.code === 'email_not_confirmed') return 'eNotConfirmed'
  if (error.status === 429 || error.code === 'over_request_rate_limit') return 'eRateLimit'
  // fetch ล้มเหลว (ไม่มีสัญญาณ / DNS) → AuthRetryableFetchError
  if (error.name === 'AuthRetryableFetchError' || !error.status) return 'eOffline'
  return null
}

export default function LoginPage() {
  const { session, notice, signIn } = useAuth()
  const { t } = useLang()
  const location = useLocation()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  if (session) {
    const to = location.state?.from && location.state.from !== '/login' ? location.state.from : '/'
    return <Navigate to={to} replace />
  }

  if (session === undefined) {
    return (
      <div className="center-screen" role="status" aria-live="polite">
        <p className="loading">{t('loading')}</p>
      </div>
    )
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    const trimmed = email.trim()
    if (!trimmed || !password) {
      setError(t('eRequired'))
      return
    }
    setBusy(true)
    setError('')
    try {
      const { error: err } = await signIn(trimmed, password)
      if (err) {
        const key = errorKey(err)
        setError(key ? t(key) : t('eUnknown', { m: err.message }))
        setBusy(false)
      }
      // สำเร็จ → session เปลี่ยน → component นี้ redirect เอง
    } catch {
      setError(t('eOffline'))
      setBusy(false)
    }
  }

  const message = error || (notice ? t(notice) : '')

  return (
    <div className="login">
      <div className="login-box">
        <div className="brand">
          <div className="logo">OK</div>
          <div className="brand-name">
            {t('company')}
            <small>{t('companySub')}</small>
          </div>
        </div>
        <h1>{t('loginTitle')}</h1>
        <p>{t('loginHint')}</p>

        {!isConfigured ? (
          <p className="err" role="alert">
            {t('eNotConfigured')}
          </p>
        ) : (
          <form className="login-form" onSubmit={handleSubmit} noValidate>
            <div className="field">
              <label htmlFor="email">{t('email')}</label>
              <input
                id="email"
                type="email"
                inputMode="email"
                autoComplete="username"
                autoCapitalize="none"
                spellCheck={false}
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                disabled={busy}
              />
            </div>
            <div className="field">
              <label htmlFor="password">{t('password')}</label>
              <input
                id="password"
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                disabled={busy}
              />
            </div>
            <p className="err" role="alert" aria-live="assertive">
              {message}
            </p>
            <button className="btn primary block" type="submit" disabled={busy}>
              {busy ? t('signingIn') : t('signIn')}
            </button>
          </form>
        )}

        <LangToggle />
      </div>
    </div>
  )
}
