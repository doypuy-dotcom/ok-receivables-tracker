// เปลี่ยนรหัสผ่านของบัญชีตัวเอง — ใช้ได้ทั้ง owner และ sales (prd ข้อ 9)
// ใช้ supabase.auth.updateUser เท่านั้น ไม่แตะตาราง profiles (ผู้ใช้เปลี่ยน role ตัวเองไม่ได้ — AGENTS.md)
// dialog ในแอป ไม่ใช่ window.alert / prompt (AGENTS.md)
import { useState } from 'react'
import { useDesktopFocus } from '../lib/focus.js'
import { useLang } from '../lib/i18n.js'
import { supabase } from '../lib/supabase.js'
import Dialog from './Dialog.jsx'

// ความยาวขั้นต่ำที่ฟอร์มตรวจ — ตัวบังคับจริงคือ Supabase Auth (ดู progress.md)
export const PASSWORD_MIN = 8

// error จาก Supabase Auth → key ของ i18n เพื่อให้ข้อความเป็นภาษาคน ไทย/อังกฤษ
function passwordErrorKey(error) {
  if (typeof navigator !== 'undefined' && navigator.onLine === false) return 'eOffline'
  // fetch ล้มเหลว (ไม่มีสัญญาณ / DNS) → AuthRetryableFetchError และไม่มี status
  if (error.name === 'AuthRetryableFetchError' || !error.status) return 'eOffline'

  const code = String(error.code ?? '')
  const msg = String(error.message ?? '')

  if (code === 'weak_password' || /at least|weak/i.test(msg)) return 'ePwWeak'
  if (code === 'same_password' || /should be different/i.test(msg)) return 'ePwSame'
  if (code === 'reauthentication_needed' || /reauthenticat/i.test(msg)) return 'ePwReauth'
  if (error.status === 429 || code === 'over_request_rate_limit') return 'eRateLimit'
  if (error.status === 401 || code === 'session_not_found') return 'eNotAuth'
  return 'ePwSave'
}

export default function PasswordDialog({ onClose, onSaved }) {
  const { t } = useLang()
  const [pw, setPw] = useState('')
  const [pw2, setPw2] = useState('')
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)
  const firstRef = useDesktopFocus()

  const submit = async () => {
    if (busy) return
    if (!pw || !pw2) {
      setErr(t('eFields'))
      return
    }
    if (pw.length < PASSWORD_MIN) {
      setErr(t('ePwShort'))
      return
    }
    if (pw !== pw2) {
      setErr(t('ePwMismatch'))
      return
    }

    setBusy(true)
    setErr('')
    let error = null
    try {
      ;({ error } = await supabase.auth.updateUser({ password: pw }))
    } catch {
      // network error ที่ไม่ได้ถูกห่อเป็น AuthError
      error = { name: 'AuthRetryableFetchError' }
    }
    if (error) {
      setBusy(false)
      setErr(t(passwordErrorKey(error)))
      return
    }
    // สำเร็จ → session เดิมยังใช้ได้ต่อ ไม่ต้องล็อกอินใหม่ · parent ปิดกล่องและแจ้งผล
    onSaved(t('pwSaved'))
  }

  const footer = (
    <>
      <button type="button" className="btn" onClick={onClose} disabled={busy}>
        {t('cancel')}
      </button>
      <button type="submit" className="btn primary" disabled={busy}>
        {busy ? t('saving') : t('save')}
      </button>
    </>
  )

  return (
    <Dialog title={t('changePw')} onClose={onClose} onSubmit={submit} footer={footer}>
      <div className="field">
        <label htmlFor="f-pw">{t('pwNew')}</label>
        <input
          id="f-pw"
          ref={firstRef}
          type="password"
          autoComplete="new-password"
          autoCapitalize="none"
          spellCheck={false}
          value={pw}
          onChange={(e) => {
            setPw(e.target.value)
            setErr('')
          }}
          disabled={busy}
        />
        <p className="hint">{t('pwHint')}</p>
      </div>
      <div className="field">
        <label htmlFor="f-pw2">{t('pwConfirm')}</label>
        <input
          id="f-pw2"
          type="password"
          autoComplete="new-password"
          autoCapitalize="none"
          spellCheck={false}
          value={pw2}
          onChange={(e) => {
            setPw2(e.target.value)
            setErr('')
          }}
          disabled={busy}
        />
      </div>
      <p className="err" role="alert">
        {err}
      </p>
    </Dialog>
  )
}
