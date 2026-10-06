// ข้อความแจ้งผลสั้น ๆ (.toast ของ ui-reference) — ห้ามใช้ window.alert / confirm (AGENTS.md)
// อยู่เหนือ route ทั้งหมด จึงแจ้งผลข้ามหน้าได้ (ยกเลิกการ์ดในหน้ารายละเอียด → เด้งกลับหน้าตาราง)
import { createContext, createElement, useCallback, useContext, useEffect, useState } from 'react'

const ToastContext = createContext(null)

const HIDDEN = { msg: '', seq: 0 }

export function ToastProvider({ children }) {
  // seq เพิ่มทุกครั้งที่เรียก เพื่อให้ข้อความเดิมซ้ำ ๆ เริ่มนับเวลาใหม่
  const [toast, setToast] = useState(HIDDEN)

  const show = useCallback((msg) => setToast((prev) => ({ msg, seq: prev.seq + 1 })), [])

  useEffect(() => {
    if (!toast.msg) return
    const id = setTimeout(() => setToast(HIDDEN), 2400)
    return () => clearTimeout(id)
  }, [toast])

  return createElement(
    ToastContext.Provider,
    { value: show },
    children,
    createElement(
      'div',
      { className: 'toast' + (toast.msg ? ' show' : ''), role: 'status', 'aria-live': 'polite' },
      toast.msg,
    ),
  )
}

export function useToast() {
  return useContext(ToastContext)
}
