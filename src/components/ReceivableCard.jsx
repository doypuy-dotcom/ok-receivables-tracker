// การ์ด 1 ใบในหน้าตาราง ตาม ui-reference: ยังค้าง (ยอด + แถบ 3 แถบ) หรือ จ่ายแล้ว (+ ปุ่มสรุปผล)
import { fmtDate, fmtMonth, money } from '../lib/format.js'
import { useLang } from '../lib/i18n.js'
import StatusBars, { LateLine } from './StatusBars.jsx'

function cardStatusClass(row) {
  if (row.is_paid) return 's-paid'
  return row.days_to_actual_due < 0 ? 's-over' : 's-open'
}

// onAddPay: ฝ่ายขายเท่านั้น และการ์ดที่ยังค้างเท่านั้น (ไม่ส่งมาก็ไม่มีปุ่ม) — V1 รอบ ก
export default function ReceivableCard({ row, onOpen, onSummary, onAddPay }) {
  const { t, lang } = useLang()

  const onKeyDown = (e) => {
    if (e.target !== e.currentTarget) return
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault()
      onOpen(row)
    }
  }

  const head = (
    <div className="card-head">
      <h3>{row.company_name}</h3>
      <div className="chips">
        <span className="chip">{t('credit', { n: row.credit_days })}</span>
        <span className="chip">{t('acct', { m: fmtMonth(lang, row.account_month) })}</span>
      </div>
    </div>
  )

  return (
    <article
      className={'card ' + cardStatusClass(row)}
      role="link"
      tabIndex={0}
      onClick={() => onOpen(row)}
      onKeyDown={onKeyDown}
    >
      {head}
      {row.is_paid ? (
        <div className="card-body">
          <div className="amount-col">
            <div className="paid-big">{t('paid')}</div>
            <button
              type="button"
              className="btn"
              onClick={(e) => {
                e.stopPropagation()
                onSummary(row)
              }}
            >
              {t('summary')}
            </button>
          </div>
          <div className="paid-info">
            <span className="status-tag">{t('status')}</span>
            <span>{t('paidOn', { d: fmtDate(lang, row.paid_in_full_date, true) })}</span>
            <LateLine days={row.paid_late_actual_days} kind="a" />
            <LateLine days={row.paid_late_credit_days} kind="c" />
            <span className="num muted">{t('totalAmt', { a: money(row.total_amount) })}</span>
          </div>
        </div>
      ) : (
        <div className="card-body">
          <div className="amount-col">
            <div>
              <div className="lbl">{t('outstanding')}</div>
              <div className="amount num">{money(row.balance)}</div>
              <div className="unit">{t('baht')}</div>
            </div>
            <div className="card-cta">
              <span className="link">{t('viewDetail')}</span>
              {/* กดปุ่มนี้ต้องไม่เปิดหน้ารายละเอียดไปด้วย → stopPropagation
                  (ปุ่มเป็น <button> ซ้อนในการ์ด onKeyDown ของการ์ดจึงไม่ทำงานตอนกด Enter ที่ปุ่ม) */}
              {onAddPay && (
                <button
                  type="button"
                  className="btn primary"
                  onClick={(e) => {
                    e.stopPropagation()
                    onAddPay(row)
                  }}
                >
                  + {t('addPay')}
                </button>
              )}
            </div>
          </div>
          <div>
            <span className="status-tag">{t('status')}</span>
            <StatusBars row={row} />
          </div>
        </div>
      )}
    </article>
  )
}
