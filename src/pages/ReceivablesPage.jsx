// หน้าตารางยอดค้างชำระ ตาม listView ของ ui-reference
// ข้อมูลทั้งหมดจาก receivable_summary (ค่าคำนวณมาจาก view) — แอปแค่กรอง เรียง และจัดรูปแบบ
// ตัวกรองอยู่ใน URL (?m=2026-10-01,2026-11-01 | ?m=all, &unpaid=1) กดกลับจากหน้ารายละเอียดแล้วยังอยู่
// Realtime (M5): มีคนแก้ข้อมูล → โหลดทั้งหน้าใหม่ รวม "ข้อมูล ณ" (useLiveReload)
import { useCallback, useEffect, useMemo, useState } from 'react'
import { useLocation, useNavigate, useSearchParams } from 'react-router-dom'
import { useAuth } from '../auth/useAuth.js'
import CompaniesDialog from '../components/CompaniesDialog.jsx'
import MonthFilter from '../components/MonthFilter.jsx'
import PaymentForm from '../components/PaymentForm.jsx'
import ReceivableCard from '../components/ReceivableCard.jsx'
import ReceivableForm from '../components/ReceivableForm.jsx'
import SummaryDialog from '../components/SummaryDialog.jsx'
import { fetchLatestChange, fetchSummaries } from '../lib/data.js'
import { currentMonthBangkok, fmtMonth, fmtStamp, loadErrorKey, money, sumMoney } from '../lib/format.js'
import { useLang } from '../lib/i18n.js'
import { useLiveReload } from '../lib/live.js'
import { useToast } from '../lib/toast.js'

const MONTH_RE = /^\d{4}-\d{2}-01$/

function readMonths(params, fallback) {
  const m = params.get('m')
  if (m === null) return new Set([fallback])
  if (m === 'all') return new Set()
  const list = m.split(',').filter((x) => MONTH_RE.test(x))
  return list.length ? new Set(list) : new Set([fallback])
}

const byDue = (a, b) => a.actual_due_date.localeCompare(b.actual_due_date)

async function loadList() {
  const [summary, latest] = await Promise.all([fetchSummaries(), fetchLatestChange()])
  const error = summary.error ?? latest.error
  if (error) return { status: 'error', rows: [], asOf: null, error: loadErrorKey(error) }
  // "ข้อมูล ณ" = เวลาที่ข้อมูลถูกแก้ไขล่าสุด (audit_logs ครอบคลุมการยกเลิกการ์ดและการแก้การจ่ายด้วย)
  return { status: 'ready', rows: summary.data, asOf: latest.data[0]?.created_at ?? null, error: null }
}

