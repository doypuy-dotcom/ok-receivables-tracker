// หน้ารายละเอียดการ์ด ตาม detailView ของ ui-reference + ประวัติการแก้ไข (schema.md 3.5)
// อ่านจาก receivable_summary, payments, audit_logs (+ profiles สำหรับชื่อคนแก้) ไม่คำนวณเงินเอง
// Realtime (M5): มีคนแก้ข้อมูล → โหลดการ์ดนี้ใหม่ และถ้าการ์ดถูกยกเลิกโดยคนอื่น → แจ้งแล้วพากลับหน้าตาราง
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useLocation, useNavigate, useParams } from 'react-router-dom'
import { useAuth } from '../auth/useAuth.js'
import EditHistory from '../components/EditHistory.jsx'
import NotesPanel from '../components/NotesPanel.jsx'
import PaymentForm from '../components/PaymentForm.jsx'
import PaymentList from '../components/PaymentList.jsx'
import ReceivableForm from '../components/ReceivableForm.jsx'
import StatusBars, { LateLine } from '../components/StatusBars.jsx'
import SummaryDialog from '../components/SummaryDialog.jsx'
import {
  fetchCompanyNameLogs,
  fetchEditLogs,
  fetchNotes,
  fetchPayments,
  fetchProfiles,
  fetchSummary,
} from '../lib/data.js'
import { fmtDate, fmtMonth, loadErrorKey, money } from '../lib/format.js'
import { buildHistory } from '../lib/history.js'
import { useLang } from '../lib/i18n.js'
import { useLiveReload } from '../lib/live.js'
import { useToast } from '../lib/toast.js'

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

const EMPTY = { row: null, payments: [], history: [], notes: [], userNames: {}, userRoles: {}, companyNames: {} }

async function loadDetail(id) {
  const [summary, payments, logs, notes] = await Promise.all([
    fetchSummary(id),
    fetchPayments(id),
    fetchEditLogs(id),
    fetchNotes(id),
  ])
  const error = summary.error ?? payments.error ?? logs.error ?? notes.error
  if (error) return { error }
  if (!summary.data) return { notFound: true }

  const history = buildHistory(logs.data)
  // ชื่อคนที่ต้องแสดง: คนแก้ไขในประวัติ + คนเขียนหมายเหตุ (ขอ profiles ครั้งเดียว)
  const userIds = [...new Set([...history.map((h) => h.log.user_id), ...notes.data.map((n) => n.created_by)])]
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
  // role ของคนเขียนหมายเหตุ: ใช้ติดป้าย "เจ้าของ / ฝ่ายขาย" (V2 ข้อ 2)
  const userRoles = Object.fromEntries(profiles.data.map((p) => [p.id, p.role]))
  // เรียงเก่า → ใหม่ ชื่อล่าสุดของแต่ละบริษัทจึงทับชื่อเก่า
  const companyNames = Object.fromEntries(companyLogs.data.map((l) => [l.record_id, l.new_value?.name]))
  companyNames[summary.data.company_id] = summary.data.company_name

  return {
    data: {
      row: summary.data,
      payments: payments.data,
      history,
      notes: notes.data,
      userNames,
      userRoles,
      companyNames,
    },
  }
}

