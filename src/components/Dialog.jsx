// dialog ในแอป (ห้ามใช้ window.alert / confirm / prompt) ตาม .dlg-* ของ ui-reference
// มี onSubmit → ห่อเนื้อหาด้วย <form> เพื่อให้กด Enter บนคอมบันทึกได้ทันที
// noValidate: ปิดการตรวจของเบราว์เซอร์ (step / min) ที่จะกันการส่งฟอร์มแบบเงียบ ๆ
// ข้อความผิดพลาดทั้งหมดมาจากฟอร์มเองเป็นภาษาไทย/อังกฤษ และยังมี constraint + trigger ใน database กันอีกชั้น
import { useEffect, useRef } from 'react'
import { useLang } from '../lib/i18n.js'

export default function Dialog({ title, onClose, children, footer, onSubmit }) {
  const { t } = useLang()
  const ref = useRef(null)

  useEffect(() => {
    const el = ref.current
    if (el && !el.open) el.showModal()
    return () => el?.open && el.close()
  }, [])

  const body = (
    <>
      <div className="dlg-b">{children}</div>
      <div className="dlg-f">
        {footer ?? (
          <button type="button" className="btn primary" onClick={onClose}>
            {t('close')}
          </button>
        )}
      </div>
    </>
  )

  return (
    <dialog
      ref={ref}
      aria-labelledby="dlg-title"
      onCancel={(e) => {
        e.preventDefault()
        onClose()
      }}
      onClick={(e) => {
        // แตะพื้นหลังนอกกล่อง → ปิด
        if (e.target === e.currentTarget) onClose()
      }}
    >
      <div className="dlg-h">
        <h2 id="dlg-title">{title}</h2>
        <button type="button" className="close-x" aria-label={t('close')} onClick={onClose}>
          ×
        </button>
      </div>
      {onSubmit ? (
        <form
          noValidate
          onSubmit={(e) => {
            e.preventDefault()
            onSubmit()
          }}
        >
          {body}
        </form>
      ) : (
        body
      )}
    </dialog>
  )
}