export default function ReceivablesPage() {
  const { profile } = useAuth()
  const { t, lang } = useLang()
  const toast = useToast()
  const navigate = useNavigate()
  const location = useLocation()
  const [params, setParams] = useSearchParams()
  const [state, setState] = useState({ status: 'loading', rows: [], asOf: null, error: null })
  const [summaryRow, setSummaryRow] = useState(null)
  // ฟอร์มที่เปิดอยู่: null | 'rec' (เพิ่มยอดค้าง) | 'companies'
  const [dialog, setDialog] = useState(null)
  // การ์ดที่กดปุ่ม "เพิ่มการจ่าย" บนหน้าตาราง (V1 รอบ ก) — ฟอร์มเดียวกับในหน้ารายละเอียด
  // เก็บแค่ id แล้วหาแถวจากข้อมูลล่าสุด: Realtime โหลดใหม่ตอนกล่องเปิดอยู่ → ยอดคงเหลือในฟอร์มตามจริง
  const [payId, setPayId] = useState(null)
  const isSales = profile.role === 'sales'

  const thisMonth = useMemo(() => currentMonthBangkok(), [])
  const months = useMemo(() => readMonths(params, thisMonth), [params, thisMonth])
  const unpaidOnly = params.get('unpaid') === '1'

  const [reloadKey, setReloadKey] = useState(0)

  useEffect(() => {
    let alive = true
    loadList().then((next) => alive && setState(next))
    return () => {
      alive = false
    }
  }, [reloadKey])

  const retry = () => {
    setState((s) => ({ ...s, status: 'loading', error: null }))
    setReloadKey((k) => k + 1)
  }

  // โหลดใหม่เงียบ ๆ (ไม่ขึ้นข้อความ ไม่ล้างหน้าจอเป็นสถานะกำลังโหลด) สำหรับ Realtime
  // คนอื่นบันทึก → การ์ด ยอดรวม และ "ข้อมูล ณ" อัปเดตตามโดยไม่ต้องรีเฟรช
  const liveReload = useCallback(() => setReloadKey((k) => k + 1), [])
  useLiveReload(liveReload)

  // หลังบันทึก / ยกเลิก: โหลดข้อมูลใหม่ (รวม "ข้อมูล ณ") แล้วแจ้งผล
  const reload = (msg) => {
    setReloadKey((k) => k + 1)
    toast(msg)
  }

  const afterWrite = (msg) => {
    setDialog(null)
    reload(msg)
  }

  const afterPayWrite = (msg) => {
    setPayId(null)
    reload(msg)
  }

  const setFilter = (nextMonths, nextUnpaid) => {
    const p = new URLSearchParams(params)
    p.set('m', nextMonths.size === 0 ? 'all' : [...nextMonths].sort().join(','))
    if (nextUnpaid) p.set('unpaid', '1')
    else p.delete('unpaid')
    setParams(p, { replace: true })
  }

  const view = useMemo(() => {
    const rows = state.rows
    // ค้างข้ามเดือน: แสดงเสมอไม่ว่าจะเลือกเดือนไหน จนกว่าจะจ่ายครบ (prd ข้อ 6)
    const carried = rows.filter((r) => r.is_carried_over).sort(byDue)
    let rest = rows.filter((r) => !r.is_carried_over && (months.size === 0 || months.has(r.due_month)))
    if (unpaidOnly) rest = rest.filter((r) => !r.is_paid)
    rest.sort((a, b) => Number(a.is_paid) - Number(b.is_paid) || byDue(a, b))
    const options = [...new Set([...rows.map((r) => r.due_month), thisMonth, ...months])].sort()
    return {
      carried,
      rest,
      options,
      dueSum: sumMoney(rest.map((r) => r.balance)),
      dueCount: rest.filter((r) => !r.is_paid).length,
      carrySum: sumMoney(carried.map((r) => r.balance)),
    }
  }, [state.rows, months, unpaidOnly, thisMonth])

  const openCard = (row) => navigate(`/r/${row.id}`, { state: { from: location.search } })

  // ปุ่ม "เพิ่มการจ่าย" บนการ์ด: เฉพาะฝ่ายขาย และเฉพาะการ์ดที่ยังค้าง (จ่ายครบแล้วไม่มีอะไรให้บันทึก)
  // undefined → การ์ดไม่แสดงปุ่มเลย (สิทธิ์จริงยังบังคับด้วย RLS)
  const addPay = isSales ? (row) => !row.is_paid && setPayId(row.id) : undefined

  // การ์ดถูกยกเลิกหรือจ่ายครบโดยคนอื่นระหว่างกล่องเปิดอยู่ → ไม่มีแถว กล่องปิดไปเอง
  const payRow = payId ? state.rows.find((r) => r.id === payId) : null

  return (
    <>
      <h1 className="page-title">{t('title')}</h1>
      <p className="page-sub">{t('sub')}</p>

      <section className="controls" aria-label="filters">
        <div className="ctl-left">
          <MonthFilter
            options={view.options}
            months={months}
            unpaidOnly={unpaidOnly}
            onMonths={(m) => setFilter(m, unpaidOnly)}
            onUnpaidOnly={(u) => setFilter(months, u)}
          />
          <div className="meta">
            <span className="pill role">{t('role', { r: t(profile.role) })}</span>
          </div>
        </div>
        <div className="ctl-right">
          {state.status === 'ready' && state.asOf && (
            <span className="pill num">🕘 {t('asOf', { d: fmtStamp(lang, state.asOf) })}</span>
          )}
          {/* เจ้าของดูอย่างเดียว (prd ข้อ 9) จึงไม่มีปุ่มเพิ่ม/แก้ไขให้เห็นเลย — สิทธิ์จริงบังคับด้วย RLS */}
          {isSales && (
            <div className="actions">
              <button type="button" className="btn" onClick={() => setDialog('companies')}>
                {t('companies')}
              </button>
              <button type="button" className="btn primary" onClick={() => setDialog('rec')}>
                + {t('addRec')}
              </button>
            </div>
          )}
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

      {state.status === 'ready' && (
        <>
          <div className="totals">
            <div className="total">
              <span>{t('dueSel')}</span>
              <strong className="num">{money(view.dueSum)}</strong> {t('baht')}
              <span>{t('items', { n: view.dueCount })}</span>
            </div>
            <div className={'total' + (view.carried.length ? ' warn' : '')}>
              <span>{t('carryTotal')}</span>
              <strong className="num">{money(view.carrySum)}</strong> {t('baht')}
              <span>{t('items', { n: view.carried.length })}</span>
            </div>
          </div>

          {view.carried.length > 0 && (
            <>
              <h2 className="section-h">{t('carryH')}</h2>
              <div className="grid">
                {view.carried.map((row) => (
                  <div key={row.id} className="carry">
                    <div className="carry-note">
                      {t('carryNote', { m: fmtMonth(lang, row.due_month, true), a: money(row.balance) })}
                    </div>
                    <ReceivableCard row={row} onOpen={openCard} onSummary={setSummaryRow} onAddPay={addPay} />
                  </div>
                ))}
              </div>
            </>
          )}

          <h2 className="section-h">{t('listH')}</h2>
          {view.rest.length ? (
            <div className="grid">
              {view.rest.map((row) => (
                <ReceivableCard
                  key={row.id}
                  row={row}
                  onOpen={openCard}
                  onSummary={setSummaryRow}
                  onAddPay={addPay}
                />
              ))}
            </div>
          ) : (
            <div className="empty">
              {t('empty')}
              {isSales && (
                <>
                  <br />
                  {t('emptySales')}
                </>
              )}
            </div>
          )}
        </>
      )}

      {summaryRow && <SummaryDialog row={summaryRow} onClose={() => setSummaryRow(null)} />}

      {/* เพิ่มการจ่ายจากหน้าตารางได้เลย ไม่ต้องเข้าหน้ารายละเอียด (V1 รอบ ก) */}
      {isSales && payRow && (
        <PaymentForm
          row={payRow}
          payment={null}
          onClose={() => setPayId(null)}
          onSaved={afterPayWrite}
          onCancelled={afterPayWrite}
        />
      )}

      {isSales && dialog === 'rec' && (
        <ReceivableForm row={null} onClose={() => setDialog(null)} onSaved={afterWrite} onCancelled={afterWrite} />
      )}
      {isSales && dialog === 'companies' && (
        /* เพิ่มบริษัทแล้วกล่องยังเปิดอยู่ (เพิ่มติดกันหลายบริษัทได้) ตาม ui-reference */
        <CompaniesDialog rows={state.rows} onClose={() => setDialog(null)} onSaved={reload} />
      )}
    </>
  )
}