export default function ReceivableDetailPage() {
  const { id } = useParams()
  const { profile } = useAuth()
  const { t, lang } = useLang()
  const toast = useToast()
  const navigate = useNavigate()
  const location = useLocation()
  const [state, setState] = useState({ status: 'loading', ...EMPTY, error: null })
  const [payMonth, setPayMonth] = useState('all')
  const [showSummary, setShowSummary] = useState(false)
  // ฟอร์มที่เปิดอยู่: null | { kind: 'rec' } | { kind: 'pay', payment: null | แถวที่กำลังแก้ }
  const [dialog, setDialog] = useState(null)
  const isSales = profile.role === 'sales'

  const validId = UUID_RE.test(id)

  const [reloadKey, setReloadKey] = useState(0)
  // การโหลดรอบนี้มาจาก Realtime หรือเปล่า: ถ้าใช่แล้วการ์ดหายไป = คนอื่นยกเลิกขณะเราเปิดดูอยู่
  // (ต่างจากการเปิดลิงก์ของการ์ดที่ถูกยกเลิกไปก่อนแล้ว ซึ่งแสดงข้อความ "ไม่พบยอดค้างนี้" ค้างไว้)
  const fromLiveRef = useRef(false)

  useEffect(() => {
    if (!validId) return
    const fromLive = fromLiveRef.current
    fromLiveRef.current = false
    let alive = true
    loadDetail(id).then((res) => {
      if (!alive) return
      if (res.error) setState({ status: 'error', ...EMPTY, error: loadErrorKey(res.error) })
      else if (res.notFound) setState({ status: fromLive ? 'gone' : 'notFound', ...EMPTY, error: null })
      else setState({ status: 'ready', ...res.data, error: null })
    })
    return () => {
      alive = false
    }
  }, [id, validId, reloadKey])

  // โหลดใหม่เงียบ ๆ สำหรับ Realtime: ยอดคงเหลือ แถบ รายการเงินเข้า และประวัติการแก้ไขอัปเดตตาม
  const liveReload = useCallback(() => {
    fromLiveRef.current = true
    setReloadKey((k) => k + 1)
  }, [])
  useLiveReload(liveReload)

  // การ์ดที่เปิดดูอยู่ถูกยกเลิกโดยคนอื่น → แจ้งข้อความแล้วพากลับหน้าตาราง (ตัวกรองเดิม)
  useEffect(() => {
    if (state.status !== 'gone') return
    toast(t('recGone'))
    navigate('/' + (location.state?.from ?? ''), { replace: true })
  }, [state.status, toast, t, navigate, location.state])

  const retry = () => {
    setState((s) => ({ ...s, status: 'loading', error: null }))
    setReloadKey((k) => k + 1)
  }

  const goBack = () => navigate('/' + (location.state?.from ?? ''))

  // หลังบันทึก / ยกเลิกการจ่าย: โหลดการ์ดใหม่ (ยอดคงเหลือ แถบ และประวัติการแก้ไขอัปเดตตาม)
  const afterWrite = (msg) => {
    setDialog(null)
    setReloadKey((k) => k + 1)
    toast(msg)
  }

  // เขียนหมายเหตุแล้ว: โหลดใหม่เพื่อให้รายการใหม่ขึ้น (ฟอร์มยังเปิดอยู่ เขียนต่อได้อีก)
  const afterNote = (msg) => {
    setReloadKey((k) => k + 1)
    toast(msg)
  }

  // ยกเลิกการ์ดแล้วการ์ดหายจาก receivable_summary → พากลับหน้าตาราง (ตัวกรองเดิม)
  const afterCancelCard = (msg) => {
    setDialog(null)
    toast(msg)
    navigate('/' + (location.state?.from ?? ''), { replace: true })
  }

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

  // 'gone' = การ์ดถูกยกเลิกโดยคนอื่น — effect ด้านบนพากลับหน้าตารางแล้ว แสดงสถานะกำลังโหลดระหว่างนั้น
  if (status === 'loading' || status === 'gone') {
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
          {/* เจ้าของดูอย่างเดียว (prd ข้อ 9) จึงไม่มีปุ่มเพิ่ม/แก้ไขให้เห็นเลย — สิทธิ์จริงบังคับด้วย RLS */}
          {isSales && (
            <p className="panel-actions">
              {!row.is_paid && (
                <button
                  type="button"
                  className="btn primary"
                  onClick={() => setDialog({ kind: 'pay', payment: null })}
                >
                  + {t('addPay')}
                </button>
              )}
              <button type="button" className="btn" onClick={() => setDialog({ kind: 'rec' })}>
                {t('editRec')}
              </button>
            </p>
          )}
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
            <PaymentList
              payments={shownPayments}
              onEdit={isSales ? (payment) => setDialog({ kind: 'pay', payment }) : undefined}
            />
          ) : (
            <div className="empty">{t('noPayMonth')}</div>
          )}
        </section>

        {/* หมายเหตุ: **เจ้าของและฝ่ายขายเขียนได้ทั้งคู่** (V2 ข้อ 2 — migration 007)
            แก้/ลบไม่ได้ทั้งคู่ และยังเขียนในการ์ดที่ยกเลิกแล้วไม่ได้ (schema.md 3.6)
            canWrite เป็นเรื่องหน้าจอเท่านั้น สิทธิ์จริงอยู่ที่ RLS */}
        <section className="panel-box notes-box">
          <NotesPanel
            receivableId={row.id}
            notes={state.notes}
            userNames={state.userNames}
            userRoles={state.userRoles}
            myRole={profile.role}
            canWrite={Boolean(profile.role)}
            onSaved={afterNote}
          />
        </section>

        <section className="panel-box history-box">
          <h2>{t('historyH')}</h2>
          <EditHistory entries={state.history} userNames={state.userNames} companyNames={state.companyNames} />
        </section>
      </div>

      {showSummary && <SummaryDialog row={row} onClose={() => setShowSummary(false)} />}

      {isSales && dialog?.kind === 'rec' && (
        <ReceivableForm
          row={row}
          onClose={() => setDialog(null)}
          onSaved={afterWrite}
          onCancelled={afterCancelCard}
        />
      )}
      {isSales && dialog?.kind === 'pay' && (
        <PaymentForm
          row={row}
          payment={dialog.payment}
          onClose={() => setDialog(null)}
          onSaved={afterWrite}
          onCancelled={afterWrite}
        />
      )}
    </>
  )
}
