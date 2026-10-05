// รายการเงินเข้า (.txns ของ ui-reference) — อ่านอย่างเดียวใน M3
import { fmtDate, fmtTime, money } from '../lib/format.js'
import { useLang } from '../lib/i18n.js'

export default function PaymentList({ payments }) {
  const { t, lang } = useLang()
  return (
    <ul className="txns">
      {payments.map((p) => (
        <li key={p.id} className="txn">
          <span className="dot" />
          <div className="what">
            <b>{p.method === 'cheque' ? t('cheque') : t('transfer')}</b>
            <span className="num">
              {fmtDate(lang, p.paid_date, true)} {fmtTime(lang, p.paid_time)}
            </span>
          </div>
          <div className="amt num">+{money(p.amount)}</div>
        </li>
      ))}
    </ul>
  )
}
