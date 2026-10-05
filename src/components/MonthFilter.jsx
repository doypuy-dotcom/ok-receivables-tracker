// ตัวกรองเดือนที่ครบกำหนด ตาม ui-reference: ทุกเดือน / เลือกหลายเดือน / เฉพาะที่ยังค้างชำระ
// months = Set ของ "YYYY-MM-01" (ว่าง = ทุกเดือน)
import { useEffect, useRef, useState } from 'react'
import { fmtMonth } from '../lib/format.js'
import { useLang } from '../lib/i18n.js'

export default function MonthFilter({ options, months, unpaidOnly, onMonths, onUnpaidOnly }) {
  const { t, lang } = useLang()
  const [open, setOpen] = useState(false)
  const ref = useRef(null)

  useEffect(() => {
    if (!open) return
    const onDown = (e) => {
      if (!ref.current?.contains(e.target)) setOpen(false)
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

  const label =
    months.size === 0
      ? t('allMonths')
      : months.size === 1
        ? fmtMonth(lang, [...months][0], true)
        : t('monthsSel', { n: months.size })

  const toggle = (m, checked) => {
    const next = new Set(months)
    if (checked) next.add(m)
    else next.delete(m)
    onMonths(next)
  }

  return (
    <div className="mfilter" ref={ref}>
      <button type="button" className="mf-btn" aria-expanded={open} onClick={() => setOpen((v) => !v)}>
        <span aria-hidden="true">📅</span>
        <span>
          <span className="cap">{t('monthCap')}</span>
          <span className="val">{label}</span>
        </span>
      </button>
      {open && (
        <div className="panel">
          <label>
            <input type="checkbox" checked={months.size === 0} onChange={() => onMonths(new Set())} />
            {t('allMonths')}
          </label>
          <hr />
          {options.map((m) => (
            <label key={m}>
              <input type="checkbox" checked={months.has(m)} onChange={(e) => toggle(m, e.target.checked)} />
              {fmtMonth(lang, m, true)}
            </label>
          ))}
          <hr />
          <label>
            <input type="checkbox" checked={unpaidOnly} onChange={(e) => onUnpaidOnly(e.target.checked)} />
            {t('unpaidOnly')}
          </label>
        </div>
      )}
    </div>
  )
}
