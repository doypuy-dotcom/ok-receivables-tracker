// ปุ่มยกเลิกแบบยืนยัน 2 ขั้น ตาม ui-reference (arm): กดครั้งแรก = เตือน, กดอีกครั้ง = ทำจริง
// ไม่มีการลบข้อมูลจริง การยกเลิกคือ is_cancelled = true (AGENTS.md)
import { useState } from 'react'
import { useLang } from '../lib/i18n.js'

export default function CancelButton({ label, onArm, onConfirm, disabled }) {
  const { t } = useLang()
  const [armed, setArmed] = useState(false)

  return (
    <button
      type="button"
      className={'btn danger left' + (armed ? ' armed' : '')}
      disabled={disabled}
      onClick={() => {
        if (!armed) {
          setArmed(true)
          onArm()
          return
        }
        onConfirm()
      }}
    >
      {armed ? t('confirmAgain') : label}
    </button>
  )
}
