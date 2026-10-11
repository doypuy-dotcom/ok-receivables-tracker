// ฟอร์มเพิ่ม / แก้ไข / ยกเลิกการจ่าย (ฝ่ายขายเท่านั้น) ตาม payForm ของ ui-reference
// โอน = วันที่เงินเข้า, เช็ค = วันที่เช็คขึ้นเงิน — ป้ายของช่องวันที่เปลี่ยนตามวิธีจ่าย (prd ข้อ 7)
// แก้ไขแล้วห้ามเปลี่ยนการ์ด: ฟอร์มไม่มีช่องเลือกการ์ด และไม่ส่ง receivable_id ตอน update (schema.md 3.4)
import { useState } from 'react'
import { cancelPayment, insertPayment, updatePayment } from '../lib/data.js'
import { saveErrorKey } from '../lib/dbError.js'
import { useDesktopFocus } from '../lib/focus.js'
import { addMoney, cmpMoney, isMoneyText, money, nowTimeBangkok, todayBangkok } from '../lib/format.js'
import { useLang } from '../lib/i18n.js'
import CancelButton from './CancelButton.jsx'
import DateField from './DateField.jsx'
import Dialog from './Dialog.jsx'

function initialValues(payment) {
  if (!payment) {
    return { amt: '', method: 'transfer', date: todayBangkok(), time: nowTimeBangkok() }
  }
  return {
    amt: payment.amount,
    method: payment.method,
    date: payment.paid_date,
    time: String(payment.paid_time).slice(0, 5),
  }
}

export default function PaymentForm({ row, payment, onClose, onSaved, onCancelled }) {
  const { t } = useLang()
  const [v, setV] = useState(() => initialValues(payment))
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)
  const firstRef = useDesktopFocus()

  // ยอดที่ยังบันทึกได้ = ยอดคงเหลือ + ยอดเดิมของรายการที่กำลังแก้ (คิดด้วยสตางค์แบบ BigInt ไม่ใช้ float)
  const room = payment ? addMoney(row.balance, payment.amount) : row.balance

  // ช่องวันที่ของแอป (DateField) ส่งค่าเป็น string ส่วนช่องอื่นส่ง event มา
  const setValue = (key, value) => {
    setV((prev) => ({ ...prev, [key]: value }))
    setErr('')
  }

  const set = (key) => (e) => setValue(key, e.target.value)

  const submit = async () => {
    if (busy) return
    const amt = v.amt.trim()
    if (!amt || !v.date || !v.time) {
      setErr(t('eFields'))
      return
    }
    if (!isMoneyText(amt)) {
      setErr(t('eAmtFormat'))
      return
    }
    if (!(Number(amt) > 0)) {
      setErr(t('eAmt'))
      return
    }
    // ตรวจในฟอร์มเพื่อบอกผู้ใช้ก่อน ตัวบังคับจริงคือ trigger check_payment_rules
    if (cmpMoney(amt, room) > 0) {
      setErr(t('eOver', { a: money(room) }))
      return
    }
    setBusy(true)
    const values = { amount: amt, method: v.method, paid_date: v.date, paid_time: v.time }
    const res = payment
      ? await updatePayment(payment.id, values)
      : await insertPayment({ receivable_id: row.id, ...values })
    setBusy(false)
    if (res.error) {
      setErr(t(saveErrorKey(res.error)))
      return
    }
    if (payment && res.data.length === 0) {
      setErr(t('eNoWrite'))
      return
    }
    onSaved(t('savedPay'))
  }

  const cancelPay = async () => {
    if (busy) return
    setBusy(true)
    const { data, error } = await cancelPayment(payment.id)
    setBusy(false)
    if (error) {
      setErr(t(saveErrorKey(error)))
      return
    }
    if (data.length === 0) {
      setErr(t('eNoWrite'))
      return
    }
    onCancelled(t('cancelled'))
  }

  const footer = (
    <>
      {payment && (
        <CancelButton
          label={t('cancelPay')}
          disabled={busy}
          onArm={() => setErr(t('confirmCancel'))}
          onConfirm={cancelPay}
        />
      )}
      <button type="button" className="btn" onClick={onClose} disabled={busy}>
        {t('cancel')}
      </button>
      <button type="submit" className="btn primary" disabled={busy}>
        {busy ? t('saving') : t('save')}
      </button>
    </>
  )

  return (
    <Dialog title={payment ? t('editPay') : t('addPay')} onClose={onClose} onSubmit={submit} footer={footer}>
      <div className="preview">
        {row.company_name}
        <br />
        <span className="num">{t('balanceNow', { a: money(row.balance) })}</span>
        {payment && <div className="hint">{t('editPayHint')}</div>}
      </div>
      <div className="field">
        <label htmlFor="f-amt">{t('fAmt')}</label>
        <input
          id="f-amt"
          ref={firstRef}
          type="number"
          inputMode="decimal"
          step="0.01"
          min="0"
          value={v.amt}
          onChange={set('amt')}
        />
      </div>
      <div className="field">
        <span className="lab">{t('fMethod')}</span>
        <div className="seg">
          <label>
            <input
              type="radio"
              name="f-method"
              value="transfer"
              checked={v.method === 'transfer'}
              onChange={set('method')}
            />
            {t('transfer')}
          </label>
          <label>
            <input
              type="radio"
              name="f-method"
              value="cheque"
              checked={v.method === 'cheque'}
              onChange={set('method')}
            />
            {t('cheque')}
          </label>
        </div>
      </div>
      <div className="row2">
        {/* ช่องของแอปเอง: พิมพ์ วว/ดด/ปปปป (ปี พ.ศ.) + ปฏิทิน — ป้ายยังเปลี่ยนตามวิธีจ่ายเหมือนเดิม */}
        <DateField
          id="f-date"
          label={v.method === 'cheque' ? t('fDateC') : t('fDateT')}
          value={v.date}
          onChange={(x) => setValue('date', x)}
        />
        <div className="field">
          <label htmlFor="f-time">{t('fTime')}</label>
          <input id="f-time" type="time" value={v.time} onChange={set('time')} />
        </div>
      </div>
      <p className="err" role="alert">
        {err}
      </p>
    </Dialog>
  )
}
