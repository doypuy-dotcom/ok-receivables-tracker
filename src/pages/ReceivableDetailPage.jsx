// หน้ารายละเอียดการ์ด ตาม detailView ของ ui-reference + ประวัติการแก้ไข (schema.md 3.5)
// อ่านจาก receivable_summary, payments, audit_logs (+ profiles สำหรับชื่อคนแก้) ไม่คำนวณเงินเอง
import { useEffect, useMemo, useState } from 'react'
import { useLocation, useNavigate, useParams } from 'react-router-dom'
import EditHistory from '../components/EditHistory.jsx'
import PaymentList from '../components/PaymentList.jsx'
import StatusBars, { LateLine } from '../components/StatusBars.jsx'
import SummaryDialog from '../components/SummaryDialog.jsx'
import {
  fetchCompanyNameLogs,
  fetchEditLogs,
  fetchPayments,
  fetchProfiles,
  fetchSummary,
} from '../lib/data.js'
import { fmtDate, fmtMonth, loadErrorKey, money } from '../lib/format.js'
import { buildHistory } from '../lib/history.js'
import { useLang } from '../lib/i18n.js'

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

const EMPTY = { row: null, payments: [], history: [], userNames: {}, companyNames: {} }

async function loadDetail(id) {
  const [summary, payments, logs] = await Promise.all([fetchSummary(id), fetchPayments(id), fetchEditLogs(id)])
  const error = summary.error ?? payments.error ?? logs.error
  if (error) return { error }
  if (!summary.data) return { notFound: true }

  const history = buildHistory(logs.data)
  const userIds = [...new Set(history.map((h) => h.log.user_id))]
  const companyIds = [
    ...new Set(
      history.flatMap((h) => (h.changed.includes('company_id') ? [h.oldV.company_id, h.newV.company_id] : [])),
    ),
  ].filter(Boolean)

  const [profiles, companyLogs] = await Promise.all([
    userIds.length ? fetchProfiles(userIds) : { data: [] },
    companyIds.length ? fetchCompanyNameLogs(companyIds) : { data: [] },
  ])
  const error2 = profiles.error ?? companyLogs.error
  if (error2) return { error: error2 }

  const userNames = Object.fromEntries(profiles.data.map((p) => [p.id, p.display_name]))
  // เรียงเก่า → ใหม่ ชื่อล่าสุดของแต่ละบริษัทจึงทับชื่อเก่า
  const companyNames = Object.fromEntries(companyLogs.data.map((l) => [l.record_id, l.new_value?.name]))
  companyNames[summary.data.company_id] = summary.data.company_name

  return { data: { row: summary.data, payments: payments.data, history, userNames, companyNames } }
}

