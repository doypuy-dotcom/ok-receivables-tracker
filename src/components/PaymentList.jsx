// รายการเงินเข้า (.txns ของ ui-reference) — ฝ่ายขายกดที่รายการเพื่อแก้ไข (ส่ง onEdit มา), เจ้าของอ่านอย่างเดียว
import { fmtDate, fmtTime, money } from '../lib/format.js'
import { useLang } from '../lib/i18n.js'

export default function PaymentList({ payments, onEdit }) {
  const { t, lang } = useLang()
  return (
    <ul className="txns">
      {payments.map((p) => (
        <li
          key={p.id}
          className={'txn' + (onEdit ? ' editable' : '')}
          {...(onEdit
            ? {
                role: 'button',
                tabIndex: 0,
                'aria-label': t('editPay'),
                onClick: () => onEdit(p),
                onKeyDown: (e) => {
                  if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault()
                    onEdit(p)
                  }
                },
              }
            : {})}
        >
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
