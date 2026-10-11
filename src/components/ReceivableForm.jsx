// ฟอร์มเพิ่ม / แก้ไขยอดค้าง (ฝ่ายขายเท่านั้น) ตาม recForm ของ ui-reference
// บริษัท: เลือกจากรายชื่อเดิม หรือพิมพ์ชื่อใหม่เพื่อสร้าง (ตัดช่องว่างหน้า/หลังก่อนส่ง — schema.md 3.2)
// วันครบกำหนดเครดิตแสดงทันทีตอนกรอก (ตัวอย่างในเบราว์เซอร์ ค่าจริงมาจาก view หลังบันทึก)
// ปุ่มยกเลิกยอดค้างเป็นแบบยืนยัน 2 ขั้น แล้วพากลับหน้าตาราง
import { useEffect, useMemo, useState } from 'react'
import {
  cancelReceivable,
  fetchCompanies,
  insertCompany,
  insertReceivable,
  reactivateCompany,
  updateReceivable,
} from '../lib/data.js'
import { saveErrorKey } from '../lib/dbError.js'
import { useDesktopFocus } from '../lib/focus.js'
import { addDays, fmtDate, isMoneyText, loadErrorKey, previousMonthBangkok } from '../lib/format.js'
import { useLang } from '../lib/i18n.js'
import CancelButton from './CancelButton.jsx'
import DateField, { MonthField } from './DateField.jsx'
import Dialog from './Dialog.jsx'

const MONTH_RE = /^\d{4}-(0[1-9]|1[0-2])$/

function initialValues(row) {
  if (!row) {
    return {
      company: '',
      acct: previousMonthBangkok(),
      total: '',
      cdays: '60',
      cstart: '',
      astart: '',
      adue: '',
    }
  }
  return {
    company: row.company_name,
    acct: row.account_month.slice(0, 7),
    total: row.total_amount,
    cdays: String(row.credit_days),
    cstart: row.credit_start_date,
    astart: row.actual_start_date,
    adue: row.actual_due_date,
  }
}

// ตรวจในฟอร์มเป็นแค่ความสะดวก ตัวบังคับจริงคือ constraint + trigger ใน database
function validate(v) {
  if (!v.company.trim() || !v.acct || !v.total.trim() || !v.cdays.trim() || !v.cstart || !v.astart || !v.adue) {
    return 'eFields'
  }
  if (!MONTH_RE.test(v.acct)) return 'eAcctMonth'
  if (!isMoneyText(v.total)) return 'eTotalFormat'
  if (!(Number(v.total) > 0)) return 'eTotal'
  if (!/^\d+$/.test(v.cdays.trim()) || Number(v.cdays) <= 0) return 'eDays'
  if (v.adue < v.astart) return 'eDue'
  return null
}

