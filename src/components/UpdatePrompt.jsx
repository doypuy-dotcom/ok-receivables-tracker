// แจ้งเมื่อมีเวอร์ชันใหม่ของแอป (M6) — ตาม registerType: 'prompt' ใน vite.config.js
// service worker ตัวใหม่จะ "รอ" อยู่จนผู้ใช้กดอัปเดต จึงไม่รีโหลดกลางคันตอนกำลังกรอกฟอร์ม
// ผู้ใช้ที่ไม่กด ก็ได้เวอร์ชันใหม่เองเมื่อปิดแอป (ทุกหน้าต่าง) แล้วเปิดใหม่ — ไม่ต้องลบแอปทิ้ง
import { useEffect, useState } from 'react'
import { useRegisterSW } from 'virtual:pwa-register/react'
import { useLang } from '../lib/i18n.js'

// เช็กว่ามีเวอร์ชันใหม่ไหม ทุก 1 ชั่วโมง สำหรับเครื่องที่เปิดแอปค้างไว้ทั้งวัน
const CHECK_EVERY = 60 * 60 * 1000

export default function UpdatePrompt() {
  const { t } = useLang()
  const [reg, setReg] = useState(null)
  const {
    needRefresh: [needRefresh, setNeedRefresh],
    updateServiceWorker,
  } = useRegisterSW({
    onRegisteredSW: (_url, r) => setReg(r ?? null),
  })

  // เช็กเพิ่มตอนกลับมาที่แอปและตอนเน็ตกลับมา (มือถือพักแอปแล้วตัดการเชื่อมต่อ — เหมือน lib/live.js)
  useEffect(() => {
    if (!reg) return
    const check = () => {
      if (document.visibilityState !== 'visible' || navigator.onLine === false) return
      reg.update().catch(() => {
        // ไม่มีสัญญาณ / เซิร์ฟเวอร์ไม่ตอบ → ข้ามไป เดี๋ยวรอบหน้าเช็กใหม่
      })
    }
    const id = setInterval(check, CHECK_EVERY)
    document.addEventListener('visibilitychange', check)
    window.addEventListener('online', check)
    return () => {
      clearInterval(id)
      document.removeEventListener('visibilitychange', check)
      window.removeEventListener('online', check)
    }
  }, [reg])

  if (!needRefresh) return null

  return (
    <div className="sw-update" role="status" aria-live="polite">
      <b>{t('swUpdate')}</b>
      {/* true = ใช้ service worker ตัวใหม่แล้วโหลดหน้าใหม่ให้เลย */}
      <button type="button" className="btn primary" onClick={() => updateServiceWorker(true)}>
        {t('swUpdateNow')}
      </button>
      <button type="button" className="btn ghost" onClick={() => setNeedRefresh(false)}>
        {t('swLater')}
      </button>
    </div>
  )
}