export default function ReceivableDetailPage() {
  const { id } = useParams()
  const { t, lang } = useLang()
  const navigate = useNavigate()
  const location = useLocation()
  const [state, setState] = useState({ status: 'loading', ...EMPTY, error: null })
  const [payMonth, setPayMonth] = useState('all')
  const [showSummary, setShowSummary] = useState(false)

  const validId = UUID_RE.test(id)

  const [reloadKey, setReloadKey] = useState(0)

  useEffect(() => {
    if (!validId) return
    let alive = true
    loadDetail(id).then((res) => {
      if (!alive) return
      if (res.error) setState({ status: 'error', ...EMPTY, error: loadErrorKey(res.error) })
      else if (res.notFound) setState({ status: 'notFound', ...EMPTY, error: null })
      else setState({ status: 'ready', ...res.data, error: null })
    })
    return () => {
      alive = false
    }
  }, [id, validId, reloadKey])

  const retry = () => {
    setState((s) => ({ ...s, status: 'loading', error: null }))
    setReloadKey((k) => k + 1)
  }

  const goBack = () => navigate('/' + (location.state?.from ?? ''))

  // เดือนของรายการเงินเข้า (ใหม่ → เก่า) สำหรับตัวเลือก
  const payMonths = useMemo(
    () => [...new Set(state.payments.map((p) => p.paid_date.slice(0, 7)))].sort().reverse(),
    [state.payments],
  )
  const shownPayments = useMemo(
    () => state.payments.filter((p) => payMonth === 'all' || p.paid_date.startsWith(payMonth)).reverse(),
    [state.payments, payMonth],
  )

  const back = (
    <button type="button" className="btn ghost back" onClick={goBack}>
      ← {t('back')}
    </button>
  )

  // id ผิดรูปแบบ (ลิงก์เสีย) → ไม่ต้องถาม database
  const status = validId ? state.status : 'notFound'

  if (status === 'loading') {
    return (
      <>
        {back}
        <p className="loading block-msg" role="status" aria-live="polite">
          {t('loading')}
        </p>
      </>
    )
  }

  if (status === 'error') {
    return (
      <>
        {back}
        <div className="load-err block-msg" role="alert">
          <p className="err">{t(state.error)}</p>
          <button type="button" className="btn primary" onClick={retry}>
            {t('retry')}
          </button>
        </div>
      </>
    )
  }

  if (status === 'notFound') {
    return (
      <>
        {back}
        <div className="empty">{t('notFound')}</div>
      </>
    )
  }

  const row = state.row

  return (
    <>
      {back}
      <section className="acct">
        <div className="name">{row.company_name}</div>
        <div className="meta">
          {t('credit', { n: row.credit_days })}, {t('acct', { m: fmtMonth(lang, row.account_month, true) })}
        </div>
        {row.is_paid ? (
          <div className="bal">{t('paid')}</div>
        ) : (
          <div className="bal num">
            {money(row.balance)}
            <small>{t('baht')}</small>
          </div>
        )}
        <div className="of num">{t('totalAmt', { a: money(row.total_amount) })}</div>
      </section>

      <div className="detail-grid">
        <section className="panel-box">
          <h2>{t('status')}</h2>
          {row.is_paid ? (
            <>
              <div className="paid-info">
                <span>{t('paidOn', { d: fmtDate(lang, row.paid_in_full_date, true) })}</span>
                <LateLine days={row.paid_late_actual_days} kind="a" />
                <LateLine days={row.paid_late_credit_days} kind="c" />
              </div>
              <p>
                <button type="button" className="btn" onClick={() => setShowSummary(true)}>
                  {t('summary')}
                </button>
              </p>
            </>
          ) : (
            <StatusBars row={row} />
          )}
          <h2 className="panel-h2-gap">{t('info')}</h2>
          <dl className="kv num">
            <dt>{t('fCstart')}</dt>
            <dd>{fmtDate(lang, row.credit_start_date, true)}</dd>
            <dt>{t('fCdays')}</dt>
            <dd>{row.credit_days}</dd>
            <dt>{t('creditDue', { d: '' })}</dt>
            <dd>{fmtDate(lang, row.credit_due_date, true)}</dd>
            <dt>{t('fAstart')}</dt>
            <dd>{fmtDate(lang, row.actual_start_date, true)}</dd>
            <dt>{t('fAdue')}</dt>
            <dd>{fmtDate(lang, row.actual_due_date, true)}</dd>
          </dl>
        </section>

        <section className="panel-box">
          <div className="txn-head">
            <h2>{t('incoming')}</h2>
            <select aria-label={t('incoming')} value={payMonth} onChange={(e) => setPayMonth(e.target.value)}>
              <option value="all">{t('all')}</option>
              {payMonths.map((m) => (
                <option key={m} value={m}>
                  {fmtMonth(lang, m, true)}
                </option>
              ))}
            </select>
          </div>
          {state.payments.length === 0 ? (
            <div className="empty">{t('noPay')}</div>
          ) : shownPayments.length ? (
            <PaymentList payments={shownPayments} />
          ) : (
            <div className="empty">{t('noPayMonth')}</div>
          )}
        </section>

        <section className="panel-box history-box">
          <h2>{t('historyH')}</h2>
          <EditHistory entries={state.history} userNames={state.userNames} companyNames={state.companyNames} />
        </section>
      </div>

      {showSummary && <SummaryDialog row={row} onClose={() => setShowSummary(false)} />}
    </>
  )
}
