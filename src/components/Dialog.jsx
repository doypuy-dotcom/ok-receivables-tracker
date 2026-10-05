// dialog ในแอป (ห้ามใช้ window.alert / confirm / prompt) ตาม .dlg-* ของ ui-reference
import { useEffect, useRef } from 'react'
import { useLang } from '../lib/i18n.js'

export default function Dialog({ title, onClose, children, footer }) {
  const { t } = useLang()
  const ref = useRef(null)

  useEffect(() => {
    const el = ref.current
    if (el && !el.open) el.showModal()
    return () => el?.open && el.close()
  }, [])

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
      <div className="dlg-b">{children}</div>
      <div className="dlg-f">
        {footer ?? (
          <button type="button" className="btn primary" onClick={onClose}>
            {t('close')}
          </button>
        )}
      </div>
    </dialog>
  )
}
