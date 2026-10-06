// โฟกัสช่องแรกของฟอร์มให้เฉพาะเครื่องที่ชี้ด้วยเมาส์ (ฝ่ายขายใช้คอมเป็นหลัก)
// บนมือถือไม่โฟกัสเอง เพราะคีย์บอร์ดจะเด้งขึ้นมาทับฟอร์มทันทีที่เปิด
import { useEffect, useRef } from 'react'

export function useDesktopFocus(ready = true) {
  const ref = useRef(null)
  useEffect(() => {
    if (!ready) return
    if (window.matchMedia?.('(pointer: fine)').matches) ref.current?.focus()
  }, [ready])
  return ref
}
