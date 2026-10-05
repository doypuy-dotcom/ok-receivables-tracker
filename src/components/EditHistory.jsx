// ประวัติการแก้ไขของการ์ด (schema.md 3.5): แก้ไข / ยกเลิก ของการ์ดและการจ่าย
// แต่ละรายการ: ใครแก้, เมื่อไหร่, ช่องที่เปลี่ยน จากค่าเดิม → ค่าใหม่
import { fmtDate, fmtMonth, fmtStamp, money } from '../lib/format.js'
import { useLang } from '../lib/i18n.js'

const FIELD_LABEL = {
  company_id: 'fCompany',
  account_month: 'fAcct',
  total_amount: 'fTotal',
  credit_days: 'fCdays',
  credit_start_date: 'fCstart',
  actual_start_date: 'fAstart',
  actual_due_date: 'fAdue',
  amount: 'fAmt',
  method: 'fMethod',
  paid_time: 'fTime',
  is_cancelled: 'fCancelled',
}

export default function EditHistory({ entries, userNames, companyNames }) {
  const { t, lang } = useLang()

  const label = (key, row) => {
    if (key === 'paid_date') return t(row.method === 'cheque' ? 'fDateC' : 'fDateT')
    return FIELD_LABEL[key] ? t(FIELD_LABEL[key]) : key
  }

  const value = (key, v) => {
    if (v === null || v === undefined) return '–'
    switch (key) {
      case 'company_id':
        return companyNames[v] ?? v
      case 'account_month':
        return fmtMonth(lang, v, true)
      case 'total_amount':
      case 'amount':
        return `${money(v)} ${t('baht')}`
      case 'credit_start_date':
      case 'actual_start_date':
      case 'actual_due_date':
      case 'paid_date':
        return fmtDate(lang, v, true)
      case 'method':
        return v === 'cheque' ? t('cheque') : t('transfer')
      case 'paid_time':
        return String(v).slice(0, 5)
      case 'is_cancelled':
        return v ? t('vCancelled') : t('vActive')
      default:
        return typeof v === 'object' ? JSON.stringify(v) : String(v)
    }
  }

  if (entries.length === 0) return <div className="empty">{t('noHistory')}</div>

  return (
    <ul className="hist">
      {entries.map(({ log, title, changed, oldV, newV }) => (
        <li key={log.id}>
          <div className="hist-head">
            <b>{t(title)}</b>
            <span className="num">
              {t('hBy', { u: userNames[log.user_id] ?? t('unknownUser') })} · {fmtStamp(lang, log.created_at)}
            </span>
          </div>
          {log.table_name === 'payments' && (
            <div className="hist-ref num">
              {value('method', oldV.method)} · {value('amount', oldV.amount)} · {value('paid_date', oldV.paid_date)}
            </div>
          )}
          {changed.length > 0 && (
            <ul className="hist-changes">
              {changed.map((k) => (
                <li key={k} className="num">
                  <span className="hist-field">{label(k, newV)}</span>
                  <span className="hist-old">{value(k, oldV[k])}</span>
                  <span aria-hidden="true"> → </span>
                  <span className="hist-new">{value(k, newV[k])}</span>
                </li>
              ))}
            </ul>
          )}
        </li>
      ))}
    </ul>
  )
}
