// หน้าตารางยอดค้างชำระ ตาม listView ของ ui-reference
// ข้อมูลทั้งหมดจาก receivable_summary (ค่าคำนวณมาจาก view) — แอปแค่กรอง เรียง และจัดรูปแบบ
// ตัวกรองอยู่ใน URL (?m=2026-10-01,2026-11-01 | ?m=all, &unpaid=1) กดกลับจากหน้ารายละเอียดแล้วยังอยู่
import { useEffect, useMemo, useState } from 'react'
import { useLocation, useNavigate, useSearchParams } from 'react-router-dom'
import { useAuth } from '../auth/useAuth.js'
import MonthFilter from '../components/MonthFilter.jsx'
import ReceivableCard from '../components/ReceivableCard.jsx'
import SummaryDialog from '../components/SummaryDialog.jsx'
import { fetchLatestPaymentUpdate, fetchSummaries } from '../lib/data.js'
import { currentMonthBangkok, fmtMonth, fmtStamp, loadErrorKey, money, sumMoney } from '../lib/format.js'
import { useLang } from '../lib/i18n.js'

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
  const [summary, latestPay] = await Promise.all([fetchSummaries(), fetchLatestPaymentUpdate()])
  const error = summary.error ?? latestPay.error
  if (error) return { status: 'error', rows: [], asOf: null, error: loadErrorKey(error) }
  // "ข้อมูล ณ" = updated_at ล่าสุดของการ์ด (view) และการจ่าย
  const stamps = [...summary.data.map((r) => r.updated_at), ...latestPay.data.map((p) => p.updated_at)]
  const asOf = stamps.reduce((best, s) => (best === null || Date.parse(s) > Date.parse(best) ? s : best), null)
  return { status: 'ready', rows: summary.data, asOf, error: null }
}

export default function ReceivablesPage() {
  const { profile } = useAuth()
  const { t, lang } = useLang()
  const navigate = useNavigate()
  const location = useLocation()
  const [params, setParams] = useSearchParams()
  const [state, setState] = useState({ status: 'loading', rows: [], asOf: null, error: null })
  const [summaryRow, setSummaryRow] = useState(null)

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
                    <ReceivableCard row={row} onOpen={openCard} onSummary={setSummaryRow} />
                  </div>
                ))}
              </div>
            </>
          )}

          <h2 className="section-h">{t('listH')}</h2>
          {view.rest.length ? (
            <div className="grid">
              {view.rest.map((row) => (
                <ReceivableCard key={row.id} row={row} onOpen={openCard} onSummary={setSummaryRow} />
              ))}
            </div>
          ) : (
            <div className="empty">{t('empty')}</div>
          )}
        </>
      )}

      {summaryRow && <SummaryDialog row={summaryRow} onClose={() => setSummaryRow(null)} />}
    </>
  )
}
