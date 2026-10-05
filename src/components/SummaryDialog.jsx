// สรุปผลของการ์ดที่จ่ายครบ (prd ข้อ 7) ตาม summaryDlg ของ ui-reference
import { useEffect, useState } from 'react'
import { fetchPayments } from '../lib/data.js'
import { fmtDate, loadErrorKey } from '../lib/format.js'
import { useLang } from '../lib/i18n.js'
import Dialog from './Dialog.jsx'
import PaymentList from './PaymentList.jsx'
import { LateLine } from './StatusBars.jsx'

export default function SummaryDialog({ row, onClose }) {
  const { t, lang } = useLang()
  const [state, setState] = useState({ status: 'loading', payments: [], error: null })
  const [reloadKey, setReloadKey] = useState(0)

  useEffect(() => {
    let alive = true
    fetchPayments(row.id).then(({ data, error }) => {
      if (!alive) return
      if (error) setState({ status: 'error', payments: [], error: loadErrorKey(error) })
      else setState({ status: 'ready', payments: data, error: null })
    })
    return () => {
      alive = false
    }
  }, [row.id, reloadKey])

  return (
    <Dialog title={`${t('sumH')}: ${row.company_name}`} onClose={onClose}>
      <dl className="kv num">
        <dt>{t('sumPaidOn')}</dt>
        <dd>{fmtDate(lang, row.paid_in_full_date, true)}</dd>
        <dt>{t('sumCount')}</dt>
        <dd>{state.status === 'ready' ? t('times', { n: state.payments.length }) : '–'}</dd>
        <dt>{t('sumVsActual')}</dt>
        <dd>
          <LateLine days={row.paid_late_actual_days} kind="a" />
        </dd>
        <dt>{t('sumVsCredit')}</dt>
        <dd>
          <LateLine days={row.paid_late_credit_days} kind="c" />
        </dd>
      </dl>
      {state.status === 'loading' && (
        <p className="loading" role="status">
          {t('loading')}
        </p>
      )}
      {state.status === 'error' && (
        <div className="load-err" role="alert">
          <p className="err">{t(state.error)}</p>
          <button
            type="button"
            className="btn"
            onClick={() => {
              setState({ status: 'loading', payments: [], error: null })
              setReloadKey((k) => k + 1)
            }}
          >
            {t('retry')}
          </button>
        </div>
      )}
      {state.status === 'ready' &&
        (state.payments.length ? (
          <PaymentList payments={state.payments} />
        ) : (
          <div className="empty">{t('noPay')}</div>
        ))}
    </Dialog>
  )
}
