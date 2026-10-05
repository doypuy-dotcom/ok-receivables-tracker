// placeholder — ตารางยอดค้างจริงทำใน M3
import { useAuth } from '../auth/useAuth.js'
import { useLang } from '../lib/i18n.js'

export default function ReceivablesPage() {
  const { profile } = useAuth()
  const { t } = useLang()

  return (
    <>
      <h1 className="page-title">{t('placeholder')}</h1>
      <p className="page-sub">{t('placeholderSub')}</p>
      <div className="meta">
        <span className="pill role">{t('role', { r: t(profile.role) })}</span>
      </div>
    </>
  )
}
