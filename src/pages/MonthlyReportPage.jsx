// หน้าสรุปรายเดือน (V2 — prd.md ข้อ 6.1) ใช้ได้ทั้ง owner และ sales
//
// ข้อมูลทั้งหมดจาก 3 view ของ migration 006: monthly_report, monthly_report_total, report_asof
// **ยอดเงินทุกตัวรวมแถวยอดรวมมาจาก database** แอปแค่กรองแถวตามเดือนที่เลือกแล้วจัดรูปแบบ (AGENTS.md)
//
// บล็อก "ยอดค้างข้ามเดือน" ใต้ตาราง = การ์ดที่ `due_month < เดือนที่เลือก` และ `not is_paid`
// (ลูกค้าสั่ง 19 ต.ค. ข้อ 4) **ไม่ใช่ is_carried_over** ที่ผูกกับเดือนปัจจุบัน ไม่งั้นเลือกเดือนย้อนหลัง
// แล้วการ์ดใบเดิมจะโผล่ทั้งในตารางและในบล็อก — view 006 จึงไม่มีคอลัมน์ is_carried_over ให้หยิบผิด
//
// เดือนที่เลือกอยู่ใน URL (?m=2026-10) กดย้อนกลับ/รีเฟรชแล้วยังอยู่เดือนเดิม เหมือนตัวกรองหน้าตาราง
// Realtime: ใช้ useLiveReload ตัวเดียวกับหน้าหลัก → ฝ่ายขายบันทึกการจ่าย ตัวเลขในรายงานเปลี่ยนเอง
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useAuth } from '../auth/useAuth.js'
import { MonthField } from '../components/DateField.jsx'
import ReportSheet from '../components/ReportSheet.jsx'
import { fetchReportAsOf, fetchReportRows, fetchReportTotals } from '../lib/data.js'
import { exportSheets } from '../lib/exportSheet.js'
import { currentMonthBangkok, fmtMonth, loadErrorKey } from '../lib/format.js'
import { useLang } from '../lib/i18n.js'
import { useLiveReload } from '../lib/live.js'
import { useToast } from '../lib/toast.js'

const MONTH_RE = /^\d{4}-(0[1-9]|1[0-2])$/

async function loadReport() {
  const [rows, totals, asOf] = await Promise.all([fetchReportRows(), fetchReportTotals(), fetchReportAsOf()])
  const error = rows.error ?? totals.error ?? asOf.error
  if (error) return { status: 'error', rows: [], totals: [], asOf: null, error: loadErrorKey(error) }
  return { status: 'ready', rows: rows.data, totals: totals.data, asOf: asOf.data, error: null }
}

export default function MonthlyReportPage() {
  const { profile } = useAuth()
  const { t, lang } = useLang()
  const toast = useToast()
  const [params, setParams] = useSearchParams()
  const [state, setState] = useState({ status: 'loading', rows: [], totals: [], asOf: null, error: null })
  const [reloadKey, setReloadKey] = useState(0)
  const [busy, setBusy] = useState('')
  const sheetRef = useRef(null)

  const thisMonth = useMemo(() => currentMonthBangkok().slice(0, 7), [])
  const param = params.get('m')
  const month = MONTH_RE.test(param ?? '') ? param : thisMonth

  useEffect(() => {
    let alive = true
    loadReport().then((next) => alive && setState(next))
    return () => {
      alive = false
    }
  }, [reloadKey])

  const retry = () => {
    setState((s) => ({ ...s, status: 'loading', error: null }))
    setReloadKey((k) => k + 1)
  }

  // โหลดใหม่เงียบ ๆ (ไม่ล้างหน้าจอเป็นสถานะกำลังโหลด) — รวม "ดู ณ" ที่มาจาก report_asof
  const liveReload = useCallback(() => setReloadKey((k) => k + 1), [])
  useLiveReload(liveReload)

  const setMonth = (value) => {
    if (!MONTH_RE.test(value)) return
    const p = new URLSearchParams(params)
    p.set('m', value)
    setParams(p, { replace: true })
  }

  const view = useMemo(() => {
    const first = `${month}-01`
    return {
      rows: state.rows.filter((r) => r.due_month === first).sort((a, b) => a.seq - b.seq),
      total: state.totals.find((x) => x.due_month === first) ?? null,
      // ค้างข้ามเดือน: ครบกำหนดก่อนเดือนที่เลือกและยังจ่ายไม่ครบ (is_paid มาจาก database)
      carry: state.rows
        .filter((r) => r.due_month < first && !r.is_paid)
        .sort((a, b) => a.actual_due_date.localeCompare(b.actual_due_date) || a.company_name.localeCompare(b.company_name, lang)),
    }
  }, [state.rows, state.totals, month, lang])

  const runExport = async (kind) => {
    if (busy) return
    const nodes = Array.from(sheetRef.current?.querySelectorAll('.sheet') ?? [])
    if (nodes.length === 0) return
    // ชื่อไฟล์เป็น ปี พ.ศ.-เดือน ตามที่ลูกค้าอ่าน (ไม่ใส่ชื่อบริษัทลูกค้าในชื่อไฟล์)
    const be = Number(month.slice(0, 4)) + 543
    const baseName = `OK-monthly-${be}-${month.slice(5, 7)}`
    setBusy(kind)
    try {
      const how = await exportSheets({
        kind,
        nodes,
        baseName,
        title: t('repHead', { m: fmtMonth(lang, month, true) }),
      })
      if (how !== 'cancelled') toast(t(how === 'shared' ? 'expShared' : 'expSaved'))
    } catch (err) {
      toast(t(err?.key ?? 'eExport'))
    } finally {
      setBusy('')
    }
  }

  const ready = state.status === 'ready'

  return (
    <>
      <h1 className="page-title">{t('repTitle')}</h1>
      <p className="page-sub">{t('repSub')}</p>

      <section className="controls" aria-label="report-controls">
        <div className="ctl-left">
          {/* ช่องเดือนของแอป (ดด/ปปปป ปี พ.ศ. + ปฏิทิน) — ห้ามใช้ input type="month" (AGENTS.md) */}
          <MonthField id="rep-month" label={t('repMonth')} value={month} onChange={setMonth} />
          <div className="meta">
            <span className="pill role">{t('role', { r: t(profile.role) })}</span>
          </div>
        </div>
        <div className="ctl-right">
          <div className="actions">
            <button type="button" className="btn primary" disabled={!ready || busy !== ''} onClick={() => runExport('pdf')}>
              {busy === 'pdf' ? t('expBusy') : t('expPdf')}
            </button>
            <button type="button" className="btn" disabled={!ready || busy !== ''} onClick={() => runExport('jpg')}>
              {busy === 'jpg' ? t('expBusy') : t('expJpg')}
            </button>
          </div>
          <p className="muted export-hint">{t('expHint')}</p>
        </div>
      </section>

      {state.status === 'loading' && (
        <p className="loading block-msg" role="status" aria-live="polite">
          {t('loading')}
        </p>
      )}

      {state.status === 'error' && (
        <div className="load-err block-msg" role="alert">
          <p className="err">{t(state.error)}</p>
          <button type="button" className="btn primary" onClick={retry}>
            {t('retry')}
          </button>
        </div>
      )}

      {ready && (
        <div className="sheet-wrap" ref={sheetRef}>
          <ReportSheet
            month={month}
            rows={view.rows}
            total={view.total}
            carry={view.carry}
            asOf={state.asOf}
            userName={profile.display_name}
          />
        </div>
      )}
    </>
  )
}
