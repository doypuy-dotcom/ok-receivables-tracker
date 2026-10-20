// หน้าสถิติ (V2 ข้อ 3 — prd.md ข้อ 6.3) ใช้ได้ทั้ง owner และ sales · ไม่มีใครแก้ตัวเลขได้
// ที่มา: feedback อาจารย์ 20 ต.ค. 2569 — "ให้มีหน้าสรุปเป็นสถิติ วิเคราะห์ลูกค้า"
//
// ข้อมูลทั้งหมดจาก 5 view ของ migration 008 (schema.md 4.5) + report_asof ของ 006:
//   stats_overview            ภาพรวม ณ วันนี้ + data_since (บรรทัดบอกข้อจำกัดของข้อมูล)
//   stats_collection_by_month ส่วน 1 — เก็บเงินของเดือนที่เลือกได้กี่ %
//   stats_aging               ส่วน 2 — อายุหนี้ค้าง 4 กลุ่ม (4 แถวเสมอ)
//   stats_company_behavior    ส่วน 3 — พฤติกรรมการจ่ายต่อบริษัท (เรียงมาแล้วจาก view)
//   stats_company_balance     ส่วน 4 — ยอดค้างต่อบริษัท (view ส่งทุกบริษัท หน้านี้แสดง 5 อันดับ)
//
// **ยอดเงิน / % / ค่าเฉลี่ย / การจัดกลุ่ม / ลำดับ คำนวณใน database ทั้งหมด** (AGENTS.md)
// หน้านี้ทำได้แค่ 4 อย่าง: เลือกแถวของเดือนที่กด, เลือกแถว seq <= 5, จัดรูปแบบตัวเลข,
// และเลือกสี/ข้อความจากตัวนับจำนวนใบ (จำนวนเต็มจาก view) — ไม่มีการบวก หาร หรือปัดเศษที่นี่เลย
// ความกว้างของแถบก็เอา % จาก view ไปต่อเป็น width ตรง ๆ (ดู StatBar)
//
// เดือนที่เลือกอยู่ใน URL (?m=2026-10) เหมือนหน้ารายงาน · Realtime: useLiveReload ตัวเดียวกับทุกหน้า
import { useCallback, useEffect, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { MonthField } from '../components/DateField.jsx'
import StatBar from '../components/StatBar.jsx'
import {
  fetchReportAsOf,
  fetchStatsAging,
  fetchStatsBalance,
  fetchStatsBehavior,
  fetchStatsMonths,
  fetchStatsOverview,
} from '../lib/data.js'
import { currentMonthBangkok, fmtDate, fmtStamp, loadErrorKey, money } from '../lib/format.js'
import { useLang } from '../lib/i18n.js'
import { useLiveReload } from '../lib/live.js'

const MONTH_RE = /^\d{4}-(0[1-9]|1[0-2])$/

// ชื่อกลุ่มอายุหนี้ + สีของแถบ: ยังไม่ถึงกำหนด = เขียว · เลยกำหนด = เหลือง · เกิน 60 วัน = แดง
// รหัสกลุ่ม (not_due / d1_30 / …) มาจาก view เพราะหน้าจอมี 2 ภาษา จึงเก็บข้อความไว้ที่ i18n
const BUCKETS = {
  not_due: { key: 'bNotDue', tone: 'money' },
  d1_30: { key: 'bD1', tone: '' },
  d31_60: { key: 'bD31', tone: '' },
  d60_plus: { key: 'bD60', tone: 'over' },
}

const EMPTY = { status: 'loading', overview: null, months: [], aging: [], behavior: [], balance: [], asOf: null, error: null }

async function loadStats() {
  const [overview, months, aging, behavior, balance, asOf] = await Promise.all([
    fetchStatsOverview(),
    fetchStatsMonths(),
    fetchStatsAging(),
    fetchStatsBehavior(),
    fetchStatsBalance(),
    fetchReportAsOf(),
  ])
  const error = overview.error ?? months.error ?? aging.error ?? behavior.error ?? balance.error ?? asOf.error
  if (error) return { ...EMPTY, status: 'error', error: loadErrorKey(error) }
  return {
    status: 'ready',
    overview: overview.data,
    months: months.data,
    aging: aging.data,
    behavior: behavior.data,
    balance: balance.data,
    asOf: asOf.data,
    error: null,
  }
}

export default function StatsPage() {
  const { t, lang } = useLang()
  const [params, setParams] = useSearchParams()
  const [state, setState] = useState(EMPTY)
  const [reloadKey, setReloadKey] = useState(0)

  const thisMonth = useMemo(() => currentMonthBangkok().slice(0, 7), [])
  const param = params.get('m')
  const month = MONTH_RE.test(param ?? '') ? param : thisMonth

  useEffect(() => {
    let alive = true
    loadStats().then((next) => alive && setState(next))
    return () => {
      alive = false
    }
  }, [reloadKey])

  const retry = () => {
    setState((s) => ({ ...s, status: 'loading', error: null }))
    setReloadKey((k) => k + 1)
  }

  // โหลดใหม่เงียบ ๆ เมื่อมีใครบันทึกการจ่าย / เพิ่มการ์ด (ข้อมูลล่าสุดเสมอ)
  const liveReload = useCallback(() => setReloadKey((k) => k + 1), [])
  useLiveReload(liveReload)

  const setMonth = (value) => {
    if (!MONTH_RE.test(value)) return
    const p = new URLSearchParams(params)
    p.set('m', value)
    setParams(p, { replace: true })
  }

  const ov = state.overview
  // เลือกแถวของเดือนที่กด (ไม่ใช่คำนวณ) — เดือนที่ไม่มีการ์ดเลยจะไม่มีแถว
  const monthRow = state.months.find((m) => m.due_month === `${month}-01`) ?? null
  // 5 อันดับแรกตาม seq ที่ view เรียงมาแล้ว · สัดส่วนรวมของกลุ่มนี้ = cum_pct ของแถวสุดท้ายที่แสดง
  const top = state.balance.filter((b) => b.seq <= 5)
  const topShare = top.length > 0 ? top[top.length - 1] : null

  return (
    <>
      <h1 className="page-title">{t('stTitle')}</h1>
      <p className="page-sub">{t('stSub')}</p>

      <section className="controls" aria-label="stats-controls">
        <div className="ctl-left">
          {/* ช่องเดือนของแอป (ดด/ปปปป ปี พ.ศ. + ปฏิทิน) — ห้ามใช้ input type="month" (AGENTS.md) */}
          <MonthField id="st-month" label={t('stMonth')} value={month} onChange={setMonth} />
        </div>
        <div className="ctl-right">
          {state.asOf ? <p className="muted st-meta num">{t('stAsOf', { s: fmtStamp(lang, state.asOf.viewed_at) })}</p> : null}
          {/* ข้อจำกัดของข้อมูล: วันเริ่มมาจาก data_since ของ database ไม่ฮาร์ดโค้ดไว้ในแอป */}
          {ov?.data_since ? <p className="muted st-meta">{t('stSince', { d: fmtDate(lang, ov.data_since) })}</p> : null}
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

      {state.status === 'ready' && !ov && <div className="empty block-msg">{t('stNoData')}</div>}

      {state.status === 'ready' && ov && (
        <div className="stats-grid">
          {/* ---------------- ส่วน 1: เก็บเงินของเดือนที่เลือกได้กี่ % ---------------- */}
          <section className="panel-box">
            <h2>{t('stH1')}</h2>
            {monthRow ? (
              <>
                <dl className="st-figs">
                  <div>
                    <dt>{t('stDue')}</dt>
                    <dd className="num">{money(monthRow.due_total)}</dd>
                  </div>
                  <div>
                    <dt>{t('stCollected')}</dt>
                    <dd className="num ok">{money(monthRow.collected_total)}</dd>
                  </div>
                  <div>
                    <dt>{t('stLeft')}</dt>
                    <dd className="num over">{money(monthRow.balance_total)}</dd>
                  </div>
                </dl>
                <StatBar
                  label={t('stCollectedPct')}
                  value={`${monthRow.collected_pct}%`}
                  pct={monthRow.collected_pct}
                  tone="money"
                  sub={t('stMonthCards', { n: monthRow.card_count, p: monthRow.paid_card_count })}
                />
              </>
            ) : (
              <div className="empty">{t('stNoMonth')}</div>
            )}
          </section>

          {/* ---------------- ส่วน 2: อายุหนี้ค้าง ณ วันนี้ ---------------- */}
          <section className="panel-box">
            <h2>{t('stH2')}</h2>
            {ov.outstanding_card_count > 0 ? (
              <>
                <p className="st-sum num">{t('stAgingTotal', { a: money(ov.outstanding_total), n: ov.outstanding_card_count })}</p>
                {state.aging.map((g) => (
                  <StatBar
                    key={g.bucket}
                    label={t(BUCKETS[g.bucket]?.key ?? g.bucket)}
                    value={money(g.balance_total)}
                    pct={g.pct_of_outstanding}
                    tone={BUCKETS[g.bucket]?.tone ?? ''}
                    sub={t('stBucketSub', { n: g.card_count, p: g.pct_of_outstanding })}
                  />
                ))}
              </>
            ) : (
              <div className="empty">{t('stNoDebt')}</div>
            )}
          </section>

          {/* ---------------- ส่วน 3: พฤติกรรมการจ่ายของลูกค้า ---------------- */}
          <section className="panel-box stats-wide">
            <h2>{t('stH3')}</h2>
            <p className="st-sum muted">{t('stH3Sub')}</p>
            {state.behavior.length === 0 ? (
              <div className="empty">{t('stNoStats')}</div>
            ) : (
              <ul className="st-cos">
                {state.behavior.map((c) => (
                  <li key={c.company_id}>
                    <div className="st-co-head">
                      <b>{c.company_name}</b>
                      {c.is_thin ? <span className="status-tag thin">{t('stThin')}</span> : null}
                    </div>
                    {c.paid_card_count > 0 ? (
                      <>
                        <div className="sub num">
                          {t('stPaidCards', { n: c.paid_card_count })} · {t('stOnTime', { p: c.on_time_pct })}
                        </div>
                        {c.late_card_count > 0 ? (
                          <div className="sub over num">
                            {t('stAvgLate', { n: c.avg_late_days })} · {t('stMaxLate', { n: c.max_late_days })}
                          </div>
                        ) : (
                          <div className="sub ok">{t('stNeverLate')}</div>
                        )}
                      </>
                    ) : (
                      <div className="sub">{t('stNoPaid')}</div>
                    )}
                    {c.overdue_now_count > 0 ? (
                      <div className="sub over num">
                        {t('stOverdueNow', { n: c.overdue_now_count, a: money(c.overdue_now_total) })}
                      </div>
                    ) : null}
                  </li>
                ))}
              </ul>
            )}
          </section>

          {/* ---------------- ส่วน 4: ยอดค้างกระจุกที่ใคร ---------------- */}
          <section className="panel-box stats-wide">
            <h2>{t('stH4')}</h2>
            <p className="st-sum muted">{t('stH4Sub')}</p>
            {top.length === 0 ? (
              <div className="empty">{t('stNoDebt')}</div>
            ) : (
              <>
                {top.map((b) => (
                  <StatBar
                    key={b.company_id}
                    label={`${b.seq}. ${b.company_name}`}
                    value={money(b.balance_total)}
                    pct={b.pct_of_outstanding}
                    tone="over"
                    sub={t('stTopSub', { p: b.pct_of_outstanding, n: b.open_card_count })}
                  />
                ))}
                <p className="st-sum num">{t('stTopShare', { n: top.length, p: topShare.cum_pct })}</p>
              </>
            )}
          </section>
        </div>
      )}
    </>
  )
}