export default function ReceivableForm({ row, onClose, onSaved, onCancelled }) {
  const { t, lang } = useLang()
  const [companies, setCompanies] = useState(null)
  const [loadErr, setLoadErr] = useState(null)
  const [v, setV] = useState(() => initialValues(row))
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)
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
  }, [])

  // รายการให้เลือกเฉพาะบริษัทที่เปิดอยู่ (ที่ปิดไว้ยังเทียบชื่อซ้ำได้ตอนบันทึก)
  const options = useMemo(
    () =>
      (companies ?? [])
        .filter((c) => c.is_active)
        .map((c) => c.name)
        .sort((a, b) => a.localeCompare(b, 'th')),
    [companies],
  )

  // ช่องวันที่ของแอป (DateField / MonthField) ส่งค่าเป็น string ส่วนช่องอื่นส่ง event มา
  const setValue = (key, value) => {
    setV((prev) => {
      // ใส่วันเริ่มนับเครดิตแล้วช่อง "วันเริ่มนับวันจริง" ยังว่าง → เติมให้ (ส่วนใหญ่เป็นวันเดียวกัน) แก้ทับได้
      if (key === 'cstart' && value && !prev.astart) return { ...prev, cstart: value, astart: value }
      return { ...prev, [key]: value }
    })
    setErr('')
  }

  const set = (key) => (e) => setValue(key, e.target.value)

  const creditDue = /^\d+$/.test(v.cdays.trim()) ? addDays(v.cstart, Number(v.cdays)) : null

  // ชื่อที่พิมพ์ใหม่ → สร้างบริษัท, ชื่อที่ตรงกับบริษัทที่ปิดไว้ → เปิดกลับมาใช้ (name เป็น unique)
  const resolveCompanyId = async (name) => {
    const found = companies.find((c) => c.name === name)
    if (!found) {
      const { data, error } = await insertCompany(name)
      if (error) return { error }
      return { id: data.id }
    }
    if (!found.is_active) {
      const { error } = await reactivateCompany(found.id)
      if (error) return { error }
    }
    return { id: found.id }
  }

  const submit = async () => {
    if (busy) return
    const clean = { ...v, company: v.company.trim(), total: v.total.trim(), cdays: v.cdays.trim() }
    const problem = validate(clean)
    if (problem) {
      setErr(t(problem))
      return
    }
    setBusy(true)
    const co = await resolveCompanyId(clean.company)
    if (co.error) {
      setBusy(false)
      setErr(t(saveErrorKey(co.error)))
      return
    }
    // ยอดเงินส่งเป็น string: numeric(14,2) ฝั่ง database รับไปตรง ๆ ไม่ผ่าน float ของ JavaScript
    const values = {
      company_id: co.id,
      account_month: clean.acct + '-01',
      total_amount: clean.total,
      credit_days: Number(clean.cdays),
      credit_start_date: clean.cstart,
      actual_start_date: clean.astart,
      actual_due_date: clean.adue,
    }
    const res = row ? await updateReceivable(row.id, values) : await insertReceivable(values)
    setBusy(false)
    if (res.error) {
      setErr(t(saveErrorKey(res.error)))
      return
    }
    // update ที่ RLS ไม่ให้ผ่านคืน 0 แถวโดยไม่มี error
    if (row && res.data.length === 0) {
      setErr(t('eNoWrite'))
      return
    }
    onSaved(t('savedRec'))
  }

  const cancelCard = async () => {
    if (busy) return
    setBusy(true)
    const { data, error } = await cancelReceivable(row.id)
    setBusy(false)
    if (error) {
      setErr(t(saveErrorKey(error)))
      return
    }
    if (data.length === 0) {
      setErr(t('eNoWrite'))
      return
    }
    onCancelled(t('cancelled'))
  }

  const title = row ? t('editRec') : t('addRec')

  if (loadErr) {
    return (
      <Dialog title={title} onClose={onClose}>
        <p className="err" role="alert">
          {t(loadErr)}
        </p>
      </Dialog>
    )
  }

  if (companies === null) {
    return (
      <Dialog title={title} onClose={onClose}>
        <p className="loading" role="status">
          {t('loading')}
        </p>
      </Dialog>
    )
  }

  const footer = (
    <>
      {row && (
        <CancelButton
          label={t('cancelRec')}
          disabled={busy}
          onArm={() => setErr(t('confirmCancel'))}
          onConfirm={cancelCard}
        />
      )}
      <button type="button" className="btn" onClick={onClose} disabled={busy}>
        {t('cancel')}
      </button>
      <button type="submit" className="btn primary" disabled={busy}>
        {busy ? t('saving') : t('save')}
      </button>
    </>
  )

  return (
    <Dialog title={title} onClose={onClose} onSubmit={submit} footer={footer}>
      <div className="field">
        <label htmlFor="f-company">{t('fCompany')}</label>
        <input
          id="f-company"
          ref={firstRef}
          list="co-dl"
          autoComplete="off"
          value={v.company}
          onChange={set('company')}
        />
        <span className="hint">{t('fCompanyHint')}</span>
        <datalist id="co-dl">
          {options.map((name) => (
            <option key={name} value={name} />
          ))}
        </datalist>
      </div>
      <div className="row2">
        {/* ช่องของแอปเอง: พิมพ์ ดด/ปปปป (ปี พ.ศ.) + ไอคอนเลือกเดือน — เลิกใช้ type="month" ที่เป็นภาษาอังกฤษ */}
        <MonthField id="f-acct" label={t('fAcct')} value={v.acct} onChange={(x) => setValue('acct', x)} />
        <div className="field">
          <label htmlFor="f-total">{t('fTotal')}</label>
          <input
            id="f-total"
            type="number"
            inputMode="decimal"
            step="0.01"
            min="0"
            value={v.total}
            onChange={set('total')}
          />
        </div>
      </div>
      <div className="row2">
        <div className="field">
          <label htmlFor="f-cdays">{t('fCdays')}</label>
          <input id="f-cdays" type="number" inputMode="numeric" min="1" value={v.cdays} onChange={set('cdays')} />
        </div>
        <DateField id="f-cstart" label={t('fCstart')} value={v.cstart} onChange={(x) => setValue('cstart', x)} />
      </div>
      <div className="preview num" aria-live="polite">
        {t('previewCredit', { d: creditDue ? fmtDate(lang, creditDue, true) : '–' })}
      </div>
      <div className="row2">
        <DateField id="f-astart" label={t('fAstart')} value={v.astart} onChange={(x) => setValue('astart', x)} />
        <DateField id="f-adue" label={t('fAdue')} value={v.adue} onChange={(x) => setValue('adue', x)} />
      </div>
      <span className="hint">{t('fAdueHint')}</span>
      <p className="err" role="alert">
        {err}
      </p>
    </Dialog>
  )
}
