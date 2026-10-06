// header ตาม ui-reference: โลโก้ + ชื่อบริษัท | ชื่อผู้ใช้ + ตำแหน่ง ▾ (เมนูเปลี่ยนรหัสผ่าน / ออกจากระบบ) | ปุ่มภาษา
import { useEffect, useRef, useState } from 'react'
import { useAuth } from '../auth/useAuth.js'
import { useLang } from '../lib/i18n.js'
import { useToast } from '../lib/toast.js'
import LangToggle from './LangToggle.jsx'
import PasswordDialog from './PasswordDialog.jsx'

export default function Header() {
  const { profile, signOut } = useAuth()
  const { t } = useLang()
  const toast = useToast()
  const [open, setOpen] = useState(false)
  const [pwOpen, setPwOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const menuRef = useRef(null)

  useEffect(() => {
    if (!open) return
    const onDown = (e) => {
      if (!menuRef.current?.contains(e.target)) setOpen(false)
    }
    const onKey = (e) => {
      if (e.key === 'Escape') setOpen(false)
    }
    document.addEventListener('pointerdown', onDown)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('pointerdown', onDown)
      document.removeEventListener('keydown', onKey)
    }
  }, [open])

  const handleLogout = async () => {
    setBusy(true)
    setError('')
    const { error: err } = await signOut()
    // สำเร็จ → session หาย → RequireAuth พาไปหน้า login เอง
    if (err) {
      setBusy(false)
      setError(t('eLogout'))
    }
  }

  const roleLabel = t(profile.role)

  return (
    <header className="topbar">
      <div className="topbar-in">
        <div className="brand">
          <div className="logo">OK</div>
          <div className="brand-name">
            {t('company')}
            <small>{t('title')}</small>
          </div>
        </div>
        <div className="spacer" />
        <div className="user-menu" ref={menuRef}>
          <button
            type="button"
            className="user-btn"
            aria-expanded={open}
            aria-haspopup="menu"
            onClick={() => setOpen((v) => !v)}
          >
            <span className="user-text">
              <span className="user-name">{profile.display_name}</span>
              <span className="user-role">{roleLabel}</span>
            </span>
            <span aria-hidden="true">▾</span>
          </button>
          {open && (
            <div className="menu" role="menu">
              <div className="menu-info">
                <b>{profile.display_name}</b>
                <span>{t('role', { r: roleLabel })}</span>
              </div>
              <button
                type="button"
                role="menuitem"
                onClick={() => {
                  setOpen(false)
                  setError('')
                  setPwOpen(true)
                }}
                disabled={busy}
              >
                {t('changePw')}
              </button>
              <button type="button" role="menuitem" onClick={handleLogout} disabled={busy}>
                {t('logout')}
              </button>
              {error && (
                <p className="err menu-err" role="alert">
                  {error}
                </p>
              )}
            </div>
          )}
        </div>
        <LangToggle />
      </div>
      {pwOpen && (
        <PasswordDialog
          onClose={() => setPwOpen(false)}
          onSaved={(msg) => {
            setPwOpen(false)
            toast(msg)
          }}
        />
      )}
    </header>
  )
}
