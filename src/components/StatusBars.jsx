// แถบ 3 แถบ (วันจริง / วันเครดิต / เงิน) + ข้อความเลยกำหนด ตาม ui-reference — ทุกค่ามาจาก receivable_summary
import { fmtDate, money, pctLabel } from '../lib/format.js'
import { useLang } from '../lib/i18n.js'

function DayLine({ n, kind }) {
  const { t } = useLang()
  const k = t(kind === 'a' ? 'kActual' : 'kCredit')
  if (n > 0) return <div className="sub">{t('left', { n, k })}</div>
  if (n === 0) return <div className="sub over">{t('today')}</div>
  return <div className="sub over">{t('over', { n: -n, k })}</div>
}

function Bar({ label, pct, fillClass, children }) {
  return (
    <div className="bar">
      <div className="bar-top">
        <span className="num">{label}</span>
        <span className="pct num">{pctLabel(pct)}%</span>
      </div>
      <div className="track">
        <div className={'fill ' + fillClass} style={{ width: `${pct}%` }} />
      </div>
      {children}
    </div>
  )
}

export default function StatusBars({ row }) {
  const { t, lang } = useLang()
  return (
    <>
      <Bar
        label={t('actualDue', { d: fmtDate(lang, row.actual_due_date, true) })}
        pct={row.actual_pct}
        fillClass={row.days_to_actual_due < 0 ? 'over' : ''}
      >
        <DayLine n={row.days_to_actual_due} kind="a" />
      </Bar>
      <Bar
        label={t('creditDue', { d: fmtDate(lang, row.credit_due_date, true) })}
        pct={row.credit_pct}
        fillClass={row.days_to_credit_due < 0 ? 'over' : ''}
      >
        <DayLine n={row.days_to_credit_due} kind="c" />
      </Bar>
      <Bar label={t('paidOf', { p: money(row.paid_amount), t: money(row.total_amount) })} pct={row.money_pct} fillClass="money">
        <div className="remain num">{t('remain', { a: money(row.balance) })}</div>
      </Bar>
    </>
  )
}

// "ตรงเวลา" / "ช้ากว่ากำหนด N วัน" จาก paid_late_*_days (003)
export function LateLine({ days, kind }) {
  const { t } = useLang()
  const k = t(kind === 'a' ? 'kActual' : 'kCredit')
  return days > 0 ? <span className="late">{t('late', { n: days, k })}</span> : <span className="ok">{t('onTime', { k })}</span>
}
