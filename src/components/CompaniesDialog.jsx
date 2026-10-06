// รายชื่อบริษัท (ฝ่ายขายเท่านั้น) ตาม companiesDlg ของ ui-reference: ดูรายการ + เพิ่มบริษัทใหม่
// "ค้าง N รายการ" นับจากการ์ดที่ยังจ่ายไม่ครบใน receivable_summary (ทุกเดือน ไม่ใช่แค่เดือนที่กรองอยู่)
import { useEffect, useState } from 'react'
import { fetchCompanies, insertCompany } from '../lib/data.js'
import { saveErrorKey } from '../lib/dbError.js'
import { useDesktopFocus } from '../lib/focus.js'
import { loadErrorKey } from '../lib/format.js'
import { useLang } from '../lib/i18n.js'
import Dialog from './Dialog.jsx'

export default function CompaniesDialog({ rows, onClose, onSaved }) {
  const { t } = useLang()
  const [companies, setCompanies] = useState(null)
  const [loadErr, setLoadErr] = useState(null)
  const [name, setName] = useState('')
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)
  const [reloadKey, setReloadKey] = useState(0)
  const firstRef = useDesktopFocus(companies !== null)

  useEffect(() => {
    let alive = true
    fetchCompanies().then(({ data, error }) => {
      if (!alive) return
      if (error) setLoadErr(loadErrorKey(error))
      else setCompanies(data)
    })
    return () => {
      alive = false
    }
  }, [reloadKey])

  const openCount = (id) => rows.filter((r) => r.company_id === id && !r.is_paid).length

  const add = async () => {
    if (busy) return
    const clean = name.trim()
    if (!clean) {
      setErr(t('eFields'))
      return
    }
    // ชื่อซ้ำเทียบแบบตรงตัวอักษรเหมือน unique ของ database (รวมบริษัทที่ปิดอยู่)
    if (companies.some((c) => c.name === clean)) {
      setErr(t('coExists'))
      return
    }
    setBusy(true)
    const { error } = await insertCompany(clean)
    setBusy(false)
    if (error) {
      setErr(t(saveErrorKey(error)))
      return
    }
    setName('')
    setErr('')
    setReloadKey((k) => k + 1)
    onSaved(t('coAdded'))
  }

  if (loadErr) {
    return (
      <Dialog title={t('coH')} onClose={onClose}>
        <p className="err" role="alert">
          {t(loadErr)}
        </p>
      </Dialog>
    )
  }

  const footer = (
    <>
      <button type="button" className="btn" onClick={onClose} disabled={busy}>
        {t('cancel')}
      </button>
      <button type="submit" className="btn primary" disabled={busy || companies === null}>
        {busy ? t('saving') : t('coAdd')}
      </button>
    </>
  )

  const active = (companies ?? [])
    .filter((c) => c.is_active)
    .sort((a, b) => a.name.localeCompare(b.name, 'th'))

  return (
    <Dialog title={t('coH')} onClose={onClose} onSubmit={add} footer={footer}>
      {companies === null ? (
        <p className="loading" role="status">
          {t('loading')}
        </p>
      ) : active.length === 0 ? (
        <div className="empty">{t('coNone')}</div>
      ) : (
        <ul className="co-list">
          {active.map((c) => (
            <li key={c.id}>
              {c.name}
              <span className="num">{t('coOpen', { n: openCount(c.id) })}</span>
            </li>
          ))}
        </ul>
      )}
      <div className="field">
        <label htmlFor="f-co">{t('coName')}</label>
        <input id="f-co" ref={firstRef} autoComplete="off" value={name} onChange={(e) => setName(e.target.value)} />
      </div>
      <p className="err" role="alert">
        {err}
      </p>
    </Dialog>
  )
}
